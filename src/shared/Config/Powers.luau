--!strict
--[[
	Combat powers: the energy beam, the shield bubble and hard-light constructs.

	Costs: WillpowerCost / ChargeCost are paid once per cast; *PerSecond values
	drain continuously while the power is held. MinWillpower is what you need to
	START the power. Cooldown is in seconds from the moment of use.

	"Scaled by strength" means multiplied by the caster's strength multiplier at
	the moment of casting (Config.Ring.Strength): weaker at low willpower.
]]

local Theme = require(script.Parent.Theme)

local Powers = {
	-- Hold to fire a continuous beam from the ring toward the crosshair.
	Beam = {
		DamagePerSecond = 32,
		Range = 180,
		-- Server damage ticks per second.
		TickRate = 10,
		WillpowerPerSecond = 16,
		ChargePerSecond = 0.2,
		MinWillpower = 8,
		Cooldown = 0.4,
		-- Visual thickness (studs) of the beam.
		Width = 0.7,
		-- Times per second the client sends its aim point while firing.
		AimSendRate = 15,
		-- Seconds without an aim update before other clients stop drawing a beam.
		VisualTimeout = 0.4,
		-- While the beam keeps hitting a target, the server asks every client to
		-- play a BeamImpact burst at most this often (seconds) per beam.
		ImpactEffectInterval = 0.3,
	},

	-- Toggle a bubble that absorbs most damage. Drains while up.
	Shield = {
		Radius = 5.5,
		WillpowerPerSecond = 9,
		ChargePerSecond = 0.1,
		MinWillpower = 10,
		-- Fraction of incoming damage absorbed while shielded (0..1).
		DamageReduction = 0.8,
		-- Cooldown after the shield drops (by choice or when willpower runs out).
		Cooldown = 1.5,
		-- While shielded you cannot fire the beam or cast constructs.
		BlocksAttacks = true,
		Color = Theme.RingGreen,
		Transparency = 0.72,
	},

	Constructs = {
		-- A hard-light wall standing on the ground at the aim point, facing you.
		-- It blocks movement and absorbs hits until destroyed or it expires.
		Wall = {
			DisplayName = "Wall",
			WillpowerCost = 22,
			ChargeCost = 1.2,
			Cooldown = 4,
			MinWillpower = 10,
			-- Max distance from the caster to the aim point.
			Range = 70,
			-- Width x height x thickness (studs). Not scaled.
			Size = Vector3.new(18, 11, 1.2),
			-- Scaled by strength.
			Health = 300,
			Duration = 10,
			-- The wall stands on the first surface found up to this many studs below
			-- the aim point; with nothing there (aiming at the sky) it floats,
			-- centred on the aim point.
			GroundSnapDistance = 40,
			-- Studs the wall's foot sinks into the ground, so slopes show no gap.
			GroundSink = 0.4,
			-- A wall aimed closer than this (studs, horizontally) to its caster is
			-- pushed out to this distance, so it never appears on top of them.
			MinDistance = 4,
		},

		-- A giant hammer that slams down on the aim point: area damage and knockback.
		Hammer = {
			DisplayName = "Hammer",
			WillpowerCost = 28,
			ChargeCost = 1.6,
			Cooldown = 5,
			MinWillpower = 10,
			Range = 80,
			-- Scaled by strength.
			Damage = 70,
			Radius = 12,
			-- Upward/outward push (studs/s) on targets that can move.
			Knockback = 70,
			-- Seconds from appearing to impact, and how long the hammer lingers after.
			SwingTime = 0.35,
			LingerTime = 0.8,
			-- Look (studs). The head is HeadSize.X wide, HeadSize.Y tall at impact
			-- (its lower face strikes the aim point) and HeadSize.Z long along the
			-- handle. It appears with the handle tilted up RaiseAngle degrees from
			-- level (90 = straight up), the head high over the near side of the aim
			-- point, and swings down about the end of the handle.
			HeadSize = Vector3.new(6, 10, 6),
			HandleLength = 14,
			HandleDiameter = 1.3,
			RaiseAngle = 75,
		},

		-- A hard-light cage that traps the nearest target within CaptureRadius of
		-- the aim point. Trapped targets cannot move or attack.
		Cage = {
			DisplayName = "Cage",
			WillpowerCost = 32,
			ChargeCost = 2,
			Cooldown = 8,
			MinWillpower = 15,
			Range = 80,
			CaptureRadius = 12,
			-- Scaled by strength.
			Duration = 6,
			-- Look: BarCount vertical bars (BarThickness studs) in a circle around the
			-- target's bounding box, with Padding studs of room around and above it.
			BarCount = 10,
			BarThickness = 0.45,
			Padding = 1.5,
		},
	},

	-- Constructs are drawn in this colour and material on every client.
	ConstructColor = Theme.RingGreen,
	ConstructTransparency = 0.25,
	-- Hard-light look: construct outlines (wall edges, hammer bands, cage rings)
	-- are this thick (studs) and this transparent, and every construct glows.
	ConstructEdge = {
		Thickness = 0.35,
		Transparency = 0,
	},
	ConstructLight = {
		Range = 16,
		Brightness = 1.5,
	},

	-- How far a construct's aim point may be from the caster, on top of the
	-- construct's Range: RangeTolerance studs, plus the caster's current speed
	-- times LatencyAllowance seconds (the client aimed from where it was a
	-- moment ago, which matters at flying speed).
	Aim = {
		RangeTolerance = 6,
		LatencyAllowance = 0.25,
	},

	-- Cycle order for the "next / previous construct" actions and the HUD.
	ConstructOrder = { "Wall", "Hammer", "Cage" },

	-- Client feel (PowerController) ---------------------------------------------
	Client = {
		-- Seconds combat mode (the over-the-shoulder aim) stays on after a cast.
		CastCombatTime = 0.5,
		-- Seconds the client waits for the server to confirm a beam (BeamActive)
		-- or a shield toggle (Shielding) before giving up on it locally.
		ConfirmTimeout = 1.5,
		-- Seconds the ConstructCast / BeamPose animations (Config.Assets) fade.
		AnimationFadeTime = 0.15,
	},
}

return Powers
