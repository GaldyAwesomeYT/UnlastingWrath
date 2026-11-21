# Parry Arena (Roblox)

A Roblox PvP/PvE game built around parrying. Players attack with the mouse and parry with F.

## Stack and workflow
- Luau code lives in `src/`, synced into Roblox Studio with **Rojo** (version pinned in `rokit.toml`, currently 7.7.1).
- Start the sync with `rojo serve` from the project folder, then click Connect in the Rojo widget in Studio.
- The Studio place file is saved by Studio, not by Rojo. Don't expect code edits to save the place.
- Test with Studio's Play button. There is no automated test suite yet.

## Layout
- `default.project.json`: maps `src/server` → ServerScriptService/Server, `src/client` → StarterPlayerScripts/Client, `src/shared` → ReplicatedStorage/Shared.
- `src/shared/Config.luau`: all tuning numbers. Change values here, not in logic.
- `src/shared/Remotes.luau`: RemoteEvents (Attack, Parry, Feedback, Round). Server creates them.
- `src/server/CombatService.luau`: server-authoritative attacks, parries, stuns, kill credit, and dummy AI.
- `src/server/GameService.luau`: round loop (lobby countdown, first to KillsToWin, intermission).
- `src/server/RoundState.luau`: shared "round active" flag.
- `src/server/Main.server.luau`: builds the floor and training dummy, starts services.
- `src/client/Main.client.luau`: input, cursor aiming, HUD (mode label, feedback, health bar, round status, parry flash).

## Rules
- Combat logic stays on the server. The client only sends intent (attack, parry) and displays results.
- Player-vs-player combat is only allowed while `RoundState.active` is true. The training dummy always works.
- Keep the two control modes working: Simple (click attacks nearest enemy in front) and Manual (character faces cursor, click swings at what's under it). Toggle with Tab.
- Don't add sound IDs or assets you can't confirm are usable. `Config.ParrySoundId` stays empty until the user sets it.
- Make small, focused changes and tell the user which files changed so they can copy them to `C:\Projects\RobloxGame` (or commit them locally).

## Current status
- Working and tested in Studio: attacks, parries, stun, dummy AI, health bar, round countdown, kill counter, parry screen flash.
- Next planned: stun timer, balance tuning, lobby/spawn/map polish, scoreboard.
