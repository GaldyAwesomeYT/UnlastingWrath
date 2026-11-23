-- This player's key bindings for each move (see ControlActions for the list and defaults). The rest of
-- the client asks here instead of reading keys from Config:
--   Controls.matches(id, input)  true if an input event is this move's key or mouse button
--   Controls.isDown(id)          true while the move's key or mouse button is held (for polling)
--   Controls.label(id)           the binding as text for the UI, e.g. "Left Shift" or "Right Mouse"
-- Bindings are loaded from the server when the game starts and saved there when they change, so they
-- carry over between sessions (when the server can reach DataStores).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ControlActions = require(ReplicatedStorage.Shared.ControlActions)

local Controls = {}

local bindings = {} -- [id] = binding string
local listeners = {}

local function resetBindings()
	for _, action in ipairs(ControlActions.list) do
		bindings[action.id] = action.default
	end
end
resetBindings()

local function changed()
	for _, listener in ipairs(listeners) do
		listener()
	end
end

-- Sends the bindings to the server, after a short pause so a burst of changes is one save.
local saveToken = 0
local function save()
	saveToken += 1
	local token = saveToken
	task.delay(1, function()
		if token == saveToken then
			Remotes.Keybinds:FireServer(table.clone(bindings))
		end
	end)
end

-- Calls `listener` whenever any binding changes.
function Controls.onChanged(listener)
	table.insert(listeners, listener)
end

function Controls.binding(id)
	return bindings[id]
end

function Controls.matches(id, input)
	local kind, name = ControlActions.parse(bindings[id])
	if kind == "Key" then
		return input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode[name]
	elseif kind == "Mouse" then
		return input.UserInputType == Enum.UserInputType[name]
	end
	return false
end

function Controls.isDown(id)
	local kind, name = ControlActions.parse(bindings[id])
	if kind == "Key" then
		return UserInputService:IsKeyDown(Enum.KeyCode[name])
	elseif kind == "Mouse" then
		return UserInputService:IsMouseButtonPressed(Enum.UserInputType[name])
	end
	return false
end

-- A binding as readable text: "LeftShift" -> "Left Shift", "MouseButton2" -> "Right Mouse".
local MOUSE_NAMES = { MouseButton1 = "Left Mouse", MouseButton2 = "Right Mouse", MouseButton3 = "Middle Mouse" }
function Controls.label(id)
	local kind, name = ControlActions.parse(bindings[id])
	if kind == "Mouse" then
		return MOUSE_NAMES[name]
	elseif kind == "Key" then
		return (string.gsub(name, "(%l)(%u)", "%1 %2"))
	end
	return "?"
end

-- The binding string for a pressed key, or nil if that key can't be used (WASD, Space, Escape).
function Controls.bindingForKey(keyCode)
	local binding = "Key:" .. keyCode.Name
	return ControlActions.parse(binding) and binding or nil
end

-- The binding string for a mouse button input, or nil.
function Controls.bindingForMouse(input)
	local binding = "Mouse:" .. input.UserInputType.Name
	return ControlActions.parse(binding) and binding or nil
end

-- Binds a move. If another move already uses that key or button, the two swap, so nothing is left
-- double-bound.
function Controls.set(id, binding)
	if not ControlActions.parse(binding) or bindings[id] == nil then return end
	local old = bindings[id]
	for otherId, otherBinding in pairs(bindings) do
		if otherId ~= id and otherBinding == binding then
			bindings[otherId] = old
		end
	end
	bindings[id] = binding
	changed()
	save()
end

function Controls.resetAll()
	resetBindings()
	changed()
	save()
end

-- Saved bindings from the server: take only valid entries for known moves, ignore the rest.
Remotes.Keybinds.OnClientEvent:Connect(function(saved)
	if type(saved) ~= "table" then return end
	for _, action in ipairs(ControlActions.list) do
		if ControlActions.parse(saved[action.id]) then
			bindings[action.id] = saved[action.id]
		end
	end
	changed()
end)
Remotes.Keybinds:FireServer() -- no argument: ask for this player's saved bindings

return Controls
