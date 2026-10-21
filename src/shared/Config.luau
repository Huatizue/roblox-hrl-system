--!strict

local Config = {

	LaunchSpeed = 70,
	MaxSpeed = 280,
	BoostAcceleration = 420,
	BurnTime = 2.5,
	DragCoefficient = 0.08,
	InducedDragCoefficient = 0.00015,
	MinSpeed = 45,
	MaxLateralAcceleration = 1300,
	MinControlAuthority = 0.35,
	Gravity = 40,
	MaxLifetime = 12,

	GuidanceLaw = "InterceptPath",
	PathLookahead = 40,
	TerminalRange = 80,
	TerminalTurnRate = 900,
	NavigationConstant = 4,
	PursuitGain = 5,
	ArmingDelay = 0.2,
	TargetAccelerationSmoothing = 0.85,
	TargetVelocityWindow = 0.1,

	CursorLookahead = 35,
	CursorPursuitGain = 3.5,
	AimUpdateRate = 30,
	AimTimeout = 0.5,
	MaxAimOriginDistance = 150,

	SeekerFieldOfView = 70,
	SeekerRange = 1600,
	SeekerUpdateRate = 20,
	LockLossTimeout = 0.75,

	ProximityFuzeRadius = 7,
	MissDistance = 30,
	CollisionRadius = 0.6,
	BlastRadius = 20,
	MaxDamage = 100,
	MinDamageFraction = 0.25,
	DamageOwner = false,

	LauncherToolName = "MissileLauncher",
	TakeControlKey = Enum.KeyCode.E,
	ToggleModeKey = Enum.KeyCode.Q,
	TargetTag = "MissileTarget",
	LockTime = 1.0,
	LockConeAngle = 12,
	LockRange = 1400,
	FireCooldown = 1.25,
	MaxActiveMissilesPerPlayer = 4,
	LaunchForwardOffset = 3,

	SimulationRate = 60,
	SnapshotRate = 20,
	CorrectionBlendTime = 0.15,
	CorrectionSnapDistance = 40,

	Demo = {
		Enabled = true,
		DroneCount = 5,
		DroneHealth = 100,
		DroneSpeed = 70,
		DroneRespawnTime = 4,
		WreckRemoveRadius = 3,
		WreckBlastSpeed = 35,
		WreckLifetime = 12,
		ArenaRadius = 350,
		MinAltitude = 50,
		MaxAltitude = 140,
	},
}

export type Config = typeof(Config)

return Config
