--!strict
--[[
	Player-facing text shown by the client UI.

	Strings with %s / %d are string.format patterns; the comment on each says what
	fills them, in order. Keep those markers when editing the wording.
]]

local Text = {
	Welcome = {
		-- First ever session. (town name)
		FirstSession = "Welcome to %s. Explore the town to discover its districts.",
		-- Every later session. (town name, session number, districts discovered, total districts)
		Returning = "Welcome back to %s! Session %d · %d/%d districts discovered.",
		-- Shown when the DataStore is unavailable (e.g. Studio without API access).
		SavingDisabled = "Saving is unavailable this session: you can play, but your progress will not be kept.",
		-- Shown when the save takes a while to load (Config.Data.ClientLoadingNoticeDelay).
		Loading = "Loading your save…",
	},

	-- A district was discovered for the first time. (district name, discovered count, total)
	DistrictDiscovered = "New area discovered: %s (%d/%d)",

	DistrictsPanel = {
		Title = "Districts",
		-- (discovered count, total)
		Progress = "Discovered %d / %d",
		UndiscoveredName = "???",
		-- Shown in the badge of a district not discovered yet.
		UndiscoveredIcon = "?",
		UndiscoveredSubtitle = "Not discovered yet",
		CurrentTag = "You are here",
		-- The close button names the way to close the panel on each device.
		Close = {
			-- (the key bound to ToggleDistricts in Config.Input, as named on the
			-- player's keyboard layout)
			KeyboardMouse = "Close  [%s]",
			-- The controller's own button glyph (CloseMenu in Config.Input) is shown beside it.
			Gamepad = "Close",
			Touch = "Close",
		},
	},

	-- Warning overlay near the edge of the play area.
	Boundary = {
		Title = "Signal fading",
		Hint = "Turn back toward town",
		-- At (or past) the hard edge, where the player cannot go further.
		EdgeHint = "You can't go any further this way",
	},

	Ring = {
		-- HUD labels.
		WillpowerLabel = "WILLPOWER",
		ChargeLabel = "RING",
		-- Shown (server Notify) when the ring runs out of charge.
		Depleted = "Your ring has gone dark. Recharge it at the battery in the Sheriff's Office.",
		-- Shown once when charge drops to Config.Ring.Charge.LowThreshold.
		Low = "Ring charge low. Recharge at the battery in the Sheriff's Office.",
		Recharged = "Ring fully charged.",
		-- Short feedback when the server refuses a power. (%s = power name, for Cooldown)
		Rejected = {
			NotReady = "Your ring isn't ready yet",
			Cooldown = "%s is recharging",
			NoWillpower = "Not enough willpower",
			NoCharge = "Out of ring charge",
			Busy = "You can't do that right now",
			NoTarget = "Nothing to trap there",
			OutOfRange = "Too far away",
		},
	},

	-- Touch button labels that change while flying (the defaults are the Label
	-- fields in Config/Input.luau).
	Flight = {
		-- The Fly button while flying.
		LandLabel = "Land",
		-- The Boost button while a toggled boost is on (pressing it returns to cruise).
		CruiseLabel = "Cruise",
	},

	-- The oath spoken at the ring battery. Original text written for this game.
	Oath = {
		Lines = {
			"I carry this light into the dark places.",
			"Where fear speaks, my will answers.",
			"I will not look away. I will not stand down.",
			"This light is my promise. Let it hold.",
		},
		Interrupted = "The oath was interrupted.",
	},

	Combat = {
		-- Name shown above the training dummies (with their health bar).
		DummyName = "Practice Target",
	},
}

return Text
