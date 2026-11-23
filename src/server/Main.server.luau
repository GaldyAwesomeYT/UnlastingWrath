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

-- Arena markings (only if not already in the place): a center line and a pad under each fighter's
-- spawn point. Visual only: no collision, so they don't change movement or combat.
if not Workspace:FindFirstChild("ArenaMarkings") then
	local folder = Instance.new("Folder")
	folder.Name = "ArenaMarkings"
	folder.Parent = Workspace
	local top = -0.5 -- arena floor top
	local function marking(name, size, x, z, color)
		local part = makePart(name, size, CFrame.new(x, top + size.Y / 2 + 0.01, z), folder)
		part.Color = color
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Material = Enum.Material.SmoothPlastic
	end
	marking("CenterLine", Vector3.new(0.4, 0.1, 80), 0, 0, Color3.fromRGB(230, 230, 230))
	marking("PadLeft", Vector3.new(6, 0.1, 6), -Config.FighterSpawnX, 0, Color3.fromRGB(80, 140, 230))
	marking("PadRight", Vector3.new(6, 0.1, 6), Config.FighterSpawnX, 0, Color3.fromRGB(230, 90, 90))
end

-- Shared arena dummy (always available, any mode). Training players get their own dummies.
CombatService.spawnDummy(Vector3.new(0, 3, -20), {
	health = Config.DummyHealth,
	attackInterval = Config.DummyAttackInterval,
	windup = Config.DummyWindup,
}, "Dummy")
GameService.start()
require(script.Parent.BladeService).start()
require(script.Parent.KeybindService).start()
