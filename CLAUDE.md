# Parry Arena (Roblox)

A Roblox PvP/PvE game built around a blade. Players swing it with the mouse, guard with F, and clash blades to parry.

## Stack and workflow
- Luau code lives in `src/`, synced into Roblox Studio with **Rojo** (version pinned in `rokit.toml`, currently 7.7.1).
- Start the sync with `rojo serve` from the project folder, then click Connect in the Rojo widget in Studio.
- The Studio place file is saved by Studio, not by Rojo. Don't expect code edits to save the place.
- Test with Studio's Play button. There is no automated test suite yet.

## Layout
- `default.project.json`: maps `src/server` → ServerScriptService/Server, `src/client` → StarterPlayerScripts/Client, `src/shared` → ReplicatedStorage/Shared, `src/replicatedfirst` → ReplicatedFirst (loading screen; restart `rojo serve` after changing this file).
- `src/shared/Config.luau`: all tuning numbers. Change values here, not in logic.
- `src/shared/Remotes.luau`: RemoteEvents (Feedback, Round, Scores, Dash, Ready, ReadyState, MatchStart, Block, Options, Sheathe, ScoresRequest, QuickDraw). Server creates them.
- `src/server/BladeService.luau`: creates each player's blade and handle, and hands the blade's physics to that player's client.
- `src/server/CombatService.luau`: server-authoritative blade hits (by body part), clashes (parries), guard, sheathe state, stuns, kill credit, and dummy AI.
- `src/server/TrainingService.luau`: training mode (you vs your own dummy).
- `src/server/GameService.luau`: ready-up queue (needs `Config.MatchSize` players), lobby countdown, first to KillsToWin between the fighters, intermission, kill counts, post-kill reset countdown, and scores broadcast.
- `src/server/RoundState.luau`: shared "active", "paused", and "fighters" state.
- `src/server/Main.server.luau`: builds the floor and training dummy, starts services.
- `src/client/Main.client.luau`: input, HUD (mode label, feedback, self health bar top-left, opponent health bars top-right, stun bar, dash cooldown bar, round status, parry flash, scoreboard, Ready button), body facing, dash, duel intro camera.
- `src/client/Weapon.luau`: blade control and arm posing. A virtual cursor in an on-screen circle aims the blade, the arms are posed through the shoulder Motor6Ds (joint kept on the shoulder), plus guard, sheathe, and look-around.
- `src/client/LockedCamera.luau`: shift-lock style camera fixed to the head, turning with the body's facing (plus look-around offsets). Sheathing or drawing the blade pans smoothly between it and Roblox's normal camera (`Config.CameraPanTime`).
- `src/client/LockOn.luau`: lock-on target choice (the other fighter in a match, else the nearest training dummy) and the marker over it. `Main.client.luau` turns the body toward it.
- `src/client/Menu.luau`: title menu.

## Rules
- Combat logic stays on the server. The client moves its own blade and sends intent (guard, sheathe, dash) and displays results. The server reads the replicated blade for hits and clashes.
- Player-vs-player combat is only allowed between the two fighters while `RoundState.active` is true. The training dummy always works.
- At round start the server freezes the fighters and pauses combat for the duel intro's total time (the `Config.Duel*` values). The camera is client-only and uses Roblox's built-in camera APIs.
- Matches are 1v1 from a ready-up queue: a match starts only after `Config.MatchSize` players press Ready and stay ready through `Config.LobbyCountdown`. Everyone must press Ready again for the next match. Fighters spawn at x = ±12 on the arena's center line, facing each other (`startMatch` in `GameService`; assumes `MatchSize` = 2).
- Controls: the mouse moves the blade (no click to attack), F holds the guard, hold right mouse and move the mouse to look around (the blade holds still), X sheathes or draws the blade, Shift dashes, Q toggles lock-on (on by default: the body always faces the opponent, so A/D strafe without turning the camera; with no target or lock-on off, the body turns toward where it moves, as before), hold Left Alt to free the cursor for GUI buttons (gameplay input is locked meanwhile), Tab toggles the scoreboard. The old Simple/Manual click modes (M) and Q block are gone.
- Blade hits: the server samples points along the blade and tests them against the target's real part boxes (`Config.BladeThickness`). The blade must be moving (`Config.HitMinSpeed`), so a blade resting against someone deals nothing. Damage scales with the part touched (`Config.HitMultipliers`: head, torso, limb). Don't go back to a distance-from-center check.
- Sheathed mode (X): the blade sits on the left hip and can't hit, clash or guard (server flag set through the `Sheathe` remote). Once fully sheathed the game is in "default mode": Roblox's normal camera, free cursor, no cursor circle, no look-around, the body turns toward movement, and the arms are animated too. While the blade is drawn, the Animate script keeps running for the legs (`Config.LegAnimation`); While drawn, each arm hangs on its own Weld (the shoulder Motor6D is disabled), because the animator only drives Motor6Ds and so can't move the arms; default mode switches the Motor6Ds back on (`weldFor` and `releaseArms` in `Weapon.luau`). Clearing the Motor6D Transform after each animation update did not work. With `LegAnimation` false, the script is off while drawn. Keep both modes working.
- Quick draw: while sheathed, hold left click (`Config.QuickDrawButton`) and swing the mouse right, up or down (`Config.QuickDrawThreshold` pixels) to draw and slash straight out of the sheath. The client scripts the slash arc (`Config.QuickDrawTime`) through the normal blade, so hits and clashes use the usual checks; the `QuickDraw` remote tells the server, which confirms the player was sheathed and gives hits within `Config.QuickDrawBonusTime` a `Config.QuickDrawBonus` damage multiplier. A swing to the left does nothing.
- Camera and body facing: the locked camera follows the body's facing, so the body must not auto-turn toward a backward move or while looking around (it spins). `Main.client.luau` turns `AutoRotate` off in those cases.
- After every kill, combat pauses for `Config.KillResetCountdown` seconds, then the fighters are moved back to their match spots (x = ±12, facing each other, not the spawn location) and healed to full. Written, not yet tested in Studio. Kill counts live on the server; clients get them via the `Scores` remote.
- Don't add sound IDs or assets you can't confirm are usable. `Config.ParrySoundId` stays empty until the user sets it.
- Make small, focused changes and tell the user which files changed so they can copy them to `C:\Projects\RobloxGame` (or commit them locally).

## Current status
- Working and tested in Studio (from before the blade rework): parries, stun, dummy AI, health bar, round countdown, kill counter, parry screen flash.
- Written, not yet tested in Studio: lock-on (Q) with strafing, F guard, right-mouse look-around (polls the button each frame because Roblox's camera script can mark the press as handled), body-part blade hits, X sheathe with default animation and default mode (normal camera, cursor, and movement), the no-spin fix for backward movement, and the arm joint fix (arms stay attached to the shoulders).
- Stun timer (HUD bar under health, counts down the parry stun; server sends only the duration): written, not yet tested in Studio.
- Scoreboard (Tab) with per-round kills, and post-kill reset countdown with full heal: written, not yet tested in Studio.
- Guard (hold F, `Config.GuardKey`): the blade eases in front of the body, and while held incoming hits deal `Config.BlockReduction` (30%) less damage, and the target sees "BLOCK". Dodge still takes priority. Not available while sheathed.
- Dash (Shift, `Config.DashKey`): the client drives the movement with a LinearVelocity (the client owns its physics); the server only checks cooldown and grants the dodge window, so attacks show "DODGE!". Opponent HP bar top-right (only the other fighter, only during a match; `MatchStart` sends `{}` when a match ends): written, not yet tested in Studio.
- Ready-up queue (Ready button, 1v1 once 2 players are ready, countdown cancels if someone unreadies): written, not yet tested in Studio.
- Round duel intro (fighters only): the server anchors both fighters and pauses combat for the sum of `Config.DuelWideTime`, `DuelCloseTime` (×2), `DuelReturnTime`, and `DuelPanTime` (5.0s), and fires `MatchStart`. The client moves only the camera: wide level side-on shot, diagonal close-up on each fighter's midsection from the camera side (weapon-ready framing), wide shot again, then pan to the normal follow view. If the local character dies during the intro, the follow camera is restored immediately. Written, not yet tested in Studio.
- Next planned: balance tuning, lobby/spawn/map polish.
