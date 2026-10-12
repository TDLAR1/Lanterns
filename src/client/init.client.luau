--!strict
--[[
	Client entry point.

	Startup order matters:
	  1. Once the game has loaded, Shared.Remotes is required first. On the
	     client it waits until the server has created every RemoteEvent /
	     RemoteFunction, so no controller ever touches a remote that is not
	     there yet.
	  2. Every controller's Init runs, in dependency order. Init is synchronous
	     (it must not yield): build UI, create signals, connect events and remotes.
	  3. Every controller's Start runs in its own thread, in the same order.
	     Start may yield (ProfileController waits for the server), so a slow
	     Start never delays the others.

	Controllers that need each other require each other directly; this file only
	decides the order. Add a new controller after everything it uses, in all
	three lists.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Client scripts can start before the initial replication has finished; after
-- Loaded every Shared module is present (only Workspace content streams later).
if not game:IsLoaded() then
	game.Loaded:Wait()
end

require(ReplicatedStorage.Shared.Remotes)

-- Dependency order (each controller only uses the ones above it).
local HudController = require(script.Controllers.HudController)
local InputController = require(script.Controllers.InputController)
local NotificationController = require(script.Controllers.NotificationController)
local ProfileController = require(script.Controllers.ProfileController)
local ZoneController = require(script.Controllers.ZoneController)
local DistrictsPanelController = require(script.Controllers.DistrictsPanelController)
local BoundaryController = require(script.Controllers.BoundaryController)

local startedAt = os.clock()

HudController:Init()
InputController:Init()
NotificationController:Init()
ProfileController:Init()
ZoneController:Init()
DistrictsPanelController:Init()
BoundaryController:Init()

task.spawn(HudController.Start, HudController)
task.spawn(InputController.Start, InputController)
task.spawn(NotificationController.Start, NotificationController)
task.spawn(ProfileController.Start, ProfileController)
task.spawn(ZoneController.Start, ZoneController)
task.spawn(DistrictsPanelController.Start, DistrictsPanelController)
task.spawn(BoundaryController.Start, BoundaryController)

print(string.format("[Client] Initialised controllers in %.0f ms", (os.clock() - startedAt) * 1000))
