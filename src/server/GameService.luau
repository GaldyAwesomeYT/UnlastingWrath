-- Match flow: ready-up queue, lobby countdown once enough players are ready, first-to-X-kills
-- match between the ready players (fighters), intermission, kill tracking, and the reset
-- countdown after each kill (heals fighters back to full).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RoundState = require(script.Parent.RoundState)
local CombatService = require(script.Parent.CombatService)
local TrainingService = require(script.Parent.TrainingService)
local LeaderboardService = require(script.Parent.LeaderboardService)

local GameService = {}

local kills = {} -- [Player] = kills this match
local ready = {} -- [Player] = true while queued

Players.RespawnTime = Config.RespawnTime

local function broadcast(message)
	Remotes.Round:FireAllClients(message)
end

-- Every player's kill count this match, highest first (ties by name, so the order doesn't jump around).
local function scoreList()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		table.insert(list, { name = player.Name, kills = kills[player] or 0 })
	end
	table.sort(list, function(a, b)
		if a.kills ~= b.kills then
			return a.kills > b.kills
		end
		return a.name < b.name
	end)
	return list
end

local function broadcastScores()
	Remotes.Scores:FireAllClients(scoreList())
end

-- Players who are ready and still in the server, in join order.
local function readyPlayers()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if ready[player] then
			table.insert(list, player)
		end
	end
	return list
end

local function readyCount()
	return #readyPlayers()
end

-- Lobby text: who is queued, e.g. "Ready: Alice - need 1 more".
local function queueText()
	local names = {}
	for _, player in ipairs(readyPlayers()) do
		table.insert(names, player.Name)
	end
	local needed = Config.MatchSize - #names
	if #names == 0 then
		return "Lobby: press Ready to queue (" .. Config.MatchSize .. " players per match)"
	end
	return "Ready: " .. table.concat(names, ", ") .. " - need " .. needed .. " more"
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

-- Fighter start positions: opposite sides of the sumo arena's dohyo, each facing the other.
local SPAWN_SPOTS = {
	Config.DuelArenaCenter + Vector3.new(-Config.DuelSpawnOffset, 0, 0),
	Config.DuelArenaCenter + Vector3.new(Config.DuelSpawnOffset, 0, 0),
}
local matchFighters = {} -- the current match's fighters, in SPAWN_SPOTS order

-- Moves each fighter to their spot, facing the other fighter.
local function placeFighters()
	for i, player in ipairs(matchFighters) do
		local spot = SPAWN_SPOTS[i]
		local other = SPAWN_SPOTS[3 - i]
		local character = player.Character
		local root = character and character:WaitForChild("HumanoidRootPart", 2)
		if root then
			root.CFrame = CFrame.lookAt(spot, Vector3.new(other.X, spot.Y, other.Z))
		end
	end
end

-- Waits (up to `timeout` seconds) until every fighter has a living character, e.g. after a respawn.
local function waitForFighters(timeout)
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local allAlive = true
		for _, player in ipairs(matchFighters) do
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if not (humanoid and humanoid.Health > 0) then
				allAlive = false
			end
		end
		if allAlive then return end
		task.wait(0.1)
	end
end

-- After a kill: pause combat, count down, wait for any respawns, put the fighters back on their
-- spots (not the spawn location), then heal them to full.
local function resetAfterKill(message)
	RoundState.paused = true
	for seconds = Config.KillResetCountdown, 1, -1 do
		broadcast(message .. " - resetting in " .. seconds)
		task.wait(1)
	end
	waitForFighters(5)
	placeFighters()
	for player in pairs(RoundState.fighters) do
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = humanoid.MaxHealth
		end
		if player.Character then
			CombatService.clearClash(player.Character) -- empty the Max-Clash bar and end any weakened state
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
	LeaderboardService.recordKill(killer) -- all-time global and regional totals

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

-- Title menu Play: applies the chosen game mode and training difficulty. Duel players queue with
-- Ready; Training players get their own dummy and leave the queue. Ignored for a fighter mid-match.
local function setOptions(player, gameMode, difficulty)
	if RoundState.active and RoundState.fighters[player] then return end
	if not table.find(Config.GameModes, gameMode) then
		gameMode = Config.DefaultGameMode
	end
	if type(difficulty) ~= "string" or not Config.Difficulties[difficulty] then
		difficulty = Config.DefaultDifficulty
	end

	if gameMode == "Training" then
		ready[player] = nil
		Remotes.ReadyState:FireClient(player, false)
		TrainingService.start(player, difficulty)
	else
		TrainingService.stop(player)
	end
end

-- Ready button: toggles a player's queue status. Ignored while a match is running or in training.
local function setReady(player, wantReady)
	if RoundState.active or TrainingService.isTraining(player) then
		Remotes.ReadyState:FireClient(player, false)
		return
	end
	ready[player] = wantReady and true or nil
end

local function onPlayerRemoving(player)
	ready[player] = nil
	TrainingService.stop(player)
	if RoundState.active and RoundState.fighters[player] then
		RoundState.active = false
		broadcast(player.Name .. " left - match over")
	end
end

-- Waits until MatchSize players are ready. Only posts a status line when it changes.
local function waitForQueue()
	local last = nil
	while readyCount() < Config.MatchSize do
		local message = queueText()
		if message ~= last then
			broadcast(message)
			last = message
		end
		task.wait(0.25)
	end
end

-- Returns true if the countdown finished with enough players still ready.
-- Shows who is in the match, e.g. "Alice vs Bob - starts in 3".
local function lobbyCountdown()
	for seconds = Config.LobbyCountdown, 1, -1 do
		local players = readyPlayers()
		if #players < Config.MatchSize then
			return false
		end
		local names = {}
		for i = 1, Config.MatchSize do
			table.insert(names, players[i].Name)
		end
		broadcast(table.concat(names, " vs ") .. " - starts in " .. seconds)
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
	matchFighters = fighters
	local spots = SPAWN_SPOTS
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
		-- Send the fighters back to the lobby (a respawn lands on the lobby's SpawnLocation).
		local finished = matchFighters
		task.wait(Config.DuelEndReturnDelay)
		for _, player in ipairs(finished) do
			if player.Parent then
				task.spawn(function() player:LoadCharacter() end)
			end
		end
		task.wait(Config.IntermissionTime)
	end
end

function GameService.start()
	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end
	Players.PlayerAdded:Connect(function(player)
		bindPlayer(player)
		broadcastScores() -- the new player appears on everyone's board
	end)
	Players.PlayerRemoving:Connect(function(player)
		onPlayerRemoving(player)
		task.delay(0.2, broadcastScores) -- after the player has left the list
	end)
	-- A client asks for the scores when it loads and when it opens the board: it can't have received
	-- earlier broadcasts (a late joiner, or scores sent before its scripts ran).
	Remotes.ScoresRequest.OnServerEvent:Connect(function(player)
		Remotes.Scores:FireClient(player, scoreList())
	end)
	Remotes.Ready.OnServerEvent:Connect(setReady)
	Remotes.Options.OnServerEvent:Connect(setOptions)
	task.spawn(runLoop)
end

return GameService
