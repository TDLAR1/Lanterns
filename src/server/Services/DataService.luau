--!strict
--[[
	DataService: loads, holds and saves every player's data with ProfileStore
	(session locked, so two servers can never write the same save at once).

	  * A profile is loaded when the player joins and released when they leave.
	    ProfileStore autosaves in between and saves everything on shutdown.
	  * Other services read and change a player's data through GetData(). The
	    returned table IS the save: modify it in place, never replace it, and only
	    while it is loaded (GetData returns nil otherwise).
	  * If Roblox reports no DataStore access at all (e.g. Studio without API
	    access), ProfileStore falls back to in-memory data and the game keeps
	    working; IsSavingEnabled() tells whether progress will actually be saved.
	  * If the DataStore is reachable but keeps failing (an outage), a save that
	    cannot load within Config.Data.SessionStartTimeout gets the player kicked
	    with LoadFailedKickMessage rather than playing on untracked progress.

	API:
	  DataService:GetData(player): PlayerData?
	  DataService:WaitForData(player, timeout): PlayerData?   (yields)
	  DataService:GetSessionCount(player): number
	  DataService:IsSavingEnabled(): boolean
	  DataService.ProfileLoaded    Signal(player, data)
	  DataService.ProfileReleased  Signal(player)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local DataConfig = require(Shared.Config.Data)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)
local WorldConfig = require(Shared.Config.World)

local ProfileStore = require(script.Parent.Parent.Vendor.ProfileStore)

-- The parts of ProfileStore's API this service uses, typed for our save format.
-- ProfileStore's own generic types intersect Data with a recursive JSON union
-- that strict mode cannot compare, and its params type leaves out Cancel (which
-- it does support), so the store is cast to these once, below.
type ProfileSignal = {
	Connect: (self: ProfileSignal, listener: () -> ()) -> { Disconnect: (self: any) -> () },
}

type Profile = {
	Data: Types.PlayerData,
	SessionLoadCount: number,
	OnSessionEnd: ProfileSignal,
	AddUserId: (self: Profile, userId: number) -> (),
	Reconcile: (self: Profile) -> (),
	EndSession: (self: Profile) -> (),
}

type SessionParams = {
	-- Polled while the session is starting; returning true makes it give up (returns nil).
	Cancel: () -> boolean,
}

type Store = {
	StartSessionAsync: (self: Store, profileKey: string, params: SessionParams) -> Profile?,
}

-- A thread parked in WaitForData, plus the delayed thread that wakes it on timeout.
type Waiter = {
	thread: thread,
	timeoutThread: thread,
}

local usingMock = RunService:IsStudio() and DataConfig.UseMockInStudio
local profileStore = ProfileStore.New(DataConfig.StoreName, DataConfig.Template)
-- The Mock store has the same API but keeps data in memory only.
local store: Store = (if usingMock then profileStore.Mock else profileStore) :: any

local profiles: { [Player]: Profile } = {}
local loading: { [Player]: boolean } = {}
local waiters: { [Player]: { Waiter } } = {}

local DataService = {
	-- A player's data finished loading and is ready to use. (player, data)
	ProfileLoaded = Signal.new() :: Signal.Signal<Player, Types.PlayerData>,
	-- A loaded profile was released: the player left, or the save was taken by
	-- another server. GetData returns nil from now on. (player)
	ProfileReleased = Signal.new() :: Signal.Signal<Player>,
}

-- Wakes every WaitForData call for this player with `data` (nil = gave up).
local function resumeWaiters(player: Player, data: Types.PlayerData?)
	local list = waiters[player]
	if list == nil then
		return
	end
	waiters[player] = nil
	for _, waiter in list do
		task.cancel(waiter.timeoutThread)
		task.spawn(waiter.thread, data)
	end
end

local function isInGame(player: Player): boolean
	return player.Parent == Players
end

local function startSession(player: Player): Profile?
	-- Cancelling stops ProfileStore's (possibly long) retry loop once the player has
	-- left. Passing Cancel also switches off ProfileStore's own start timeout, so
	-- the deadline lives here: without it a DataStore outage would retry for as
	-- long as the player stays, and they would never reach the load-failed kick.
	-- ProfileStore also checks Cancel after a load succeeds and releases a profile
	-- that arrives too late, so no load can finish after this deadline.
	-- Cancel runs inside UpdateAsync transforms, so it must never yield.
	local startedAt = os.clock()
	local params: SessionParams = {
		Cancel = function(): boolean
			return not isInGame(player) or os.clock() - startedAt >= DataConfig.SessionStartTimeout
		end,
	}
	-- pcall: ProfileStore errors (rather than returning nil) on misuse such as a
	-- duplicate session; the player must still get the load-failed path.
	local ok, result = pcall(function(): Profile?
		return store:StartSessionAsync(DataConfig.KeyPrefix .. player.UserId, params)
	end)
	if not ok then
		warn(`[DataService] Could not start a session for {player.Name} ({player.UserId}): {result}`)
		return nil
	end
	return result
end

local function loadProfile(player: Player)
	-- PlayerAdded and the "already in game" pass in Start can both reach a player.
	if profiles[player] ~= nil or loading[player] then
		return
	end
	loading[player] = true
	local profile = startSession(player)
	loading[player] = nil

	if profile == nil then
		resumeWaiters(player, nil)
		if isInGame(player) then
			player:Kick(DataConfig.LoadFailedKickMessage)
		end
		return
	end

	if not isInGame(player) then
		-- Left while the profile was loading.
		profile:EndSession()
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()

	profile.OnSessionEnd:Connect(function()
		-- PlayerRemoving forgets the profile BEFORE ending the session, so if it is
		-- still stored here the session was ended from outside: another server took
		-- the save, or this server is shutting down.
		local endedElsewhere = profiles[player] == profile
		if endedElsewhere then
			profiles[player] = nil
		end
		DataService.ProfileReleased:Fire(player)
		-- During shutdown everyone is leaving anyway; "opened on another server" would be wrong.
		if endedElsewhere and not ProfileStore.IsClosing and isInGame(player) then
			player:Kick(DataConfig.SessionTakenKickMessage)
		end
	end)

	profiles[player] = profile
	local data: Types.PlayerData = profile.Data
	DataService.ProfileLoaded:Fire(player, data)
	-- OnCriticalToggle only announces changes; a player loading in while saving is
	-- already failing must be told now (the client queues it until it listens).
	if ProfileStore.IsCriticalState then
		Remotes.Notify:FireClient(player, DataConfig.SavingTroubleMessage, "Warning")
	end
	resumeWaiters(player, data)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	profiles[player] = nil
	resumeWaiters(player, nil)
	if profile ~= nil then
		profile:EndSession()
	end
end

local function buildSummary(player: Player, data: Types.PlayerData): Types.ProfileSummary
	-- Config order (not save order) so the client can show them as listed; ids
	-- that are not districts any more are left out.
	local discovered = {}
	for _, district in WorldConfig.Districts do
		if data.DiscoveredDistricts[district.Id] == true then
			table.insert(discovered, district.Id)
		end
	end
	return {
		SessionCount = DataService:GetSessionCount(player),
		DiscoveredDistricts = discovered,
		TotalDistricts = #WorldConfig.Districts,
		SavingEnabled = DataService:IsSavingEnabled(),
	}
end

-- The player's loaded data, or nil if it is not loaded (yet / any more).
function DataService.GetData(_self: DataService, player: Player): Types.PlayerData?
	local profile = profiles[player]
	if profile == nil then
		return nil
	end
	return profile.Data
end

-- Yields until the player's data is loaded and returns it. Returns nil if the
-- player leaves, their data cannot be loaded, or `timeout` seconds pass first.
function DataService.WaitForData(self: DataService, player: Player, timeout: number): Types.PlayerData?
	local data = self:GetData(player)
	if data ~= nil or not isInGame(player) then
		return data
	end

	local list = waiters[player]
	if list == nil then
		list = {}
		waiters[player] = list
	end
	local thread = coroutine.running()
	local waiter: Waiter
	waiter = {
		thread = thread,
		timeoutThread = task.delay(timeout, function()
			-- Still waiting (resumeWaiters cancels this thread otherwise): give up.
			local current = waiters[player]
			if current ~= nil then
				local index = table.find(current, waiter)
				if index ~= nil then
					table.remove(current, index)
				end
				if #current == 0 then
					waiters[player] = nil
				end
			end
			task.spawn(thread, nil)
		end),
	}
	table.insert(list, waiter)
	return coroutine.yield()
end

-- How many sessions this save has had, including the current one (0 if not loaded).
function DataService.GetSessionCount(_self: DataService, player: Player): number
	local profile = profiles[player]
	return if profile ~= nil then profile.SessionLoadCount else 0
end

-- False when progress will be lost at the end of the session: the Studio mock
-- store is in use, or Roblox reports no DataStore access.
function DataService.IsSavingEnabled(_self: DataService): boolean
	return not usingMock and ProfileStore.DataStoreState == "Access"
end

function DataService.Init(_self: DataService)
	if usingMock then
		print("[DataService] Using the in-memory mock store (Config.Data.UseMockInStudio); nothing will be saved")
	end

	Remotes.GetProfileSummary:SetHandler(function(player: Player): Types.ProfileSummary?
		local data = DataService:WaitForData(player, DataConfig.ClientWaitTimeout)
		if data == nil then
			return nil
		end
		return buildSummary(player, data)
	end)
end

function DataService.Start(_self: DataService)
	ProfileStore.OnError:Connect(function(message: string, storeName: string, profileKey: string)
		warn(`[DataService] ProfileStore error ({storeName} / {profileKey}): {message}`)
	end)
	ProfileStore.OnOverwrite:Connect(function(storeName: string, profileKey: string)
		warn(`[DataService] Save {storeName} / {profileKey} held data that is not a valid profile (edited by hand?)`)
	end)
	-- Critical state = many DataStore failures in a short time. Profiles stay
	-- loaded and keep retrying, so players only need reassurance, not a kick.
	ProfileStore.OnCriticalToggle:Connect(function(isCritical: boolean)
		if isCritical then
			Remotes.Notify:FireAll(DataConfig.SavingTroubleMessage, "Warning")
		else
			Remotes.Notify:FireAll(DataConfig.SavingRecoveredMessage, "Success")
		end
	end)

	Players.PlayerAdded:Connect(loadProfile)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	-- In Studio Play Solo the player can join before this script runs.
	for _, player in Players:GetPlayers() do
		task.spawn(loadProfile, player)
	end
end

export type DataService = typeof(DataService)

return DataService
