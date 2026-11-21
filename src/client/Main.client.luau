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
	Dodged = { text = "DODGE!", color = Color3.fromRGB(120, 200, 255) },
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
	modeLabel.Text = "  Mode: " .. mode .. "  (M to switch, Tab: scores)"
end
updateModeLabel()

-- Scoreboard (Tab toggles it): every player's kills this round, highest first.
local board = Instance.new("Frame")
board.Name = "Scoreboard"
board.AnchorPoint = Vector2.new(0.5, 0)
board.Position = UDim2.new(0.5, 0, 0, 60)
board.Size = UDim2.fromOffset(320, 0)
board.AutomaticSize = Enum.AutomaticSize.Y
board.BackgroundColor3 = Color3.new(0, 0, 0)
board.BackgroundTransparency = 0.4
board.BorderSizePixel = 0
board.Visible = false
board.Parent = gui

local boardLayout = Instance.new("UIListLayout")
boardLayout.SortOrder = Enum.SortOrder.LayoutOrder
boardLayout.Padding = UDim.new(0, 4)
boardLayout.Parent = board

local boardPadding = Instance.new("UIPadding")
boardPadding.PaddingTop = UDim.new(0, 8)
boardPadding.PaddingBottom = UDim.new(0, 8)
boardPadding.PaddingLeft = UDim.new(0, 12)
boardPadding.PaddingRight = UDim.new(0, 12)
boardPadding.Parent = board

local function makeRow(text, order, color)
	local row = Instance.new("TextLabel")
	row.Size = UDim2.new(1, 0, 0, 22)
	row.BackgroundTransparency = 1
	row.Font = Enum.Font.GothamBold
	row.TextSize = 18
	row.TextColor3 = color
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.Text = text
	row.LayoutOrder = order
	row.Parent = board
end

local function renderScores(list)
	for _, child in ipairs(board:GetChildren()) do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	makeRow("Scoreboard (first to " .. Config.KillsToWin .. ")", 0, Color3.fromRGB(255, 220, 60))
	for i, entry in ipairs(list) do
		makeRow(entry.name .. " - " .. entry.kills .. " kills", i, Color3.new(1, 1, 1))
	end
end

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

-- Opponent HP bars (top right): one per other player, read from their replicated Humanoid.
local opponentPanel = Instance.new("Frame")
opponentPanel.Name = "OpponentBars"
opponentPanel.AnchorPoint = Vector2.new(1, 0)
opponentPanel.Position = UDim2.new(1, -16, 0, 16)
opponentPanel.Size = UDim2.fromOffset(260, 0)
opponentPanel.AutomaticSize = Enum.AutomaticSize.Y
opponentPanel.BackgroundTransparency = 1
opponentPanel.Parent = gui

local opponentLayout = Instance.new("UIListLayout")
opponentLayout.SortOrder = Enum.SortOrder.Name
opponentLayout.Padding = UDim.new(0, 6)
opponentLayout.Parent = opponentPanel

local opponentBars = {} -- [Player] = { frame = Frame, fill = Frame }

local function addOpponentBar(other)
	if other == player or opponentBars[other] then return end

	local frame = Instance.new("Frame")
	frame.Name = other.Name
	frame.Size = UDim2.new(1, 0, 0, 34)
	frame.BackgroundTransparency = 1
	frame.Parent = opponentPanel

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0, 16)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Right
	nameLabel.Text = other.Name
	nameLabel.Parent = frame

	local back = Instance.new("Frame")
	back.Size = UDim2.new(1, 0, 0, 14)
	back.Position = UDim2.fromOffset(0, 18)
	back.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	back.BorderSizePixel = 0
	back.Parent = frame

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BorderSizePixel = 0
	fill.Parent = back

	opponentBars[other] = { frame = frame, fill = fill }
end

local function removeOpponentBar(other)
	local bar = opponentBars[other]
	if bar then
		bar.frame:Destroy()
		opponentBars[other] = nil
	end
end

-- Shows only the other fighter's bar, and only while this player is in a match.
-- Called with the fighter list when a match starts, and with {} when it ends.
local function setOpponentBars(fighters)
	for other in pairs(opponentBars) do
		removeOpponentBar(other)
	end
	local iAmFighting = false
	for _, fighter in ipairs(fighters) do
		if fighter == player then
			iAmFighting = true
		end
	end
	if not iAmFighting then return end
	for _, fighter in ipairs(fighters) do
		addOpponentBar(fighter)
	end
end

Players.PlayerRemoving:Connect(removeOpponentBar)

RunService.RenderStepped:Connect(function()
	for other, bar in pairs(opponentBars) do
		local character = other.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local alive = humanoid ~= nil and humanoid.Health > 0
		bar.frame.Visible = alive
		if alive then
			local ratio = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
			bar.fill.Size = UDim2.fromScale(ratio, 1)
			if ratio > 0.5 then
				bar.fill.BackgroundColor3 = Color3.fromRGB(80, 220, 90)
			elseif ratio > 0.25 then
				bar.fill.BackgroundColor3 = Color3.fromRGB(230, 200, 60)
			else
				bar.fill.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
			end
		end
	end
end)

-- Ready button (bottom center): joins or leaves the match queue. The match starts once
-- Config.MatchSize players are ready.
local readyButton = Instance.new("TextButton")
readyButton.Name = "ReadyButton"
readyButton.Size = UDim2.fromOffset(180, 44)
readyButton.AnchorPoint = Vector2.new(0.5, 1)
readyButton.Position = UDim2.new(0.5, 0, 1, -16)
readyButton.Font = Enum.Font.GothamBold
readyButton.TextSize = 20
readyButton.TextColor3 = Color3.new(1, 1, 1)
readyButton.BorderSizePixel = 0
readyButton.Parent = gui

local isReady = false
local function setReadyLocal(value)
	isReady = value
	readyButton.Text = isReady and "UNREADY" or "READY"
	readyButton.BackgroundColor3 = isReady and Color3.fromRGB(60, 160, 80) or Color3.fromRGB(60, 60, 60)
end
setReadyLocal(false)

readyButton.Activated:Connect(function()
	setReadyLocal(not isReady)
	Remotes.Ready:FireServer(isReady)
end)
Remotes.ReadyState.OnClientEvent:Connect(setReadyLocal)

-- While set, this character is locked facing this Player (used during the match intro).
local facingTarget = nil

-- Restores the default follow camera on this player's current character.
local function restoreFollowCamera()
	camera.CameraType = Enum.CameraType.Custom
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		camera.CameraSubject = humanoid
	end
end

-- Round start duel intro: a side shot framing both fighters, about 12 studs from their midpoint.
-- The server freezes the fighters for the same time; this only moves the camera.
-- If this player's character dies or is replaced during the intro, the follow camera is restored at once.
local function playDuelIntro(fighters)
	local myCharacter = player.Character
	local myRoot = myCharacter and myCharacter:FindFirstChild("HumanoidRootPart")
	local otherPlayer = (fighters[1] == player) and fighters[2] or fighters[1]
	local otherRoot = otherPlayer and otherPlayer.Character and otherPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not (myRoot and otherRoot) then return end

	-- Lock this fighter facing the opponent for the intro (overrides Manual-mode aiming).
	facingTarget = otherPlayer
	camera.CameraType = Enum.CameraType.Scriptable

	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local aborted = player.Character ~= myCharacter or not humanoid or humanoid.Health <= 0
		if aborted or os.clock() - started >= Config.DuelIntroTime then
			connection:Disconnect()
			facingTarget = nil
			restoreFollowCamera()
			return
		end

		local between = Vector3.new(otherRoot.Position.X - myRoot.Position.X, 0, otherRoot.Position.Z - myRoot.Position.Z)
		if between.Magnitude < 0.01 then return end
		local mid = (myRoot.Position + otherRoot.Position) / 2
		local side = Vector3.yAxis:Cross(between.Unit)
		-- 11.5 sideways + 3.5 up: about 12 studs from the midpoint.
		camera.CFrame = CFrame.lookAt(mid + side * 11.5 + Vector3.new(0, 3.5, 0), mid + Vector3.new(0, 2, 0))
	end)
end

Remotes.MatchStart.OnClientEvent:Connect(function(fighters)
	setOpponentBars(fighters)
	for _, fighter in ipairs(fighters) do
		if fighter == player then
			task.spawn(playDuelIntro, fighters)
			return
		end
	end
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

	-- Match intro: hold the fighter facing the opponent, ignoring cursor aiming.
	if facingTarget then
		humanoid.AutoRotate = false
		local otherRoot = facingTarget.Character and facingTarget.Character:FindFirstChild("HumanoidRootPart")
		if otherRoot then
			local flat = Vector3.new(otherRoot.Position.X, root.Position.Y, otherRoot.Position.Z)
			if (flat - root.Position).Magnitude > 0.5 then
				root.CFrame = CFrame.lookAt(root.Position, flat)
			end
		end
		return
	end

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

-- Dash: the client drives its own character with a horizontal LinearVelocity for
-- Config.DashDuration seconds (the client owns its physics, so this stays smooth and
-- holding a movement key doesn't cancel it). The server is told to grant the dodge window.
local lastDash = -math.huge
local function startDash()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root and humanoid.Health > 0) then return end

	local now = os.clock()
	if now - lastDash < Config.DashCooldown then return end

	local dir = Vector3.new(humanoid.MoveDirection.X, 0, humanoid.MoveDirection.Z)
	if dir.Magnitude < 0.01 then
		dir = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	end
	if dir.Magnitude < 0.01 then return end
	dir = dir.Unit

	lastDash = now
	Remotes.Dash:FireServer()

	local attachment = Instance.new("Attachment")
	attachment.Parent = root

	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.VectorVelocity = dir * Config.DashSpeed
	velocity.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	velocity.MaxAxesForce = Vector3.new(1e5, 0, 1e5) -- horizontal only, so gravity still applies
	velocity.Parent = root

	task.delay(Config.DashDuration, function()
		velocity:Destroy()
		attachment:Destroy()
	end)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if mode == "Manual" then
			Remotes.Attack:FireServer(mode, cursorAim())
		else
			Remotes.Attack:FireServer(mode)
		end
	elseif input.KeyCode == Enum.KeyCode[Config.DashKey] then
		startDash()
	elseif input.KeyCode == Enum.KeyCode.F then
		Remotes.Parry:FireServer()
	elseif input.KeyCode == Enum.KeyCode.M then
		mode = (mode == "Simple") and "Manual" or "Simple"
		updateModeLabel()
	elseif input.KeyCode == Enum.KeyCode.Tab then
		board.Visible = not board.Visible
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
Remotes.Scores.OnClientEvent:Connect(renderScores)
