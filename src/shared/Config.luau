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
	LobbyCountdown = 5,       -- seconds before each round starts
	IntermissionTime = 5,     -- seconds after a round ends
	RespawnTime = 3,          -- seconds until a dead player respawn
	KillCredit = 6,           -- a kill counts if the victim was hit by the killer this recently

	-- PvE training dummy
	DummyHealth = 100,
	DummyAggroRange = 15,     -- studs
	DummyAttackInterval = 2.5, -- seconds between dummy swings
	DummyWindup = 0.7,        -- telegraph time before a dummy swing lands
}

return Config
