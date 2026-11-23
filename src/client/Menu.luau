-- Title menu: Play, Settings, Mode and Difficulty. Opens after the loading screen and again from
-- the MENU button. Play calls callbacks.onPlay with the chosen mode and difficulty.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Config = require(ReplicatedStorage.Shared.Config)
local ControlActions = require(ReplicatedStorage.Shared.ControlActions)
local Controls = require(script.Parent.Controls)

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
	local controlsPanel = makePanel("ControlsPanel", screen)

	-- Main page
	makeLabel("PARRY ARENA", 1, mainPanel, Enum.Font.GothamBlack, 36, ACCENT)
	makeLabel("First to " .. Config.KillsToWin .. " kills. Swing the blade with your mouse.", 2, mainPanel, Enum.Font.Gotham, 14, MUTED)
	local playButton = makeButton("PLAY", 3, mainPanel, PLAY_COLOR)
	local settingsButton = makeButton("SETTINGS", 4, mainPanel)
	local controlsButton = makeButton("CONTROLS", 5, mainPanel)
	local modeButton = makeButton("", 6, mainPanel)
	local difficultyButton = makeButton("", 7, mainPanel)
	local hint = makeLabel("", 8, mainPanel, Enum.Font.Gotham, 14, MUTED)

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

	-- Settings page: how to play (information only). The key names follow the player's own bindings.
	makeLabel("Settings", 1, settingsPanel, Enum.Font.GothamBlack, 28, ACCENT)
	makeLabel("Blade: the tip follows your mouse. Move the mouse fast to swing.", 2, settingsPanel, Enum.Font.Gotham, 14, MUTED)
	makeLabel("Damage depends on where the blade hits: head hurts most, limbs least. The blade must be moving.", 3, settingsPanel, Enum.Font.Gotham, 14, MUTED)
	local guardHelp = makeLabel("", 4, settingsPanel, Enum.Font.Gotham, 14, MUTED)
	local lockHelp = makeLabel("", 5, settingsPanel, Enum.Font.Gotham, 14, MUTED)
	local sheatheHelp = makeLabel("", 6, settingsPanel, Enum.Font.Gotham, 14, MUTED)
	local quickHelp = makeLabel("", 7, settingsPanel, Enum.Font.Gotham, 14, MUTED)
	local keysHelp = makeLabel("", 8, settingsPanel, Enum.Font.Gotham, 14, MUTED)
	local backButton = makeButton("BACK", 9, settingsPanel)

	local function refreshHelp()
		guardHelp.Text = "Clash blades to parry: the faster swing wins and stuns the slower one. Hold " .. Controls.label("Guard") .. " to guard."
		lockHelp.Text = Controls.label("LockOn") .. ": lock on to your opponent (A and D then strafe around them). Hold " .. Controls.label("Look") .. " to look around."
		sheatheHelp.Text = Controls.label("Sheathe") .. ": sheathe or draw the blade. Sheathed, you move like a normal Roblox player."
		quickHelp.Text = "Quick draw: sheathed, hold " .. Controls.label("QuickDraw") .. " and swing the mouse right, up or down to slash out of the sheath."
		keysHelp.Text = "WASD: move  -  " .. Controls.label("Dash") .. ": dash  -  " .. Controls.label("Scoreboard")
			.. ": scoreboard  -  " .. Controls.label("FreeCursor") .. ": free the cursor"
	end

	-- Controls page: one row per move, showing its key. Click a row, then press the key or mouse button to
	-- use. Esc cancels. A key another move already uses is swapped over to it. Saved per player.
	makeLabel("Controls", 1, controlsPanel, Enum.Font.GothamBlack, 28, ACCENT)
	makeLabel("Click a move, then press the key or mouse button you want. Esc cancels. W, A, S, D and Space can't be used.", 2, controlsPanel, Enum.Font.Gotham, 14, MUTED)

	local capturing = nil -- the move id being rebound, or nil
	local captureConnection = nil
	local controlButtons = {} -- [move id] = its button

	local function refreshControls()
		for _, action in ipairs(ControlActions.list) do
			local button = controlButtons[action.id]
			button.Text = capturing == action.id and "Press a key..." or Controls.label(action.id)
			button.BackgroundColor3 = capturing == action.id and ACCENT or BUTTON_COLOR
			button.TextColor3 = capturing == action.id and Color3.new(0, 0, 0) or Color3.new(1, 1, 1)
		end
	end

	local function stopCapture()
		if captureConnection then
			captureConnection:Disconnect()
			captureConnection = nil
		end
		capturing = nil
		refreshControls()
	end

	local function startCapture(id)
		stopCapture()
		capturing = id
		refreshControls()
		captureConnection = UserInputService.InputBegan:Connect(function(input, processed)
			local binding = nil
			if input.UserInputType == Enum.UserInputType.Keyboard then
				if input.KeyCode == Enum.KeyCode.Escape then
					stopCapture()
					return
				end
				binding = Controls.bindingForKey(input.KeyCode)
				if not binding then
					controlButtons[id].Text = "Can't use that key"
					return
				end
			elseif input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.MouseButton2
				or input.UserInputType == Enum.UserInputType.MouseButton3 then
				-- A click on a menu button isn't a binding (it picks another move to rebind).
				if processed then return end
				binding = Controls.bindingForMouse(input)
			else
				return
			end
			if binding then
				local moveId = capturing
				stopCapture()
				Controls.set(moveId, binding)
			end
		end)
	end

	for i, action in ipairs(ControlActions.list) do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 36)
		row.BackgroundTransparency = 1
		row.LayoutOrder = 2 + i
		row.Parent = controlsPanel

		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(0.55, 0, 1, 0)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.Gotham
		name.TextSize = 15
		name.TextColor3 = Color3.new(1, 1, 1)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Text = action.label
		name.Parent = row

		local button = Instance.new("TextButton")
		button.Size = UDim2.new(0.43, 0, 1, 0)
		button.Position = UDim2.fromScale(0.57, 0)
		button.BackgroundColor3 = BUTTON_COLOR
		button.BorderSizePixel = 0
		button.Font = Enum.Font.GothamBold
		button.TextSize = 15
		button.TextColor3 = Color3.new(1, 1, 1)
		button.AutoButtonColor = true
		button.Parent = row
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = button
		controlButtons[action.id] = button

		-- Activated fires when the click is released, after its press has already passed the capture.
		button.Activated:Connect(function()
			startCapture(action.id)
		end)
	end
	local resetButton = makeButton("RESET TO DEFAULTS", 3 + #ControlActions.list, controlsPanel)
	local controlsBackButton = makeButton("BACK", 4 + #ControlActions.list, controlsPanel)

	Controls.onChanged(function()
		refreshHelp()
		refreshControls()
	end)
	refreshHelp()
	refreshControls()

	local function showPage(page)
		if page ~= "controls" then
			stopCapture()
		end
		mainPanel.Visible = page == "main"
		settingsPanel.Visible = page == "settings"
		controlsPanel.Visible = page == "controls"
	end

	local function open()
		refreshMain()
		showPage("main")
		screen.Enabled = true
	end

	local function close()
		stopCapture()
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
	controlsButton.Activated:Connect(function()
		showPage("controls")
	end)
	controlsBackButton.Activated:Connect(function()
		showPage("main")
	end)
	resetButton.Activated:Connect(function()
		stopCapture()
		Controls.resetAll()
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
