--!strict
--[[
	FlightService: the server's authority over flight.

	The client moves its own character while flying (FlightController: smooth,
	no input lag). The server decides who may fly and boost, pays for it, and
	checks that nobody moves faster than flight allows:

	  * SetFlying(true) takes off when RingService allows it (a ring with charge,
	    willpower >= Config.Flight.MinWillpowerToTakeOff, nothing blocking
	    powers). A refusal is answered with PowerRejected AND an explicit
	    Flying = false, so a client that took off optimistically lands again.
	  * SetBoosting(true) boosts while flying with at least MinWillpowerToBoost.
	  * One drain loop (Config.Flight.Server.DrainInterval) pays for every flyer:
	    ring charge always, willpower at the cruise or boost rate. Out of charge
	    lands the player; out of willpower (or below MinWillpowerToBoost) only
	    ends the boost.
	  * One sampling loop (Config.Flight.Server.SampleInterval) measures how far
	    each flyer moved since the last sample. Faster than boost speed (with
	    tolerance) for MaxViolations samples in a row, which only a modified
	    client can do, lands them and puts them back at the last valid sample.
	  * Death, losing the character, leaving and RingService.Depleted("Charge")
	    all land the player.

	State is mirrored to each Player as the attributes Flying and Boosting
	(only the server writes them; clients read them).

	API:
	  FlightService:IsFlying(player): boolean
	  FlightService:ForceLand(player)                 (lands if flying; always clears the attributes)
	  FlightService.FlightStarted  Signal(player)
	  FlightService.FlightEnded    Signal(player)     (exactly once per FlightStarted)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local FlightConfig = require(Shared.Config.Flight)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Util.Signal)
local TagsModule = require(Shared.Util.Tags)
local Types = require(Shared.Types)

local Characters = require(script.Parent.Characters)
local RingService = require(script.Parent.RingService)

local Attributes = TagsModule.Attributes
local serverConfig = FlightConfig.Server

type FlightState = {
	-- The character that took off; flight ends with it.
	character: Model,
	boosting: boolean,
	-- Died / removed hooks for this flight, disconnected on landing.
	connections: { RBXScriptConnection },
	-- Speed check: the previous sample and when it was taken (os.clock()), the
	-- character's pivot at the last sample that passed, and how many samples in
	-- a row have failed.
	samplePosition: Vector3,
	sampleTime: number,
	validPivot: CFrame,
	violations: number,
}

local flights: { [Player]: FlightState } = {}

local FlightService = {
	FlightStarted = Signal.new() :: Signal.Signal<Player>,
	FlightEnded = Signal.new() :: Signal.Signal<Player>,
}

local function setBoosting(player: Player, state: FlightState, boosting: boolean)
	state.boosting = boosting
	player:SetAttribute(Attributes.Boosting, boosting)
end

-- Ends the flight (if any). The attributes are written even when the server
-- had no flight: a client that believes it is flying is corrected either way.
local function land(player: Player)
	player:SetAttribute(Attributes.Flying, false)
	player:SetAttribute(Attributes.Boosting, false)
	local state = flights[player]
	if state == nil then
		return
	end
	flights[player] = nil
	for _, connection in state.connections do
		connection:Disconnect()
	end
	table.clear(state.connections)
	FlightService.FlightEnded:Fire(player)
end

local function reject(player: Player, reason: Types.PowerRejectReason)
	Remotes.PowerRejected:FireClient(player, "Flight", reason)
end

local function takeOff(player: Player)
	if flights[player] ~= nil then
		-- A repeated request (e.g. the client lost track): already flying.
		player:SetAttribute(Attributes.Flying, true)
		return
	end

	local ok: boolean, reason: Types.PowerRejectReason? =
		RingService:CanUse(player, "Flight", FlightConfig.MinWillpowerToTakeOff)
	local character = player.Character
	local root = Characters.GetRootPart(player, true)
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	if not ok or character == nil or root == nil or humanoid == nil then
		reject(player, reason or "NotReady")
		player:SetAttribute(Attributes.Flying, false)
		return
	end

	local state: FlightState = {
		character = character,
		boosting = false,
		connections = {},
		samplePosition = root.Position,
		sampleTime = os.clock(),
		validPivot = character:GetPivot(),
		violations = 0,
	}
	flights[player] = state

	-- The guards keep a late event from landing a newer flight.
	table.insert(
		state.connections,
		humanoid.Died:Connect(function()
			if flights[player] == state then
				land(player)
			end
		end)
	)
	table.insert(
		state.connections,
		character.AncestryChanged:Connect(function()
			if flights[player] == state and not character:IsDescendantOf(Workspace) then
				land(player)
			end
		end)
	)

	player:SetAttribute(Attributes.Boosting, false)
	player:SetAttribute(Attributes.Flying, true)
	FlightService.FlightStarted:Fire(player)
	Remotes.PowerEffect:FireAll("Takeoff", root.Position, 1)
end

local function onSetFlying(player: Player, enabled: boolean)
	if enabled then
		takeOff(player)
	else
		land(player)
	end
end

local function onSetBoosting(player: Player, on: boolean)
	local state = flights[player]
	if state == nil then
		return
	end
	if not on then
		if state.boosting then
			setBoosting(player, state, false)
		end
		return
	end
	if state.boosting then
		return
	end
	if RingService:GetWillpower(player) < FlightConfig.MinWillpowerToBoost then
		reject(player, "NoWillpower")
		player:SetAttribute(Attributes.Boosting, false)
		return
	end
	setBoosting(player, state, true)
end

local function onDepleted(player: Player, resource: RingService.Resource)
	if resource == "Charge" then
		land(player)
		return
	end
	local state = flights[player]
	if state ~= nil and state.boosting then
		setBoosting(player, state, false)
	end
end

-- Snapshot of the flying players, so landing someone mid-loop is safe.
local function flyingPlayers(): { Player }
	local list = {}
	for player in flights do
		table.insert(list, player)
	end
	return list
end

-- Drain ----------------------------------------------------------------------

local function drainPlayer(player: Player, deltaTime: number)
	local state = flights[player]
	if state == nil then
		return
	end
	-- Backstop for the Died / AncestryChanged hooks (e.g. a root part destroyed
	-- by the void without the character itself being removed).
	if player.Character ~= state.character or Characters.GetRootPart(player, true) == nil then
		land(player)
		return
	end

	-- WillpowerPerSecond may be 0 (cruising is free): RingService skips a zero
	-- spend, so willpower keeps regenerating while cruising.
	local willpowerRate = if state.boosting
		then FlightConfig.BoostWillpowerPerSecond
		else FlightConfig.WillpowerPerSecond
	local paid = RingService:Drain(player, willpowerRate * deltaTime, FlightConfig.ChargePerSecond * deltaTime)

	-- Drain fires Depleted when a resource hits zero, whose handler may already
	-- have landed this player.
	if flights[player] ~= state then
		return
	end
	if not paid and RingService:GetCharge(player) <= 0 then
		land(player)
		return
	end
	-- Drain also reports false when willpower is at zero while cruising for free;
	-- that only matters for a boost.
	if state.boosting and (not paid or RingService:GetWillpower(player) < FlightConfig.MinWillpowerToBoost) then
		setBoosting(player, state, false)
	end
end

local function drainLoop()
	while true do
		-- The real elapsed time, so a server hitch is still paid for in full.
		local deltaTime = task.wait(serverConfig.DrainInterval)
		for _, player in flyingPlayers() do
			-- Own thread per player: an error is reported without stopping the
			-- drain for everyone else.
			task.spawn(drainPlayer, player, deltaTime)
		end
	end
end

-- Speed check ----------------------------------------------------------------

local function samplePlayer(player: Player)
	local state = flights[player]
	if state == nil or player.Character ~= state.character then
		return
	end
	local root = Characters.GetRootPart(player, true)
	if root == nil then
		return
	end

	local now = os.clock()
	local position = root.Position
	local elapsed = now - state.sampleTime
	-- Measured against the previous sample (not the last valid one), so a single
	-- jump (a server teleport, a burst of late network updates) costs at most
	-- one violation instead of failing every sample after it.
	local moved = (position - state.samplePosition).Magnitude
	state.samplePosition = position
	state.sampleTime = now

	-- Scaled by the real time between samples, so a late loop never reads as
	-- speeding. The boost cap covers the takeoff impulse, climbing and the
	-- boundary push-back too.
	local allowed = FlightConfig.BoostSpeed * serverConfig.SpeedTolerance * elapsed + serverConfig.LagAllowance
	if moved <= allowed then
		state.violations = 0
		state.validPivot = state.character:GetPivot()
		return
	end

	state.violations += 1
	if state.violations < serverConfig.MaxViolations then
		return
	end

	local character = state.character
	local validPivot = state.validPivot
	land(player)
	character:PivotTo(validPivot)
	-- Whatever carried it here must not carry it straight back out.
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	warn(
		string.format(
			"[FlightService] %s (%d) flew too fast (%.0f studs in %.2f s, %d samples in a row); landed and moved back",
			player.Name,
			player.UserId,
			moved,
			elapsed,
			serverConfig.MaxViolations
		)
	)
end

local function sampleLoop()
	while true do
		task.wait(serverConfig.SampleInterval)
		for _, player in flyingPlayers() do
			task.spawn(samplePlayer, player)
		end
	end
end

-- API ------------------------------------------------------------------------

function FlightService.IsFlying(_self: FlightService, player: Player): boolean
	return flights[player] ~= nil
end

-- Lands the player now (e.g. the battery's oath, a cutscene). Safe to call when
-- they are not flying.
function FlightService.ForceLand(_self: FlightService, player: Player)
	land(player)
end

function FlightService.Init(_self: FlightService)
	Remotes.SetFlying:Connect(onSetFlying)
	Remotes.SetBoosting:Connect(onSetBoosting)
	RingService.Depleted:Connect(onDepleted)
	-- Connected here, before any flight can start, so none outlives its player.
	Players.PlayerRemoving:Connect(land)
end

function FlightService.Start(_self: FlightService)
	-- Clients read the attributes as booleans from the start.
	local function onPlayerAdded(player: Player)
		if flights[player] == nil then
			player:SetAttribute(Attributes.Flying, false)
			player:SetAttribute(Attributes.Boosting, false)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	task.spawn(drainLoop)
	sampleLoop()
end

export type FlightService = typeof(FlightService)

return FlightService
