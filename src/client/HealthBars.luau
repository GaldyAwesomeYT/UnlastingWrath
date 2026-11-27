-- Health bars over other players' and training dummies' heads. Hidden while the local player is fighting
-- in a duel (the opponent bars in the HUD cover that). To stay cheap, only the closest
-- Config.HealthBarMaxVisible bars on screen (within Config.HealthBarMaxDistance) are shown; the rest are
-- culled, and bars are refreshed on a timer instead of every frame.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Shared.Config)

local HealthBars = {}

local player = Players.LocalPlayer
local inMatch = false
local bars = {} -- [character Model] = { gui, fill, name, text }

local function makeBar(character)
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Size = UDim2.fromOffset(110, 30)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.AlwaysOnTop = false
	gui.ResetOnSpawn = false
	gui.Enabled = false

	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, 0, 0, 14)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBold
	name.TextSize = 12
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextStrokeTransparency = 0.4
	name.Text = character.Name
	name.Parent = gui

	local back = Instance.new("Frame")
	back.Position = UDim2.fromOffset(0, 16)
	back.Size = UDim2.new(1, 0, 0, 10)
	back.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	back.BorderSizePixel = 0
	back.Parent = gui
	Instance.new("UICorner", back).CornerRadius = UDim.new(0, 4)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 1.5
	stroke.Parent = back

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(80, 220, 110)
	fill.BorderSizePixel = 0
	fill.Parent = back
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 4)

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextSize = 9
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.5
	text.ZIndex = 2
	text.Parent = back

	gui.Parent = player:WaitForChild("PlayerGui")
	return { gui = gui, fill = fill, name = name, text = text }
end

local function dropBar(character)
	local bar = bars[character]
	if bar then
		bar.gui:Destroy()
		bars[character] = nil
	end
end

-- Whether `character` should get a bar: another player, or a training dummy this player can fight
-- (never someone else's training dummy; in Training, only the player's own).
local function wanted(character)
	if character == player.Character or not character.Parent then return false end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not (humanoid and humanoid.Health > 0 and character:FindFirstChild("Head")) then return false end
	if Players:GetPlayerFromCharacter(character) then return true end
	local owner = character:GetAttribute("OwnerUserId")
	if owner ~= nil and owner ~= player.UserId then return false end
	if player:GetAttribute("Training") and owner ~= player.UserId then return false end
	return true
end

local function refresh()
	local camera = workspace.CurrentCamera
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if inMatch or not camera or not root then
		for _, bar in pairs(bars) do
			bar.gui.Enabled = false
		end
		return
	end

	-- Candidates: everything wanted, on screen and in range, with its distance.
	local candidates = {}
	local seen = {}
	local function consider(character)
		seen[character] = true
		if not wanted(character) then return end
		local head = character.Head
		local distance = (head.Position - camera.CFrame.Position).Magnitude
		if distance > Config.HealthBarMaxDistance then return end
		local _, onScreen = camera:WorldToViewportPoint(head.Position)
		if not onScreen then return end
		table.insert(candidates, { character = character, distance = distance })
	end
	for _, other in ipairs(Players:GetPlayers()) do
		if other.Character then
			consider(other.Character)
		end
	end
	for _, child in ipairs(workspace:GetChildren()) do
		if child:IsA("Model") and not seen[child] and child:FindFirstChildOfClass("Humanoid") then
			consider(child)
		end
	end

	-- Cull beyond the limit: keep the closest ones.
	table.sort(candidates, function(a, b)
		return a.distance < b.distance
	end)
	local show = {}
	for i = 1, math.min(#candidates, Config.HealthBarMaxVisible) do
		show[candidates[i].character] = true
	end

	for character, bar in pairs(bars) do
		if not show[character] then
			bar.gui.Enabled = false
			if not character.Parent then
				dropBar(character)
			end
		end
	end
	for character in pairs(show) do
		local bar = bars[character]
		if not bar then
			bar = makeBar(character)
			bars[character] = bar
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local fraction = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
		bar.gui.Adornee = character.Head
		bar.gui.Enabled = true
		bar.fill.Size = UDim2.fromScale(fraction, 1)
		bar.fill.BackgroundColor3 = Color3.fromRGB(220, 70, 70):Lerp(Color3.fromRGB(80, 220, 110), fraction)
		bar.text.Text = math.ceil(humanoid.Health) .. " / " .. math.ceil(humanoid.MaxHealth)
		bar.name.Text = character.Name
	end
end

-- True while the local player is a fighter in a duel: the head bars are hidden then.
function HealthBars.setInMatch(value)
	inMatch = value == true
end

function HealthBars.start()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < Config.HealthBarRefreshTime then return end
		elapsed = 0
		refresh()
	end)
end

return HealthBars
