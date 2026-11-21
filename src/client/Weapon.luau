-- Blade control and arm posing for R6 characters.
-- The server creates the blade (BladeService). This client drives it.
--   * Cursor: the real mouse is locked to the screen center. A virtual cursor moves with mouse movement,
--     kept inside a circle drawn on screen. Holding Config.FreeCursorKey (or the title menu being open)
--     frees the real mouse, and the blade holds its last position until it's released.
--   * Grip: the hands hold the blade near the chest. The grip shifts slightly with the cursor (up to
--     Config.GripMotion studs), like a paintbrush's grip.
--   * Guard: eases the blade into a pose in front of the body, instead of snapping.
--   * Blade: points from the grip toward the cursor's spot in front of the camera.
--   * Arms: the right hand holds the grip, the left hand holds the handle further toward the tip. Each
--     arm stretches or shortens to reach, within Config.ArmMaxStretch. Length changes in steps, so the
--     arm isn't resized every frame.
-- Arms are posed through the shoulder Motor6D C0 each frame, with Transform kept at identity.
-- The default R6 Animate script is turned off while the blade is drawn, and back on once it is fully
-- sheathed (see setDefaultAnimation and poseHands).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Weapon = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local HALF = Config.WeaponLength / 2
local GUARD_UP = 0.4 -- how far the guard blade tilts up from straight ahead
local MIN_ARM_SCALE = 0.4 -- arms can shorten to this fraction of their length, so the hand can reach close in
local ARM_STEP = 0.25 -- arm length changes in steps of this many studs, so the arm isn't resized every frame

-- Guard state: `guarding` is the button; `guardBlend` eases 0 (cursor aim) to 1 (guard pose).
local guarding = false
local guardBlend = 0

-- Sheathe state: `sheathed` is the toggle; `sheatheBlend` eases 0 (blade ready) to 1 (blade on the left hip).
local sheathed = false
local sheatheBlend = 0

-- Virtual cursor: an offset in pixels from the screen center, kept inside a circle.
local aimOffset = Vector2.zero
local aimRadius = 1
local freeKeyHeld = false -- set by Main.client from the Config.FreeCursorKey input

-- Look around: while the look button is held, the mouse turns the camera (yaw/pitch offsets from the
-- body's facing, in radians) instead of moving the cursor. Both reset when the button is released.
local looking = false
local lookYaw = 0
local lookPitch = 0
local isMenuOpen = function()
	return false
end

-- Screen HUD for the cursor area: a circle showing where the cursor can go, and a dot for the cursor.
local hud = Instance.new("ScreenGui")
hud.Name = "AimArea"
hud.ResetOnSpawn = false
hud.IgnoreGuiInset = true
hud.DisplayOrder = 5
hud.Enabled = false

local boundary = Instance.new("Frame")
boundary.Name = "Boundary"
boundary.AnchorPoint = Vector2.new(0.5, 0.5)
boundary.BackgroundTransparency = 1
boundary.Parent = hud
local boundaryCorner = Instance.new("UICorner")
boundaryCorner.CornerRadius = UDim.new(1, 0) -- full circle
boundaryCorner.Parent = boundary
local boundaryStroke = Instance.new("UIStroke")
boundaryStroke.Color = Color3.fromRGB(255, 255, 255)
boundaryStroke.Transparency = 0.5
boundaryStroke.Thickness = 2
boundaryStroke.Parent = boundary

local reticle = Instance.new("Frame")
reticle.Name = "Reticle"
reticle.AnchorPoint = Vector2.new(0.5, 0.5)
reticle.Size = UDim2.fromOffset(8, 8)
reticle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
reticle.BorderSizePixel = 0
reticle.Parent = hud
local reticleCorner = Instance.new("UICorner")
reticleCorner.CornerRadius = UDim.new(1, 0)
reticleCorner.Parent = reticle

-- Prints a problem once, so a broken pose shows up in Studio's Output without flooding it every frame.
local warned = {}
local function warnOnce(message)
	if not warned[message] then
		warned[message] = true
		warn("Weapon: " .. message)
	end
end

-- The joint's original C0 (its rest offset). We overwrite C0 to pose limbs, so read the rest value first.
local restC0 = setmetatable({}, { __mode = "k" })
local function originalC0(motor)
	if not restC0[motor] then
		restC0[motor] = motor.C0
	end
	return restC0[motor]
end

-- An arm's rest length. Arms stretch from this, so read it before any stretching.
local restArm = setmetatable({}, { __mode = "k" })
local function restArmLength(arm)
	if not restArm[arm] then
		restArm[arm] = arm.Size.Y
	end
	return restArm[arm]
end

-- Shoulder joint position, motor and arm part for one side ("Right" or "Left"). R6 motors are named "Right Shoulder" etc.
local function shoulderOf(character, side)
	local torso = character:FindFirstChild("Torso")
	local motor = torso and torso:FindFirstChild(side .. " Shoulder")
	local arm = character:FindFirstChild(side .. " Arm")
	if not (torso and motor and arm) then return nil end
	return (torso.CFrame * originalC0(motor)).Position, motor, arm, torso
end

-- Keeps a direction in the half-space in front of the character (180 degrees). Anything pointing
-- behind is pushed onto the edge of that half (straight left, right, up or down).
local function clampToFront(d, forward)
	local along = d:Dot(forward)
	if along >= 0 then
		return d
	end
	local flat = d - forward * along
	if flat.Magnitude < 1e-3 then
		return Vector3.yAxis -- pointing exactly straight back: use straight up
	end
	return flat.Unit
end

-- A limb segment's CFrame. R6 limbs run along Y from the joint at their top (+Y) to their bottom, so Y
-- points opposite to the direction of travel.
local function segmentCFrame(center, travel, hint)
	local y = -travel
	local x = hint:Cross(y)
	if x.Magnitude < 1e-3 then
		x = Vector3.xAxis:Cross(y)
	end
	x = x.Unit
	local z = x:Cross(y)
	return CFrame.fromMatrix(center, x, y, z)
end

-- Poses a limb by its Motor6D so the segment sits where `center` and `travel` say. The pose is written
-- into C0 with Transform kept at identity, so the animator can't undo it.
-- Motor6D: Part1.CFrame = Part0.CFrame * C0 * Transform * C1:Inverse(), so C0 = Part0.CFrame:Inverse() * desired * C1.
local function placeMotor(motor, center, travel, hint)
	local desired = segmentCFrame(center, travel, hint)
	if motor.Transform ~= CFrame.new() then
		motor.Transform = CFrame.new()
	end
	local newC0 = motor.Part0.CFrame:Inverse() * desired * motor.C1
	-- Only write when the pose actually moved, so a still arm isn't re-set every frame.
	local old = motor.C0
	if (newC0.Position - old.Position).Magnitude > 1e-3
		or (newC0.LookVector - old.LookVector).Magnitude > 1e-4
		or (newC0.UpVector - old.UpVector).Magnitude > 1e-4 then
		motor.C0 = newC0
	end
end

-- The joint's original C1 (where the shoulder sits on the arm part).
local restC1 = setmetatable({}, { __mode = "k" })
local function originalC1(motor)
	if not restC1[motor] then
		restC1[motor] = motor.C1
	end
	return restC1[motor]
end

-- The shoulder joint sits JOINT_DROP studs below the top of the arm (R6: arm is 2 tall, joint at y = 0.5).
local JOINT_DROP = 0.5

-- Poses one arm so its hand reaches `target`, with the arm's joint kept exactly on the shoulder.
-- The arm stretches (up to Config.ArmMaxStretch) or shortens (down to MIN_ARM_SCALE) to fit, in steps
-- of ARM_STEP. The joint's C1 is moved along the arm as it resizes, so the shoulder end stays attached.
-- Returns the hand position.
local function poseArm(character, side, target, look)
	local shoulder, motor, arm = shoulderOf(character, side)
	if not shoulder then return nil end

	local rest = restArmLength(arm)
	local restOne = originalC1(motor)
	local toTarget = target - shoulder
	local dist = toTarget.Magnitude
	local travel = dist > 1e-3 and toTarget.Unit or -Vector3.yAxis
	-- The hand is (len - JOINT_DROP) from the joint, so the length that reaches `dist` is dist + JOINT_DROP.
	local wanted = math.clamp(dist + JOINT_DROP, rest * MIN_ARM_SCALE, rest * Config.ArmMaxStretch)
	local len = math.floor(wanted / ARM_STEP + 0.5) * ARM_STEP

	if math.abs(arm.Size.Y - len) > 0.001 then
		arm.Size = Vector3.new(arm.Size.X, len, arm.Size.Z)
	end

	-- Keep the joint JOINT_DROP below the top of the resized arm.
	local jointY = len / 2 - JOINT_DROP
	local c1 = restOne - Vector3.new(0, restOne.Position.Y, 0) + Vector3.new(0, jointY, 0)
	if (motor.C1.Position - c1.Position).Magnitude > 1e-3 then
		motor.C1 = c1
	end

	-- Arm orientation, then slide its center so the joint point lands exactly on the shoulder.
	local rotation = segmentCFrame(Vector3.zero, travel, look)
	local center = shoulder - rotation:VectorToWorldSpace(c1.Position)
	placeMotor(motor, center, travel, look)
	return shoulder + travel * (len - JOINT_DROP)
end

-- Moves the virtual cursor by the mouse delta and keeps it inside the circle. Also sets the mouse lock
-- and shows the cursor area only while the mouse is locked.
local mouseHeldByUs = false -- true while this script has locked the mouse, so it is released once when the blade is sheathed

local function updateCursor()
	-- Default mode (blade fully sheathed): no cursor circle, no mouse lock, no look-around. The normal
	-- Roblox camera and mouse controls take over, so we leave them alone.
	if Weapon.isDefaultMode() then
		if mouseHeldByUs then
			mouseHeldByUs = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
		hud.Enabled = false
		if looking then
			Weapon.setLooking(false)
		end
		return
	end
	mouseHeldByUs = true

	local free = Weapon.isFree()

	-- Look button: polled every frame instead of using input events. Roblox's default camera script also
	-- binds right mouse and can mark the press as handled, so an InputBegan listener may never see it.
	local lookHeld = UserInputService:IsMouseButtonPressed(Enum.UserInputType[Config.LookButton])
	if lookHeld ~= looking then
		Weapon.setLooking(lookHeld)
	end

	UserInputService.MouseBehavior = free and Enum.MouseBehavior.Default or Enum.MouseBehavior.LockCenter
	hud.Enabled = not free

	local view = camera.ViewportSize
	aimRadius = math.min(view.X, view.Y) * Config.AimRange
	if free then return end

	local delta = UserInputService:GetMouseDelta()
	if looking then
		-- Looking around: the mouse turns the camera, and the cursor (and so the blade) holds still.
		lookYaw += delta.X * Config.LookSensitivity
		local limit = math.rad(Config.LookPitchLimit)
		lookPitch = math.clamp(lookPitch - delta.Y * Config.LookSensitivity, -limit, limit)
	else
		aimOffset += Vector2.new(delta.X, delta.Y) * Config.AimSensitivity
		if aimOffset.Magnitude > aimRadius then
			aimOffset = aimOffset.Unit * aimRadius
		end
	end

	-- Draw the circle and the cursor dot.
	local center = view / 2
	boundary.Position = UDim2.fromOffset(center.X, center.Y)
	boundary.Size = UDim2.fromOffset(aimRadius * 2, aimRadius * 2)
	local dot = center + aimOffset
	reticle.Position = UDim2.fromOffset(dot.X, dot.Y)
end

-- Where the blade's center should go, and which way it points. The grip sits at the chest and shifts a
-- little with the cursor. The cursor's circle maps to direction: the edge of the circle is
-- Config.AimMaxAngle degrees from straight ahead, in that direction. Guard eases the direction toward
-- the guard pose.
local function bladeTarget(character, root)
	local shoulder = shoulderOf(character, "Right")
	if not shoulder then return nil end
	local look = root.CFrame.LookVector

	local pivot = root.CFrame * Config.WeaponGripTarget
	local n = aimRadius > 0 and aimOffset / aimRadius or Vector2.zero
	local cursorGrip = pivot + root.CFrame.RightVector * (n.X * Config.GripMotion) - Vector3.yAxis * (n.Y * Config.GripMotion)
	local grip = cursorGrip:Lerp(pivot, guardBlend)

	-- Pixels right (n.X > 0) turn the blade right; pixels down (n.Y > 0) point it down.
	local maxAngle = math.rad(Config.AimMaxAngle)
	local cursorDir = (root.CFrame * CFrame.Angles(-n.Y * maxAngle, -n.X * maxAngle, 0)).LookVector
	local guardDir = (look + Vector3.yAxis * GUARD_UP).Unit
	local dir = cursorDir:Lerp(guardDir, guardBlend)
	dir = dir.Magnitude > 1e-3 and clampToFront(dir.Unit, look) or look
	return grip + dir * HALF, dir
end

-- Sets the server-made blade's targets, so the owning client moves it there.
local function driveBlade(character, root)
	local blade = character:FindFirstChild("Blade")
	local position = blade and blade:FindFirstChild("BladePosition")
	local orientation = blade and blade:FindFirstChild("BladeOrientation")
	if not (position and orientation) then return end

	local center, dir = bladeTarget(character, root)
	if not center then return end

	-- Sheathing: ease the blade from the ready pose to the left hip (pointing down and back).
	if sheatheBlend > 0 then
		local t = sheatheBlend * sheatheBlend * (3 - 2 * sheatheBlend) -- smoothstep, so it eases at both ends
		local hipCenter = root.CFrame * Config.SheathePosition
		local hipDir = root.CFrame:VectorToWorldSpace(Config.SheatheDirection.Unit)
		center = center:Lerp(hipCenter, t)
		local mixed = dir:Lerp(hipDir, t)
		dir = mixed.Magnitude > 1e-3 and mixed.Unit or hipDir
	end
	position.Position = center
	local up = if math.abs(dir.Y) > 0.99 then Vector3.zAxis else Vector3.yAxis
	orientation.CFrame = CFrame.lookAt(center, center + dir, up)
end

-- While the cursor is free, the character can't walk or jump, so the body can't move away from the
-- frozen blade. The original values are saved and restored when the cursor locks again.
local movementLocked = nil -- { humanoid = Humanoid, walkSpeed = number, jumpPower = number }

local function setMovementLocked(locked)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if locked then
		if humanoid and not (movementLocked and movementLocked.humanoid == humanoid) then
			movementLocked = { humanoid = humanoid, walkSpeed = humanoid.WalkSpeed, jumpPower = humanoid.JumpPower }
		end
		if movementLocked then
			movementLocked.humanoid.WalkSpeed = 0
			movementLocked.humanoid.JumpPower = 0
		end
	elseif movementLocked then
		local saved = movementLocked
		movementLocked = nil
		if saved.humanoid.Parent then
			saved.humanoid.WalkSpeed = saved.walkSpeed
			saved.humanoid.JumpPower = saved.jumpPower
		end
	end
end

local function driveCharacterBlade(dt)
	updateCursor()
	setMovementLocked(Weapon.isFree())

	-- Ease the guard in and out.
	local step = dt / Config.GuardBlendTime
	local target = guarding and 1 or 0
	guardBlend += math.clamp(target - guardBlend, -step, step)

	-- Ease the blade to the hip and back.
	local sheatheStep = dt / Config.SheatheTime
	sheatheBlend += math.clamp((sheathed and 1 or 0) - sheatheBlend, -sheatheStep, sheatheStep)

	-- While the cursor is free, the blade holds its last target (the guard pose still eases in if already held).
	if Weapon.isFree() then return end

	local character = player.Character
	if not character then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid and humanoid.Health > 0) then return end
	driveBlade(character, root)
end

-- Legs at their standard rest pose: the original hip offsets, no swing.
local function restLegs(character)
	local torso = character:FindFirstChild("Torso")
	if not torso then return end
	for _, side in ipairs({ "Right", "Left" }) do
		local motor = torso:FindFirstChild(side .. " Hip")
		if motor then
			-- Only write when something changed, so the joint isn't re-set every frame.
			local rest = originalC0(motor)
			if motor.Transform ~= CFrame.new() then
				motor.Transform = CFrame.new()
			end
			if motor.C0 ~= rest then
				motor.C0 = rest
			end
		end
	end
end

-- Walk swing for the legs (off unless Config.AnimateLegs is true). Phase advances with ground speed.
local walkPhase = 0
local lastLegTime = os.clock()

local function poseLegs(character, root)
	local now = os.clock()
	local dt = math.min(now - lastLegTime, 0.1)
	lastLegTime = now

	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	walkPhase += dt * speed * 0.5
	local amount = math.clamp(speed / 16, 0, 1)
	local swing = math.sin(walkPhase) * 0.5 * amount

	local torso = character:FindFirstChild("Torso")
	if not torso then return end
	local look = root.CFrame.LookVector
	for _, side in ipairs({ "Right", "Left" }) do
		local motor = torso:FindFirstChild(side .. " Hip")
		local leg = character:FindFirstChild(side .. " Leg")
		if motor and leg then
			local hip = (torso.CFrame * originalC0(motor)).Position
			local phase = side == "Right" and swing or -swing
			local travel = (-Vector3.yAxis * math.cos(phase) + look * math.sin(phase)).Unit
			placeMotor(motor, hip + travel * (leg.Size.Y / 2), travel, look)
		end
	end
end

-- The default R6 animation (the Animate script) writes every limb each frame, which overwrites the
-- arm pose. It is off while the blade is drawn (and tracks it already started are stopped), and on
-- while the blade is sheathed. The legs lose their walk animation while it is off.
local function setDefaultAnimation(character, enabled)
	task.spawn(function()
		local animate = character:WaitForChild("Animate", 5)
		if animate and animate:IsA("LocalScript") then
			animate.Disabled = not enabled
		end
		if enabled then return end
		local humanoid = character:WaitForChild("Humanoid", 5)
		local animator = humanoid and humanoid:WaitForChild("Animator", 5)
		if animator then
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
				track:Stop(0)
			end
		end
	end)
end

-- True while the default animation is running (blade fully sheathed). The hand and leg posing steps aside.
local animationActive = false

-- The standard R6 joints, taken from a blank R6 rig: each Torso motor's C0 and C1. The default animation
-- is built for exactly these, so the limbs are put back to them when it takes over.
local R6_REST = {
	["Right Shoulder"] = {
		C0 = CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
		C1 = CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
	},
	["Left Shoulder"] = {
		C0 = CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
		C1 = CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
	},
	["Right Hip"] = {
		C0 = CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
		C1 = CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
	},
	["Left Hip"] = {
		C0 = CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
		C1 = CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
	},
}
local R6_ARM_SIZE = Vector3.new(1, 2, 1)

-- Puts the limbs on the standard R6 joints and arm size, so the default animation moves a normal body
-- (the arm posing stretched the arms and moved their joints). Only writes what differs, so it can run
-- every frame while the default animation is active.
local function restoreRestPose(character)
	local torso = character:FindFirstChild("Torso")
	if not torso then return end
	for name, rest in pairs(R6_REST) do
		local motor = torso:FindFirstChild(name)
		if motor then
			if motor.C0 ~= rest.C0 then
				motor.C0 = rest.C0
			end
			if motor.C1 ~= rest.C1 then
				motor.C1 = rest.C1
			end
		end
	end
	for _, side in ipairs({ "Right", "Left" }) do
		local arm = character:FindFirstChild(side .. " Arm")
		if arm and arm.Size ~= R6_ARM_SIZE then
			arm.Size = R6_ARM_SIZE
		end
	end
end

-- Every frame, after the animator: both hands on the blade.
local function poseHands()
	local character = player.Character
	if not character then return end

	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid and humanoid.Health > 0) then return end
	if not character:FindFirstChild("Right Arm") then return end

	-- Blade fully sheathed: the default animation takes over the whole body.
	if Weapon.isDefaultMode() then
		-- Reset the joints before the animation starts, and keep checking them while it runs.
		restoreRestPose(character)
		if not animationActive then
			animationActive = true
			-- Clear any leftover pose from the arm posing, so the animation starts from nothing.
			local torso = character:FindFirstChild("Torso")
			if torso then
				for name in pairs(R6_REST) do
					local motor = torso:FindFirstChild(name)
					if motor then
						motor.Transform = CFrame.new()
					end
				end
			end
			setDefaultAnimation(character, true)
		end
		return
	end
	-- Blade being drawn: take the body back from the default animation.
	if animationActive then
		animationActive = false
		setDefaultAnimation(character, false)
	end

	local look = root.CFrame.LookVector
	local blade = character:FindFirstChild("Blade")
	local grip, dir
	if blade then
		-- The real blade: its base is where the right hand holds it, and its LookVector points to the tip.
		dir = blade.CFrame.LookVector
		grip = (blade.CFrame * CFrame.new(0, 0, HALF)).Position
	else
		dir = look
		grip = root.CFrame * Config.WeaponGripTarget
	end

	-- Sheathed: the hands ease down to hang at the sides (arms at rest length, pointing straight down).
	local t = sheatheBlend * sheatheBlend * (3 - 2 * sheatheBlend)
	local function restHand(side)
		local shoulder, _, arm = shoulderOf(character, side)
		if not shoulder then return nil end
		return shoulder - Vector3.yAxis * (restArmLength(arm) - JOINT_DROP)
	end
	local function blended(target, side)
		local rest = t > 0 and restHand(side)
		return rest and target:Lerp(rest, t) or target
	end

	local rightHand = poseArm(character, "Right", blended(grip, "Right"), look)
	if rightHand then
		poseArm(character, "Left", blended(rightHand + dir * Config.WeaponHandSpacing, "Left"), look)
	else
		warnOnce("Right arm pose failed: no Torso 'Right Shoulder' motor or 'Right Arm' part found.")
	end

	if Config.AnimateLegs then
		poseLegs(character, root)
	else
		restLegs(character)
	end
end

-- True while the cursor is free: Left Alt held, or the title menu open. Gameplay input is locked then.
function Weapon.isFree()
	return (freeKeyHeld and not Weapon.isDefaultMode()) or isMenuOpen()
end

-- True once the blade is fully sheathed: the player moves, looks and uses the mouse like in a default
-- Roblox baseplate (normal camera, free cursor, body turns toward movement). Drawing the blade ends it at once.
function Weapon.isDefaultMode()
	return sheathed and sheatheBlend >= 1
end

-- Left Alt pressed or released (called from Main.client).
function Weapon.setFreeKey(held)
	freeKeyHeld = held == true
	if freeKeyHeld then
		Weapon.setLooking(false) -- the free cursor ends any look-around
	end
end

-- Look button pressed or released (called from Main.client). Can't start while the cursor is free.
-- Releasing puts the camera back behind the body.
function Weapon.setLooking(held)
	looking = held == true and not Weapon.isFree()
	if not looking then
		lookYaw, lookPitch = 0, 0
	end
end

function Weapon.isLooking()
	return looking
end

-- The camera's look-around offsets from the body's facing: yaw (right is positive), pitch (up is positive).
function Weapon.getLook()
	return lookYaw, lookPitch
end

-- Guard button held or released. Guard can't be raised while the cursor is free.
function Weapon.setGuard(held)
	guarding = held == true and not Weapon.isFree() and not sheathed
end

-- Sheathes the blade on the left hip, or draws it again. Returns true when the blade is now sheathed.
-- The server is told so a sheathed blade can't hit, clash or guard. Not allowed while the cursor is free.
function Weapon.toggleSheathe()
	if Weapon.isFree() then return sheathed end
	sheathed = not sheathed
	if sheathed then
		guarding = false
	end
	Remotes.Sheathe:FireServer(sheathed)
	return sheathed
end

function Weapon.isSheathed()
	return sheathed
end

-- menuOpenCheck: function returning true while the title menu is open (its buttons need the real mouse).
function Weapon.start(menuOpenCheck)
	isMenuOpen = menuOpenCheck or isMenuOpen
	hud.Parent = player:WaitForChild("PlayerGui")

	local function onCharacter(character)
		-- A new character starts with the blade drawn (the server's state for it starts that way too).
		sheathed = false
		sheatheBlend = 0
		animationActive = false
		setDefaultAnimation(character, false)
	end
	if player.Character then
		onCharacter(player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)

	RunService.RenderStepped:Connect(driveCharacterBlade)
	RunService:BindToRenderStep("BladeHands", Enum.RenderPriority.Last.Value, poseHands)
end

return Weapon
