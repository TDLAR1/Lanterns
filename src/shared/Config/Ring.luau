--!strict
--[[
	The power ring's two resources.

	WILLPOWER is the moment-to-moment resource: every power spends it and it
	regenerates by itself shortly after you stop using powers. Low willpower makes
	constructs weaker (see Strength).

	RING CHARGE is the long-term battery: powers wear it down slowly and it never
	regenerates on its own. The only way to refill it is the ring battery in the
	Sheriff's Office (the oath moment). At zero charge the ring goes dark: no
	powers until you recharge.

	Per-power costs live in Config/Flight.luau and Config/Powers.luau.
]]

local Theme = require(script.Parent.Theme)

local Ring = {
	Willpower = {
		Max = 100,
		-- Points regained per second once regeneration has started.
		RegenPerSecond = 12,
		-- Seconds after the last spend before regeneration starts.
		RegenDelay = 1.25,
	},

	Charge = {
		-- A new ring starts full (Config.Data.Template uses this).
		Max = 100,
		-- At or below this the HUD warns that the ring needs recharging.
		LowThreshold = 20,
	},

	--[[
		How strong constructs are, from the caster's willpower at the moment of
		casting. At or above FullAtWillpowerFraction of max willpower they are at
		full strength (multiplier 1); below that the multiplier falls linearly to
		MinMultiplier at zero willpower. The multiplier scales construct health,
		duration and damage (see Config/Powers.luau).
	]]
	Strength = {
		FullAtWillpowerFraction = 0.6,
		MinMultiplier = 0.45,
	},

	-- The ring battery in the Sheriff's Office back room.
	Battery = {
		PromptActionText = "Recharge ring",
		PromptObjectText = "Ring battery",
		-- Seconds the prompt must be held.
		PromptHoldDuration = 0.6,
		-- Studs from the battery within which the prompt shows.
		PromptMaxDistance = 10,
		-- Length of the oath moment (seconds). Charge fills over this time.
		OathDuration = 8,
		-- Moving further than this from the battery during the oath cancels it.
		CancelDistance = 14,
		-- Willpower is also refilled when the oath completes.
		RefillsWillpower = true,
	},

	-- The ring part welded to the character's right hand.
	Visual = {
		Color = Theme.RingGreen,
		-- Band (a short cylinder around the finger) and the stone on top.
		BandDiameter = 0.42,
		BandWidth = 0.18,
		StoneSize = 0.2,
		LightRange = 6,
		LightBrightness = 1.2,
	},

	-- Seconds between updates of the ring attributes (Willpower, RingCharge, ...)
	-- that clients read for the HUD.
	AttributeUpdateInterval = 0.1,
}

return Ring
