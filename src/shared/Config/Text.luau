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
			KeyboardMouse = "Close  [M]",
			Gamepad = "Close  (B)",
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
}

return Text
