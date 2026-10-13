--!strict
--[[
	Sound and animation hooks.

	Every power plays a sound and (where it makes sense) an animation through
	these entries. They ship EMPTY because audio and animations must be uploaded
	to (or owned by) your own Roblox account or group before a game may use them.
	To add one, upload it (or take a free one from the Creator Store), copy its
	asset id and paste it as "rbxassetid://<id>". An empty string means "no asset":
	the game simply skips it, so nothing breaks while these are blank.
]]

local Assets = {
	Sounds = {
		-- Flight
		Takeoff = "",
		FlightLoop = "", -- looped while flying; pitch rises with speed
		BoostStart = "",
		Land = "",
		-- Beam
		BeamLoop = "", -- looped while firing
		BeamImpact = "",
		-- Shield
		ShieldUp = "",
		ShieldDown = "",
		-- Constructs
		WallSpawn = "",
		WallShatter = "",
		HammerSwing = "",
		HammerImpact = "",
		CageClose = "",
		CageRelease = "",
		-- Ring
		PowerRejected = "", -- short "fizzle" when a power can't be used
		RingDepleted = "",
		OathChoir = "", -- plays during the oath moment
		OathComplete = "",
		BatteryFlare = "", -- the battery flaring when an oath completes (heard by everyone nearby)
	},

	Animations = {
		FlyIdle = "", -- looped while hovering
		FlyForward = "", -- looped while flying fast
		BeamPose = "", -- arm raised while firing
		ConstructCast = "", -- short gesture when casting a construct
		OathPose = "", -- ring raised toward the battery
	},

	-- Volume (0..10, Roblox Sound.Volume) for every sound above.
	SoundVolume = 0.6,

	-- Sounds played at a part or position (3D) are heard at full volume within
	-- RollOffMinDistance studs and fade out by RollOffMaxDistance.
	RollOffMinDistance = 10,
	RollOffMaxDistance = 220,
	-- A one-shot sound is removed this many seconds after it starts at the
	-- latest, even if it never reports finishing (e.g. it failed to load).
	MaxOneShotSeconds = 15,
	-- Seconds a looped sound takes to fade out when it is stopped.
	LoopFadeTime = 0.2,
}

return Assets
