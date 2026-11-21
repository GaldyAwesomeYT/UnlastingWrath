-- Title menu: Play, Settings, Mode and Difficulty. Opens after the loading screen and again from
-- the MENU button. Play calls callbacks.onPlay with the chosen mode and difficulty.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local Menu = {}

local PANEL_COLOR = Color3.fromRGB(22, 22, 30)
local BUTTON_COLOR = Color3.fromRGB(58, 58, 70)
local PLAY_COLOR = Color3.fromRGB(60, 160, 80)
local ACCENT = Color3.fromRGB(255, 220, 60)
local MUTED = Color3.fromRGB(190, 190, 200)

local function makeLabel(text, order, parent, font, textSize, color)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextSize = textSize
	label.TextColor3 = color
	label.TextWrapped = true
	label.Text = text
	label.LayoutOrder = order
	label.Parent = parent
	return label
end

local function makeButton(text, order, parent, color)
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, 0, 0, 46)
	button.BackgroundColor3 = color or BUTTON_COLOR
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.TextSize = 18
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Text = text
	button.LayoutOrder = order
	button.AutoButtonColor = true
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button
	return button
end

-- A centered, phone-friendly column: 90% of the screen width, capped at 360px.
local function makePanel(name, parent)
	local panel = Instance.new("Frame")
	panel.Name = name
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.9, 0, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = parent

	local maxWidth = Instance.new("UISizeConstraint")
	maxWidth.MaxSize = Vector2.new(360, 10000)
	maxWidth.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 20)
	padding.PaddingBottom = UDim.new(0, 20)
	padding.PaddingLeft = UDim.new(0, 20)
	padding.PaddingRight = UDim.new(0, 20)
	padding.Parent = panel

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel
	return panel
end

-- callbacks = { onPlay = function(gameMode, difficulty) }
-- Returns { open = fn, close = fn, isOpen = fn }.
function Menu.start(callbacks)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screen = Instance.new("ScreenGui")
	screen.Name = "MainMenu"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 50
	screen.Parent = playerGui

	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.35
	backdrop.BorderSizePixel = 0
	backdrop.Parent = screen

	local mainPanel = makePanel("MainPanel", screen)
	local settingsPanel = makePanel("SettingsPanel", screen)

	-- Main page
	makeLabel("PARRY ARENA", 1, mainPanel, Enum.Font.GothamBlack, 36, ACCENT)
	makeLabel("First to " .. Config.KillsToWin .. " kills. Swing the blade with your mouse.", 2, mainPanel, Enum.Font.Gotham, 14, MUTED)
	local playButton = makeButton("PLAY", 3, mainPanel, PLAY_COLOR)
	local settingsButton = makeButton("SETTINGS", 4, mainPanel)
	local modeButton = makeButton("", 5, mainPanel)
	local difficultyButton = makeButton("", 6, mainPanel)
	local hint = makeLabel("", 7, mainPanel, Enum.Font.Gotham, 14, MUTED)

	local modeIndex = table.find(Config.GameModes, Config.DefaultGameMode) or 1
	local difficultyIndex = table.find(Config.DifficultyNames, Config.DefaultDifficulty) or 1

	local function selectedMode()
		return Config.GameModes[modeIndex]
	end

	local function selectedDifficulty()
		return Config.DifficultyNames[difficultyIndex]
	end

	local function refreshMain()
		modeButton.Text = "Mode: " .. selectedMode()
		difficultyButton.Text = "Difficulty: " .. selectedDifficulty()
		if selectedMode() == "Duel" then
			hint.Text = "Duel: press Ready in the game to queue for a 1v1 match. Difficulty doesn't apply."
		else
			hint.Text = "Training: fight your own dummy. Difficulty sets how tough it is."
		end
	end

	-- Settings page (information only: the controls are fixed)
	makeLabel("Settings", 1, settingsPanel, Enum.Font.GothamBlack, 28, ACCENT)
	makeLabel("Blade: the tip follows your mouse. Move the mouse fast to swing.", 2, settingsPanel, Enum.Font.Gotham, 14, MUTED)
	makeLabel("Slow, controlled swings do more damage to the head.", 3, settingsPanel, Enum.Font.Gotham, 14, MUTED)
	makeLabel("Clash blades to parry: the faster swing wins and stuns the slower one. Hold right mouse to guard.", 4, settingsPanel, Enum.Font.Gotham, 14, MUTED)
	makeLabel("WASD: move  -  Shift: dash  -  Tab: scoreboard", 5, settingsPanel, Enum.Font.Gotham, 14, MUTED)
	local backButton = makeButton("BACK", 6, settingsPanel)

	local function showPage(page)
		mainPanel.Visible = page == "main"
		settingsPanel.Visible = page == "settings"
	end

	local function open()
		refreshMain()
		showPage("main")
		screen.Enabled = true
	end

	local function close()
		screen.Enabled = false
	end

	modeButton.Activated:Connect(function()
		modeIndex = modeIndex % #Config.GameModes + 1
		refreshMain()
	end)
	difficultyButton.Activated:Connect(function()
		difficultyIndex = difficultyIndex % #Config.DifficultyNames + 1
		refreshMain()
	end)
	playButton.Activated:Connect(function()
		close()
		callbacks.onPlay(selectedMode(), selectedDifficulty())
	end)
	settingsButton.Activated:Connect(function()
		showPage("settings")
	end)
	backButton.Activated:Connect(function()
		showPage("main")
	end)

	open()
	return {
		open = open,
		close = close,
		isOpen = function()
			return screen.Enabled
		end,
	}
end

return Menu
