-- Creates each player's blade on the server. The server creates the blade and its two constraints,
-- then hands ownership to that player, so the player's client simulates it. The client moves the blade
-- by setting the targets on its AlignPosition and AlignOrientation (Weapon.luau). The server reads the
-- replicated blade for hits and clashes (CombatService).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local BladeService = {}

local HALF = Config.WeaponLength / 2

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
