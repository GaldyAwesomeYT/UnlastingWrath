-- Tuning values shared by server and client. Change numbers here, not in logic.
local Config = {
	GameName = "Parry Arena",

	-- Attacks
	AttackDamage = 10,
	AttackRange = 7,          -- studs
	AttackCooldown = 0.5,     -- seconds
	SimpleConeDot = 0,        -- Simple mode: target must be in front (0 = front half)
	ManualConeDot = 0.85,     -- Manual mode: target must be within ~32 degrees of the cursor

	-- Parrying
	ParryWindow = 0.3,        -- seconds a parry press stays active
	ParryCooldown = 1.0,      -- seconds between parry presses
	ParryStunDuration = 1.0,  -- attacker is stunned this long after being parried
	ParrySoundId = "",        -- e.g. "rbxassetid://123456789"; leave empty for silent parries

	-- Rounds
	KillsToWin = 5,           -- first to this many kills wins the round
	MatchSize = 2,            -- players who must press Ready before the lobby countdown starts (1v1)
	LobbyCountdown = 5,       -- seconds before each match starts (ready players must stay ready)
	IntermissionTime = 5,     -- seconds after a round ends
	-- Round start duel intro: wide shot, close on fighter A, close on fighter B, wide shot, pan to follow view.
	-- The server freezes both fighters for the sum of these.
	DuelWideTime = 1.2,       -- first wide shot (level, side-on)
	DuelCloseTime = 1.0,      -- each close-up of a fighter's midsection and hands
	DuelReturnTime = 0.8,     -- wide shot again before the pan
	DuelPanTime = 1.0,        -- pan from the wide shot to the fighter's normal view
	RespawnTime = 3,          -- seconds until a dead player respawn
	KillCredit = 6,           -- a kill counts if the victim was hit by the killer this recently
	KillResetCountdown = 3,   -- after each kill: combat pauses this many seconds, then everyone is healed to full

	-- PvE training dummy
	DummyHealth = 100,
	DummyAggroRange = 15,     -- studs
	DummyAttackInterval = 2.5, -- seconds between dummy swings
	DummyWindup = 0.7,        -- telegraph time before a dummy swing lands

	-- Dash / dodge
	DashKey = "LeftShift",    -- Enum.KeyCode name; SHIFT on the keyboard
	DashSpeed = 60,           -- studs/second while dashing (walk speed is 16)
	DashDuration = 0.2,       -- seconds of dash; the character is untouchable by attacks for this long
	DashCooldown = 1.0,       -- seconds between dashes

	-- Block (hold)
	BlockKey = "Q",           -- Enum.KeyCode name; hold to block
	BlockReduction = 0.3,     -- fraction of attack damage removed while blocking (30%)
}

return Config
