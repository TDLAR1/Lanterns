--!strict
-- Damage rules and the training dummies.

local Theme = require(script.Parent.Theme)

local Combat = {
	-- Whether ring powers can hurt other players. Off: the town is a shared hub;
	-- powers only affect Damageable targets (dummies, and mission enemies later).
	PvPEnabled = false,

	TrainingDummy = {
		Health = 250,
		-- Seconds after being destroyed before a dummy stands up again.
		RespawnTime = 4,
		-- Studs; the dummy's overall height.
		Height = 6,

		-- Seconds a fresh dummy takes to rise out of the ground.
		RiseTime = 0.5,
		-- When defeated it tips over (FallAngle degrees, away from its last
		-- attacker) over FallTime seconds, rests for FallenTime, then sinks
		-- SinkDepth studs while fading out over FadeTime.
		FallAngle = 84,
		FallTime = 0.55,
		FallenTime = 0.5,
		FadeTime = 0.6,
		SinkDepth = 0.6,

		-- Hits rock the dummy on its stand, away from the attacker: a damped
		-- spring on the lean angle. Each hit adds Impulse + damage * ImpulsePerDamage
		-- (radians per second) of lean speed; Stiffness (1/s^2) pulls it upright
		-- and Damping (1/s) settles it. Lean never exceeds MaxLean radians.
		Wobble = {
			Impulse = 0.6,
			ImpulsePerDamage = 0.055,
			Stiffness = 120,
			Damping = 9,
			MaxLean = 0.45,
			-- A caged dummy has little room to rock: impulses are scaled by this.
			CagedScale = 0.35,
		},

		-- Colours of the practice target (wooden post and arms, burlap body and
		-- head, iron base, painted target rings outer -> inner; the centre glows).
		Look = {
			Wood = Color3.fromRGB(120, 88, 60),
			Burlap = Color3.fromRGB(196, 170, 120),
			Base = Color3.fromRGB(72, 74, 78),
			TargetOuter = Color3.fromRGB(236, 228, 204),
			TargetMiddle = Color3.fromRGB(176, 52, 44),
			TargetCentre = Theme.RingGreen,
		},
	},

	-- Damage numbers shown to the attacker.
	HitFeedback = {
		Enabled = true,
		-- Hits within this many seconds on the same target merge into one number.
		MergeWindow = 0.35,
	},
}

return Combat
