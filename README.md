# Roblox Game

Source is kept in `src/` and synced into Roblox Studio with Rojo.

## Setup

1. Install [Rokit](https://github.com/rojo-rbx/rokit), then run `rokit install` to get Rojo.
2. Install the Rojo plugin in Roblox Studio.
3. Run `rojo serve`, then click **Connect** in the Rojo plugin inside Studio.

## Layout

- `src/server/` → ServerScriptService/Server (server-only code)
- `src/client/` → StarterPlayer/StarterPlayerScripts/Client (client-only code)
- `src/shared/` → ReplicatedStorage/Shared (code used by both)

## Controls

- Left click: attack
- F: parry (time it right before an enemy swing lands)
- Tab: switch between Simple (click attacks nearest enemy in front) and Manual (character faces the cursor; click swings at what is under it)
