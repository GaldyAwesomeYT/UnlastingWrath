-- Match flow: ready-up queue, lobby countdown once enough players are ready, first-to-X-kills
-- match between the ready players (fighters), intermission, kill tracking, and the reset
-- countdown after each kill (heals fighters back to full).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RoundState = require(script.Parent.RoundState)
local CombatService = require(script.Parent.CombatService)

local GameService = {}

local kills = {} -- [Player] = kills this match
local ready = {} -- [Player] = true while queued

Players.RespawnTime = Config.RespawnTime

local function broadcast(message)
	Remotes.Round:FireAllClients(message)
end

-- Sends every player's kill count this match, highest first.
local function broadcastScores()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		table.insert(list, { name = player.Name, kills = kills[player] or 0 })
	end
	table.sort(list, function(a, b) return a.kills > b.kills end)
	Remotes.Scores:FireAllClients(list)
end

local function readyCount()
	local n = 0
	for player in pairs(ready) do
		if player.Parent == Players then
			n = n + 1
		end
	end
	return n
end

-- The first MatchSize ready players, in join order.
local function pickFighters()
	local picked = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if ready[player] and #picked < Config.MatchSize then
			table.insert(picked, player)
		end
	end
	return picked
end

-- After a kill: pause combat, count down, then heal every fighter to full.
local function resetAfterKill(message)
	RoundState.paused = true
	for seconds = Config.KillResetCountdown, 1, -1 do
		broadcast(message .. " - resetting in " .. seconds)
		task.wait(1)
	end
	for player in pairs(RoundState.fighters) do
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
		broadcast(killer.Name .. " wins the match!")
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

-- Ready button: toggles a player's queue status. Ignored while a match is running.
local function setReady(player, wantReady)
	if RoundState.active then
		Remotes.ReadyState:FireClient(player, false)
		return
	end
	ready[player] = wantReady and true or nil
end

local function onPlayerRemoving(player)
	ready[player] = nil
	if RoundState.active and RoundState.fighters[player] then
		RoundState.active = false
		broadcast(player.Name .. " left - match over")
	end
end

-- Waits until MatchSize players are ready. Only posts a status line when it changes.
local function waitForQueue()
	local last = nil
	while readyCount() < Config.MatchSize do
		local message = "Queue: " .. readyCount() .. "/" .. Config.MatchSize .. " ready - press Ready"
		if message ~= last then
			broadcast(message)
			last = message
		end
		task.wait(0.25)
	end
end

-- Returns true if the countdown finished with enough players still ready.
local function lobbyCountdown()
	for seconds = Config.LobbyCountdown, 1, -1 do
		if readyCount() < Config.MatchSize then
			return false
		end
		broadcast("Match starts in " .. seconds)
		task.wait(1)
	end
	return readyCount() >= Config.MatchSize
end

local function startMatch()
	local fighters = pickFighters()
	RoundState.fighters = {}
	for _, player in ipairs(fighters) do
		RoundState.fighters[player] = true
	end

	-- Everyone must press Ready again for the next match.
	ready = {}
	for _, player in ipairs(Players:GetPlayers()) do
		Remotes.ReadyState:FireClient(player, false)
	end

	kills = {}
	RoundState.active = true
	RoundState.paused = false
	-- Spawn the two fighters on opposite sides of the arena, each facing the other.
	local spots = { Vector3.new(-12, 3, 0), Vector3.new(12, 3, 0) }
	local placed = 0
	for i, player in ipairs(fighters) do
		local spot = spots[i]
		local other = spots[3 - i]
		task.spawn(function()
			player:LoadCharacter()
			local character = player.Character or player.CharacterAdded:Wait()
			local root = character:WaitForChild("HumanoidRootPart")
			root.CFrame = CFrame.lookAt(spot, Vector3.new(other.X, spot.Y, other.Z))
			placed = placed + 1
		end)
	end

	-- Wait for both fighters to be placed (give up after 10s if one left while loading).
	local deadline = os.clock() + 10
	while placed < #fighters and os.clock() < deadline do
		task.wait(0.1)
	end

	-- Duel intro: freeze both fighters (anchored) and pause combat while the client plays a side shot.
	RoundState.paused = true
	local frozenRoots = {}
	for _, fighter in ipairs(fighters) do
		local root = fighter.Character and fighter.Character:FindFirstChild("HumanoidRootPart")
		if root then
			root.Anchored = true
			table.insert(frozenRoots, root)
		end
	end
	Remotes.MatchStart:FireAllClients(fighters)
	broadcastScores()
	local introTime = Config.DuelWideTime + 2 * Config.DuelCloseTime + Config.DuelReturnTime + Config.DuelPanTime
	task.wait(introTime)

	-- Unfreeze and return to play. A root that was destroyed (the character died) is skipped.
	for _, root in ipairs(frozenRoots) do
		if root.Parent then
			root.Anchored = false
		end
	end
	RoundState.paused = false
	broadcast("FIGHT! First to " .. Config.KillsToWin .. " kills")
end

local function runLoop()
	while true do
		waitForQueue()
		if not lobbyCountdown() then
			broadcast("Countdown cancelled - waiting for players to ready up")
			continue
		end

		startMatch()
		while RoundState.active do
			task.wait(0.25)
		end
		Remotes.MatchStart:FireAllClients({}) -- empty list: the match is over, clients clear fighter UI
		task.wait(Config.IntermissionTime)
	end
end

function GameService.start()
	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end
	Players.PlayerAdded:Connect(bindPlayer)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	Remotes.Ready.OnServerEvent:Connect(setReady)
	task.spawn(runLoop)
end

return GameService
