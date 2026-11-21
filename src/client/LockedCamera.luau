-- Shift-lock style third-person camera. The camera is fixed to the character's head: offset to the right,
-- behind, and slightly above it. It turns exactly with the character's facing, with no lag or follow
-- smoothing, and the mouse never turns it. (Roblox's shift lock also turns the camera with the mouse,
-- which would move the blade's aim every frame.) While isBusy() is true (the duel intro), this camera
-- steps aside.
-- Sheathed (default mode), the camera is Roblox's normal one. Switching between the two is a smooth pan
-- (Config.CameraPanTime), like the end of the duel intro but without the cutscene: the camera stays
-- scriptable and eases from where it is to where the other camera sits, then hands over.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local LockedCamera = {}

local LOOK_DISTANCE = 50 -- how far ahead the camera looks; keeps the view parallel to the character's facing

-- Where Roblox's normal follow camera roughly sits (the same view the duel intro pans to): a little
-- behind and above the character, looking at its chest.
local FOLLOW_BACK = 8
local FOLLOW_UP = 3
local FOLLOW_FOCUS_UP = 1.5

local function smoothstep(t)
	return t * t * (3 - 2 * t)
end

-- getLook (optional): returns the look-around yaw (right is positive) and pitch (up is positive), in radians.
-- isDefaultMode (optional): true while the blade is sheathed; the camera is then Roblox's normal one.
function LockedCamera.start(isBusy, getLook, isDefaultMode)
	local player = Players.LocalPlayer
	local camera = workspace.CurrentCamera

	local lastNormal = nil -- whether the previous frame was default mode (nil = unknown, e.g. after death)
	local panFrom = nil -- the camera's CFrame when the current pan began, or nil when not panning
	local panTime = 0

	-- The locked camera's pose for this frame.
	local function lockedPose(root, head)
		-- The character's facing, flattened so the camera stays level.
		local look = root.CFrame.LookVector
		look = Vector3.new(look.X, 0, look.Z)
		if look.Magnitude < 1e-3 then
			look = Vector3.new(0, 0, -1)
		end
		look = look.Unit

		-- Look around: turn the view by yaw (around the vertical axis) and pitch, both zero normally.
		local yaw, pitch = 0, 0
		if getLook then
			yaw, pitch = getLook()
		end
		local facing = CFrame.lookAt(Vector3.zero, look)
		look = (facing * CFrame.fromEulerAnglesYXZ(0, -yaw, 0)).LookVector -- level, so the camera sits at the same height
		local view = (facing * CFrame.fromEulerAnglesYXZ(pitch, -yaw, 0)).LookVector
		local right = look:Cross(Vector3.yAxis).Unit

		local position = head.Position
			+ right * Config.CameraRightOffset
			- look * Config.CameraBackDistance
			+ Vector3.yAxis * Config.CameraHeight
		return CFrame.lookAt(position, position + view * LOOK_DISTANCE)
	end

	-- Roughly where Roblox's normal camera would sit behind the character right now.
	local function followPose(root)
		local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		look = look.Magnitude > 1e-3 and look.Unit or Vector3.new(0, 0, -1)
		return CFrame.lookAt(
			root.Position - look * FOLLOW_BACK + Vector3.new(0, FOLLOW_UP, 0),
			root.Position + Vector3.new(0, FOLLOW_FOCUS_UP, 0)
		)
	end

	-- Gives control to Roblox's normal camera.
	local function handToRoblox(humanoid)
		if camera.CameraType ~= Enum.CameraType.Custom then
			camera.CameraType = Enum.CameraType.Custom
		end
		if humanoid and camera.CameraSubject ~= humanoid then
			camera.CameraSubject = humanoid
		end
	end

	RunService:BindToRenderStep("LockedCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		if isBusy() then
			lastNormal, panFrom = nil, nil
			return
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local head = character and character:FindFirstChild("Head")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not (root and head and humanoid and humanoid.Health > 0) then
			-- Dead or respawning: give control back to Roblox's default camera.
			lastNormal, panFrom = nil, nil
			handToRoblox(humanoid)
			return
		end

		local normal = isDefaultMode ~= nil and isDefaultMode()

		-- The mode just switched (blade sheathed or drawn): start a pan from where the camera is now.
		if lastNormal ~= nil and normal ~= lastNormal then
			panFrom = camera.CFrame
			panTime = 0
		end
		lastNormal = normal

		if panFrom then
			-- Ease toward the other camera's live pose, so a walking character is followed during the pan.
			if camera.CameraType ~= Enum.CameraType.Scriptable then
				camera.CameraType = Enum.CameraType.Scriptable
			end
			panTime += dt
			local alpha = math.clamp(panTime / Config.CameraPanTime, 0, 1)
			local goal = normal and followPose(root) or lockedPose(root, head)
			camera.CFrame = panFrom:Lerp(goal, smoothstep(alpha))
			if alpha >= 1 then
				panFrom = nil
				if normal then
					handToRoblox(humanoid) -- the pan is done; Roblox's camera continues from here
				end
			end
			return
		end

		if normal then
			handToRoblox(humanoid)
			return
		end

		if camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Scriptable
		end
		camera.CFrame = lockedPose(root, head)
	end)
end

return LockedCamera
