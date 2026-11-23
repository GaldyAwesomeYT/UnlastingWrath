-- Fullscreen leaderboard, opened and closed with the player's Scoreboard key (Main.client.luau calls
-- toggle). While it is open the mouse is free (Main.client passes isOpen to Weapon) so the tabs can be
-- clicked. Three boards:
--   Server    this server's kills in the current match (pushed by the server through setServerScores)
--   Global    all-time kills, every server
--   Regional  all-time kills among players from the player's own country or region
-- Global and Regional are asked for from the server each time they are opened or selected.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Leaderboard = {}

local ACCENT = Color3.fromRGB(255, 220, 60)
local PANEL_COLOR = Color3.fromRGB(22, 22, 30)
local BUTTON_COLOR = Color3.fromRGB(58, 58, 70)
local MUTED = Color3.fromRGB(190, 190, 200)
local ME_COLOR = Color3.fromRGB(70, 110, 170) -- highlight for the local player's row

local TABS = { "Server", "Global", "Regional" }

-- Builds the screen. Returns { toggle, close, isOpen, setServerScores }.
function Leaderboard.start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screen = Instance.new("ScreenGui")
	screen.Name = "Leaderboard"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 40 -- under the title menu (50), over the game HUD
	screen.Enabled = false
	screen.Parent = playerGui

	-- Dark full-screen backdrop. Active, so clicks on it don't reach the game.
	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.25
	backdrop.BorderSizePixel = 0
	backdrop.Active = true
	backdrop.Parent = screen

	-- The content column: centered, up to 560px wide, filling the height.
	local column = Instance.new("Frame")
	column.AnchorPoint = Vector2.new(0.5, 0.5)
	column.Position = UDim2.fromScale(0.5, 0.5)
	column.Size = UDim2.new(0.92, 0, 0.9, 0)
	column.BackgroundTransparency = 1
	column.Parent = backdrop
	local widthLimit = Instance.new("UISizeConstraint")
	widthLimit.MaxSize = Vector2.new(560, 10000)
	widthLimit.Parent = column

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = column

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 44)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 34
	title.TextColor3 = ACCENT
	title.Text = "LEADERBOARD"
	title.LayoutOrder = 1
	title.Parent = column

	-- Tab buttons in a row.
	local tabRow = Instance.new("Frame")
	tabRow.Size = UDim2.new(1, 0, 0, 40)
	tabRow.BackgroundTransparency = 1
	tabRow.LayoutOrder = 2
	tabRow.Parent = column
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 8)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabRow

	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.new(1, 0, 0, 22)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextSize = 15
	subtitle.TextColor3 = MUTED
	subtitle.Text = ""
	subtitle.LayoutOrder = 3
	subtitle.Parent = column

	-- The list panel takes the rest of the column; it scrolls when there are many rows.
	local listPanel = Instance.new("Frame")
	listPanel.Size = UDim2.new(1, 0, 1, -170)
	listPanel.BackgroundColor3 = PANEL_COLOR
	listPanel.BackgroundTransparency = 0.1
	listPanel.BorderSizePixel = 0
	listPanel.LayoutOrder = 4
	listPanel.Parent = column
	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 10)
	panelCorner.Parent = listPanel

	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.new(1, -16, 1, -16)
	list.Position = UDim2.fromOffset(8, 8)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = listPanel
	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 4)
	listLayout.Parent = list

	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(1, 0, 0, 22)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 14
	hint.TextColor3 = MUTED
	hint.Text = "Press the scoreboard key or Esc to close"
	hint.LayoutOrder = 5
	hint.Parent = column

	local current = "Server"
	local serverRows = {}
	local tabButtons = {}

	local function clearList()
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	local function addLine(text, order, color, font, highlight)
		local row = Instance.new("TextLabel")
		row.Size = UDim2.new(1, -8, 0, 30)
		row.BackgroundColor3 = ME_COLOR
		row.BackgroundTransparency = highlight and 0.3 or 1
		row.BorderSizePixel = 0
		row.Font = font or Enum.Font.GothamBold
		row.TextSize = 18
		row.TextColor3 = color or Color3.new(1, 1, 1)
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.Text = "  " .. text
		row.LayoutOrder = order
		row.Parent = list
		return row
	end

	-- Fills the list with "1. Name ... kills" rows, or a message if there are none.
	local function showRows(rows, emptyText)
		clearList()
		if not rows or #rows == 0 then
			addLine(emptyText, 1, MUTED, Enum.Font.Gotham)
			return
		end
		for i, entry in ipairs(rows) do
			local label = addLine(i .. ".  " .. entry.name, i, nil, nil, entry.name == player.Name)
			local count = Instance.new("TextLabel")
			count.Size = UDim2.new(0, 120, 1, 0)
			count.Position = UDim2.new(1, -130, 0, 0)
			count.BackgroundTransparency = 1
			count.Font = Enum.Font.GothamBold
			count.TextSize = 18
			count.TextColor3 = ACCENT
			count.TextXAlignment = Enum.TextXAlignment.Right
			count.Text = tostring(entry.kills) .. (entry.kills == 1 and " kill" or " kills")
			count.Parent = label
		end
	end

	local function showTab()
		for _, name in ipairs(TABS) do
			local button = tabButtons[name]
			button.BackgroundColor3 = name == current and ACCENT or BUTTON_COLOR
			button.TextColor3 = name == current and Color3.new(0, 0, 0) or Color3.new(1, 1, 1)
		end
		if current == "Server" then
			subtitle.Text = "This server - kills this match (first to " .. Config.KillsToWin .. ")"
			showRows(serverRows, "No players yet.")
		elseif current == "Global" then
			subtitle.Text = "All-time kills, every server"
			clearList()
			addLine("Loading...", 1, MUTED, Enum.Font.Gotham)
		else
			subtitle.Text = "All-time kills in your region"
			clearList()
			addLine("Loading...", 1, MUTED, Enum.Font.Gotham)
		end
	end

	-- Shows `kind` and, for the all-time boards, asks the server for its rows.
	local function chooseTab(kind)
		current = kind
		showTab()
		if kind == "Server" then
			Remotes.ScoresRequest:FireServer()
		else
			Remotes.Leaderboard:FireServer(kind)
		end
	end

	for i, name in ipairs(TABS) do
		local button = Instance.new("TextButton")
		button.Size = UDim2.new(1 / #TABS, -6, 1, 0)
		button.BorderSizePixel = 0
		button.Font = Enum.Font.GothamBold
		button.TextSize = 17
		button.Text = string.upper(name)
		button.LayoutOrder = i
		button.AutoButtonColor = true
		button.Parent = tabRow
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = button
		tabButtons[name] = button
		button.Activated:Connect(function()
			chooseTab(name)
		end)
	end

	-- Answer to a Global or Regional request. Ignored if the player has switched to another tab since.
	Remotes.Leaderboard.OnClientEvent:Connect(function(kind, rows, region)
		if kind ~= current then return end
		if kind == "Regional" then
			subtitle.Text = region and ("All-time kills in your region (" .. region .. ")") or "All-time kills in your region"
		end
		if rows == nil then
			showRows(nil, "Couldn't load this board. Try again in a moment.")
		else
			showRows(rows, "No kills recorded yet.")
		end
	end)

	local api = {}

	function api.isOpen()
		return screen.Enabled
	end

	function api.close()
		screen.Enabled = false
	end

	function api.toggle()
		if screen.Enabled then
			screen.Enabled = false
		else
			screen.Enabled = true
			chooseTab(current) -- fresh data for whichever tab was last used
		end
	end

	-- The server board's rows: { { name = string, kills = number } }, highest first.
	function api.setServerScores(rows)
		serverRows = rows
		if current == "Server" then
			showTab()
		end
	end

	showTab()
	return api
end

return Leaderboard
