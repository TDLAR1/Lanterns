--!strict
-- Save-data settings. Profiles are stored with ProfileStore (session locked).

local RingConfig = require(script.Parent.Ring)
local Types = require(script.Parent.Parent.Types)

-- Shared by SessionStartTimeout and ClientWaitTimeout below so the two cannot drift apart.
local SESSION_START_TIMEOUT = 120

local Data = {
	-- DataStore name. Changing it starts everyone from scratch, so only do that on purpose.
	StoreName = "PlayerData_v1",
	-- DataStore key = KeyPrefix .. UserId
	KeyPrefix = "Player_",

	-- true = never touch the real DataStore in Studio (in-memory data, lost when you stop).
	-- false = use the real DataStore when Studio has API access (Game Settings > Security).
	UseMockInStudio = false,

	-- Longest a player's save may take to load before they are kicked with
	-- LoadFailedKickMessage. DataService gives ProfileStore a Cancel callback, which
	-- switches off ProfileStore's own 120 s start timeout, so this deadline replaces it.
	-- Keep it well above ~50 s: the time ProfileStore needs to take over a save that is
	-- still locked by a server that crashed or never released it.
	SessionStartTimeout = SESSION_START_TIMEOUT,
	-- How long one GetProfileSummary request waits for the save to load. Must stay at or
	-- above SessionStartTimeout so a save that loads slowly (session takeover, DataStore
	-- hiccup) is still answered instead of the client giving up first.
	ClientWaitTimeout = SESSION_START_TIMEOUT + 10,
	-- Seconds the client waits before asking for the summary again after an empty answer
	-- (e.g. the request was rate limited or arrived before the server was ready).
	ClientRetryDelay = 5,
	-- Seconds without a summary before the client tells the player their save is still loading.
	ClientLoadingNoticeDelay = 5,

	LoadFailedKickMessage = "We couldn't load your save data. Please rejoin in a moment.",
	SessionTakenKickMessage = "Your save data was opened on another server. Please rejoin.",

	-- Told to everyone (Notify) when the DataStore keeps failing, and again once it recovers.
	-- Data stays in memory meanwhile and is saved as soon as the DataStore works again.
	SavingTroubleMessage = "Saving is having trouble right now. Keep playing: your progress is kept and will save once it recovers.",
	SavingRecoveredMessage = "Saving is working again. Your progress is safe.",

	-- Default data for new players. Fields added here later are filled into
	-- existing saves automatically when they load.
	Template = {
		SchemaVersion = 1,
		DiscoveredDistricts = {},
		Ring = {
			-- A brand-new ring starts full.
			Charge = RingConfig.Charge.Max,
		},
	} :: Types.PlayerData,
}

return Data
