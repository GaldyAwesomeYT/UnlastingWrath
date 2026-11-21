-- Round flow: lobby countdown, first-to-X-kills rounds, intermission, kill tracking,
-- and the reset countdown after each kill (heals everyone back to full).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RoundState = require(script.Parent.RoundState)
local CombatService = require(script.Parent.CombatService)

local GameService = {}

local kills = {} -- [Player] = kills this round

Players.RespawnTime = Config.RespawnTime

local function broadcast(message)
	Remotes.Round:FireAllClients(message)
end

-- Sends every player's kill count this round, highest first.
local function broadcastScores()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		table.insert(list, { name = player.Name, kills = kills[player] or 0 })
	end
	table.sort(list, function(a, b) return a.kills > b.kills end)
	Remotes.Scores:FireAllClients(list)
end

-- After a kill: pause combat, count down, then heal every living player to full.
local function resetAfterKill(message)
	RoundState.paused = true
	for seconds = Config.KillResetCountdown, 1, -1 do
		broadcast(message .. " - resetting in " .. seconds)
		task.wait(1)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = humanoid.MaxHealth
		end
	end
	RoundState.paused = false
	broadcast("FIGHT!")
end

local function onDeath(player, character)
	if not RoundState.active then return end

	local last = CombatService.getLastAttacker(character)
	if not last or last.player == player then return end
	if os.clock() - last.time > Config.KillCredit then return end

	local killer = last.player
	kills[killer] = (kills[killer] or 0) + 1
	broadcastScores()

	if kills[killer] >= Config.KillsToWin then
		RoundState.active = false
		broadcast(killer.Name .. " wins the round!")
		return
	end

	task.spawn(resetAfterKill, killer.Name .. " scored a kill (" .. kills[killer] .. "/" .. Config.KillsToWin .. ")")
end

local function watchCharacter(player, character)
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.Died:Connect(function()
		onDeath(player, character)
	end)
end

local function bindPlayer(player)
	player.CharacterAdded:Connect(function(character)
		watchCharacter(player, character)
	end)
	if player.Character then
		watchCharacter(player, player.Character)
	end
end

local function loadEveryone()
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			player:LoadCharacter()
		end)
	end
end

local function runLoop()
	while true do
		for seconds = Config.LobbyCountdown, 1, -1 do
			broadcast("Round starts in " .. seconds)
			task.wait(1)
		end

		kills = {}
		RoundState.active = true
		RoundState.paused = false
		loadEveryone()
		broadcastScores()
		broadcast("FIGHT! First to " .. Config.KillsToWin .. " kills")

		while RoundState.active do
			task.wait(0.25)
		end
		task.wait(Config.IntermissionTime)
	end
end

function GameService.start()
	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end
	Players.PlayerAdded:Connect(bindPlayer)
	task.spawn(runLoop)
end

return GameService
