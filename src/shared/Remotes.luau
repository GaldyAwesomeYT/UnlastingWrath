-- Creates the RemoteEvents on the server and waits for them on the client.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = { "Feedback", "Round", "Scores", "Dash", "Ready", "ReadyState", "MatchStart", "Block", "Options", "Sheathe", "ScoresRequest", "QuickDraw" }
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
	Feedback = folder:WaitForChild("Feedback"), -- server -> client: kind string
	Round = folder:WaitForChild("Round"),     -- server -> client: status message
	Scores = folder:WaitForChild("Scores"),   -- server -> client: list of { name, kills }, highest first
	Dash = folder:WaitForChild("Dash"),       -- client -> server: dash request (no args); server grants the dodge window
	Block = folder:WaitForChild("Block"),     -- client -> server: boolean, true while the guard button is held
	Ready = folder:WaitForChild("Ready"),     -- client -> server: true to queue, false to leave the queue
	ReadyState = folder:WaitForChild("ReadyState"), -- server -> client: boolean, syncs the Ready button
	MatchStart = folder:WaitForChild("MatchStart"), -- server -> client: list of fighter Players when placed; {} when the match ends
	ScoresRequest = folder:WaitForChild("ScoresRequest"), -- client -> server: no args; the server answers that client with the Scores list
	QuickDraw = folder:WaitForChild("QuickDraw"), -- client -> server: "Right", "Up" or "Down"; a slash straight out of the sheath (only valid while sheathed)
	Sheathe = folder:WaitForChild("Sheathe"), -- client -> server: boolean, true while the blade is sheathed (no hits, clashes or guard)
	Options = folder:WaitForChild("Options"),  -- client -> server: (gameMode string, difficulty string), sent when Play is pressed
}
