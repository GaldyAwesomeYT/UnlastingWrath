-- All-time kill leaderboards, kept in OrderedDataStores:
--   * Global: every player's total kills across all servers ("GlobalKills").
--   * Regional: the same total, ranked only among players from one country or region
--     ("RegionKills_<code>", the code from LocalizationService, e.g. "US").
-- GameService calls recordKill when a kill is credited. A client asks for a board with the Leaderboard
-- remote ("Global" or "Regional") and gets back the top rows. Boards are cached for CACHE_SECONDS, so
-- a busy server doesn't hit the DataStore for every request. If DataStores or the region lookup aren't
-- available, the board comes back empty-handed (nil) and a warning is printed.
local DataStoreService = game:GetService("DataStoreService")
local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local LeaderboardService = {}

local TOP_COUNT = 50 -- rows per board
local CACHE_SECONDS = 60 -- how long a fetched board is reused
local REQUEST_INTERVAL = 2 -- seconds a player must wait between board requests

local regionOf = {} -- [Player] = region code, once looked up
local nameOf = {} -- [userId] = name, so each name is fetched once
local cache = {} -- [store name] = { time = os.clock(), rows = { { name, kills } } }
local lastRequest = {} -- [Player] = os.clock()

local function store(name)
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	return ok and result or nil
end

-- The store name for a region, or nil if the code isn't a plain 2-letter code.
local function regionStoreName(region)
	if type(region) == "string" and string.match(region, "^%a%a$") then
		return "RegionKills_" .. string.upper(region)
	end
	return nil
end

-- Looks up each player's country or region when they join.
local function lookUpRegion(player)
	local ok, region = pcall(function()
		return LocalizationService:GetCountryRegionForPlayerAsync(player)
	end)
	if ok and regionStoreName(region) then
		regionOf[player] = string.upper(region)
	else
		warn("LeaderboardService: couldn't get a region for " .. player.Name .. ": " .. tostring(region))
	end
end

-- Adds one kill to the killer's global and regional totals.
function LeaderboardService.recordKill(player)
	local userId = tostring(player.UserId)
	local regionName = regionStoreName(regionOf[player])
	task.spawn(function()
		local names = { "GlobalKills", regionName }
		for _, name in ipairs(names) do
			local ordered = store(name)
			if ordered then
				local ok, err = pcall(function()
					ordered:IncrementAsync(userId, 1)
				end)
				if not ok then
					warn("LeaderboardService: couldn't record a kill in " .. name .. ": " .. tostring(err))
				end
			end
		end
	end)
end

-- A player's name from their user id, cached. Falls back to a placeholder if the lookup fails.
local function nameFor(userId)
	if nameOf[userId] then
		return nameOf[userId]
	end
	local online = Players:GetPlayerByUserId(userId)
	if online then
		nameOf[userId] = online.Name
		return online.Name
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	nameOf[userId] = ok and name or ("Player " .. userId)
	return nameOf[userId]
end

-- The top rows of a store as { { name = string, kills = number } }, highest first, or nil on failure.
-- Names are looked up in parallel, since each can take a web request.
local function fetchRows(storeName)
	local cached = cache[storeName]
	if cached and os.clock() - cached.time < CACHE_SECONDS then
		return cached.rows
	end

	local ordered = store(storeName)
	if not ordered then return nil end
	local ok, pages = pcall(function()
		return ordered:GetSortedAsync(false, TOP_COUNT)
	end)
	if not ok then
		warn("LeaderboardService: couldn't read " .. storeName .. ": " .. tostring(pages))
		return nil
	end

	local entries = pages:GetCurrentPage()
	local rows = table.create(#entries)
	local remaining = #entries
	for i, entry in ipairs(entries) do
		task.spawn(function()
			local userId = tonumber(entry.key)
			rows[i] = { name = userId and nameFor(userId) or tostring(entry.key), kills = entry.value }
			remaining -= 1
		end)
	end
	local deadline = os.clock() + 10
	while remaining > 0 and os.clock() < deadline do
		task.wait(0.05)
	end
	if remaining > 0 then return nil end

	cache[storeName] = { time = os.clock(), rows = rows }
	return rows
end

function LeaderboardService.start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(lookUpRegion, player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(lookUpRegion, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		regionOf[player] = nil
		lastRequest[player] = nil
	end)

	-- A client asks for "Global" or "Regional"; the answer is (kind, rows or nil, region code or nil).
	Remotes.Leaderboard.OnServerEvent:Connect(function(player, kind)
		if kind ~= "Global" and kind ~= "Regional" then return end
		local now = os.clock()
		if lastRequest[player] and now - lastRequest[player] < REQUEST_INTERVAL then return end
		lastRequest[player] = now

		task.spawn(function()
			if kind == "Global" then
				Remotes.Leaderboard:FireClient(player, kind, fetchRows("GlobalKills"))
				return
			end
			-- The region lookup can still be running just after joining, so give it a moment.
			local waited = 0
			while not regionOf[player] and waited < 5 and player.Parent do
				task.wait(0.25)
				waited += 0.25
			end
			local region = regionOf[player]
			local name = regionStoreName(region)
			if not name then
				Remotes.Leaderboard:FireClient(player, kind, nil, nil)
				return
			end
			Remotes.Leaderboard:FireClient(player, kind, fetchRows(name), region)
		end)
	end)
end

return LeaderboardService
