-- Server-authoritative combat: blade hits, clashes (parries), guard, stuns, and dummy AI.
-- The client drives the blade (Weapon.luau). Every heartbeat the server reads each player's
-- replicated blade and resolves:
--   * hits: a moving blade (tip speed at least Config.HitMinSpeed) touches a body part of another living character
--   * clashes: two blades touch. The faster tip wins the parry and the slower player is stunned.
-- Damage: scales with the body part the blade touches (Config.HitMultipliers): head, torso, or limb.
-- Guard (held button): the client puts the blade in front of the body. While guarding, damage is reduced.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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
		s = {
			stunnedUntil = 0,
			lastDash = 0,
			dashUntil = -math.huge,
			guarding = false,
			sheathed = false,    -- blade on the hip: it can't hit, clash or guard
			hitAt = {},          -- [target character] = last time this blade hit it
			clashAt = {},        -- [other character] = last time these blades clashed
			prevRel = nil,       -- blade tip relative to the body last heartbeat (for swing speed)
			prevTime = nil,
			speed = 0,           -- tip speed this heartbeat
			seg = nil,           -- { base, tip } of the blade this heartbeat
		}
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

-- Every living character or dummy in the workspace, except `except`.
local function allFighters(except)
	local list = {}
	for _, child in ipairs(workspace:GetChildren()) do
		if child:IsA("Model") and child ~= except and isAlive(child) then
			table.insert(list, child)
		end
	end
	return list
end

-- Closest distance between segments p1..q1 and p2..q2 (standard clamped closest-point test).
local function segmentSegmentDistance(p1, q1, p2, q2)
	local d1 = q1 - p1
	local d2 = q2 - p2
	local r = p1 - p2
	local a = d1:Dot(d1)
	local e = d2:Dot(d2)
	local f = d2:Dot(r)
	local s, t = 0, 0
	if a <= 1e-9 and e <= 1e-9 then
		return r.Magnitude
	elseif a <= 1e-9 then
		t = math.clamp(f / e, 0, 1)
	else
		local c = d1:Dot(r)
		if e <= 1e-9 then
			s = math.clamp(-c / a, 0, 1)
		else
			local b = d1:Dot(d2)
			local denom = a * e - b * b
			if denom > 1e-9 then
				s = math.clamp((b * f - c * e) / denom, 0, 1)
			end
			t = (b * s + f) / e
			if t < 0 then
				t = 0
				s = math.clamp(-c / a, 0, 1)
			elseif t > 1 then
				t = 1
				s = math.clamp((b - c) / a, 0, 1)
			end
		end
	end
	return ((p1 + d1 * s) - (p2 + d2 * t)).Magnitude
end

-- Damage multiplier for a body part: head, torso (includes the dummy's root), or limb.
local function regionMultiplier(part)
	if part.Name == "Head" then
		return Config.HitMultipliers.Head
	elseif part.Name == "HumanoidRootPart" or string.find(part.Name, "Torso") then
		return Config.HitMultipliers.Torso
	end
	return Config.HitMultipliers.Limb
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

local BLADE_SAMPLES = 10 -- points checked along the blade; spacing stays under Config.BladeThickness

-- The body part of `target` that the blade (base..tip) actually touches, or nil. Looks at the real
-- part boxes, so the blade must reach the body; being near the character's center isn't enough.
-- If several parts are touched, the one the blade reaches deepest wins.
local function bladeHitPart(target, base, tip)
	local best, bestDist = nil, Config.BladeThickness
	for _, part in ipairs(target:GetChildren()) do
		-- The target's own blade and handle are parts of the character, but they aren't its body.
		if part:IsA("BasePart") and part.Name ~= "Blade" and part.Name ~= "Grip" then
			for i = 0, BLADE_SAMPLES do
				local d = distanceToPart(part, base:Lerp(tip, i / BLADE_SAMPLES))
				if d <= bestDist then
					best, bestDist = part, d
				end
			end
		end
	end
	return best
end

-- Whether two characters are allowed to fight each other right now: player-vs-player combat is
-- only between the two fighters of an active match. Dummies are always allowed.
local function canFight(attacker, target)
	local attackerPlayer = Players:GetPlayerFromCharacter(attacker)
	local targetPlayer = Players:GetPlayerFromCharacter(target)
	if attackerPlayer and targetPlayer then
		return RoundState.active and RoundState.fighters[attackerPlayer] and RoundState.fighters[targetPlayer] and true or false
	end
	return true
end

-- Applies a hit from attacker to target. `multiplier` scales the damage (body region for controlled
-- swings, 1 otherwise). Guarding reduces the damage.
local function resolveHit(attacker, target, multiplier)
	local now = os.clock()
	if not canFight(attacker, target) then return end

	local attackerPlayer = Players:GetPlayerFromCharacter(attacker)
	local targetState = getState(target)

	if now < targetState.dashUntil then
		notify(target, "Dodged")
		return
	end

	local damage = Config.AttackDamage * (multiplier or 1)
	if targetState.guarding then
		damage = damage * (1 - Config.BlockReduction)
		notify(target, "Blocked")
	end
	target:FindFirstChildOfClass("Humanoid"):TakeDamage(damage)
	if attackerPlayer then
		lastHits[target] = { player = attackerPlayer, time = now }
	end
	notify(attacker, "Hit")
end

-- Two blades touched. The faster tip wins the parry; the slower player is stunned.
local function resolveClash(a, b, now)
	local sa, sb = getState(a), getState(b)
	local winner, loser = a, b
	if sb.speed > sa.speed then
		winner, loser = b, a
	end
	getState(loser).stunnedUntil = now + Config.ParryStunDuration
	notify(winner, "Parried")
	notify(loser, "Stunned", Config.ParryStunDuration)
end

-- Each heartbeat: measure every blade's tip speed relative to its body (so walking and dashing
-- don't count as swinging), then resolve hits and clashes.
local function checkSwings()
	local now = os.clock()

	-- Pass 1: read each blade.
	local swinging = {} -- list of characters with a blade this heartbeat
	for _, attackerPlayer in ipairs(Players:GetPlayers()) do
		local character = attackerPlayer.Character
		local blade = character and character:FindFirstChild("Blade")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if blade and root and isAlive(character) then
			local s = getState(character)
			local half = Config.WeaponLength / 2
			local center = blade.Position
			local look = blade.CFrame.LookVector
			local tip = center + look * half
			local base = center - look * half

			local rel = tip - root.Position
			local speed = 0
			if s.prevRel and s.prevTime then
				local dt = now - s.prevTime
				if dt > 0 then
					speed = ((rel - s.prevRel) / dt).Magnitude
				end
			end
			s.prevRel, s.prevTime = rel, now
			s.speed = speed
			s.seg = { base = base, tip = tip }
			table.insert(swinging, character)
		else
			if character then
				getState(character).seg = nil
			end
		end
	end

	-- Pass 2: hits (blade touches a living target) and clashes (two blades touch).
	for _, character in ipairs(swinging) do
		local s = getState(character)
		if not (RoundState.paused or s.sheathed or now < s.stunnedUntil) then
			-- A blade held still against someone doesn't hurt them; it has to be swung.
			if s.speed >= Config.HitMinSpeed then
				for _, target in ipairs(allFighters(character)) do
					local last = s.hitAt[target]
					if not last or now - last >= Config.HitCooldown then
						local part = bladeHitPart(target, s.seg.base, s.seg.tip)
						if part then
							s.hitAt[target] = now
							resolveHit(character, target, regionMultiplier(part))
						end
					end
				end
			end
		end
	end

	for i = 1, #swinging do
		for j = i + 1, #swinging do
			local a, b = swinging[i], swinging[j]
			local sa, sb = getState(a), getState(b)
			if not (RoundState.paused or sa.sheathed or sb.sheathed or now < sa.stunnedUntil or now < sb.stunnedUntil) and canFight(a, b)
				and sa.speed >= Config.ClashMinSpeed and sb.speed >= Config.ClashMinSpeed
				and (not sa.clashAt[b] or now - sa.clashAt[b] >= Config.ClashCooldown)
				and segmentSegmentDistance(sa.seg.base, sa.seg.tip, sb.seg.base, sb.seg.tip) <= Config.ClashRadius then
				sa.clashAt[b] = now
				sb.clashAt[a] = now
				resolveClash(a, b, now)
			end
		end
	end
end
RunService.Heartbeat:Connect(checkSwings)

-- Guard button: the client reports whether it is held. While held, the blade sits in front of the body
-- (client) and damage is reduced (server).
Remotes.Block.OnServerEvent:Connect(function(player, held)
	local character = player.Character
	if not character then return end
	local s = getState(character)
	s.guarding = (held == true) and not s.sheathed
end)

-- Sheathe: the client reports whether the blade is on the hip. A sheathed blade can't hit, clash or
-- guard, so sheathing also drops the guard.
Remotes.Sheathe.OnServerEvent:Connect(function(player, sheathed)
	local character = player.Character
	if not character then return end
	local s = getState(character)
	s.sheathed = (sheathed == true)
	if s.sheathed then
		s.guarding = false
	end
end)

-- Dash: the client moves its own character (see Main.client.luau). The server only checks
-- the cooldown and grants the dodge window: the character is untouchable by attacks for
-- Config.DashDuration seconds after this runs.
Remotes.Dash.OnServerEvent:Connect(function(player)
	local character = player.Character
	if not isAlive(character) then return end

	local s = getState(character)
	local now = os.clock()
	if RoundState.paused or now < s.stunnedUntil or now - s.lastDash < Config.DashCooldown then return end

	s.lastDash = now
	s.dashUntil = now + Config.DashDuration
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

-- Starts a dummy's AI: telegraph, wind up, then swing. `stats` = { attackInterval, windup }.
-- Dummies have no blade, so their swings can be blocked by guarding but not parried.
-- The loop ends when the model is destroyed.
local function startDummyAI(model, stats)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	task.spawn(function()
		while model.Parent do
			if humanoid.Health <= 0 then
				task.wait(3)
				humanoid.Health = humanoid.MaxHealth
			end
			task.wait(stats.attackInterval)

			local target = nearestLivingPlayer(model)
			if target and humanoid.Health > 0 and not RoundState.paused and os.clock() >= getState(model).stunnedUntil then
				notify(target, "Telegraph")
				task.wait(stats.windup)

				if model.Parent and humanoid.Health > 0 and not RoundState.paused and os.clock() >= getState(model).stunnedUntil
					and isAlive(target) then
					resolveHit(model, target, 1)
				end
			end
		end
	end)
end

local function makePart(name, size, cframe, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.Parent = parent
	return part
end

-- Builds a dummy at `position` with `stats` = { health, attackInterval, windup }, parents it to the
-- workspace, starts its AI, and returns the model.
function CombatService.spawnDummy(position, stats, name)
	local model = Instance.new("Model")
	model.Name = name

	local root = makePart("HumanoidRootPart", Vector3.new(2, 2, 1), CFrame.new(position), model)
	root.Transparency = 1
	local head = makePart("Head", Vector3.new(2, 1, 1), CFrame.new(position + Vector3.new(0, 1.5, 0)), model)
	head.Color = Color3.fromRGB(255, 200, 150)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = head
	weld.Parent = root

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = stats.health
	humanoid.Health = stats.health
	humanoid.Parent = model

	model.PrimaryPart = root
	model.Parent = workspace
	startDummyAI(model, stats)
	return model
end

-- Returns { player = Player, time = number } for the last player who hit this character.
function CombatService.getLastAttacker(character)
	return lastHits[character]
end

return CombatService
