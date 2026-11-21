-- Client entry point: input, cursor aiming, and combat HUD.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- "Simple": click attacks the nearest enemy in front of you.
-- "Manual": your character turns to the cursor and click swings at whatever is under it.
local mode = "Simple"

-- HUD
local gui = Instance.new("ScreenGui")
gui.Name = "CombatHUD"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local modeLabel = Instance.new("TextLabel")
modeLabel.Size = UDim2.fromOffset(300, 30)
modeLabel.Position = UDim2.fromOffset(16, 16)
modeLabel.BackgroundColor3 = Color3.new(0, 0, 0)
modeLabel.BackgroundTransparency = 0.5
modeLabel.TextColor3 = Color3.new(1, 1, 1)
modeLabel.Font = Enum.Font.GothamBold
modeLabel.TextSize = 18
modeLabel.TextXAlignment = Enum.TextXAlignment.Left
modeLabel.Parent = gui

local feedbackLabel = Instance.new("TextLabel")
feedbackLabel.Size = UDim2.new(0, 400, 0, 60)
feedbackLabel.Position = UDim2.new(0.5, -200, 0.6, 0)
feedbackLabel.BackgroundTransparency = 1
feedbackLabel.Font = Enum.Font.GothamBlack
feedbackLabel.TextSize = 40
feedbackLabel.TextColor3 = Color3.new(1, 1, 1)
feedbackLabel.Text = ""
feedbackLabel.Parent = gui

local FEEDBACK = {
	Telegraph = { text = "PARRY! (F)", color = Color3.fromRGB(255, 220, 60) },
	Parried = { text = "PARRIED!", color = Color3.fromRGB(80, 255, 120) },
	Stunned = { text = "STUNNED", color = Color3.fromRGB(255, 80, 80) },
	Hit = { text = "HIT", color = Color3.fromRGB(255, 255, 255) },
}

-- Parry effects: a green screen flash and an optional sound on the defender's screen.
local flash = Instance.new("Frame")
flash.Name = "ParryFlash"
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundColor3 = Color3.fromRGB(120, 255, 160)
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.Parent = gui

local function playParryEffects()
	flash.BackgroundTransparency = 0.6
	TweenService:Create(flash, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()

	if Config.ParrySoundId ~= "" then
		local sound = Instance.new("Sound")
		sound.SoundId = Config.ParrySoundId
		sound.Volume = 1
		sound.Parent = SoundService
		sound:Play()
		sound.Ended:Connect(function()
			sound:Destroy()
		end)
		task.delay(5, function()
			if sound.Parent then
				sound:Destroy()
			end
		end)
	end
end

local feedbackToken = 0
local function showFeedback(kind)
	local info = FEEDBACK[kind]
	if not info then return end
	if kind == "Parried" then
		playParryEffects()
	end
	feedbackToken += 1
	local token = feedbackToken
	feedbackLabel.Text = info.text
	feedbackLabel.TextColor3 = info.color
	task.delay(0.6, function()
		if feedbackToken == token then
			feedbackLabel.Text = ""
		end
	end)
end

local function updateModeLabel()
	modeLabel.Text = "  Mode: " .. mode .. "  (Tab to switch)"
end
updateModeLabel()

-- Round status (top center): countdown, kills, and winner messages.
local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "RoundStatus"
statusLabel.Size = UDim2.new(0, 600, 0, 40)
statusLabel.Position = UDim2.new(0.5, -300, 0, 16)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.GothamBold
statusLabel.TextSize = 24
statusLabel.TextColor3 = Color3.new(1, 1, 1)
statusLabel.Text = ""
statusLabel.Parent = gui

-- Health bar (bottom-left), follows the local character.
local healthBack = Instance.new("Frame")
healthBack.Name = "HealthBack"
healthBack.Size = UDim2.fromOffset(260, 20)
healthBack.Position = UDim2.new(0, 16, 1, -40)
healthBack.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
healthBack.BorderSizePixel = 0
healthBack.Parent = gui

local healthFill = Instance.new("Frame")
healthFill.Name = "Fill"
healthFill.Size = UDim2.fromScale(1, 1)
healthFill.BorderSizePixel = 0
healthFill.Parent = healthBack

local function bindHealth(character)
	local humanoid = character:WaitForChild("Humanoid")
	local function update()
		local ratio = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
		healthFill.Size = UDim2.fromScale(ratio, 1)
		if ratio > 0.5 then
			healthFill.BackgroundColor3 = Color3.fromRGB(80, 220, 90)
		elseif ratio > 0.25 then
			healthFill.BackgroundColor3 = Color3.fromRGB(230, 200, 60)
		else
			healthFill.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
		end
	end
	humanoid.HealthChanged:Connect(update)
	update()
end

if player.Character then
	bindHealth(player.Character)
end
player.CharacterAdded:Connect(bindHealth)

-- Stun bar (under the health bar). Shows remaining stun time; hidden when not stunned.
-- The server sends only the duration; the countdown runs locally from when it arrives.
local stunBack = Instance.new("Frame")
stunBack.Name = "StunBack"
stunBack.Size = UDim2.fromOffset(260, 12)
stunBack.Position = UDim2.new(0, 16, 1, -68)
stunBack.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
stunBack.BorderSizePixel = 0
stunBack.Visible = false
stunBack.Parent = gui

local stunFill = Instance.new("Frame")
stunFill.Name = "Fill"
stunFill.Size = UDim2.fromScale(1, 1)
stunFill.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
stunFill.BorderSizePixel = 0
stunFill.Parent = stunBack

local stunEnd = 0
local stunDuration = 1

local function startStun(duration)
	stunDuration = math.max(duration, 0.01)
	stunEnd = os.clock() + stunDuration
end

RunService.RenderStepped:Connect(function()
	local remaining = stunEnd - os.clock()
	if remaining <= 0 then
		stunBack.Visible = false
		return
	end
	stunBack.Visible = true
	stunFill.Size = UDim2.fromScale(math.clamp(remaining / stunDuration, 0, 1), 1)
end)

-- World point under the mouse cursor.
local function cursorAim()
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	local result = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
	return result and result.Position or (ray.Origin + ray.Direction * 100)
end

-- Manual mode: the character turns to face the cursor.
RunService.RenderStepped:Connect(function()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root and humanoid.Health > 0) then return end

	if mode ~= "Manual" then
		humanoid.AutoRotate = true
		return
	end

	humanoid.AutoRotate = false
	local aim = cursorAim()
	local flat = Vector3.new(aim.X, root.Position.Y, aim.Z)
	if (flat - root.Position).Magnitude > 0.5 then
		root.CFrame = CFrame.lookAt(root.Position, flat)
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if mode == "Manual" then
			Remotes.Attack:FireServer(mode, cursorAim())
		else
			Remotes.Attack:FireServer(mode)
		end
	elseif input.KeyCode == Enum.KeyCode.F then
		Remotes.Parry:FireServer()
	elseif input.KeyCode == Enum.KeyCode.Tab then
		mode = (mode == "Simple") and "Manual" or "Simple"
		updateModeLabel()
	end
end)

Remotes.Feedback.OnClientEvent:Connect(function(kind, duration)
	showFeedback(kind)
	if kind == "Stunned" and type(duration) == "number" then
		startStun(duration)
	end
end)
Remotes.Round.OnClientEvent:Connect(function(message)
	statusLabel.Text = message
end)
