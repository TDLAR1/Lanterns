--!strict
--[[
	WorldService: the map and the world around it.

	  * Builds the blockout map with MapBuilder, unless a map folder is already
	    in Workspace (a baked or hand-edited map is used as-is).
	  * Tidies leftovers from the place template without deleting anything:
	    stray SpawnLocations are disabled, a Baseplate is reported.
	  * Applies the static lighting from Config.World.Lighting.
	  * Hides the mission markers' developer labels on live servers
	    (Config.Map.MissionMarker.DevLabelsOutsideStudio).
	  * Tracks the tagged gameplay objects (zones, spawns, mission markers,
	    battery spot) with CollectionService. Gameplay code finds map objects
	    ONLY through the getters below (tag + attribute, never a path), so
	    blockout models can be swapped for real ones without code changes.

	API:
	  WorldService:GetMap(): Instance?
	  WorldService:GetZones(): { Zones.ZoneVolume }      (shared list: do not modify)
	  WorldService:GetDistrictSpawn(districtId): BasePart?
	  WorldService:GetMainSpawn(): SpawnLocation?
	  WorldService:GetMissionMarker(markerId): BasePart?
	  WorldService:GetBatterySpot(): BasePart?
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local MapConfig = require(Shared.Config.Map)
local TagsModule = require(Shared.Util.Tags)
local WorldConfig = require(Shared.Config.World)
local Zones = require(Shared.Util.Zones)

local Gameplay = require(script.Parent.Parent.Map.Gameplay)
local MapBuilder = require(script.Parent.Parent.Map.MapBuilder)

local Tags = TagsModule.Tags
local Attributes = TagsModule.Attributes

-- Every tag this service tracks.
local TRACKED_TAGS = {
	Tags.DistrictZone,
	Tags.DistrictSpawn,
	Tags.MainSpawn,
	Tags.MissionMarker,
	Tags.RingBatterySpot,
}

-- District id -> position in Config.World.Districts (for debug colours and validation).
local districtIndex: { [string]: number } = {}
for index, district in WorldConfig.Districts do
	districtIndex[district.Id] = index
end

local showZones = WorldConfig.DebugShowZonesInStudio and RunService:IsStudio()
-- Applied here at runtime rather than when building, so a map baked into the
-- place in Studio (labels included) is covered too.
local hideDevLabels = not RunService:IsStudio() and not MapConfig.MissionMarker.DevLabelsOutsideStudio

local map: Instance? = nil

-- tag -> set of tagged instances. CollectionService also reports instances
-- outside Workspace (e.g. templates in ServerStorage), so every getter checks
-- that what it returns is actually in the world.
local tracked: { [string]: { [Instance]: boolean } } = {}
for _, tag in TRACKED_TAGS do
	tracked[tag] = {}
end

-- Zone volumes are resolved for every player several times a second, so the
-- parsed volumes are cached and the list is rebuilt only when zones change.
local zoneVolumes: { [BasePart]: Zones.ZoneVolume? } = {}
local zoneConnections: { [BasePart]: { RBXScriptConnection } } = {}
local zoneList: { Zones.ZoneVolume } = {}
local zoneListDirty = true

local WorldService = {}

local function isInWorld(instance: Instance): boolean
	return instance:IsDescendantOf(Workspace)
end

local function debugZoneColor(districtId: string): Color3
	local index = districtIndex[districtId]
	if index == nil then
		-- Unknown district: plain white stands out against the hue wheel.
		return Color3.new(1, 1, 1)
	end
	-- Spread the districts evenly around the hue wheel so neighbours differ.
	return Color3.fromHSV((index - 1) / #WorldConfig.Districts, 0.8, 1)
end

-- Re-reads a zone part's attributes (they can be edited live in Studio).
local function refreshZone(part: BasePart)
	local zone = Zones.FromPart(part)
	zoneVolumes[part] = zone
	zoneListDirty = true
	if showZones then
		part.Transparency = WorldConfig.DebugZoneTransparency
		part.CastShadow = false
		part.Color = debugZoneColor(if zone ~= nil then zone.DistrictId else "")
	end
end

local function hideDevLabel(marker: Instance)
	local label = marker:FindFirstChild(Gameplay.DevLabelName)
	if label ~= nil and label:IsA("BillboardGui") then
		label.Enabled = false
	end
end

local function onTagAdded(tag: string, instance: Instance)
	local set = tracked[tag]
	if set[instance] then
		-- Seen already (the initial GetTagged pass and the added signal can overlap).
		return
	end
	set[instance] = true

	if tag == Tags.MissionMarker and hideDevLabels then
		hideDevLabel(instance)
	end
	if tag ~= Tags.DistrictZone then
		return
	end
	if not instance:IsA("BasePart") then
		warn(`[WorldService] {instance:GetFullName()} is tagged {Tags.DistrictZone} but is not a part; ignored`)
		return
	end
	zoneConnections[instance] = {
		instance:GetAttributeChangedSignal(Attributes.DistrictId):Connect(function()
			refreshZone(instance)
		end),
		instance:GetAttributeChangedSignal(Attributes.Priority):Connect(function()
			refreshZone(instance)
		end),
		-- Moving a zone into or out of Workspace changes whether it counts.
		instance.AncestryChanged:Connect(function()
			zoneListDirty = true
		end),
	}
	refreshZone(instance)
end

local function onTagRemoved(tag: string, instance: Instance)
	tracked[tag][instance] = nil
	if tag ~= Tags.DistrictZone or not instance:IsA("BasePart") then
		return
	end
	local connections = zoneConnections[instance]
	if connections ~= nil then
		for _, connection in connections do
			connection:Disconnect()
		end
	end
	zoneConnections[instance] = nil
	zoneVolumes[instance] = nil
	zoneListDirty = true
end

local function trackTags()
	for _, tag in TRACKED_TAGS do
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance: Instance)
			onTagAdded(tag, instance)
		end)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance: Instance)
			onTagRemoved(tag, instance)
		end)
		for _, instance in CollectionService:GetTagged(tag) do
			onTagAdded(tag, instance)
		end
	end
end

local function buildMap(): Instance?
	local existing = Workspace:FindFirstChild(WorldConfig.MapFolderName)
	if existing ~= nil then
		print(`[WorldService] Using the map already in Workspace ({existing:GetFullName()})`)
		return existing
	end
	local startedAt = os.clock()
	-- Protected so a broken map build still leaves saving and the rest of the server running.
	local ok, result = pcall(MapBuilder.Build, Workspace)
	if not ok then
		warn(`[WorldService] Building the map failed: {result}`)
		return nil
	end
	print(string.format("[WorldService] Built the blockout map in %.0f ms", (os.clock() - startedAt) * 1000))
	return result
end

-- The place template's own SpawnLocation would compete with the map's main
-- spawn, so every other enabled SpawnLocation outside the map is switched off
-- (never deleted: it may be someone's work in progress).
local function disableStraySpawns()
	local mapRoot = map
	if mapRoot == nil or WorldService:GetMainSpawn() == nil then
		-- Nothing better to spawn on; validateMap reports the missing main spawn.
		return
	end
	for _, descendant in Workspace:GetDescendants() do
		if
			descendant:IsA("SpawnLocation")
			and descendant.Enabled
			and not descendant:IsDescendantOf(mapRoot)
			and not descendant:HasTag(Tags.MainSpawn)
		then
			descendant.Enabled = false
			warn(`[WorldService] Disabled {descendant:GetFullName()}: players spawn at the map's main spawn`)
		end
	end
end

local function warnAboutBaseplate()
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate ~= nil and baseplate:IsA("BasePart") then
		warn(
			"[WorldService] Workspace.Baseplate overlaps the town ground at Y 0 and will flicker (z-fighting); delete it or move it below the map"
		)
	end
end

local function applyLighting()
	local config = WorldConfig.Lighting
	Lighting.ClockTime = config.ClockTime
	Lighting.Brightness = config.Brightness
	Lighting.OutdoorAmbient = config.OutdoorAmbient

	-- Reuse an Atmosphere already in the place (only one is used by the engine).
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	local haze = config.Atmosphere
	atmosphere.Density = haze.Density
	atmosphere.Offset = haze.Offset
	atmosphere.Color = haze.Color
	atmosphere.Decay = haze.Decay
	atmosphere.Glare = haze.Glare
	atmosphere.Haze = haze.Haze
	atmosphere.Parent = Lighting
end

-- Missing gameplay objects are reported, not fatal: the game still runs, that
-- district just cannot be detected / respawned in.
local function validateMap()
	local hasZone: { [string]: boolean } = {}
	for _, zone in WorldService:GetZones() do
		hasZone[zone.DistrictId] = true
		if districtIndex[zone.DistrictId] == nil then
			warn(
				`[WorldService] Zone {zone.Part:GetFullName()} has DistrictId "{zone.DistrictId}", which is not in Config.World.Districts`
			)
		end
	end
	for _, district in WorldConfig.Districts do
		if not hasZone[district.Id] then
			warn(
				`[WorldService] District {district.Id} has no {Tags.DistrictZone} part; players there are in no district`
			)
		end
		if WorldService:GetDistrictSpawn(district.Id) == nil then
			warn(`[WorldService] District {district.Id} has no {Tags.DistrictSpawn} part; nobody can respawn there`)
		end
	end
	if WorldService:GetMainSpawn() == nil then
		warn(`[WorldService] No SpawnLocation tagged {Tags.MainSpawn} in Workspace`)
	end
end

-- The map folder (nil if it could not be built).
function WorldService.GetMap(_self: WorldService): Instance?
	return map
end

-- Every zone volume currently in the world. The list is shared: read it, do not modify it.
function WorldService.GetZones(_self: WorldService): { Zones.ZoneVolume }
	if zoneListDirty then
		local list = {}
		for part, zone in zoneVolumes do
			if zone ~= nil and isInWorld(part) then
				table.insert(list, zone)
			end
		end
		-- A fresh table, so a caller still iterating the old list is unaffected.
		zoneList = list
		zoneListDirty = false
	end
	return zoneList
end

-- The respawn point of a district, or nil if the map has none.
function WorldService.GetDistrictSpawn(_self: WorldService, districtId: string): BasePart?
	for instance in tracked[Tags.DistrictSpawn] do
		if
			instance:IsA("BasePart")
			and instance:GetAttribute(Attributes.DistrictId) == districtId
			and isInWorld(instance)
		then
			return instance
		end
	end
	return nil
end

-- The SpawnLocation where new players appear.
function WorldService.GetMainSpawn(_self: WorldService): SpawnLocation?
	for instance in tracked[Tags.MainSpawn] do
		if instance:IsA("SpawnLocation") and isInWorld(instance) then
			return instance
		end
	end
	return nil
end

-- The mission marker part with this MarkerId, or nil.
function WorldService.GetMissionMarker(_self: WorldService, markerId: string): BasePart?
	for instance in tracked[Tags.MissionMarker] do
		if
			instance:IsA("BasePart")
			and instance:GetAttribute(Attributes.MarkerId) == markerId
			and isInWorld(instance)
		then
			return instance
		end
	end
	return nil
end

-- Where players recharge their ring.
function WorldService.GetBatterySpot(_self: WorldService): BasePart?
	for instance in tracked[Tags.RingBatterySpot] do
		if instance:IsA("BasePart") and isInWorld(instance) then
			return instance
		end
	end
	return nil
end

function WorldService.Init(_self: WorldService)
	map = buildMap()
	-- Tracked in Init (not Start) so every other service's Start already sees the map objects.
	trackTags()
	disableStraySpawns()
	warnAboutBaseplate()
	applyLighting()
	if showZones then
		print("[WorldService] Showing zone volumes (Config.World.DebugShowZonesInStudio)")
	end
end

function WorldService.Start(_self: WorldService)
	validateMap()
end

export type WorldService = typeof(WorldService)

return WorldService
