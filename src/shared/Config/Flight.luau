--!strict
--[[
	Flight tuning.

	The client moves its own character while flying (smooth, no input lag) and
	the server decides who may fly, drains willpower and ring charge, and checks
	that nobody flies faster than these numbers allow.

	Speeds are studs per second. "Responsiveness" values are rates (1/s) for
	exponential smoothing: higher reacts faster; about 1/value seconds to cover
	most of the way to the target.
]]

local Flight = {
	-- Top speed while flying normally / while holding Boost.
	CruiseSpeed = 70,
	BoostSpeed = 160,
	-- Climb / dive speed from the Ascend / Descend actions (added to the move direction).
	VerticalSpeed = 50,

	-- How quickly velocity follows the input (accelerating / slowing down).
	Acceleration = 3.5,
	BoostAcceleration = 2.2,
	Deceleration = 2.8,

	-- Upward kick (studs/s) when taking off from the ground.
	TakeoffImpulse = 40,

	-- Banking: the body rolls into turns. Roll angle (degrees) per degree per
	-- second of turning, capped at MaxBankAngle, smoothed by BankResponsiveness.
	BankPerTurnRate = 0.3,
	MaxBankAngle = 55,
	BankResponsiveness = 6,
	-- The body pitches forward as speed builds, up to this many degrees at full
	-- speed (the classic "flying" pose), and follows climbs and dives.
	MaxForwardPitch = 75,
	PitchResponsiveness = 5,

	-- Gentle bob while hovering with no input.
	HoverBobAmplitude = 0.35,
	HoverBobFrequency = 1.1,

	-- Holding Descend this close to the ground (studs below the feet) lands.
	AutoLandDistance = 3.5,

	-- Costs. Cruising only wears down ring charge, so willpower keeps
	-- regenerating and you can explore freely; boosting burns willpower fast.
	-- (Any willpower drain pauses regeneration, Config.Ring.Willpower.RegenDelay.)
	WillpowerPerSecond = 0,
	BoostWillpowerPerSecond = 10,
	ChargePerSecond = 0.06,
	-- Willpower needed to take off / to start boosting.
	MinWillpowerToTakeOff = 10,
	MinWillpowerToBoost = 5,

	-- Client feel (FlightController) -------------------------------------------

	-- Seconds the client waits for the server to confirm a takeoff (or boost) it
	-- started straight away, before landing again (or ending the boost).
	ServerAckTimeout = 1.5,
	-- Shortest time between two Fly presses (the server rate limits SetFlying to
	-- 3 a second, Config.Net, so mashing the button can never trip it).
	ToggleCooldown = 0.35,

	-- "Fly where you look": the camera's pitch steers climbs and dives, except
	-- within this many degrees of the horizon, which flies level (the default
	-- camera always looks a little down at the character).
	LevelFlightDeadZone = 15,
	-- Travel speed at which the forward pitch reaches MaxForwardPitch. Below
	-- cruise speed on purpose: at cruise you are already in the flying pose.
	FullPitchSpeed = 60,
	-- Diving (flying where you look, steeply down) tips the body head-first, up
	-- to this many degrees from upright (180 = straight down). Climbing turns it
	-- upright. Ascend / Descend alone never tilt the body: you rise and sink
	-- standing, as when hovering.
	MaxDivePitch = 150,
	-- How quickly the body turns toward its direction of travel.
	TurnResponsiveness = 7,
	-- Horizontal speeds over which the body goes from facing where the camera
	-- looks (hovering, aiming) to facing its direction of travel.
	FaceTravelMinSpeed = 6,
	FaceTravelFullSpeed = 22,
	-- Movers on the root part: force limit per unit of character mass (far above
	-- gravity, so flight is crisp) and how tightly the body follows its pose.
	ForcePerMass = 4000,
	AlignResponsiveness = 50,
	-- Hitting something bleeds speed off at this rate (so sliding past a wall
	-- does not fling you away at full speed). Velocity differences below
	-- CollisionTolerance are not treated as a hit.
	CollisionResponsiveness = 6,
	CollisionTolerance = 12,

	-- Near the ground, descending (including a dive) brakes at GroundBrake
	-- (studs/s²) so it stops GroundSkimHeight studs above standing height: you
	-- skim along instead of crashing. Holding Descend lands (AutoLandDistance).
	GroundSkimHeight = 0.5,
	GroundBrake = 300,

	-- Play-area edge: flight starts curving back once where it will be in
	-- BoundaryLookAhead seconds is inside the soft band, turning toward the inside
	-- at up to BoundaryBendSpeed, and never moves outward past it.
	BoundaryLookAhead = 1.2,
	BoundaryBendSpeed = 45,

	-- On these devices Boost is a toggle (holding a stick click or a touch button
	-- while also steering the camera is awkward). A toggled boost also ends after
	-- IdleStop seconds without movement input.
	BoostToggle = {
		Devices = { Gamepad = true, Touch = true } :: { [string]: boolean },
		IdleStop = 0.6,
	},

	-- Seconds the fly animations (Config.Assets.Animations.FlyIdle / FlyForward)
	-- take to fade in and out.
	AnimationFadeTime = 0.3,

	Camera = {
		-- Field of view (degrees) normally and at full boost.
		NormalFov = 70,
		BoostFov = 88,
		FovResponsiveness = 4,
		-- Extra degrees of field of view at full cruise speed (less when slower),
		-- on top of the boost: speed reads as speed.
		SpeedFovBonus = 4,
		-- Camera shake on takeoff and when a boost kicks in.
		TakeoffShake = { Intensity = 0.35, Duration = 0.35 },
		BoostShake = { Intensity = 0.25, Duration = 0.3 },
	},

	-- Server-side speed check (anti-exploit). Positions are sampled every
	-- SampleInterval seconds; a flying player moving faster than
	-- BoostSpeed * SpeedTolerance (+ LagAllowance studs per sample) for
	-- MaxViolations samples in a row is grounded and put back.
	Server = {
		SampleInterval = 0.5,
		SpeedTolerance = 1.4,
		LagAllowance = 30,
		MaxViolations = 3,
		-- Seconds between flight drain ticks on the server.
		DrainInterval = 0.25,
	},
}

return Flight
