--!strict
--[[
	Server entry point.

	Startup order matters:
	  1. Shared.Remotes is required first. On the server that creates every
	     RemoteEvent / RemoteFunction, so a client that starts early never waits
	     on one that does not exist yet.
	  2. Every service's Init runs, in dependency order. Init is synchronous (it
	     must not yield): wire up dependencies, create signals, register remote
	     handlers.
	  3. Every service's Start runs in its own thread, in the same order. Start
	     may yield (loading data, loops), so a slow Start never delays the others.

	Services that need each other require each other directly; this file only
	decides the order. Add a new service after everything it uses, in all three lists.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

require(ReplicatedStorage.Shared.Remotes)
local GameConfig = require(ReplicatedStorage.Shared.Config.Game)

-- Dependency order (each service only uses the ones above it).
local DataService = require(script.Services.DataService)
local WorldService = require(script.Services.WorldService)
local ZoneService = require(script.Services.ZoneService)
local SpawnService = require(script.Services.SpawnService)
local BoundaryService = require(script.Services.BoundaryService)
local RingService = require(script.Services.RingService)
local CombatService = require(script.Services.CombatService)
local FlightService = require(script.Services.FlightService)
local PowerService = require(script.Services.PowerService)
local BatteryService = require(script.Services.BatteryService)
local DummyService = require(script.Services.DummyService)

local startedAt = os.clock()

DataService:Init()
WorldService:Init()
ZoneService:Init()
SpawnService:Init()
BoundaryService:Init()
RingService:Init()
CombatService:Init()
FlightService:Init()
PowerService:Init()
BatteryService:Init()
DummyService:Init()

task.spawn(DataService.Start, DataService)
task.spawn(WorldService.Start, WorldService)
task.spawn(ZoneService.Start, ZoneService)
task.spawn(SpawnService.Start, SpawnService)
task.spawn(BoundaryService.Start, BoundaryService)
task.spawn(RingService.Start, RingService)
task.spawn(CombatService.Start, CombatService)
task.spawn(FlightService.Start, FlightService)
task.spawn(PowerService.Start, PowerService)
task.spawn(BatteryService.Start, BatteryService)
task.spawn(DummyService.Start, DummyService)

print(`[Server] {GameConfig.Name} {GameConfig.Version}`)
print(string.format("[Server] Initialised services in %.0f ms", (os.clock() - startedAt) * 1000))
