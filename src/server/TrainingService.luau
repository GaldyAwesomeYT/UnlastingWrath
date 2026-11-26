-- Training mode: each player who picks Training gets their own dummy in the arena, built at the
-- difficulty they chose. Training players stay out of the Ready queue. The shared arena dummy
-- (Main.server) is separate and always there.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local CombatService = require(script.Parent.CombatService)

local TrainingService = {}

local sessions = {} -- [Player] = { dummy = Model, connection = RBXScriptConnection }

-- The player stands on the left spawn point, facing the dummy on the right.
local PLAYER_SPOT = CFrame.lookAt(
	Vector3.new(-Config.FighterSpawnX, Config.FighterSpawnY, 0),
	Vector3.new(Config.FighterSpawnX, Config.FighterSpawnY, 0)
)
local DUMMY_POSITION = Vector3.new(Config.FighterSpawnX, Config.FighterSpawnY, 0)

local function placePlayer(character)
	local root = character:WaitForChild("HumanoidRootPart", 5)
	if root then
		root.CFrame = PLAYER_SPOT
	end
end

function TrainingService.isTraining(player)
	return sessions[player] ~= nil
end

-- Ends a player's training session and removes their dummy.
function TrainingService.stop(player)
	local session = sessions[player]
	if not session then return end
	sessions[player] = nil
	player:SetAttribute("Training", nil)
	session.connection:Disconnect()
	if session.dummy then
		session.dummy:Destroy()
	end
end

-- Starts (or restarts, at the new difficulty) a training session for this player.
function TrainingService.start(player, difficultyName)
	TrainingService.stop(player)
	local stats = Config.Difficulties[difficultyName] or Config.Difficulties[Config.DefaultDifficulty]

	local session = {}
	sessions[player] = session
	session.dummy = CombatService.spawnDummy(DUMMY_POSITION, stats, "TrainingDummy")
	-- Lets the client's lock-on pick this player's own dummy, not the shared arena dummy or someone else's.
	session.dummy:SetAttribute("OwnerUserId", player.UserId)
	player:SetAttribute("Training", true)
	-- Respawns (after a death) go back to the training spot.
	session.connection = player.CharacterAdded:Connect(placePlayer)

	if player.Character then
		placePlayer(player.Character)
	else
		player:LoadCharacter()
	end
end

return TrainingService
