--!strict
--[[
	ProfileController: the player's save summary, asked for on start and again
	until the save has loaded.

	The server answers Remotes.GetProfileSummary once the save has loaded, which
	can take up to Config.Data.ClientWaitTimeout (with nothing if it could not
	load; the server then kicks the player). If the answer is slow the player is
	told their save is still loading. On an answer this greets the player (first
	visit or welcome back with their session number) and, if the DataStore is
	unavailable this session, warns that progress will not be kept.

	The summary is only what the server chose to tell this client; nothing here
	changes saved data.

	API:
	  ProfileController:GetSummary(): ProfileSummary?   (nil until loaded, or if it failed)
	  ProfileController.SummaryLoaded  Signal(summary)  (fires at most once)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local DataConfig = require(Shared.Config.Data)
local GameConfig = require(Shared.Config.Game)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Util.Signal)
local Text = require(Shared.Config.Text)
local Types = require(Shared.Types)

local NotificationController = require(script.Parent.NotificationController)

local summary: Types.ProfileSummary? = nil

local ProfileController = {
	-- The summary arrived from the server. (summary)
	SummaryLoaded = Signal.new() :: Signal.Signal<Types.ProfileSummary>,
}

-- Checks the shape of the server's answer so a malformed or missing field can
-- never break the UI. Returns nil if it is unusable.
local function readSummary(raw: any): Types.ProfileSummary?
	if type(raw) ~= "table" then
		return nil
	end
	local sessionCount, total, savingEnabled, ids =
		raw.SessionCount, raw.TotalDistricts, raw.SavingEnabled, raw.DiscoveredDistricts
	if
		type(sessionCount) ~= "number"
		or type(total) ~= "number"
		or type(savingEnabled) ~= "boolean"
		or type(ids) ~= "table"
	then
		return nil
	end
	local discovered: { string } = {}
	for _, id in ids do
		if type(id) == "string" then
			table.insert(discovered, id)
		end
	end
	return {
		SessionCount = sessionCount,
		DiscoveredDistricts = discovered,
		TotalDistricts = total,
		SavingEnabled = savingEnabled,
	}
end

local function greet(loaded: Types.ProfileSummary)
	-- ProfileStore counts the session being played, so the first visit is 1.
	if loaded.SessionCount <= 1 then
		NotificationController:Notify(string.format(Text.Welcome.FirstSession, GameConfig.TownName), "Info")
	else
		NotificationController:Notify(
			string.format(
				Text.Welcome.Returning,
				GameConfig.TownName,
				loaded.SessionCount,
				#loaded.DiscoveredDistricts,
				loaded.TotalDistricts
			),
			"Info"
		)
	end
	if not loaded.SavingEnabled then
		NotificationController:Notify(Text.Welcome.SavingDisabled, "Warning")
	end
end

function ProfileController.GetSummary(_self: ProfileController): Types.ProfileSummary?
	return summary
end

function ProfileController.Init(_self: ProfileController) end

function ProfileController.Start(_self: ProfileController)
	-- A save normally loads in a second or two, but ProfileStore needs 45 s or more
	-- to take over a save still locked by a server that crashed, so say so if the
	-- answer is slow rather than leaving the player wondering.
	local answered = false
	task.delay(DataConfig.ClientLoadingNoticeDelay, function()
		if not answered then
			NotificationController:Notify(Text.Welcome.Loading, "Info")
		end
	end)

	-- Ask until the save has loaded. An empty answer means it has not (yet): the
	-- request was dropped or arrived before the server was ready. If the save
	-- cannot load at all the server kicks the player, so the loop ends with the
	-- session. Each request blocks on the server until the save loads, so asking
	-- at most once per ClientRetryDelay stays well inside RateLimits.GetProfileSummary.
	local warned = false
	while true do
		-- Yields until the server has loaded the save (or gives up on it).
		local ok, result = pcall(function(): Types.ProfileSummary?
			return Remotes.GetProfileSummary:Invoke()
		end)
		if not ok then
			answered = true
			warn(`[ProfileController] Could not ask for the profile summary: {result}`)
			return
		end
		local loaded = readSummary(result)
		if loaded ~= nil then
			answered = true
			summary = loaded
			ProfileController.SummaryLoaded:Fire(loaded)
			greet(loaded)
			return
		end
		if not warned then
			warned = true
			warn("[ProfileController] The server sent no profile summary yet; asking again")
		end
		task.wait(DataConfig.ClientRetryDelay)
	end
end

export type ProfileController = typeof(ProfileController)

return ProfileController
