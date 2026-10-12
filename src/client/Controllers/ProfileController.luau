--!strict
--[[
	ProfileController: the player's save summary, asked for once on start.

	The server answers Remotes.GetProfileSummary once the save has loaded (or
	with nothing if it could not load in time). On an answer this greets the
	player (first visit or welcome back with their session number) and, if the
	DataStore is unavailable this session, warns that progress will not be kept.

	The summary is only what the server chose to tell this client; nothing here
	changes saved data.

	API:
	  ProfileController:GetSummary(): ProfileSummary?   (nil until loaded, or if it failed)
	  ProfileController.SummaryLoaded  Signal(summary)  (fires at most once)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
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
	-- Yields until the server has loaded the save (or gives up on it).
	local ok, result = pcall(function(): Types.ProfileSummary?
		return Remotes.GetProfileSummary:Invoke()
	end)
	if not ok then
		warn(`[ProfileController] Could not ask for the profile summary: {result}`)
		return
	end
	local loaded = readSummary(result)
	if loaded == nil then
		warn("[ProfileController] The server sent no profile summary; progress info is unavailable this session")
		return
	end
	summary = loaded
	ProfileController.SummaryLoaded:Fire(loaded)
	greet(loaded)
end

export type ProfileController = typeof(ProfileController)

return ProfileController
