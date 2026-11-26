# Roblox Game

Scripts live in Roblox Studio and are edited through the Roblox Studio MCP server. `src/` is a mirror of them kept for git history. Rojo is no longer used.

## Layout

- `src/server/` → ServerScriptService/Server (server-only code)
- `src/client/` → StarterPlayer/StarterPlayerScripts/Client (client-only code)
- `src/shared/` → ReplicatedStorage/Shared (code used by both)

## Controls

- Left click: attack
- F: parry (time it right before an enemy swing lands)
- Tab: switch between Simple (click attacks nearest enemy in front) and Manual (character faces the cursor; click swings at what is under it)
