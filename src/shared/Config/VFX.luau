--!strict
--[[
	Visual effects of the ring powers (client only: VFXController and the
	helpers in StarterPlayerScripts.Client.VFX).

	Every effect is built from Parts, Beams, Trails, ParticleEmitters,
	Attachments and Lights using Roblox's built-in particle textures, so nothing
	has to be uploaded. Every client draws every player's effects, so keep
	particle rates, counts and lifetimes modest.

	Sizes are studs, times seconds, rates particles per second, counts particles
	per burst. "Responsiveness" values are rates (1/s) for exponential smoothing:
	about 1/value seconds to cover most of the way.
]]

local Theme = require(script.Parent.Theme)

-- A burst (or stream) of particles: Count particles leave at up to Speed
-- studs/s and live up to Lifetime seconds, shrinking from Size to nothing.
export type BurstSpec = {
	Count: number,
	Speed: number,
	Lifetime: number,
	Size: number,
	-- Degrees around the emitter's up direction; 180 (the default) = every way.
	Spread: number?,
	Drag: number?,
	-- Constant acceleration (studs/s²): gravity, or a rise.
	Acceleration: Vector3?,
	-- Starting transparency (they fade to invisible). Default 0.
	Transparency: number?,
	-- 1 (the default) glows; 0 is solid (dust, smoke).
	LightEmission: number?,
	-- Defaults to the sparkle texture and ring green.
	Texture: string?,
	Color: Color3?,
}

-- A light that flashes on at Brightness and dims out over Time.
export type LightSpec = {
	Range: number,
	Brightness: number,
	Time: number,
}

-- Built-in particle textures (shipped with the Roblox client).
local Textures = {
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Glow = "rbxasset://textures/particles/explosion01_core.dds",
}

local VFX = {
	Textures = Textures,

	-- Ring green for glows and particles; the hot centre of beams and flashes is
	-- nearly white with a green tint.
	Color = Theme.RingGreen,
	CoreColor = Color3.fromRGB(205, 255, 222),

	-- Workspace folder holding this client's effect parts (never replicated).
	FolderName = "RingEffects",

	-- The energy beam (the local one and other players'). Its core diameter is
	-- Config.Powers.Beam.Width; glow widths are multiples of it.
	Beam = {
		CoreTransparency = 0.05,
		-- Two soft glow layers around the core (flat Beams facing the camera).
		InnerGlowScale = 2.4,
		InnerGlowTransparency = 0.55,
		OuterGlowScale = 5,
		OuterGlowTransparency = 0.84,
		-- Crawling energy along the beam (sparkle texture scrolling forward).
		EnergyScale = 2,
		EnergyTransparency = 0.3,
		EnergyTextureLength = 2.5,
		EnergyTextureSpeed = 6,
		-- The width wobbles by up to FlickerAmount (fraction), about FlickerSpeed
		-- radians per second, so the beam feels alive.
		FlickerAmount = 0.16,
		FlickerSpeed = 32,
		-- Glow ball and light at the ring while firing.
		Muzzle = {
			Size = 0.95,
			Transparency = 0.15,
			LightRange = 9,
			LightBrightness = 2.5,
			SparkRate = 22,
			SparkLifetime = 0.25,
			SparkSpeed = 4,
			SparkSize = 0.22,
		},
		-- Glow, light and sparks where the beam hits something.
		Impact = {
			GlowSize = 1.9,
			GlowTransparency = 0.3,
			LightRange = 12,
			LightBrightness = 3,
			SparkRate = 70,
			SparkLifetime = 0.3,
			SparkSpeed = 16,
			SparkSize = 0.3,
			-- Degrees around "back toward the caster" the sparks spray, and how
			-- fast they fall (studs/s²).
			SparkSpread = 70,
			SparkGravity = 30,
		},
		-- Other players' beams arrive about 10 times a second (the server's beam
		-- tick); their drawn ends glide toward each update at this rate.
		RemoteResponsiveness = 20,
	},

	-- A ring of short neon segments that expands (or contracts) and fades: the
	-- takeoff burst, the hammer shockwave and the cage snap.
	Shockwave = {
		Segments = 22,
		Thickness = 0.35,
		Transparency = 0.1,
	},

	--[[
		One-shot effects (Remotes.PowerEffect). Particle bursts ("Sparks", "Dust",
		...) share one shape: Count particles leave at up to Speed studs/s and live
		up to Lifetime seconds, shrinking from Size; optional Spread (degrees
		around straight up, 180 = every way), Drag, Acceleration (studs/s², e.g.
		gravity), Transparency (at the start), LightEmission (1 glows, 0 is
		solid), Texture and Color. Lights flash on at Brightness and dim out over
		Time.
	]]
	Effects = {
		BeamImpact = {
			Sparks = { Count = 16, Speed = 22, Lifetime = 0.35, Size = 0.32, Acceleration = Vector3.new(0, -60, 0) } :: BurstSpec,
			-- A flash ball growing from FlashFrom to FlashTo (diameters).
			FlashFrom = 1,
			FlashTo = 2.6,
			FlashTime = 0.18,
			FlashTransparency = 0.2,
			Light = { Range = 14, Brightness = 4, Time = 0.27 } :: LightSpec,
		},
		Takeoff = {
			-- Studs below the root part the burst is centred (around the feet).
			FootOffset = 2.6,
			-- Diameters of the expanding ring, and of the flat disc flash under it.
			RingFrom = 2,
			RingTo = 15,
			DiscTo = 12,
			DiscTransparency = 0.55,
			Time = 0.45,
			-- Up and outward, like air pushed away by the launch.
			Sparks = { Count = 22, Speed = 14, Lifetime = 0.5, Size = 0.35, Spread = 75, Drag = 3 } :: BurstSpec,
			Light = { Range = 16, Brightness = 3, Time = 0.65 } :: LightSpec,
		},
		Shield = {
			-- Bubble pulse diameters, as multiples of the bubble
			-- (Config.Powers.Shield.Radius * 2).
			UpFrom = 0.45,
			UpTo = 1.2,
			DownFrom = 1,
			DownTo = 1.45,
			Time = 0.38,
			StartTransparency = 0.35,
			-- A raised shield's sparkles hang in the air; a dropped one's fall away.
			UpSparks = { Count = 18, Speed = 9, Lifetime = 0.6, Size = 0.3, Drag = 2 } :: BurstSpec,
			DownSparks = {
				Count = 18,
				Speed = 9,
				Lifetime = 0.6,
				Size = 0.3,
				Drag = 2,
				Acceleration = Vector3.new(0, -50, 0),
			} :: BurstSpec,
			Light = { Range = 14, Brightness = 2.5, Time = 0.75 } :: LightSpec,
		},
		WallSpawn = {
			-- A bright scan line sweeps up the wall in ScanTime (building a
			-- shimmering panel behind it, Margin studs bigger than the wall all
			-- round), then the panel fades over ShimmerTime. A wall this client
			-- cannot see (streamed out) is drawn facing the camera.
			ScanTime = 0.32,
			ScanThickness = 0.5,
			ScanEndTransparency = 0.4,
			Margin = 0.3,
			ShimmerTime = 0.6,
			ShimmerTransparency = 0.35,
			-- Drifting off the wall's surface while it builds (Count in total).
			Sparkles = {
				Count = 36,
				Speed = 2,
				Lifetime = 0.8,
				Size = 0.35,
				Drag = 1,
				Acceleration = Vector3.new(0, 2, 0),
			} :: BurstSpec,
			Light = { Range = 18, Brightness = 2.5, Time = 0.9 } :: LightSpec,
		},
		WallShatter = {
			-- Shards: ShardSize* across, ShardThickness* thick, flying out of either
			-- face at Speed* plus Upward, falling with Gravity, tumbling up to Spin
			-- radians per second and fading over Lifetime.
			ShardCount = 18,
			ShardSizeMin = 0.6,
			ShardSizeMax = 1.7,
			ShardThicknessMin = 0.15,
			ShardThicknessMax = 0.35,
			SpeedMin = 10,
			SpeedMax = 26,
			Upward = 10,
			Gravity = 55,
			Spin = 9,
			Lifetime = 0.95,
			Sparks = { Count = 24, Speed = 26, Lifetime = 0.6, Size = 0.35, Acceleration = Vector3.new(0, -28, 0) } :: BurstSpec,
			Light = { Range = 18, Brightness = 3, Time = 0.6 } :: LightSpec,
		},
		HammerImpact = {
			-- The shockwave ring grows from StartFraction of the radius (the
			-- effect's scale) to the full radius in Time; a flat disc flash from
			-- DiscFrom of the radius.
			StartFraction = 0.25,
			DiscFrom = 0.3,
			DiscTransparency = 0.6,
			Time = 0.45,
			Dust = {
				Count = 22,
				Speed = 11,
				Lifetime = 1.2,
				Size = 3.2,
				Texture = Textures.Smoke,
				Color = Color3.fromRGB(150, 140, 122),
				LightEmission = 0,
				Transparency = 0.35,
				Spread = 80,
				Drag = 2.5,
			} :: BurstSpec,
			Sparks = {
				Count = 20,
				Speed = 24,
				Lifetime = 0.5,
				Size = 0.4,
				Spread = 70,
				Acceleration = Vector3.new(0, -80, 0),
			} :: BurstSpec,
			-- Light range is LightRangeScale times the radius.
			LightRangeScale = 2,
			LightBrightness = 4,
			LightTime = 0.65,
			-- Camera shake: full ShakeIntensity within the radius, falling to 0 at
			-- ShakeDistance studs from the impact.
			ShakeIntensity = 0.9,
			ShakeDuration = 0.45,
			ShakeDistance = 70,
		},
		CageClose = {
			-- A ring snaps inward from RingFrom to RingTo (diameters) in Time while
			-- a flash shrinks from FlashSize to FlashEndScale of it.
			RingFrom = 14,
			RingTo = 5,
			Time = 0.16,
			FlashSize = 7,
			FlashEndScale = 0.3,
			FlashTime = 0.25,
			FlashTransparency = 0.3,
			Sparks = { Count = 20, Speed = 12, Lifetime = 0.45, Size = 0.35, Drag = 4 } :: BurstSpec,
			Light = { Range = 16, Brightness = 4, Time = 0.5 } :: LightSpec,
		},
		CageRelease = {
			FlashFrom = 3,
			FlashTo = 8,
			FlashTime = 0.4,
			FlashTransparency = 0.45,
			Sparks = {
				Count = 24,
				Speed = 6,
				Lifetime = 1,
				Size = 0.3,
				Drag = 2,
				Acceleration = Vector3.new(0, 10, 0),
			} :: BurstSpec,
			Light = { Range = 14, Brightness = 3, Time = 0.8 } :: LightSpec,
		},
		BatteryFlare = {
			FlashFrom = 2,
			FlashTo = 24,
			FlashTime = 0.85,
			FlashTransparency = 0.05,
			RingTo = 36,
			Sparks = { Count = 60, Speed = 26, Lifetime = 1, Size = 0.45, Drag = 2 } :: BurstSpec,
			-- A few huge soft glows blooming out of the battery.
			Bloom = {
				Count = 5,
				Speed = 3,
				Lifetime = 0.9,
				Size = 12,
				Texture = Textures.Glow,
				Transparency = 0.35,
			} :: BurstSpec,
			Light = { Range = 60, Brightness = 8, Time = 1.3 } :: LightSpec,
		},
		RingDepleted = {
			Sparks = {
				Count = 10,
				Speed = 6,
				Lifetime = 0.8,
				Size = 0.25,
				Acceleration = Vector3.new(0, -40, 0),
			} :: BurstSpec,
			Smoke = {
				Count = 4,
				Speed = 1.5,
				Lifetime = 1.4,
				Size = 1.2,
				Texture = Textures.Smoke,
				Color = Color3.fromRGB(90, 96, 92),
				LightEmission = 0,
				Transparency = 0.5,
				Spread = 30,
				Acceleration = Vector3.new(0, 1.5, 0),
			} :: BurstSpec,
			-- The ring's light stutters out over FlickerTime: each frame it is on
			-- (and weaker each time) with chance FlickerOnChance.
			LightRange = 8,
			LightBrightness = 3,
			FlickerTime = 0.8,
			FlickerOnChance = 0.65,
		},
	},

	-- Thickness of the flat ground discs under takeoff and hammer bursts.
	DiscThickness = 0.15,

	-- The wall effects find the wall they belong to (for its size and facing):
	-- the wall standing (or removed up to RememberTime seconds ago) within
	-- MatchDistance studs of the effect.
	Walls = {
		MatchDistance = 2,
		RememberTime = 2,
	},

	-- Glowing trails on every flying player's hands and feet, and a soft light.
	-- "Boost" values apply while boosting.
	Flight = {
		TrailLifetime = 0.3,
		BoostTrailLifetime = 0.55,
		-- Ribbon width.
		TrailWidth = 0.35,
		BoostTrailWidth = 0.6,
		TrailTransparency = 0.35,
		BoostTrailTransparency = 0.08,
		LightRange = 8,
		LightBrightness = 1,
		BoostLightRange = 13,
		BoostLightBrightness = 2.2,
		-- Sparkles shed behind a boosting flyer.
		BoostSparkRate = 40,
		BoostSparkLifetime = 0.5,
		BoostSparkSize = 0.3,
		BoostSparkSpeed = 1,
		-- The FlightLoop sound's pitch: MinPitch hovering, MaxPitch at boost speed.
		MinPitch = 0.85,
		MaxPitch = 1.35,
	},

	-- A soft glow and slow sparkles around anyone whose shield is up (the bubble
	-- itself is the server's).
	ShieldAura = {
		LightRange = 13,
		LightBrightness = 1.4,
		-- A slow stream (SparkRate per second) over the bubble's surface.
		SparkRate = 8,
		Sparkles = { Count = 0, Speed = 0.5, Lifetime = 1.2, Size = 0.3, Drag = 1 } :: BurstSpec,
	},

	-- Thin light streaks rushing out past the screen edges while the local
	-- player boosts.
	SpeedStreaks = {
		Count = 16,
		MaxOpacity = 0.55,
		-- Pixels at UI scale 1.
		Thickness = 2,
		LengthMin = 50,
		LengthMax = 150,
		LifetimeMin = 0.22,
		LifetimeMax = 0.4,
		-- Distances are fractions of half the screen (1 = the edge): streaks
		-- start StartRadius (to StartRadius + StartSpread) out from the centre,
		-- so the middle where you aim stays clear, and rush outward at Speed per
		-- second.
		StartRadius = 0.55,
		StartSpread = 0.2,
		Speed = 2.2,
		-- How quickly the streaks fade in when a boost starts and out when it ends.
		Responsiveness = 6,
		-- Speed (fraction of Config.Flight.BoostSpeed) needed for full streaks.
		FullAtSpeedFraction = 0.75,
	},

	-- The local ring's light follows willpower: at zero willpower it shines at
	-- MinWillpowerBrightness of its normal brightness (and MinWillpowerRange of
	-- its range); with no ring charge it all but goes out.
	RingGlow = {
		MinWillpowerBrightness = 0.25,
		MinWillpowerRange = 0.6,
		DepletedBrightness = 0.05,
		-- Extra brightness (multiplier) while firing the beam.
		FiringBoost = 1.8,
	},

	-- Floating damage numbers shown to the attacker (Remotes.HitConfirmed).
	HitNumbers = {
		Lifetime = 0.9,
		-- Studs the number rises over its lifetime.
		Rise = 3,
		-- Text size grows with the amount, reaching TextSizeMax at AmountForMax.
		TextSizeMin = 20,
		TextSizeMax = 34,
		AmountForMax = 60,
		-- Random sideways offset (studs) so quick numbers do not stack exactly.
		Jitter = 1.2,
		-- Starts this much bigger and settles in PopTime.
		PopScale = 1.5,
		PopTime = 0.12,
		FadeTime = 0.35,
		MaxDistance = 300,
		Color = Color3.fromRGB(225, 255, 235),
		StrokeColor = Theme.PanelColor,
		StrokeThickness = 2,
	},
}

return VFX
