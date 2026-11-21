-- Loading screen: replaces Roblox's default loading screen (ReplicatedFirst runs before the rest
-- of the game). The bar fills over MIN_TIME seconds and waits at 95% until the game reports it has
-- loaded, then the screen fades out and the title menu takes over.
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local MIN_TIME = 2 -- seconds the bar takes to fill, even if the game loads sooner
local TIPS = {
	"Clash blades with an opponent to parry. The faster swing wins.",
	"Hold right mouse to guard and take less damage.",
	"Dash with Shift to dodge an incoming attack.",
	"Slow, controlled swings do more damage to the head.",
}
local ACCENT = Color3.fromRGB(255, 220, 60)

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100
gui.Parent = playerGui

local background = Instance.new("Frame")
background.Size = UDim2.fromScale(1, 1)
background.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
background.BorderSizePixel = 0
background.Parent = gui

local function makeText(text, anchorY, size, font, textSize, color)
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, anchorY)
	label.Size = size
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextSize = textSize
	label.TextColor3 = color
	label.TextWrapped = true
	label.Text = text
	label.Parent = gui
	return label
end

local title = makeText("PARRY ARENA", 0.4, UDim2.new(0.9, 0, 0, 60), Enum.Font.GothamBlack, 44, ACCENT)
local tip = makeText(TIPS[math.random(#TIPS)], 0.5, UDim2.new(0.9, 0, 0, 44), Enum.Font.Gotham, 16, Color3.new(1, 1, 1))
local barBack = Instance.new("Frame")
barBack.AnchorPoint = Vector2.new(0.5, 0.5)
barBack.Position = UDim2.fromScale(0.5, 0.6)
barBack.Size = UDim2.new(0.6, 0, 0, 8)
barBack.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
barBack.BorderSizePixel = 0
barBack.Parent = gui

local barMax = Instance.new("UISizeConstraint")
barMax.MaxSize = Vector2.new(320, 8)
barMax.Parent = barBack

local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = ACCENT
fill.BorderSizePixel = 0
fill.Parent = barBack

local status = makeText("Loading...", 0.66, UDim2.new(0.9, 0, 0, 24), Enum.Font.Gotham, 14, Color3.fromRGB(170, 170, 180))

local function fadeOut()
	local info = TweenInfo.new(0.5)
	TweenService:Create(background, info, { BackgroundTransparency = 1 }):Play()
	for _, label in ipairs({ title, tip, status }) do
		TweenService:Create(label, info, { TextTransparency = 1 }):Play()
	end
	for _, frame in ipairs({ barBack, fill }) do
		TweenService:Create(frame, info, { BackgroundTransparency = 1 }):Play()
	end
	task.wait(0.5)
	gui:Destroy()
end

local started = os.clock()
while true do
	local elapsed = os.clock() - started
	local loaded = game:IsLoaded()
	if loaded and elapsed >= MIN_TIME then
		break
	end
	local cap = loaded and 1 or 0.95 -- hold at 95% until the game has actually loaded
	fill.Size = UDim2.fromScale(math.min(elapsed / MIN_TIME, cap), 1)
	task.wait(0.05)
end

fill.Size = UDim2.fromScale(1, 1)
status.Text = "Ready"
task.wait(0.2)
fadeOut()
