--!strict
-- Save-data settings. Profiles are stored with ProfileStore (session locked).

local Types = require(script.Parent.Parent.Types)

local Data = {
	-- DataStore name. Changing it starts everyone from scratch, so only do that on purpose.
	StoreName = "PlayerData_v1",
	-- DataStore key = KeyPrefix .. UserId
	KeyPrefix = "Player_",

	-- true = never touch the real DataStore in Studio (in-memory data, lost when you stop).
	-- false = use the real DataStore when Studio has API access (Game Settings > Security).
	UseMockInStudio = false,

	-- How long a client's first data request may wait for the profile to load.
	ClientWaitTimeout = 30,

	LoadFailedKickMessage = "We couldn't load your save data. Please rejoin in a moment.",
	SessionTakenKickMessage = "Your save data was opened on another server. Please rejoin.",

	-- Default data for new players. Fields added here later are filled into
	-- existing saves automatically when they load.
	Template = {
		SchemaVersion = 1,
		DiscoveredDistricts = {},
	} :: Types.PlayerData,
}

return Data
