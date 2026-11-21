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
-- The default R6 Animate script is turned off for the character (see disableDefaultAnimation).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

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

-- Virtual cursor: an offset in pixels from the screen center, kept inside a circle.
local aimOffset = Vector2.zero
local aimRadius = 1
local freeKeyHeld = false -- set by Main.client from the Config.FreeCursorKey input
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

-- Poses one arm so its hand reaches `target`. The arm stretches (up to Config.ArmMaxStretch) or shortens
-- (down to MIN_ARM_SCALE) to fit, in steps of ARM_STEP. Returns the hand position.
local function poseArm(character, side, target, look)
	local shoulder, motor, arm = shoulderOf(character, side)
	if not shoulder then return nil end

	local rest = restArmLength(arm)
	local toTarget = target - shoulder
	local dist = toTarget.Magnitude
	local travel = dist > 1e-3 and toTarget.Unit or -Vector3.yAxis
	local wanted = math.clamp(dist, rest * MIN_ARM_SCALE, rest * Config.ArmMaxStretch)
	local len = math.floor(wanted / ARM_STEP + 0.5) * ARM_STEP

	if math.abs(arm.Size.Y - len) > 0.001 then
		arm.Size = Vector3.new(arm.Size.X, len, arm.Size.Z)
	end
	placeMotor(motor, shoulder + travel * (len / 2), travel, look)
	return shoulder + travel * len
end

-- Moves the virtual cursor by the mouse delta and keeps it inside the circle. Also sets the mouse lock
-- and shows the cursor area only while the mouse is locked.
local function updateCursor()
	local free = Weapon.isFree()
	UserInputService.MouseBehavior = free and Enum.MouseBehavior.Default or Enum.MouseBehavior.LockCenter
	hud.Enabled = not free

	local view = camera.ViewportSize
	aimRadius = math.min(view.X, view.Y) * Config.AimRange
	if free then return end

	local delta = UserInputService:GetMouseDelta()
	aimOffset += Vector2.new(delta.X, delta.Y) * Config.AimSensitivity
	if aimOffset.Magnitude > aimRadius then
		aimOffset = aimOffset.Unit * aimRadius
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

-- Every frame, after the animator: both hands on the blade.
local function poseHands()
	local character = player.Character
	if not character then return end

	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid and humanoid.Health > 0) then return end
	if not character:FindFirstChild("Right Arm") then return end

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

	local rightHand = poseArm(character, "Right", grip, look)
	if rightHand then
		poseArm(character, "Left", rightHand + dir * Config.WeaponHandSpacing, look)
	else
		warnOnce("Right arm pose failed: no Torso 'Right Shoulder' motor or 'Right Arm' part found.")
	end

	if Config.AnimateLegs then
		poseLegs(character, root)
	else
		restLegs(character)
	end
end

-- The default R6 animation (the Animate script) writes every limb each frame, which overwrites the
-- arm pose. Turn it off for this character and stop any tracks it already started. The legs lose
-- their walk animation too, since the script drives them as well.
local function disableDefaultAnimation(character)
	task.spawn(function()
		local animate = character:WaitForChild("Animate", 5)
		if animate and animate:IsA("LocalScript") then
			animate.Disabled = true
		end
		local humanoid = character:WaitForChild("Humanoid", 5)
		local animator = humanoid and humanoid:WaitForChild("Animator", 5)
		if animator then
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
				track:Stop(0)
			end
		end
	end)
end

-- True while the cursor is free: Left Alt held, or the title menu open. Gameplay input is locked then.
function Weapon.isFree()
	return freeKeyHeld or isMenuOpen()
end

-- Left Alt pressed or released (called from Main.client).
function Weapon.setFreeKey(held)
	freeKeyHeld = held == true
end

-- Guard button held or released. Guard can't be raised while the cursor is free.
function Weapon.setGuard(held)
	guarding = held == true and not Weapon.isFree()
end

-- menuOpenCheck: function returning true while the title menu is open (its buttons need the real mouse).
function Weapon.start(menuOpenCheck)
	isMenuOpen = menuOpenCheck or isMenuOpen
	hud.Parent = player:WaitForChild("PlayerGui")

	local function onCharacter(character)
		disableDefaultAnimation(character)
	end
	if player.Character then
		onCharacter(player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)

	RunService.RenderStepped:Connect(driveCharacterBlade)
	RunService:BindToRenderStep("BladeHands", Enum.RenderPriority.Last.Value, poseHands)
end

return Weapon
