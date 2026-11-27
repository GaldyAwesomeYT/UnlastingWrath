-- Client entry point: input, cursor aiming, and combat HUD.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Menu = require(script.Parent.Menu)
local Weapon = require(script.Parent.Weapon)
local LockedCamera = require(script.Parent.LockedCamera)
local LockOn = require(script.Parent.LockOn)
local Controls = require(script.Parent.Controls)
local Leaderboard = require(script.Parent.Leaderboard)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Roblox's built-in player list opens on Tab, on top of the game's own leaderboard. Turn it off. The
-- core GUI may not be ready right at the start, so SetCoreGuiEnabled is retried for a few seconds.
task.spawn(function()
	local StarterGui = game:GetService("StarterGui")
	for _ = 1, 20 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
		end)
		if ok then return end
		task.wait(0.25)
	end
	warn("Couldn't turn off Roblox's player list; Tab may open it over the leaderboard.")
end)

-- Title menu handle, set at the end of this script. While the menu is open, gameplay input is ignored.
local menu

-- HUD
local gui = Instance.new("ScreenGui")
gui.Name = "CombatHUD"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local modeLabel = Instance.new("TextLabel")
modeLabel.Size = UDim2.fromOffset(460, 30)
modeLabel.Position = UDim2.fromOffset(16, 16)
modeLabel.BackgroundColor3 = Color3.new(0, 0, 0)
modeLabel.BackgroundTransparency = 0.5
modeLabel.TextColor3 = Color3.new(1, 1, 1)
modeLabel.Font = Enum.Font.GothamBold
modeLabel.TextSize = 18
modeLabel.TextXAlignment = Enum.TextXAlignment.Left
modeLabel.Parent = gui

-- MENU button (top-left, under the mode label): reopens the title menu.
local menuButton = Instance.new("TextButton")
menuButton.Name = "MenuButton"
menuButton.Size = UDim2.fromOffset(100, 30)
menuButton.Position = UDim2.fromOffset(16, 52)
menuButton.BackgroundColor3 = Color3.new(0, 0, 0)
menuButton.BackgroundTransparency = 0.5
menuButton.BorderSizePixel = 0
menuButton.Font = Enum.Font.GothamBold
menuButton.TextSize = 16
menuButton.TextColor3 = Color3.new(1, 1, 1)
menuButton.Text = "MENU"
menuButton.Parent = gui
menuButton.Activated:Connect(function()
	if menu then
		menu.open()
	end
end)

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
	Telegraph = { text = "GUARD!", color = Color3.fromRGB(255, 220, 60) },
	Parried = { text = "PARRIED!", color = Color3.fromRGB(80, 255, 120) },
	Stunned = { text = "STUNNED", color = Color3.fromRGB(255, 80, 80) },
	Hit = { text = "HIT", color = Color3.fromRGB(255, 255, 255) },
	Dodged = { text = "DODGE!", color = Color3.fromRGB(120, 200, 255) },
	Blocked = { text = "BLOCK", color = Color3.fromRGB(200, 200, 200) },
	Clash = { text = "CLASH!", color = Color3.fromRGB(255, 170, 60) },
	Weakened = { text = "WEAKENED", color = Color3.fromRGB(190, 110, 255) },
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

local function refreshModeLabel()
	modeLabel.Text = "  Mouse: swing blade  |  " .. Controls.label("Guard") .. ": guard  |  " .. Controls.label("Scoreboard") .. ": leaderboard"
end
refreshModeLabel()
Controls.onChanged(refreshModeLabel)

-- Leaderboard (the Scoreboard key): a fullscreen board with Server, Global and Regional tabs.
local leaderboard = Leaderboard.start()

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

-- Max-Clash bar (above the dash bar). The server sends the value through the character's "ClashBar"
-- attribute (0 to 1) and sets "Weakened" while the player is weakened, when the bar counts the time left down.
-- Hidden while empty.
local clashBack = Instance.new("Frame")
clashBack.Name = "ClashBack"
clashBack.Size = UDim2.fromOffset(260, 12)
clashBack.Position = UDim2.new(0, 16, 1, -116)
clashBack.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
clashBack.BorderSizePixel = 0
clashBack.Visible = false
clashBack.Parent = gui

local clashFill = Instance.new("Frame")
clashFill.Name = "Fill"
clashFill.Size = UDim2.fromScale(0, 1)
clashFill.BackgroundColor3 = Color3.fromRGB(255, 170, 60)
clashFill.BorderSizePixel = 0
clashFill.Parent = clashBack

local clashLabel = Instance.new("TextLabel")
clashLabel.Size = UDim2.fromScale(1, 1)
clashLabel.BackgroundTransparency = 1
clashLabel.Font = Enum.Font.GothamBold
clashLabel.TextSize = 11
clashLabel.TextColor3 = Color3.new(1, 1, 1)
clashLabel.Text = "MAX-CLASH"
clashLabel.Parent = clashBack

local function bindClash(character)
	local function update()
		local value = character:GetAttribute("ClashBar") or 0
		local weakened = character:GetAttribute("Weakened") == true
		clashBack.Visible = value > 0 or weakened
		clashFill.Size = UDim2.fromScale(math.clamp(value, 0, 1), 1)
		clashFill.BackgroundColor3 = weakened and Color3.fromRGB(190, 110, 255) or Color3.fromRGB(255, 170, 60)
		clashLabel.Text = weakened and "WEAKENED" or "MAX-CLASH"
	end
	character:GetAttributeChangedSignal("ClashBar"):Connect(update)
	character:GetAttributeChangedSignal("Weakened"):Connect(update)
	update()
end

if player.Character then
	bindClash(player.Character)
end
player.CharacterAdded:Connect(bindClash)

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
readyButton.Visible = false -- shown after Play in Duel mode (see the title menu's onPlay below)

-- The button shows in Duel mode, except while this player is fighting in a match.
local duelMode, inMatch = false, false
local function refreshReadyVisible()
	readyButton.Visible = duelMode and not inMatch
end

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

-- Round start duel intro. The server freezes both fighters for the total of the Config.Duel*
-- times; this only moves the camera. Shot order:
--   1. wide, level, side-on shot of both fighters
--   2. close on fighter A's midsection and hands
--   3. close on fighter B's midsection and hands
--   4. wide shot again
--   5. pan from the wide shot to this player's normal follow view
-- If this player's character dies or is replaced during the intro, the follow camera is restored at once.
local function smoothstep(t)
	return t * t * (3 - 2 * t)
end

local function rootOf(p)
	return p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
end

local function playDuelIntro(fighters)
	local myCharacter = player.Character
	local myRoot = rootOf(player)
	local rootA, rootB = rootOf(fighters[1]), rootOf(fighters[2])
	if not (myRoot and rootA and rootB) then return end

	-- Lock this fighter facing the opponent for the intro.
	local otherPlayer = (fighters[1] == player) and fighters[2] or fighters[1]
	facingTarget = otherPlayer
	camera.CameraType = Enum.CameraType.Scriptable

	local function isAborted()
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		return player.Character ~= myCharacter or not humanoid or humanoid.Health <= 0
	end

	-- The camera side: the same side for every shot, so the cuts stay on one axis.
	local function cameraSide()
		local between = Vector3.new(rootB.Position.X - rootA.Position.X, 0, rootB.Position.Z - rootA.Position.Z)
		if between.Magnitude < 0.01 then
			return Vector3.new(1, 0, 0)
		end
		return Vector3.yAxis:Cross(between.Unit)
	end

	-- Level, side-on wide shot of both fighters, about 12 studs from their midpoint.
	local function wideShot()
		local mid = (rootA.Position + rootB.Position) / 2
		return CFrame.lookAt(mid + cameraSide() * 12, mid)
	end

	-- Diagonal close shot on one fighter's midsection: from the camera side and partly in front
	-- (about 45 degrees), so the hands and any weapon at the hip are in frame.
	local function closeShot(fighterRoot)
		local look = Vector3.new(fighterRoot.CFrame.LookVector.X, 0, fighterRoot.CFrame.LookVector.Z)
		if look.Magnitude < 0.01 then
			look = Vector3.new(0, 0, 1)
		end
		local offset = (look.Unit * 0.7 + cameraSide() * 0.7) * 4.5
		local focus = fighterRoot.Position
		return CFrame.lookAt(focus + offset + Vector3.new(0, 0.5, 0), focus + Vector3.new(0, -0.3, 0))
	end

	-- Plays one shot for `duration` seconds. cframeFn receives progress 0 → 1.
	-- Returns false if the character died or was replaced.
	local function runShot(duration, cframeFn)
		local started = os.clock()
		while true do
			if isAborted() then return false end
			local alpha = math.clamp((os.clock() - started) / duration, 0, 1)
			camera.CFrame = cframeFn(alpha)
			if alpha >= 1 then return true end
			RunService.RenderStepped:Wait()
		end
	end

	local completed = runShot(Config.DuelWideTime, wideShot)
		and runShot(Config.DuelCloseTime, function() return closeShot(rootA) end)
		and runShot(Config.DuelCloseTime, function() return closeShot(rootB) end)
		and runShot(Config.DuelReturnTime, wideShot)

	if completed then
		local wideEnd = wideShot()
		-- Normal Roblox follow view: a little behind and above this player's character.
		local follow = CFrame.lookAt(
			myRoot.Position - myRoot.CFrame.LookVector * 8 + Vector3.new(0, 3, 0),
			myRoot.Position + Vector3.new(0, 1.5, 0)
		)
		runShot(Config.DuelPanTime, function(alpha)
			return wideEnd:Lerp(follow, smoothstep(alpha))
		end)
	end

	facingTarget = nil
	restoreFollowCamera()
end

Remotes.MatchStart.OnClientEvent:Connect(function(fighters)
	setOpponentBars(fighters)
	LockOn.setFighters(fighters)
	inMatch = false
	for _, fighter in ipairs(fighters) do
		if fighter == player then
			inMatch = true
			break
		end
	end
	refreshReadyVisible()
	if inMatch then
		task.spawn(playDuelIntro, fighters)
	end
end)

-- Body facing: the character turns toward its movement (Roblox default). The duel intro overrides it.
RunService.RenderStepped:Connect(function(dt)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	-- A finished look-around asks the body to turn to where the camera was looking. Only the free-facing
	-- code at the end uses it; everywhere else it is dropped (lock-on, the intro and default mode set their own facing).
	local lookTurn = Weapon.takeLookTurn()
	if not (humanoid and root and humanoid.Health > 0) then
		LockOn.update(nil, false) -- hides the marker
		return
	end

	-- Match intro: hold the fighter facing the opponent, ignoring cursor aiming.
	if facingTarget then
		LockOn.update(root, false) -- hides the lock-on marker during the intro
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

	-- Blade sheathed: normal Roblox movement, the body turns toward where it walks.
	if Weapon.isDefaultMode() then
		LockOn.update(root, false)
		humanoid.AutoRotate = true
		return
	end

	-- Lock-on: the body faces the opponent, so A and D strafe around them and the camera stays on them.
	-- While looking around (right mouse) or with the cursor free, the body holds still.
	local lockedRoot = LockOn.update(root, true)
	Weapon.setLockedOn(lockedRoot ~= nil)
	if lockedRoot then
		humanoid.AutoRotate = false
		if not (Weapon.isLooking() or Weapon.isFree()) then
			local toTarget = lockedRoot.Position - root.Position
			toTarget = Vector3.new(toTarget.X, 0, toTarget.Z)
			if toTarget.Magnitude > 0.5 then -- too close to tell which way is "toward"
				local goal = CFrame.lookAt(root.Position, root.Position + toTarget)
				local alpha = math.min(1, dt * Config.LockOnTurnSpeed)
				root.CFrame = root.CFrame.Rotation:Lerp(goal.Rotation, alpha) + root.Position
			end
		end
		return
	end

	-- No lock-on: the body never turns toward its movement. The camera is locked to the body's facing and
	-- movement is relative to the camera, so turning toward a move (S, or A and D pivoting) would swing the
	-- camera and flip the move direction every frame. A, D, S and W all walk without turning, and the
	-- body's orientation follows where the player looks: hold right mouse to look around, and on release
	-- the body turns to face that way. The camera is behind the body again, so the view doesn't jump.
	humanoid.AutoRotate = false
	if lookTurn ~= 0 then
		root.CFrame = root.CFrame * CFrame.Angles(0, -lookTurn, 0) -- yaw to the right is a negative turn about Y
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

-- Dash cooldown indicator (bottom-left, under the stun bar). Fills as the cooldown recovers,
-- and is bright when the dash is ready. Uses the same lastDash clock as startDash.
local dashBack = Instance.new("Frame")
dashBack.Name = "DashCooldownBack"
dashBack.Size = UDim2.fromOffset(260, 10)
dashBack.Position = UDim2.new(0, 16, 1, -92)
dashBack.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
dashBack.BorderSizePixel = 0
dashBack.Parent = gui

local dashFill = Instance.new("Frame")
dashFill.Name = "Fill"
dashFill.Size = UDim2.fromScale(1, 1)
dashFill.BorderSizePixel = 0
dashFill.Parent = dashBack

local dashLabel = Instance.new("TextLabel")
dashLabel.Size = UDim2.fromScale(1, 1)
dashLabel.BackgroundTransparency = 1
dashLabel.Font = Enum.Font.GothamBold
dashLabel.TextSize = 12
dashLabel.TextColor3 = Color3.new(1, 1, 1)
dashLabel.Text = "DASH"
dashLabel.Parent = dashBack

RunService.RenderStepped:Connect(function()
	local remaining = Config.DashCooldown - (os.clock() - lastDash)
	if remaining <= 0 then
		dashFill.Size = UDim2.fromScale(1, 1)
		dashFill.BackgroundColor3 = Color3.fromRGB(120, 200, 255)
	else
		dashFill.Size = UDim2.fromScale(math.clamp(1 - remaining / Config.DashCooldown, 0, 1), 1)
		dashFill.BackgroundColor3 = Color3.fromRGB(70, 90, 110)
	end
end)

-- Blade swings need no click: the blade follows the mouse (Weapon.luau). F guards; holding right mouse looks around.
-- Holding Left Alt frees the cursor and locks gameplay input (no dash, no guard) until it's released.
local guardHeld = false
local function setGuard(held)
	guardHeld = held
	Weapon.setGuard(held)
	Remotes.Block:FireServer(held)
end

UserInputService.InputBegan:Connect(function(input, processed)
	-- Esc closes the leaderboard (Roblox may mark Esc as handled, so this comes before the processed check).
	if input.KeyCode == Enum.KeyCode.Escape and leaderboard.isOpen() then
		leaderboard.close()
		return
	end
	if processed or (menu and menu.isOpen()) then return end

	-- The keys are this player's own bindings (Controls), set on the Controls page of the menu.
	-- The leaderboard key opens and closes the fullscreen board. While it is open, nothing else is read.
	if Controls.matches("Scoreboard", input) then
		leaderboard.toggle()
		return
	end
	if leaderboard.isOpen() then return end

	if Controls.matches("FreeCursor", input) then
		Weapon.setFreeKey(true)
		if guardHeld then
			setGuard(false) -- dropping the guard when the cursor frees
		end
		return
	end

	if Weapon.isFree() then return end -- locked while the cursor is free

	if Controls.matches("Dash", input) then
		startDash()
	elseif Controls.matches("Sheathe", input) then
		if Weapon.toggleSheathe() and guardHeld then
			setGuard(false) -- sheathing drops the guard
		end
	elseif Controls.matches("LockOn", input) then
		LockOn.toggle()
	elseif Controls.matches("Guard", input) then
		if not Weapon.isSheathed() then
			setGuard(true)
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if Controls.matches("FreeCursor", input) then
		Weapon.setFreeKey(false)
	elseif Controls.matches("Guard", input) then
		setGuard(false) -- always release, even while the cursor is free
	end
end)

-- The mouse is free (and the blade and body hold still) while the title menu or the leaderboard is open.
Weapon.start(function()
	return (menu ~= nil and menu.isOpen()) or leaderboard.isOpen()
end)
LockedCamera.start(function()
	return facingTarget ~= nil -- the duel intro moves the camera itself
end, Weapon.getLook, Weapon.isDefaultMode)

Remotes.Feedback.OnClientEvent:Connect(function(kind, duration)
	showFeedback(kind)
	if kind == "Stunned" and type(duration) == "number" then
		startStun(duration)
	end
end)
Remotes.Round.OnClientEvent:Connect(function(message)
	statusLabel.Text = message
end)
Remotes.Scores.OnClientEvent:Connect(leaderboard.setServerScores)
Remotes.ScoresRequest:FireServer() -- get the current scores now, so the Server board isn't empty before the first match

-- Title menu (opens right away; the loading screen covers it until the game has loaded).
menu = Menu.start({
	onPlay = function(gameMode, difficulty)
		-- A fighter can't change mode mid-match (the server ignores it too), so don't let the UI drift from the server.
		if inMatch then return end
		-- Duel uses the Ready queue. Training doesn't, so the Ready button is hidden there.
		duelMode = gameMode == "Duel"
		refreshReadyVisible()
		if gameMode ~= "Duel" then
			setReadyLocal(false)
		end
		Remotes.Options:FireServer(gameMode, difficulty)
	end,
})
