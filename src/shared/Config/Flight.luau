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

	-- Costs. Flying drains willpower and ring charge every second; boosting
	-- drains willpower much faster.
	WillpowerPerSecond = 2,
	BoostWillpowerPerSecond = 10,
	ChargePerSecond = 0.06,
	-- Willpower needed to take off / to start boosting.
	MinWillpowerToTakeOff = 10,
	MinWillpowerToBoost = 5,

	Camera = {
		-- Field of view (degrees) normally and at full boost.
		NormalFov = 70,
		BoostFov = 88,
		FovResponsiveness = 4,
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
