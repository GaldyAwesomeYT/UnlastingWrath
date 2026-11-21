-- Server-authoritative combat: attacks, parries, stuns, and PvE dummy AI.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local RoundState = require(script.Parent.RoundState)

local CombatService = {}

-- Last player who damaged each character, used to credit kills.
local lastHits = setmetatable({}, { __mode = "k" })

-- Per-character combat state, keyed by the character Model (cleaned up automatically).
local states = setmetatable({}, { __mode = "k" })

local function getState(character)
	local s = states[character]
	if not s then
		s = { lastAttack = 0, lastParry = 0, parryStart = -math.huge, stunnedUntil = 0 }
		states[character] = s
	end
	return s
end

local function notify(character, kind, duration)
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		Remotes.Feedback:FireClient(player, kind, duration)
	end
end

local function isAlive(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and character:FindFirstChild("HumanoidRootPart") ~= nil
end

-- Every living character or dummy in the workspace, except the attacker.
local function allFighters(except)
	local list = {}
	for _, child in ipairs(workspace:GetChildren()) do
		if child:IsA("Model") and child ~= except and isAlive(child) then
			table.insert(list, child)
		end
	end
	return list
end

-- Applies a hit from attacker to target, or a parry if the target's parry is active.
local function resolveHit(attacker, target)
	local now = os.clock()
	local attackerPlayer = Players:GetPlayerFromCharacter(attacker)
	local targetPlayer = Players:GetPlayerFromCharacter(target)
	if attackerPlayer and targetPlayer and not RoundState.active then
		return -- no player-vs-player combat outside rounds
	end
	local targetState = getState(target)

	if now >= targetState.parryStart and now - targetState.parryStart <= Config.ParryWindow then
		targetState.parryStart = -math.huge
		getState(attacker).stunnedUntil = now + Config.ParryStunDuration
		notify(target, "Parried")
		notify(attacker, "Stunned", Config.ParryStunDuration)
		return
	end

	target:FindFirstChildOfClass("Humanoid"):TakeDamage(Config.AttackDamage)
	if attackerPlayer then
		lastHits[target] = { player = attackerPlayer, time = now }
	end
	notify(attacker, "Hit")
end

-- Simple mode: nearest enemy in front. Manual mode: enemy closest to the cursor direction.
local function findTarget(attacker, mode, aimPoint)
	local root = attacker.HumanoidRootPart
	local origin = root.Position
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if look.Magnitude < 0.01 then return nil end
	look = look.Unit

	local aimDir
	if mode == "Manual" then
		if typeof(aimPoint) ~= "Vector3" then return nil end
		aimDir = Vector3.new(aimPoint.X - origin.X, 0, aimPoint.Z - origin.Z)
		if aimDir.Magnitude < 0.01 then return nil end
		aimDir = aimDir.Unit
	end

	local best, bestScore = nil, -math.huge
	for _, candidate in ipairs(allFighters(attacker)) do
		local offset = candidate.HumanoidRootPart.Position - origin
		offset = Vector3.new(offset.X, 0, offset.Z)
		local dist = offset.Magnitude
		if dist > 0.01 and dist <= Config.AttackRange then
			local dir = offset.Unit
			if mode == "Manual" then
				local dot = dir:Dot(aimDir)
				if dot >= Config.ManualConeDot and dot > bestScore then
					best, bestScore = candidate, dot
				end
			else
				local dot = dir:Dot(look)
				if dot >= Config.SimpleConeDot and -dist > bestScore then
					best, bestScore = candidate, -dist
				end
			end
		end
	end
	return best
end

Remotes.Attack.OnServerEvent:Connect(function(player, mode, aimPoint)
	local character = player.Character
	if not isAlive(character) then return end
	if mode ~= "Manual" then mode = "Simple" end

	local s = getState(character)
	local now = os.clock()
	if now < s.stunnedUntil or now - s.lastAttack < Config.AttackCooldown then return end
	s.lastAttack = now

	local target = findTarget(character, mode, aimPoint)
	if target then
		resolveHit(character, target)
	end
end)

Remotes.Parry.OnServerEvent:Connect(function(player)
	local character = player.Character
	if not isAlive(character) then return end

	local s = getState(character)
	local now = os.clock()
	if now < s.stunnedUntil or now - s.lastParry < Config.ParryCooldown then return end
	s.lastParry = now
	s.parryStart = now
end)

local function nearestLivingPlayer(model)
	local root = model:FindFirstChild("HumanoidRootPart")
	local best, bestDist = nil, Config.DummyAggroRange
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if root and isAlive(character) then
			local dist = (character.HumanoidRootPart.Position - root.Position).Magnitude
			if dist <= bestDist then
				best, bestDist = character, dist
			end
		end
	end
	return best
end

-- Starts the training dummy's AI: telegraph, wind up, then swing.
function CombatService.addDummy(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	task.spawn(function()
		while model.Parent do
			if humanoid.Health <= 0 then
				task.wait(3)
				humanoid.Health = humanoid.MaxHealth
			end
			task.wait(Config.DummyAttackInterval)

			local target = nearestLivingPlayer(model)
			if target and humanoid.Health > 0 and os.clock() >= getState(model).stunnedUntil then
				notify(target, "Telegraph")
				task.wait(Config.DummyWindup)

				if model.Parent and humanoid.Health > 0 and os.clock() >= getState(model).stunnedUntil
					and isAlive(target) then
					resolveHit(model, target)
				end
			end
		end
	end)
end

-- Returns { player = Player, time = number } for the last player who hit this character.
function CombatService.getLastAttacker(character)
	return lastHits[character]
end

return CombatService
