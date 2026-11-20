-- Creates the RemoteEvents on the server and waits for them on the client.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = { "Attack", "Parry", "Feedback", "Round" }
local folder

if RunService:IsServer() then
	folder = Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage
	for _, name in ipairs(NAMES) do
		local event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = folder
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end

return {
	Attack = folder:WaitForChild("Attack"),   -- client -> server: (mode, aimPoint?)
	Parry = folder:WaitForChild("Parry"),     -- client -> server
	Feedback = folder:WaitForChild("Feedback"), -- server -> client: kind string
	Round = folder:WaitForChild("Round"),     -- server -> client: status message
}
