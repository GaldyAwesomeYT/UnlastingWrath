-- Shared match state.
-- active: a match is running. Player-vs-player combat is only allowed between two fighters while active.
-- paused: combat is frozen during the post-kill reset countdown.
-- fighters: [Player] = true for the players in the current match.
return { active = false, paused = false, fighters = {} }
