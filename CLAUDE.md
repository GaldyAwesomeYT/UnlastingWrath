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
- `src/shared/Remotes.luau`: RemoteEvents (Attack, Parry, Feedback, Round, Scores, Dash, Ready, ReadyState, MatchStart). Server creates them.
- `src/server/CombatService.luau`: server-authoritative attacks, parries, stuns, kill credit, and dummy AI.
- `src/server/GameService.luau`: ready-up queue (needs `Config.MatchSize` players), lobby countdown, first to KillsToWin between the fighters, intermission, kill counts, post-kill reset countdown, and scores broadcast.
- `src/server/RoundState.luau`: shared "active", "paused", and "fighters" state.
- `src/server/Main.server.luau`: builds the floor and training dummy, starts services.
- `src/client/Main.client.luau`: input, cursor aiming, HUD (mode label, feedback, self health bar top-left, opponent health bars top-right, stun bar, dash cooldown bar, round status, parry flash, scoreboard, Ready button).

## Rules
- Combat logic stays on the server. The client only sends intent (attack, parry) and displays results.
- Player-vs-player combat is only allowed between the two fighters while `RoundState.active` is true. The training dummy always works.
- At round start the server freezes the fighters and pauses combat for the duel intro's total time (the `Config.Duel*` values). The camera is client-only and uses Roblox's built-in camera APIs.
- Matches are 1v1 from a ready-up queue: a match starts only after `Config.MatchSize` players press Ready and stay ready through `Config.LobbyCountdown`. Everyone must press Ready again for the next match. Fighters spawn at x = ±12 on the arena's center line, facing each other (`startMatch` in `GameService`; assumes `MatchSize` = 2).
- Keep the two control modes working: Simple (click attacks nearest enemy in front) and Manual (character faces cursor, click swings at what's under it). Toggle with M. Tab toggles the scoreboard (moved off Tab so the two don't clash).
- After every kill, combat pauses for `Config.KillResetCountdown` seconds, then all living players are healed to full. Kill counts live on the server; clients get them via the `Scores` remote.
- Don't add sound IDs or assets you can't confirm are usable. `Config.ParrySoundId` stays empty until the user sets it.
- Make small, focused changes and tell the user which files changed so they can copy them to `C:\Projects\RobloxGame` (or commit them locally).

## Current status
- Working and tested in Studio: attacks, parries, stun, dummy AI, health bar, round countdown, kill counter, parry screen flash.
- Stun timer (HUD bar under health, counts down the parry stun; server sends only the duration): written, not yet tested in Studio.
- Scoreboard (Tab) with per-round kills, and post-kill reset countdown with full heal: written, not yet tested in Studio.
- Block (hold Q, `Config.BlockKey`): while held, incoming attacks deal `Config.BlockReduction` (30%) less damage, and the target sees "BLOCK". Parry and dodge still take priority. Written, not yet tested in Studio.
- Dash (Shift, `Config.DashKey`): the client drives the movement with a LinearVelocity (the client owns its physics); the server only checks cooldown and grants the dodge window, so attacks show "DODGE!". Opponent HP bar top-right (only the other fighter, only during a match; `MatchStart` sends `{}` when a match ends): written, not yet tested in Studio.
- Ready-up queue (Ready button, 1v1 once 2 players are ready, countdown cancels if someone unreadies): written, not yet tested in Studio.
- Round duel intro (fighters only): the server anchors both fighters and pauses combat for the sum of `Config.DuelWideTime`, `DuelCloseTime` (×2), `DuelReturnTime`, and `DuelPanTime` (5.0s), and fires `MatchStart`. The client moves only the camera: wide level side-on shot, diagonal close-up on each fighter's midsection from the camera side (weapon-ready framing), wide shot again, then pan to the normal follow view. If the local character dies during the intro, the follow camera is restored immediately. Written, not yet tested in Studio.
- Next planned: balance tuning, lobby/spawn/map polish.
