-- The moves a player can rebind on the Controls page, with their defaults (from Config). Shared, because
-- the server checks saved bindings against this list. A binding is a string: "Key:<Enum.KeyCode name>"
-- or "Mouse:<Enum.UserInputType name>", e.g. "Key:F" or "Mouse:MouseButton2".
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local ControlActions = {}

-- In the order they are listed on the Controls page.
ControlActions.list = {
	{ id = "Guard", label = "Guard (hold)", default = "Key:" .. Config.GuardKey },
	{ id = "Sheathe", label = "Sheathe / draw", default = "Key:" .. Config.SheatheKey },
	{ id = "LockOn", label = "Lock on", default = "Key:" .. Config.LockOnKey },
	{ id = "Dash", label = "Dash", default = "Key:" .. Config.DashKey },
	{ id = "Look", label = "Look around (hold)", default = "Mouse:" .. Config.LookButton },
	{ id = "QuickDraw", label = "Quick draw (hold)", default = "Mouse:" .. Config.QuickDrawButton },
	{ id = "FreeCursor", label = "Free cursor (hold)", default = "Key:" .. Config.FreeCursorKey },
	{ id = "Scoreboard", label = "Scoreboard", default = "Key:Tab" },
}

-- Keys that can't be bound: movement, jump, and Escape (cancels a rebind and opens Roblox's menu).
ControlActions.reservedKeys = { W = true, A = true, S = true, D = true, Space = true, Escape = true, Unknown = true }

ControlActions.mouseButtons = { MouseButton1 = true, MouseButton2 = true, MouseButton3 = true }

-- Splits a binding string into ("Key" or "Mouse", name), or nil if it isn't a usable binding.
function ControlActions.parse(binding)
	if type(binding) ~= "string" or #binding > 40 then return nil end
	local kind, name = string.match(binding, "^(%a+):(%w+)$")
	if kind == "Key" then
		if ControlActions.reservedKeys[name] or not Enum.KeyCode:FromName(name) then return nil end
		return kind, name
	elseif kind == "Mouse" then
		if not ControlActions.mouseButtons[name] then return nil end
		return kind, name
	end
	return nil
end

return ControlActions
