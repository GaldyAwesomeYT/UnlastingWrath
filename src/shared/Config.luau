-- Tuning values shared by server and client. Change numbers here, not in logic.
local Config = {
	GameName = "Parry Arena",

	-- Blade (mouse-controlled weapon). The client aims it; the server checks swings and hits.
	AttackDamage = 10,            -- base damage per hit
	WeaponLength = 3.2,           -- studs, blade length
	WeaponPlaneDistance = 12,     -- studs in front of the camera where the mouse aims the blade
	WeaponGripTarget = Vector3.new(0.3, 0.1, -1.4), -- point the right arm reaches toward, in the HumanoidRootPart's space (+X right, +Y up, -Z forward); about the middle of the chest
	WeaponHandSpacing = 0.3,      -- studs along the handle from the right hand to the left hand (the left hand is further toward the tip)
	WeaponResponsiveness = 60,    -- how quickly the blade turns toward the mouse (0-200)
	WeaponHitRadius = 2.2,        -- studs around the blade that count as touching a target
	ControlledSwingSpeed = 20,    -- studs/second at the tip. Slower swings are "controlled": damage depends on the body part hit
	HitCooldown = 0.5,            -- seconds before the same blade can hit the same target again
	HitMultipliers = {            -- controlled swings only: damage multiplier by body region
		Head = 2.0,
		Torso = 1.0,
		Limb = 0.5,
	},
	GuardButton = "MouseButton2", -- hold to guard (Enum.UserInputType name)

	-- Clash (parry) and guard
	ClashRadius = 0.5,            -- studs between two blades that counts as a clash
	ClashMinSpeed = 15,           -- studs/second: both blades must be moving at least this fast to clash
	ClashCooldown = 0.4,          -- seconds before the same two blades can clash again
	ParryStunDuration = 1.2,      -- the slower blade's player is stunned this long after a clash
	ParrySoundId = "",            -- e.g. "rbxassetid://123456789"; leave empty for silent parries
	BlockReduction = 0.3,         -- fraction of attack damage removed while guarding (30%)

	-- Rounds
	KillsToWin = 5,               -- first to this many kills wins the round
	MatchSize = 2,                -- players who must press Ready before the lobby countdown starts (1v1)
	FighterSpawnX = 12,           -- fighters stand at x = -FighterSpawnX and +FighterSpawnX, facing each other
	FighterSpawnY = 3,            -- height of the fighter spawn points (studs above y = 0)
	LobbyCountdown = 5,           -- seconds before each match starts (ready players must stay ready)
	IntermissionTime = 5,         -- seconds after a round ends
	-- Round start duel intro: wide shot, close on fighter A, close on fighter B, wide shot, pan to follow view.
	-- The server freezes both fighters for the sum of these.
	DuelWideTime = 1.2,           -- first wide shot (level, side-on)
	DuelCloseTime = 1.0,          -- each close-up of a fighter's midsection and hands
	DuelReturnTime = 0.8,         -- wide shot again before the pan
	DuelPanTime = 1.0,            -- pan from the wide shot to the fighter's normal view
	RespawnTime = 3,              -- seconds until a dead player respawn
	KillCredit = 6,               -- a kill counts if the victim was hit by the killer this recently
	KillResetCountdown = 3,       -- after each kill: combat pauses this many seconds, then everyone is healed to full

	-- PvE training dummy
	DummyHealth = 100,
	DummyAggroRange = 15,         -- studs
	DummyAttackInterval = 2.5,    -- seconds between dummy swings
	DummyWindup = 0.7,            -- telegraph time before a dummy swing lands

	-- Game modes and training difficulty (picked on the title menu)
	GameModes = { "Duel", "Training" }, -- Duel: 1v1 ready-up queue. Training: you vs your own dummy.
	DefaultGameMode = "Duel",
	DifficultyNames = { "Easy", "Normal", "Hard" }, -- menu order
	DefaultDifficulty = "Normal",
	Difficulties = { -- training dummy stats per difficulty
		Easy = { health = 60, attackInterval = 3.5, windup = 1.0 },
		Normal = { health = 100, attackInterval = 2.5, windup = 0.7 },
		Hard = { health = 150, attackInterval = 1.8, windup = 0.5 },
	},

	-- Dash / dodge
	DashKey = "LeftShift",        -- Enum.KeyCode name; SHIFT on the keyboard
	DashSpeed = 60,               -- studs/second while dashing (walk speed is 16)
	DashDuration = 0.2,           -- seconds of dash; the character is untouchable by attacks for this long
	DashCooldown = 1.5,           -- seconds between dashes (0.2s of dodge per 1.5s, about 13% uptime, down from 20%)
}

return Config
