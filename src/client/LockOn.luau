-- Lock-on: keeps the body facing the opponent, so the player never loses track of them. Because the
-- camera follows the body's facing and movement is relative to the camera, A and D then strafe around
-- the opponent instead of turning the player.
--   * In a match, the target is the other fighter. Outside a match, it is the nearest training dummy
--     in range (Config.LockOnRange). In Training, only the player's own dummy counts.
--   * On by default. The player's "LockOn" binding (Controls) toggles it. With no target, or switched off, the player turns the
--     old way (the body turns toward where it moves).
--   * The current target is kept until it dies, leaves, or goes out of range, so the lock doesn't flick
--     between targets.
-- Main.client.luau turns the body toward `LockOn.update`'s result each frame. A small marker shows who
-- is locked.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local LockOn = {}

local player = Players.LocalPlayer

local enabled = true
local fighters = {} -- Players in the current match, or empty when there is none
local target = nil -- the locked character Model

-- Marker over the locked target: a red arrow that stays visible through walls.
local marker = Instance.new("BillboardGui")
marker.Name = "LockOnMarker"
marker.Size = UDim2.fromOffset(34, 34)
marker.StudsOffset = Vector3.new(0, 4, 0)
marker.AlwaysOnTop = true
marker.ResetOnSpawn = false
local arrow = Instance.new("TextLabel")
arrow.Size = UDim2.fromScale(1, 1)
arrow.BackgroundTransparency = 1
arrow.Text = "▼"
arrow.TextScaled = true
arrow.TextColor3 = Color3.fromRGB(255, 70, 70)
arrow.TextStrokeTransparency = 0.4
arrow.Font = Enum.Font.GothamBold
arrow.Parent = marker

local function isAlive(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and character:FindFirstChild("HumanoidRootPart") ~= nil
end

local function inMatch()
	for _, fighter in ipairs(fighters) do
		if fighter == player then
			return true
		end
	end
	return false
end

-- Whether `character` may be locked onto right now, from `myRoot`.
local function validTarget(character, myRoot)
	if not (character and character.Parent and isAlive(character)) then
		return false
	end
	if inMatch() then
		for _, fighter in ipairs(fighters) do
			if fighter ~= player and fighter.Character == character then
				return true
			end
		end
		return false
	end
	-- No match: only training dummies (models that aren't a player's character), within range.
	if Players:GetPlayerFromCharacter(character) then
		return false
	end
	-- Someone else's training dummy is never a target. In Training, only the player's own dummy is (the
	-- shared arena dummy is skipped, so the lock can't grab it just because it is nearer).
	local owner = character:GetAttribute("OwnerUserId")
	if owner ~= nil and owner ~= player.UserId then
		return false
	end
	if player:GetAttribute("Training") and owner ~= player.UserId then
		return false
	end
	return (character.HumanoidRootPart.Position - myRoot.Position).Magnitude <= Config.LockOnRange
end

-- The nearest valid target, or nil.
local function findTarget(myRoot)
	local best, bestDist = nil, math.huge
	for _, child in ipairs(workspace:GetChildren()) do
		if child:IsA("Model") and child ~= player.Character and validTarget(child, myRoot) then
			local dist = (child.HumanoidRootPart.Position - myRoot.Position).Magnitude
			if dist < bestDist then
				best, bestDist = child, dist
			end
		end
	end
	return best
end

-- Called with the fighter list when a match starts, and {} when it ends.
function LockOn.setFighters(list)
	fighters = list or {}
	target = nil
end

-- Switches the lock on or off. Returns the new state.
function LockOn.toggle()
	enabled = not enabled
	target = nil
	return enabled
end

-- Call every frame with the local HumanoidRootPart. `active` is false when lock-on shouldn't act right
-- now (for example in default mode). Returns the locked target's HumanoidRootPart, or nil.
function LockOn.update(myRoot, active)
	if not (enabled and active and myRoot) then
		target = nil
		marker.Adornee = nil
		marker.Parent = nil
		return nil
	end

	if not validTarget(target, myRoot) then
		target = findTarget(myRoot)
	end
	if not target then
		marker.Adornee = nil
		marker.Parent = nil
		return nil
	end

	local targetRoot = target.HumanoidRootPart
	if marker.Adornee ~= targetRoot then
		marker.Adornee = targetRoot
	end
	if marker.Parent ~= player.PlayerGui then
		marker.Parent = player.PlayerGui
	end
	return targetRoot
end

return LockOn
