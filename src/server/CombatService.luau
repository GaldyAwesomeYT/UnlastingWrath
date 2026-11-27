-- Server-authoritative combat: blade hits, clashes (parries), guard, stuns, and dummy AI.
-- The client drives each player's blade (Weapon.luau); the server drives each dummy's sword. Every heartbeat
-- the server reads every replicated blade and resolves:
--   * hits: a moving blade (tip speed at least Config.HitMinSpeed) touches a body part of another living character
--   * clashes: two blades touch. A player's blade clashing with a dummy's sword is a parry: the dummy is stunned.
--     Two players clashing stun nobody; each fills their Max-Clash bar instead. A full bar weakens the player
--     (slower walking, slower blade, less damage) for Config.WeakenedDuration. The bar drains after
--     Config.ClashBarIdleTime seconds without a clash.
-- Damage: scales with the body part the blade touches (Config.HitMultipliers): head, torso, or limb.
-- Guard (held button): the client puts the blade in front of the body. While guarding, damage is reduced.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local RoundState = require(script.Parent.RoundState)
local BladeService = require(script.Parent.BladeService)

local CombatService = {}

-- Last player who damaged each character, used to credit kills.
local lastHits = setmetatable({}, { __mode = "k" })

-- Per-character combat state, keyed by the character Model (cleaned up automatically).
local states = setmetatable({}, { __mode = "k" })

-- Dummies that carry a sword, keyed by their model (see spawnDummy). Entries are removed once the model is destroyed.
local dummies = {}

local function getState(character)
	local s = states[character]
	if not s then
		s = {
			stunnedUntil = 0,
			lastDash = 0,
			dashUntil = -math.huge,
			guarding = false,
			sheathed = false,    -- blade on the hip: it can't hit, clash or guard
			canHit = true,       -- false while a dummy's sword isn't mid-swing (it can still clash)
			clash = 0,           -- Max-Clash bar, 0 to 1
			lastClash = -math.huge, -- time of this character's last player-vs-player clash
			weakened = false,    -- the bar filled: slowed, slower blade, less damage until weakenedUntil
			weakenedUntil = 0,
			baseWalkSpeed = 16,  -- walk speed to restore when weakened ends
			clashPublished = 0,  -- last bar value sent to clients (the ClashBar attribute)
			clashPublishedAt = 0,
			quickDrawUntil = -math.huge, -- hits before this time get Config.QuickDrawBonus (a draw slash)
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

-- Max-Clash bar. The value is shown on the owner's HUD through the "ClashBar" character attribute (0 to 1);
-- while weakened it shows the time left instead, and the "Weakened" attribute is true.
local function publishClash(character, s, ratio, force)
	local now = os.clock()
	ratio = math.clamp(ratio, 0, 1)
	if force or (ratio ~= s.clashPublished and now - s.clashPublishedAt >= 0.1) then
		s.clashPublished, s.clashPublishedAt = ratio, now
		character:SetAttribute("ClashBar", ratio)
	end
end

-- The blade's two constraints decide how fast it follows the mouse; lowering them slows the blade.
local function setBladeResponsiveness(character, value)
	local blade = character:FindFirstChild("Blade")
	if not blade then return end
	local position = blade:FindFirstChild("BladePosition")
	local orientation = blade:FindFirstChild("BladeOrientation")
	if position then position.Responsiveness = value end
	if orientation then orientation.Responsiveness = value end
end

local function startWeakened(character, s, now)
	s.weakened = true
	s.weakenedUntil = now + Config.WeakenedDuration
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		s.baseWalkSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = s.baseWalkSpeed * Config.WeakenedSpeedMultiplier
	end
	-- The client restores this speed after a free-cursor lock (Weapon.luau), so the slowdown survives it.
	character:SetAttribute("WalkSpeedTarget", s.baseWalkSpeed * Config.WeakenedSpeedMultiplier)
	setBladeResponsiveness(character, Config.WeaponResponsiveness * Config.WeakenedBladeResponsiveness)
	character:SetAttribute("Weakened", true)
	publishClash(character, s, 1, true)
	notify(character, "Weakened", Config.WeakenedDuration)
end

local function endWeakened(character, s)
	s.weakened = false
	s.clash = 0
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = s.baseWalkSpeed
	end
	character:SetAttribute("WalkSpeedTarget", s.baseWalkSpeed)
	setBladeResponsiveness(character, Config.WeaponResponsiveness)
	character:SetAttribute("Weakened", false)
	publishClash(character, s, 0, true)
end

-- A player-vs-player clash: fills the bar. A full bar weakens the player. The bar doesn't fill while weakened.
local function addClash(character, s, now)
	s.lastClash = now
	if s.weakened then return end
	s.clash = math.min(1, s.clash + Config.ClashBarGain)
	if s.clash >= 1 then
		startWeakened(character, s, now)
	else
		publishClash(character, s, s.clash, true)
	end
end

-- Every heartbeat: ends the weakened state on time, or drains the bar after Config.ClashBarIdleTime seconds
-- without a clash.
local function updateClashBar(character, s, now, dt)
	if s.weakened then
		if now >= s.weakenedUntil then
			endWeakened(character, s)
		else
			publishClash(character, s, (s.weakenedUntil - now) / Config.WeakenedDuration)
		end
	elseif s.clash > 0 and now - s.lastClash >= Config.ClashBarIdleTime then
		s.clash = math.max(0, s.clash - Config.ClashBarDrainPerSecond * dt)
		publishClash(character, s, s.clash, s.clash == 0)
	end
end

-- Empties the bar and ends any weakened state (used when fighters are reset).
function CombatService.clearClash(character)
	local s = states[character]
	if not s then return end
	if s.weakened then
		endWeakened(character, s)
	elseif s.clash > 0 then
		s.clash = 0
		publishClash(character, s, 0, true)
	end
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
	if getState(attacker).weakened then
		damage = damage * Config.WeakenedDamageMultiplier
	end
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

-- Two blades touched. Against a dummy's sword it is a parry: the dummy is stunned. Between two players nobody
-- is stunned; both fill their Max-Clash bar and can keep moving their blades.
local function resolveClash(a, b, now)
	local dummy, fighter
	if dummies[a] then
		dummy, fighter = a, b
	elseif dummies[b] then
		dummy, fighter = b, a
	end
	if dummy then
		getState(dummy).stunnedUntil = now + Config.ParryStunDuration
		notify(fighter, "Parried")
		return
	end

	for _, character in ipairs({ a, b }) do
		addClash(character, getState(character), now)
		notify(character, "Clash")
	end
end

-- Each heartbeat: measure every blade's tip speed relative to its body (so walking and dashing
-- don't count as swinging), then resolve hits and clashes.
local function checkSwings(dt)
	local now = os.clock()

	-- Everyone who can hold a blade: each player's character, then the dummies.
	local characters = {}
	for _, attackerPlayer in ipairs(Players:GetPlayers()) do
		local character = attackerPlayer.Character
		if character then
			updateClashBar(character, getState(character), now, dt)
			table.insert(characters, character)
		end
	end
	for model in pairs(dummies) do
		table.insert(characters, model)
	end

	-- Pass 1: read each blade.
	local swinging = {} -- list of characters with a blade this heartbeat
	for _, character in ipairs(characters) do
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
		if not (RoundState.paused or s.sheathed or now < s.stunnedUntil) and s.canHit then
			-- A blade held still against someone doesn't hurt them; it has to be swung.
			if s.speed >= Config.HitMinSpeed then
				for _, target in ipairs(allFighters(character)) do
					local last = s.hitAt[target]
					-- A dummy's sword only hurts players, never other dummies.
					local targetOk = not dummies[character] or Players:GetPlayerFromCharacter(target) ~= nil
					if targetOk and (not last or now - last >= Config.HitCooldown) then
						local part = bladeHitPart(target, s.seg.base, s.seg.tip)
						if part then
							s.hitAt[target] = now
							local bonus = now < s.quickDrawUntil and Config.QuickDrawBonus or 1
							resolveHit(character, target, regionMultiplier(part) * bonus)
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
			-- Two players need both blades moving. Against a dummy, one moving blade is enough, so a held
			-- blade can parry a dummy's swing and a swing can knock a dummy's sword aside.
			local aDummy, bDummy = dummies[a] ~= nil, dummies[b] ~= nil
			local fastEnough
			if aDummy or bDummy then
				fastEnough = math.max(sa.speed, sb.speed) >= Config.ClashMinSpeed
			else
				fastEnough = sa.speed >= Config.ClashMinSpeed and sb.speed >= Config.ClashMinSpeed
			end
			if not (aDummy and bDummy) and fastEnough
				and not (RoundState.paused or sa.sheathed or sb.sheathed or now < sa.stunnedUntil or now < sb.stunnedUntil) and canFight(a, b)
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

-- Quick draw: a slash straight out of the sheath. Only valid while the player is sheathed, alive, not
-- stunned and combat isn't paused. It draws the blade and gives hits in the next
-- Config.QuickDrawBonusTime seconds the Config.QuickDrawBonus damage multiplier. The slash itself is
-- moved by the client, so the usual hit checks apply to it.
local QUICK_DRAW_DIRECTIONS = { Right = true, Up = true, Down = true }
Remotes.QuickDraw.OnServerEvent:Connect(function(player, direction)
	local character = player.Character
	if not (isAlive(character) and QUICK_DRAW_DIRECTIONS[direction]) then return end
	local s = getState(character)
	local now = os.clock()
	if not s.sheathed or RoundState.paused or now < s.stunnedUntil then return end
	s.sheathed = false
	BladeService.setBladeHidden(character, false)
	s.quickDrawUntil = now + Config.QuickDrawBonusTime
end)

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
	BladeService.setBladeHidden(character, s.sheathed)
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

-- Dummy swords. Each dummy holds a physical sword (parts named "Blade" and "Grip", like a player's) that the
-- server moves every heartbeat, so the normal hit and clash checks apply to it. A swing has phases:
--   rest -> windup (the target gets "Telegraph"; the sword is raised) -> swing (a flat slash, the only time it
--   can hurt) -> recover (the sword is lowered) -> rest.
-- A player's blade clashing with the sword stuns the dummy (see resolveClash), which cancels its swing.
-- Poses are a grip point and a blade direction in the dummy root's space (+X right, +Y up, -Z forward).
local REST_GRIP, REST_DIR = Vector3.new(1.1, -0.3, -0.8), Vector3.new(0.2, 0.5, -1)
local WINDUP_GRIP, WINDUP_DIR = Vector3.new(1.2, 0.8, -0.4), Vector3.new(0.4, 1, -0.3)
local STUN_GRIP, STUN_DIR = Vector3.new(1.0, -0.8, -0.4), Vector3.new(0.3, -0.8, -0.5)
local SWING_GRIP = Vector3.new(0.4, 0.2, -0.8)
local SWING_FROM, SWING_TO = 75, -75 -- degrees of yaw, positive = right of forward
local DUMMY_SKIN = Color3.fromRGB(255, 200, 150)
local DUMMY_STUNNED = Color3.fromRGB(110, 150, 255)

local function swingDir(degrees)
	local a = math.rad(degrees)
	return Vector3.new(math.sin(a), 0, -math.cos(a))
end

local function placeDummyBlade(d, grip, dir)
	local rootCFrame = d.root.CFrame
	local worldDir = rootCFrame:VectorToWorldSpace(dir.Unit)
	local center = rootCFrame:PointToWorldSpace(grip) + worldDir * (Config.WeaponLength / 2)
	d.blade.CFrame = CFrame.lookAt(center, center + worldDir)
	d.handle.CFrame = d.blade.CFrame * CFrame.new(0, 0, Config.WeaponLength / 2 + 0.3)
end

-- Turns the dummy (flat, around its own height) to face a character.
local function faceDummy(d, target)
	local from = d.root.Position
	local to = target.HumanoidRootPart.Position
	local flat = Vector3.new(to.X, from.Y, to.Z)
	if (flat - from).Magnitude > 0.1 then
		d.model:PivotTo(CFrame.lookAt(from, flat))
	end
end

local function updateDummy(d, now)
	local model, humanoid, stats = d.model, d.humanoid, d.stats
	local s = getState(model)

	-- A killed dummy puts its sword down and heals back to full after Config.DummyReviveTime.
	if humanoid.Health <= 0 then
		d.deadAt = d.deadAt or now
		d.phase = "rest"
		s.canHit = false
		if now - d.deadAt >= Config.DummyReviveTime then
			humanoid.Health = humanoid.MaxHealth
			d.deadAt = nil
			d.nextAttack = now + stats.attackInterval
		end
		placeDummyBlade(d, REST_GRIP, REST_DIR)
		return
	end
	d.deadAt = nil

	-- A stun (or a paused round) cancels the swing in progress and lowers the sword.
	local stunned = now < s.stunnedUntil
	d.head.Color = stunned and DUMMY_STUNNED or DUMMY_SKIN
	if stunned or RoundState.paused then
		if d.phase ~= "rest" then
			d.phase = "rest"
			d.nextAttack = now + stats.attackInterval
		end
		s.canHit = false
		if stunned then
			placeDummyBlade(d, STUN_GRIP, STUN_DIR)
		else
			placeDummyBlade(d, REST_GRIP, REST_DIR)
		end
		return
	end

	-- Phase changes.
	if d.phase == "rest" and now >= d.nextAttack then
		local target = nearestLivingPlayer(model)
		if target then
			d.target = target
			d.phase, d.phaseStart = "windup", now
			notify(target, "Telegraph")
		end
	end
	if d.phase == "windup" then
		if isAlive(d.target) then
			faceDummy(d, d.target) -- keeps tracking until the swing starts, so a sidestep during the windup still works
			if now - d.phaseStart >= stats.windup then
				d.phase, d.phaseStart = "swing", now
			end
		else
			d.phase = "rest"
			d.nextAttack = now + stats.attackInterval
		end
	end
	if d.phase == "swing" and now - d.phaseStart >= Config.DummySwingTime then
		d.phase, d.phaseStart = "recover", now
	end
	if d.phase == "recover" and now - d.phaseStart >= Config.DummyRecoverTime then
		d.phase = "rest"
		d.nextAttack = now + stats.attackInterval
	end

	-- Pose the sword for the current phase.
	s.canHit = d.phase == "swing"
	if d.phase == "windup" then
		local t = math.clamp((now - d.phaseStart) / stats.windup, 0, 1)
		placeDummyBlade(d, REST_GRIP:Lerp(WINDUP_GRIP, t), REST_DIR.Unit:Lerp(WINDUP_DIR.Unit, t))
	elseif d.phase == "swing" then
		local t = math.clamp((now - d.phaseStart) / Config.DummySwingTime, 0, 1)
		placeDummyBlade(d, SWING_GRIP, swingDir(SWING_FROM + (SWING_TO - SWING_FROM) * t))
	elseif d.phase == "recover" then
		local t = math.clamp((now - d.phaseStart) / Config.DummyRecoverTime, 0, 1)
		placeDummyBlade(d, SWING_GRIP:Lerp(REST_GRIP, t), swingDir(SWING_TO):Lerp(REST_DIR.Unit, t))
	else
		placeDummyBlade(d, REST_GRIP, REST_DIR)
	end
end

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for model, d in pairs(dummies) do
		if model.Parent then
			updateDummy(d, now)
		else
			dummies[model] = nil
		end
	end
end)

local function makePart(name, size, cframe, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.Parent = parent
	return part
end

-- Builds a dummy at `position` with `stats` = { health, attackInterval, windup }, gives it a sword, parents it
-- to the workspace, starts its AI (updateDummy), and returns the model.
function CombatService.spawnDummy(position, stats, name)
	local model = Instance.new("Model")
	model.Name = name

	local root = makePart("HumanoidRootPart", Vector3.new(2, 2, 1), CFrame.new(position), model)
	root.Transparency = 1
	local head = makePart("Head", Vector3.new(2, 1, 1), CFrame.new(position + Vector3.new(0, 1.5, 0)), model)
	head.Color = DUMMY_SKIN
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = head
	weld.Parent = root

	-- The sword: anchored and moved by updateDummy. The names match a player's blade so hit checks skip them.
	local blade = makePart("Blade", Vector3.new(0.2, 0.1, Config.WeaponLength), CFrame.new(position), model)
	blade.Color = Color3.fromRGB(200, 205, 215)
	blade.Material = Enum.Material.Metal
	blade.CanCollide = false
	local handle = makePart("Grip", Vector3.new(0.35, 0.35, 0.9), CFrame.new(position), model)
	handle.Color = Color3.fromRGB(60, 45, 35)
	handle.CanCollide = false

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = stats.health
	humanoid.Health = stats.health
	-- A Humanoid that enters the Dead state ignores later Health writes, so the AI's heal after a kill would
	-- never work. Dummies have no joints to break, so they simply sit at 0 health until healed.
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	humanoid.Parent = model

	model.PrimaryPart = root
	model.Parent = workspace
	dummies[model] = {
		model = model,
		humanoid = humanoid,
		root = root,
		head = head,
		blade = blade,
		handle = handle,
		stats = stats,
		phase = "rest",
		phaseStart = os.clock(),
		nextAttack = os.clock() + stats.attackInterval,
	}
	return model
end

-- This character's blade as of the last heartbeat: base, tip and tip speed (studs/second relative to the
-- body). Returns nil when there is no blade to swing (none yet, dead, or sheathed). Used by practice mode.
function CombatService.getBlade(character)
	local s = states[character]
	if not (s and s.seg) or s.sheathed then return nil end
	return s.seg.base, s.seg.tip, s.speed
end

-- Returns { player = Player, time = number } for the last player who hit this character.
function CombatService.getLastAttacker(character)
	return lastHits[character]
end

return CombatService
