-- Creates each player's blade on the server. The server creates the blade and its two constraints,
-- then hands ownership to that player, so the player's client simulates it. The client moves the blade
-- by setting the targets on its AlignPosition and AlignOrientation (Weapon.luau). The server reads the
-- replicated blade for hits and clashes (CombatService).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Config = require(ReplicatedStorage.Shared.Config)

local BladeService = {}

local HALF = Config.WeaponLength / 2

-- Looks: the physical "Blade" and "Grip" parts stay as invisible hit/physics parts, and the katana
-- (ServerStorage.Weapons.Katana_Sword) is welded onto them. The saya (Katana_Saya) is welded to the
-- HumanoidRootPart at the sheathed pose (Config.SheathePosition / SheatheDirection), so the sheathed
-- blade slides into it. The katana is scaled so its tip lands on the blade's tip.
local HAND_BACK = 0.4 -- how far behind the tsuba (guard) the hand holds; the blade's base sits this far behind it
local SAYA_WIDEN = 1 -- scale of the saya's cross-section (the blade is faded out while sheathed instead of hidden by a fat saya)
local FLIP =CFrame.Angles(0, math.pi, 0) -- the models point their tip toward +Z; the blade's tip is -Z

local function zMax(part)
	local cf, s = part.CFrame, part.Size
	return part.Position.Z + (math.abs(cf.RightVector.Z) * s.X + math.abs(cf.UpVector.Z) * s.Y + math.abs(cf.LookVector.Z) * s.Z) / 2
end

local looks = nil -- { sword, saya, origin, scale }, worked out once from the templates
local function getLooks()
	if looks then return looks end
	local folder = ServerStorage:FindFirstChild("Weapons")
	local sword = folder and folder:FindFirstChild("Katana_Sword")
	local saya = folder and folder:FindFirstChild("Katana_Saya")
	local tsuba = sword and sword:FindFirstChild("Tsuba", true)
	if not (sword and saya and tsuba) then
		warn("BladeService: ServerStorage.Weapons.Katana_Sword / Katana_Saya (with a Tsuba part) not found; using the plain blade.")
		looks = { missing = true }
		return looks
	end
	local tip = -math.huge
	for _, part in ipairs(sword:GetDescendants()) do
		if part:IsA("BasePart") then tip = math.max(tip, zMax(part)) end
	end
	local origin = tsuba.Position
	-- The two models were laid out side by side along X; shifting the saya's origin by that gap puts the
	-- saya back around the blade.
	local gap = Vector3.new(saya:GetPivot().X - sword:GetPivot().X, 0, 0)
	looks = { sword = sword, saya = saya, origin = origin, sayaOrigin = Vector3.new(origin.X + gap.X, saya:GetPivot().Y, origin.Z), scale = (Config.WeaponLength - HAND_BACK) / (tip - origin.Z) }
	return looks
end

-- Fades the katana's blade (the parts named Blade_*) in as it comes out of the saya and out as it slides back
-- in, so the blade never shows through the scabbard. Parts' Transparency replicates to everyone.
-- The timings are fractions of Config.SheatheTime { start, end }, matching the draw animation (Weapon.luau):
-- the base half of the blade comes out during the straight pull, the tip half when the overhead arc starts.
-- Sheathing is the same run backwards.
local FADE_DRAW = { Blade_Lower = { 0.15, 0.4 }, Blade_Upper = { 0.38, 0.48 } }
local FADE_SHEATHE = { Blade_Upper = { 0.52, 0.62 }, Blade_Lower = { 0.6, 0.85 } }
local fadeTweens = setmetatable({}, { __mode = "k" })
function BladeService.setBladeHidden(character, hidden, instant)
	local katana = character and character:FindFirstChild("Katana")
	if not katana then return end
	for _, tween in ipairs(fadeTweens[character] or {}) do
		tween:Cancel()
	end
	local tweens = {}
	fadeTweens[character] = tweens
	local timings = hidden and FADE_SHEATHE or FADE_DRAW
	for _, part in ipairs(katana:GetChildren()) do
		if part:IsA("BasePart") and string.sub(part.Name, 1, 6) == "Blade_" then
			local goal = { Transparency = hidden and 1 or 0 }
			local window = timings[part.Name] or { 0, 1 }
			if instant then
				part.Transparency = goal.Transparency -- quick draw: the blade is out at once
			else
				local T = Config.SheatheTime
				local info = TweenInfo.new((window[2] - window[1]) * T, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, window[1] * T)
				local tween = TweenService:Create(part, info, goal)
				table.insert(tweens, tween)
				tween:Play()
			end
		end
	end
end

-- Clones `template` with every part scaled, flipped and placed relative to `anchor` (the tsuba's pose),
-- welded to `attachTo`.
local function dress(template, origin, anchor, attachTo, parent, name, widen)
	widen = widen or 1
	local info = getLooks()
	local model = Instance.new("Model") -- a Model, so the hit code (which only reads the character's direct parts) skips it
	model.Name = name
	for _, source in ipairs(template:GetDescendants()) do
		if source:IsA("BasePart") then
			local part = source:Clone()
			part:ClearAllChildren()
			-- `widen` thickens a part across its length (the saya), so the blade sits inside it.
			part.Size = Vector3.new(source.Size.X * widen, source.Size.Y, source.Size.Z * widen) * info.scale
			part.CFrame = anchor * FLIP * CFrame.new((source.Position - origin) * info.scale) * source.CFrame.Rotation
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			part.Parent = model
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = attachTo
			weld.Part1 = part
			weld.Parent = part
		end
	end
	model.Parent = parent
end

local function buildBlade(character, player)
	local root = character:WaitForChild("HumanoidRootPart", 5)
	if not root then return end

	-- Start the blade at the rest grip point, pointing forward. The client takes over right away.
	local grip = root.CFrame * Config.WeaponGripTarget
	local look = root.CFrame.LookVector
	local center = grip + look * HALF

	local blade = Instance.new("Part")
	blade.Name = "Blade"
	blade.Size = Vector3.new(0.2, 0.1, Config.WeaponLength) -- long along Z; LookVector points toward the tip
	blade.Color = Color3.fromRGB(200, 205, 215)
	blade.Material = Enum.Material.Metal
	blade.CanCollide = false
	blade.Massless = true
	blade.CFrame = CFrame.lookAt(center, center + look)
	blade.Parent = character

	local handle = Instance.new("Part")
	handle.Name = "Grip"
	handle.Size = Vector3.new(0.35, 0.35, 0.9)
	handle.Color = Color3.fromRGB(60, 45, 35)
	handle.CanCollide = false
	handle.Massless = true
	handle.CFrame = blade.CFrame * CFrame.new(0, 0, HALF + 0.3) -- behind the base, where the hand holds
	handle.Parent = character

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = blade
	weld.Part1 = handle
	weld.Parent = blade

	-- Both constraints work in OneAttachment mode: the target is a world position / CFrame that the
	-- owning client sets every frame.
	local attachment = Instance.new("Attachment")
	attachment.Name = "BladeCenter"
	attachment.Parent = blade

	local position = Instance.new("AlignPosition")
	position.Name = "BladePosition"
	position.Mode = Enum.PositionAlignmentMode.OneAttachment
	position.Attachment0 = attachment
	position.Position = center
	position.Responsiveness = Config.WeaponResponsiveness
	position.MaxForce = 1e5
	position.Parent = blade

	local orientation = Instance.new("AlignOrientation")
	orientation.Name = "BladeOrientation"
	orientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orientation.Attachment0 = attachment
	orientation.CFrame = blade.CFrame
	orientation.Responsiveness = Config.WeaponResponsiveness
	orientation.MaxTorque = 1e6
	orientation.Parent = blade

	blade:SetNetworkOwner(player)

	-- The katana and saya (see getLooks). The blade and grip become invisible hit parts.
	if not getLooks().missing then
		blade.Transparency = 1
		handle.Transparency = 1
		dress(looks.sword, looks.origin, blade.CFrame * CFrame.new(0, 0, HALF - HAND_BACK), blade, character, "Katana")

		local sheathed = CFrame.lookAt(Config.SheathePosition, Config.SheathePosition + Config.SheatheDirection.Unit)
		dress(looks.saya, looks.sayaOrigin, root.CFrame * sheathed * CFrame.new(0, 0, HALF - HAND_BACK), root, character, "Saya", SAYA_WIDEN)
	end
end

-- Gives every player a blade on each character, including the one they already have.
function BladeService.start()
	local function bind(player)
		player.CharacterAdded:Connect(function(character)
			buildBlade(character, player)
		end)
		if player.Character then
			buildBlade(player.Character, player)
		end
	end
	Players.PlayerAdded:Connect(bind)
	for _, player in ipairs(Players:GetPlayers()) do
		bind(player)
	end
end

return BladeService
