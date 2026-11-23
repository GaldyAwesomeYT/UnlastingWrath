-- Saves each player's personal key bindings (the Controls page) in a DataStore. The client sends its
-- bindings when they change, and asks for them when it starts. Everything from the client is checked
-- against ControlActions before it is saved. If DataStores aren't available (for example Studio without
-- API access), loading and saving fail quietly and bindings last for the session only.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ControlActions = require(ReplicatedStorage.Shared.ControlActions)

local KeybindService = {}

local SAVE_INTERVAL = 3 -- seconds a player must wait between saves

local store = nil
pcall(function()
	store = DataStoreService:GetDataStore("Keybinds")
end)

local lastSave = {} -- [Player] = os.clock() of their last save
local pending = {} -- [Player] = the newest bindings waiting for the save interval to pass

-- Only known moves with a valid binding make it through.
local function cleaned(data)
	if type(data) ~= "table" then return nil end
	local out = {}
	for _, action in ipairs(ControlActions.list) do
		local binding = data[action.id]
		if ControlActions.parse(binding) then
			out[action.id] = binding
		end
	end
	return out
end

local function keyFor(player)
	return "Player_" .. player.UserId
end

function KeybindService.start()
	Remotes.Keybinds.OnServerEvent:Connect(function(player, data)
		if not store then return end

		if data == nil then
			-- A request: send this player's saved bindings, if there are any.
			task.spawn(function()
				local ok, saved = pcall(function()
					return store:GetAsync(keyFor(player))
				end)
				local clean = ok and cleaned(saved)
				if clean and player.Parent then
					Remotes.Keybinds:FireClient(player, clean)
				end
			end)
			return
		end

		-- A save. Saves closer together than SAVE_INTERVAL are held back, and only the newest is kept.
		local clean = cleaned(data)
		if not clean then return end
		local userId = player.UserId
		local waitTime = (lastSave[player] or -math.huge) + SAVE_INTERVAL - os.clock()
		if pending[player] ~= nil then
			pending[player] = clean -- a save is already waiting; it will send this newer one
			return
		end
		local function write(bindings)
			lastSave[player] = os.clock()
			pcall(function()
				store:SetAsync("Player_" .. userId, bindings)
			end)
		end
		if waitTime <= 0 then
			task.spawn(write, clean)
		else
			pending[player] = clean
			task.delay(waitTime, function()
				local latest = pending[player]
				pending[player] = nil
				if latest then
					write(latest)
				end
			end)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		-- Write anything still waiting, so the last change isn't lost when the player leaves.
		local latest = pending[player]
		pending[player] = nil
		if latest and store then
			local userId = player.UserId
			task.spawn(function()
				pcall(function()
					store:SetAsync("Player_" .. userId, latest)
				end)
			end)
		end
		lastSave[player] = nil
	end)
end

return KeybindService
