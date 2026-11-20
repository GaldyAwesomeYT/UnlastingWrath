-- Server entry point: builds a test arena with a training dummy and starts combat.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
require(ReplicatedStorage.Shared.Remotes) -- creates the RemoteEvents before clients connect
local CombatService = require(script.Parent.CombatService)
local GameService = require(script.Parent.GameService)

local function makePart(name, size, cframe, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.Parent = parent
	return part
end

-- Floor, only if the place doesn't already have one.
if not Workspace:FindFirstChild("ArenaFloor") then
	makePart("ArenaFloor", Vector3.new(200, 2, 200), CFrame.new(0, -1.5, 0), Workspace) -- top at y=-0.5, just below a default baseplate (top at y=0) to avoid z-fighting
end

local function spawnDummy(position)
	local model = Instance.new("Model")
	model.Name = "Dummy"

	local root = makePart("HumanoidRootPart", Vector3.new(2, 2, 1), CFrame.new(position), model)
	root.Transparency = 1
	local head = makePart("Head", Vector3.new(2, 1, 1), CFrame.new(position + Vector3.new(0, 1.5, 0)), model)
	head.Color = Color3.fromRGB(255, 200, 150)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = head
	weld.Parent = root

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = Config.DummyHealth
	humanoid.Health = Config.DummyHealth
	humanoid.Parent = model

	model.PrimaryPart = root
	model.Parent = Workspace
	CombatService.addDummy(model)
	return model
end

spawnDummy(Vector3.new(0, 3, -20))
GameService.start()
