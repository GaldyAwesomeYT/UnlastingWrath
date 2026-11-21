-- Blade and hands for R6 characters. Each arm is a single straight part, so each hand is at the end
-- of its arm: the right arm reaches toward Config.WeaponGripTarget (about the middle of the chest) and
-- the left arm reaches the handle a bit further toward the tip. Arms are posed every frame through the
-- shoulder Motor6D Transforms, so they follow the handle as you swing.
-- The blade's base is ball-socketed to the right hand, so it pivots at the hand. It is part of the
-- character's assembly, so this client owns its physics, and the server reads the replicated blade for
-- hits and clashes.
-- The blade's direction follows the mouse (guard overrides it).
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

-- The current character's blade: { character = Model, aim = Attachment (in Terrain) }.
local current = nil

-- While guarding, the blade is held in front of the body instead of following the mouse.
local guarding = false

-- Shoulder joint position and arm part for one side ("Right" or "Left"). R6 motors are named "Right Shoulder" etc.
local function shoulderOf(character, side)
	local torso = character:FindFirstChild("Torso")
	local motor = torso and torso:FindFirstChild(side .. " Shoulder")
	local arm = character:FindFirstChild(side .. " Arm")
	if not (torso and motor and arm) then return nil end
	return (torso.CFrame * motor.C0).Position, motor, arm, torso
end

-- Where the hand ends if the arm points from its shoulder at `target`. R6 arms are straight,
-- so the hand sits at the arm's length along that direction. Returns the hand position and the travel direction.
local function handOf(character, side, target)
	local shoulder, _, arm = shoulderOf(character, side)
	if not shoulder then return nil end
	local toTarget = target - shoulder
	local travel = toTarget.Magnitude > 1e-3 and toTarget.Unit or -Vector3.yAxis
	return shoulder + travel * arm.Size.Y, travel
end

-- The right hand's position: the blade pivots here.
local function rightHandOf(character, root)
	local hand = handOf(character, "Right", root.CFrame * Config.WeaponGripTarget)
	return hand
end

-- A limb segment's CFrame. R6 arms run along Y from the shoulder joint at their top (+Y) to the hand
-- at their bottom, so Y points opposite to the direction of travel.
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

-- Poses a part by its Motor6D so the segment sits where the arm says.
-- Motor6D: Part1.CFrame = Part0.CFrame * C0 * Transform * C1:Inverse(), so Transform solves for `desired`.
local function placeMotor(motor, center, travel, hint)
	local desired = segmentCFrame(center, travel, hint)
	motor.Transform = (motor.Part0.CFrame * motor.C0):Inverse() * desired * motor.C1
end

-- Poses one arm so it points from its shoulder at `target`. Returns the hand position.
local function poseArm(character, side, target, look)
	local shoulder, motor, arm = shoulderOf(character, side)
	if not shoulder then return nil end
	local len = arm.Size.Y
	local toTarget = target - shoulder
	local travel = toTarget.Magnitude > 1e-3 and toTarget.Unit or -Vector3.yAxis
	placeMotor(motor, shoulder + travel * (len / 2), travel, look)
	return shoulder + travel * len
end

local function buildBlade(character)
	local root = character:WaitForChild("HumanoidRootPart")
	local rightArm = character:WaitForChild("Right Arm", 5)
	if not rightArm then
		warn("Blade: this character has no Right Arm part. The blade needs an R6 character.")
		return nil
	end

	local pivot = rightHandOf(character, root)
	if not pivot then return nil end
	local dir = root.CFrame.LookVector
	local center = pivot + dir * HALF

	local blade = Instance.new("Part")
	blade.Name = "Blade"
	blade.Size = Vector3.new(0.2, 0.1, Config.WeaponLength) -- long along Z; LookVector points toward the tip
	blade.Color = Color3.fromRGB(200, 205, 215)
	blade.Material = Enum.Material.Metal
	blade.CanCollide = false
	blade.Massless = true
	blade.CFrame = CFrame.lookAt(center, center + dir)
	blade.Parent = character

	local grip = Instance.new("Part")
	grip.Name = "Grip"
	grip.Size = Vector3.new(0.35, 0.35, 0.9)
	grip.Color = Color3.fromRGB(60, 45, 35)
	grip.CanCollide = false
	grip.Massless = true
	grip.CFrame = blade.CFrame * CFrame.new(0, 0, HALF + 0.3) -- behind the base, in the hand
	grip.Parent = character

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = blade
	weld.Part1 = grip
	weld.Parent = blade

	-- The hand is the bottom end of the right arm.
	local handAttachment = Instance.new("Attachment")
	handAttachment.Name = "GripAttachment"
	handAttachment.CFrame = CFrame.new(0, -rightArm.Size.Y / 2, 0)
	handAttachment.Parent = rightArm

	local baseAttachment = Instance.new("Attachment")
	baseAttachment.Name = "BaseAttachment"
	baseAttachment.CFrame = CFrame.new(0, 0, HALF)
	baseAttachment.Parent = blade

	local socket = Instance.new("BallSocketConstraint")
	socket.Attachment0 = handAttachment
	socket.Attachment1 = baseAttachment
	socket.Parent = blade

	-- The blade's orientation is driven toward `aim`, an attachment in Terrain set every frame (local only).
	local aim = Instance.new("Attachment")
	aim.Name = "BladeAim"
	aim.Parent = workspace.Terrain

	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.TwoAttachment
	align.Attachment0 = baseAttachment
	align.Attachment1 = aim
	align.Responsiveness = Config.WeaponResponsiveness
	align.MaxTorque = 1e6
	align.Parent = blade

	character.Destroying:Connect(function()
		aim:Destroy()
	end)

	return { character = character, aim = aim }
end

-- Keeps a blade direction in the half-space in front of the character (180 degrees). Anything pointing
-- behind is pushed onto the edge of that half (straight left, right, up or down), so the blade never goes behind.
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

-- Points the blade from the right hand toward the mouse's spot on a plane in front of the camera,
-- or straight ahead (tilted up) while guarding.
local function aimBlade()
	local c = current
	local character = player.Character
	if not (c and character and c.character == character) then return end

	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid and humanoid.Health > 0) then return end

	local pivot = rightHandOf(character, root)
	if not pivot then return end

	local dir = root.CFrame.LookVector
	if guarding then
		dir = (root.CFrame.LookVector + Vector3.yAxis * GUARD_UP).Unit
	else
		local mouse = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		local normal = camera.CFrame.LookVector
		local planePoint = camera.CFrame.Position + normal * Config.WeaponPlaneDistance
		local denom = ray.Direction:Dot(normal)
		if math.abs(denom) > 1e-4 then
			local t = (planePoint - ray.Origin):Dot(normal) / denom
			if t > 0 then
				local toTarget = (ray.Origin + ray.Direction * t) - pivot
				if toTarget.Magnitude > 0.01 then
					dir = toTarget.Unit
				end
			end
		end
	end

	dir = clampToFront(dir, root.CFrame.LookVector)

	-- CFrame.lookAt needs an up vector that isn't parallel to the direction.
	local up = if math.abs(dir.Y) > 0.99 then Vector3.zAxis else Vector3.yAxis
	c.aim.WorldCFrame = CFrame.lookAt(pivot, pivot + dir, up)
end

-- Every frame (after the animator, so the arms aren't overwritten): right hand on the grip,
-- left hand further along the handle toward the tip.
local function poseHands()
	-- Runs whenever the character is alive, even if the blade isn't built, so the arms rest in front.
	local character = player.Character
	if not character then return end

	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid and humanoid.Health > 0) then return end
	if not character:FindFirstChild("Right Arm") then return end

	local look = root.CFrame.LookVector
	local blade = character:FindFirstChild("Blade")
	local dir = blade and blade.CFrame.LookVector or look

	local rightHand = poseArm(character, "Right", root.CFrame * Config.WeaponGripTarget, look)
	if rightHand then
		poseArm(character, "Left", rightHand + dir * Config.WeaponHandSpacing, look)
	end
end

-- Guard button held or released: while held, the blade is held in front of the body.
function Weapon.setGuard(held)
	guarding = held == true
end

function Weapon.start()
	local function onCharacter(character)
		current = buildBlade(character)
	end
	if player.Character then
		onCharacter(player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
	RunService.RenderStepped:Connect(aimBlade)
	RunService:BindToRenderStep("BladeHands", Enum.RenderPriority.Last.Value, poseHands)
end

return Weapon
