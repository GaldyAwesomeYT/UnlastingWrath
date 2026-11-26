-- Tuning values shared by server and client. Change numbers here, not in logic.
local Config = {
	GameName = "Parry Arena",

	-- Blade (mouse-controlled weapon). The client aims it; the server checks swings and hits.
	AttackDamage = 10,            -- base damage per hit
	WeaponLength = 3.2,           -- studs, blade length
	AimMaxAngle = 88,             -- degrees from straight ahead at the edge of the cursor circle (left, right, up or down)
	AimRange = 0.3,               -- radius of the cursor circle, as a fraction of the screen's shorter side (the circle is drawn on screen)
	ShowAimCircle = false,        -- true: draw the edge of the cursor circle on screen. false: the space is still there but invisible (only the cursor dot shows)
	EdgeTurnSensitivity = 0.004,  -- radians of turn per pixel of mouse movement pushed past the edge of the cursor circle (sideways turns the body and camera)
	EdgeTurnMaxPixels = 60,       -- most pixels of push counted in one frame, so a sudden mouse jump can't spin the player
	EdgePitchLimit = 30,          -- degrees the camera can tilt up or down from pushing the cursor past the circle's top or bottom
	EdgePitchReturn = 1.2,        -- radians per second the camera tilt eases back to level once the vertical push stops
	GripMotion = 1.0,            -- studs the grip shifts with the cursor, from the chest. Keeps the arms close to the body
	GuardBlendTime = 0.15,        -- seconds the blade takes to ease into or out of the guard pose (no snapping)
	AimSensitivity = 1.0,         -- how far the blade moves per pixel of mouse movement (lower = calmer)
	FreeCursorKey = "LeftAlt",    -- hold to unlock the mouse for GUI buttons. The blade holds still while it's held
	WeaponGripTarget = Vector3.new(0.3, 0.1, -1.4), -- resting grip point, in the HumanoidRootPart's space (+X right, +Y up, -Z forward); about the middle of the chest
	ArmMaxStretch = 1.5,          -- arms can stretch to this multiple of their normal length to reach the blade
	WeaponHandSpacing = 0.3,      -- studs along the handle from the right hand to the left hand (the left hand is further toward the tip)
	LegAnimation = true,          -- true: the default R6 animation keeps running while the blade is drawn, so the legs walk, jump and fall normally (the arms stay on the blade). false: the animation is off until the blade is sheathed
	AnimateLegs = false,         -- true: procedural walk swing for the legs. Off for now: the swing made the legs spread apart
	WeaponResponsiveness = 60,    -- how quickly the blade turns toward the mouse (0-200)
	BladeThickness = 0.3,         -- studs around the blade's edge that count as touching a body part (the blade must actually reach the body)
	HitMinSpeed = 6,              -- studs/second at the tip (relative to the body). A blade resting against someone deals no damage
	HitCooldown = 0.5,            -- seconds before the same blade can hit the same target again
	HitMultipliers = {            -- damage multiplier by the body part the blade touches
		Head = 2.0,
		Torso = 1.0,
		Limb = 0.5,
	},
	SheatheKey = "X",             -- press to sheathe the blade on the left hip; press again to draw it (Enum.KeyCode name)
	SheatheTime = 0.35,           -- seconds the blade takes to travel between the hip and the ready pose
	SheathePosition = Vector3.new(-1.1, -0.7, 0.2), -- where the sheathed blade's center sits, in the HumanoidRootPart's space (left hip)
	SheatheDirection = Vector3.new(0, -0.6, 1),     -- which way the sheathed blade points, in the same space (tip down and back)
	LockOnKey = "Q",              -- toggles lock-on (Enum.KeyCode name). Locked on, the body always faces the opponent and A/D strafe
	LockOnRange = 80,             -- studs; outside a match, the nearest training dummy within this range is locked
	LockOnTurnSpeed = 14,         -- how quickly the body turns to face the target (higher = snappier)
	QuickDrawButton = "MouseButton1", -- hold while sheathed and swing the mouse right, up or down to draw and slash (Enum.UserInputType name)
	QuickDrawThreshold = 80,      -- pixels of mouse movement (while the button is held) that count as a swing
	QuickDrawTime = 0.25,         -- seconds the slash takes
	QuickDrawBonus = 1.5,         -- damage multiplier for a quick-draw slash
	QuickDrawBonusTime = 0.5,     -- seconds after the draw that hits still get the bonus (checked by the server)
	GuardKey = "F",            -- hold to guard (Enum.KeyCode name)
	LookButton = "MouseButton2",  -- hold and move the mouse to look around (Enum.UserInputType name); the blade holds still
	LookSensitivity = 0.003,      -- radians of camera turn per pixel of mouse movement while looking around
	LookPitchLimit = 70,          -- degrees the camera can look up or down while looking around

	-- Clash (parry) and guard
	ClashRadius = 0.5,            -- studs between two blades that counts as a clash
	ClashMinSpeed = 15,           -- studs/second: both player blades must be moving at least this fast to clash (against a dummy, one moving blade is enough)
	ClashCooldown = 0.4,          -- seconds before the same two blades can clash again
	ParryStunDuration = 1.2,      -- a dummy is stunned this long when a player's blade clashes with its sword (player-vs-player clashes stun nobody)
	-- Max-Clash bar: every player-vs-player clash fills it for both players. Full = weakened.
	ClashBarGain = 0.2,           -- fraction of the bar added to both players per clash (0.2 = five clashes fill it)
	ClashBarIdleTime = 3,         -- seconds without a clash before the bar starts to drain
	ClashBarDrainPerSecond = 0.25, -- fraction of the bar lost per second once it is draining
	WeakenedDuration = 5,         -- seconds a player stays weakened after the bar fills (the bar empties over this time, then resets)
	WeakenedSpeedMultiplier = 0.5, -- walk speed multiplier while weakened
	WeakenedBladeResponsiveness = 0.25, -- multiplier on WeaponResponsiveness while weakened (lower = the blade takes longer to move)
	WeakenedDamageMultiplier = 0.5, -- damage multiplier for the weakened player's hits
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
	DummyAggroRange = 6,          -- studs; a dummy swings its sword when a player is this close (the sword reaches about 4 studs)
	DummyAttackInterval = 2.5,    -- seconds between dummy swings
	DummyWindup = 0.7,            -- telegraph time: the sword is raised this long before the swing
	DummySwingTime = 0.25,        -- seconds the dummy's slash takes
	DummyRecoverTime = 0.4,       -- seconds the dummy takes to lower its sword after a swing
	DummyReviveTime = 3,          -- seconds a killed dummy waits before it is healed back to full

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

	-- Camera (locked, shift-lock style): fixed to the head, no lag
	CameraRightOffset = 1.75,     -- studs to the right of the head
	CameraBackDistance = 7,       -- studs behind the head
	CameraHeight = 0.5,           -- studs above the head
	CameraPanTime = 0.8,          -- seconds for the smooth pan when the blade is sheathed or drawn (locked camera <-> normal camera)

	-- Dash / dodge
	DashKey = "LeftShift",        -- Enum.KeyCode name; SHIFT on the keyboard
	DashSpeed = 60,               -- studs/second while dashing (walk speed is 16)
	DashDuration = 0.2,           -- seconds of dash; the character is untouchable by attacks for this long
	DashCooldown = 1.5,           -- seconds between dashes (0.2s of dodge per 1.5s, about 13% uptime, down from 20%)
}

return Config
