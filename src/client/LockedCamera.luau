-- Shift-lock style third-person camera. The camera is fixed to the character's head: offset to the right,
-- behind, and slightly above it. It turns exactly with the character's facing, with no lag or follow
-- smoothing, and the mouse never turns it. (Roblox's shift lock also turns the camera with the mouse,
-- which would move the blade's aim every frame.) While isBusy() is true (the duel intro), this camera
-- steps aside.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local LockedCamera = {}

local LOOK_DISTANCE = 50 -- how far ahead the camera looks; keeps the view parallel to the character's facing

function LockedCamera.start(isBusy)
	local player = Players.LocalPlayer
	local camera = workspace.CurrentCamera

	RunService:BindToRenderStep("LockedCamera", Enum.RenderPriority.Camera.Value + 1, function()
		if isBusy() then return end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local head = character and character:FindFirstChild("Head")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not (root and head and humanoid and humanoid.Health > 0) then
			-- Dead or respawning: give control back to Roblox's default camera.
			if camera.CameraType ~= Enum.CameraType.Custom then
				camera.CameraType = Enum.CameraType.Custom
			end
			return
		end

		if camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Scriptable
		end

		-- The character's facing, flattened so the camera stays level.
		local look = root.CFrame.LookVector
		look = Vector3.new(look.X, 0, look.Z)
		if look.Magnitude < 1e-3 then
			look = Vector3.new(0, 0, -1)
		end
		look = look.Unit
		local right = look:Cross(Vector3.yAxis).Unit

		local position = head.Position
			+ right * Config.CameraRightOffset
			- look * Config.CameraBackDistance
			+ Vector3.yAxis * Config.CameraHeight
		camera.CFrame = CFrame.lookAt(position, position + look * LOOK_DISTANCE)
	end)
end

return LockedCamera
