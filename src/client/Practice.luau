-- Practice mode, client side. The server marks this player with the "Practicing" attribute when they press a
-- button at a bamboo stand (PracticeService). While it is set:
--   * every other player is invisible to this player: body, accessories, face, blade, and the default name tag.
--     (Their head health bars are hidden through HealthBars.setPractice, called by Main.client.luau.)
--   * an EXIT PRACTICE button is on screen. It tells the server, which clears the attribute; the attribute
--     changing back is what ends the mode here, so a respawn ends it too.
-- Nothing is changed for anyone else: this only touches how this client draws other characters.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Controls = require(script.Parent.Controls)

local Practice = {}

local player = Players.LocalPlayer

local active = false
local undo = setmetatable({}, { __mode = "k" }) -- [Instance] = function that puts it back
local connections = {} -- connections to drop when practice ends

-- Hides one instance of another player's character, remembering how to restore it.
local function hide(instance)
	if undo[instance] then return end
	if instance:IsA("BasePart") then
		instance.LocalTransparencyModifier = 1
		undo[instance] = function()
			instance.LocalTransparencyModifier = 0
		end
	elseif instance:IsA("Decal") or instance:IsA("Texture") then
		local original = instance.Transparency
		instance.Transparency = 1
		undo[instance] = function()
			instance.Transparency = original
		end
	elseif instance:IsA("ParticleEmitter") or instance:IsA("Trail") or instance:IsA("Beam")
		or instance:IsA("Fire") or instance:IsA("Smoke") or instance:IsA("Sparkles")
		or instance:IsA("Light") or instance:IsA("BillboardGui") or instance:IsA("SurfaceGui") then
		local original = instance.Enabled
		instance.Enabled = false
		undo[instance] = function()
			instance.Enabled = original
		end
	elseif instance:IsA("Humanoid") then
		local original = instance.DisplayDistanceType
		instance.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None -- no name tag or default health bar
		undo[instance] = function()
			instance.DisplayDistanceType = original
		end
	end
end

local function hideCharacter(character)
	for _, instance in ipairs(character:GetDescendants()) do
		hide(instance)
	end
	table.insert(connections, character.DescendantAdded:Connect(hide))
end

local function watchPlayer(other)
	if other == player then return end
	if other.Character then
		hideCharacter(other.Character)
	end
	table.insert(connections, other.CharacterAdded:Connect(hideCharacter))
end

local function showEveryone()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	connections = {}
	for _, restore in pairs(undo) do
		pcall(restore)
	end
	undo = setmetatable({}, { __mode = "k" })
end

-- callbacks.onChanged(active) runs whenever practice mode starts or ends.
function Practice.start(callbacks)
	local gui = Instance.new("ScreenGui")
	gui.Name = "PracticeGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Same spot as the Ready button, which is hidden while practicing.
	local exitButton = Instance.new("TextButton")
	exitButton.Name = "ExitPracticeButton"
	exitButton.Size = UDim2.fromOffset(200, 44)
	exitButton.AnchorPoint = Vector2.new(0.5, 1)
	exitButton.Position = UDim2.new(0.5, 0, 1, -16)
	exitButton.BackgroundColor3 = Color3.fromRGB(190, 60, 60)
	exitButton.BorderSizePixel = 0
	exitButton.Font = Enum.Font.GothamBold
	exitButton.TextSize = 20
	exitButton.TextColor3 = Color3.new(1, 1, 1)
	exitButton.Text = "EXIT PRACTICE"
	exitButton.Parent = gui
	Instance.new("UICorner", exitButton).CornerRadius = UDim.new(0, 8)

	-- The blade owns the mouse, so the cursor has to be freed before the button can be clicked.
	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.Size = UDim2.fromOffset(320, 20)
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -64)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 14
	hint.TextColor3 = Color3.fromRGB(235, 235, 240)
	hint.TextStrokeTransparency = 0.5
	hint.Parent = gui
	local function refreshHint()
		hint.Text = "Hold " .. Controls.label("FreeCursor") .. " to use the mouse"
	end
	refreshHint()
	Controls.onChanged(refreshHint)

	exitButton.Activated:Connect(function()
		Remotes.PracticeExit:FireServer()
	end)

	local function refresh()
		local now = player:GetAttribute("Practicing") == true
		if now == active then return end
		active = now
		gui.Enabled = active
		if active then
			for _, other in ipairs(Players:GetPlayers()) do
				watchPlayer(other)
			end
			table.insert(connections, Players.PlayerAdded:Connect(watchPlayer))
		else
			showEveryone()
		end
		if callbacks and callbacks.onChanged then
			callbacks.onChanged(active)
		end
	end
	player:GetAttributeChangedSignal("Practicing"):Connect(refresh)
	refresh()
end

function Practice.isActive()
	return active
end

return Practice
