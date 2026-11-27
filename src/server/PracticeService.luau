-- Practice mode: a prompt in front of each bamboo stand in the lobby (the "Stand<N>_Bamboo_Node" models in
-- Workspace.JapaneseLobby). Pressing it (a ProximityPrompt) puts the player in practice mode at that stand: the server sets the
-- "Practicing" player attribute, which makes that player's client hide everyone else (see client Practice.luau),
-- and moves the player in front of the bamboo log. A moving blade that touches the log cuts it (the log sways,
-- chips fly, the player sees "CUT!"). The player leaves with the Exit Practice button on screen.
-- One player per stand: the stand's button is switched off while it is taken.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RoundState = require(script.Parent.RoundState)
local CombatService = require(script.Parent.CombatService)

local PracticeService = {}

local stands = {} -- list of { log, prompt, spot, fx, occupant, lastCut, swaying }
local byPlayer = {} -- [Player] = the stand they practice at

local SWAY_OUT = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SWAY_BACK = TweenInfo.new(0.45, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
local BLADE_SAMPLES = 10

local function isAlive(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and character:FindFirstChild("HumanoidRootPart") ~= nil
end

-- Distance from a world point to the surface of a part's box (0 if inside).
local function distanceToPart(part, point)
	local local_ = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2
	local outside = Vector3.new(
		math.max(math.abs(local_.X) - half.X, 0),
		math.max(math.abs(local_.Y) - half.Y, 0),
		math.max(math.abs(local_.Z) - half.Z, 0)
	)
	return outside.Magnitude
end

function PracticeService.isPracticing(player)
	return byPlayer[player] ~= nil
end

-- Leaves practice mode (a no-op if the player isn't in it) and frees the stand.
function PracticeService.stop(player)
	local stand = byPlayer[player]
	if not stand then return end
	byPlayer[player] = nil
	stand.occupant = nil
	stand.prompt.Enabled = true
	player:SetAttribute("Practicing", nil)
end

local function start(player, stand)
	if byPlayer[player] or stand.occupant then return end
	if RoundState.active and RoundState.fighters[player] then return end -- no practice mid-match
	local character = player.Character
	if not isAlive(character) then return end

	byPlayer[player] = stand
	stand.occupant = player
	stand.prompt.Enabled = false
	player:SetAttribute("Practicing", true)
	character.HumanoidRootPart.CFrame = stand.spot
end

-- The log wobbles away from the player, pivoting at its foot, then settles back.
local function sway(stand, awayDirection)
	if stand.swaying then return end
	stand.swaying = true
	local log = stand.log
	local home = log.CFrame
	local foot = home.Position - home.UpVector * (log.Size.Y / 2)
	local axis = Vector3.yAxis:Cross(awayDirection) -- rotating about this moves the top toward `awayDirection`
	local tilted = CFrame.new(foot) * CFrame.fromAxisAngle(axis, math.rad(Config.PracticeSwayDegrees)) * CFrame.new(-foot) * home
	local out = TweenService:Create(log, SWAY_OUT, { CFrame = tilted })
	out.Completed:Once(function()
		local back = TweenService:Create(log, SWAY_BACK, { CFrame = home })
		back.Completed:Once(function()
			log.CFrame = home
			stand.swaying = false
		end)
		back:Play()
	end)
	out:Play()
end

-- Every heartbeat: a practicing player's moving blade that reaches their log cuts it.
local function checkCuts()
	local now = os.clock()
	for _, stand in ipairs(stands) do
		local player = stand.occupant
		local character = player and player.Character
		if character and isAlive(character) and now - stand.lastCut >= Config.PracticeCutCooldown then
			local base, tip, speed = CombatService.getBlade(character)
			if base and speed >= Config.HitMinSpeed then
				local bestPoint, bestDist = nil, Config.BladeThickness
				for i = 0, BLADE_SAMPLES do
					local point = base:Lerp(tip, i / BLADE_SAMPLES)
					local d = distanceToPart(stand.log, point)
					if d <= bestDist then
						bestPoint, bestDist = point, d
					end
				end
				if bestPoint then
					stand.lastCut = now
					Remotes.Feedback:FireClient(player, "Cut")
					stand.fx.WorldPosition = bestPoint
					stand.fxEmitter:Emit(12)
					local away = stand.log.Position - character.HumanoidRootPart.Position
					away = Vector3.new(away.X, 0, away.Z)
					sway(stand, away.Magnitude > 0.01 and away.Unit or Vector3.zAxis)
				end
			end
		end
	end
end

-- The "button" is just a ProximityPrompt, no physical part: it sits on an invisible Attachment inside the
-- stand's log, in front of the stand (toward the lobby entrance, +z) at chest height.
local function buildPrompt(number, log, floorY)
	local attachment = Instance.new("Attachment")
	attachment.Name = "PracticePromptPoint"
	attachment.Parent = log
	attachment.WorldPosition = Vector3.new(log.Position.X, floorY + 3, log.Position.Z + Config.PracticeButtonDistance)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = "Bamboo Stand " .. number
	prompt.ActionText = "Practice"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = attachment
	return prompt
end

local function buildStand(node, number)
	local log = node:FindFirstChildWhichIsA("BasePart", true)
	if not log then return end

	-- The floor height in front of the stand.
	local origin = Vector3.new(log.Position.X, log.Position.Y + 3, log.Position.Z + Config.PracticeButtonDistance)
	local hit = workspace:Raycast(origin, Vector3.new(0, -20, 0))
	local floorY = hit and hit.Position.Y or (log.Position.Y - log.Size.Y / 2)

	local prompt = buildPrompt(number, log, floorY)

	-- Where the player stands while practicing: in front of the log, facing it.
	local standPoint = Vector3.new(log.Position.X, floorY + 3.1, log.Position.Z + Config.PracticeStandDistance)
	local spot = CFrame.lookAt(standPoint, Vector3.new(log.Position.X, standPoint.Y, log.Position.Z))

	-- Chips that fly off when the log is cut.
	local fx = Instance.new("Attachment")
	fx.Name = "CutFX"
	fx.Parent = log
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Speed = NumberRange.new(6, 11)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -25, 0)
	emitter.Size = NumberSequence.new(0.3, 0)
	emitter.Color = ColorSequence.new(Color3.fromRGB(150, 190, 90), Color3.fromRGB(215, 200, 140))
	emitter.Parent = fx

	local stand = { log = log, prompt = prompt, spot = spot, fx = fx, fxEmitter = emitter, occupant = nil, lastCut = -math.huge, swaying = false }
	table.insert(stands, stand)
	prompt.Triggered:Connect(function(player)
		start(player, stand)
	end)
end

local function bindPlayer(player)
	-- A respawn (reset, or the end of a match) ends practice.
	player.CharacterAdded:Connect(function()
		PracticeService.stop(player)
	end)
end

function PracticeService.start()
	local lobby = workspace:WaitForChild("JapaneseLobby", 10)
	if not lobby then
		warn("PracticeService: Workspace.JapaneseLobby not found, so there are no practice buttons.")
		return
	end

	for _, node in ipairs(lobby:GetChildren()) do
		local number = string.match(node.Name, "^Stand(%d+)_Bamboo_Node$")
		if number then
			buildStand(node, tonumber(number))
		end
	end
	table.sort(stands, function(a, b)
		return a.log.Position.X < b.log.Position.X
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end
	Players.PlayerAdded:Connect(bindPlayer)
	Players.PlayerRemoving:Connect(PracticeService.stop)
	Remotes.PracticeExit.OnServerEvent:Connect(PracticeService.stop)
	RunService.Heartbeat:Connect(checkCuts)
end

return PracticeService
