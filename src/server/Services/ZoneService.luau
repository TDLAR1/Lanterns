--!strict
--[[
	ZoneService: which district every player is in, and district discovery.

	One loop checks every player each Config.World.ZoneCheckInterval seconds
	(cheaper and steadier than a loop per player). The current district is
	published on the Player as an attribute (Attributes.PlayerDistrict) so any
	script, including the player's own client, can read it.

	Discovery is decided here, on the server, from the server's view of the
	character: the client is only told about it.

	API:
	  ZoneService:GetDistrict(player): string?
	  ZoneService:IsDiscovered(player, districtId): boolean
	  ZoneService.DistrictChanged     Signal(player, newDistrictId?, oldDistrictId?)
	  ZoneService.DistrictDiscovered  Signal(player, districtId)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Util.Signal)
local TagsModule = require(Shared.Util.Tags)
local Types = require(Shared.Types)
local WorldConfig = require(Shared.Config.World)
local Zones = require(Shared.Util.Zones)

local Characters = require(script.Parent.Characters)
local DataService = require(script.Parent.DataService)
local WorldService = require(script.Parent.WorldService)

local Attributes = TagsModule.Attributes

-- Only ids listed in Config.World.Districts can be discovered; a zone with any
-- other id still sets the player's district but is never saved.
local knownDistricts: { [string]: Types.DistrictId } = {}
for _, district in WorldConfig.Districts do
	knownDistricts[district.Id] = district.Id
end
local totalDistricts = #WorldConfig.Districts

local currentDistrict: { [Player]: string? } = {}

local ZoneService = {
	-- The player entered another district, or left every district / lost their
	-- character (new id nil). (player, newDistrictId?, oldDistrictId?)
	DistrictChanged = Signal.new() :: Signal.Signal<Player, string?, string?>,
	-- The player discovered a district for the first time (already saved). (player, districtId)
	DistrictDiscovered = Signal.new() :: Signal.Signal<Player, Types.DistrictId>,
}

local function countDiscovered(data: Types.PlayerData): number
	-- Counted from the config so stale ids in old saves never inflate the total.
	local count = 0
	for _, district in WorldConfig.Districts do
		if data.DiscoveredDistricts[district.Id] == true then
			count += 1
		end
	end
	return count
end

local function tryDiscover(player: Player, id: string)
	local districtId: Types.DistrictId? = knownDistricts[id]
	if districtId == nil then
		return
	end
	-- Not loaded yet: the next tick tries again, so standing still while the
	-- save loads still discovers the district.
	local data = DataService:GetData(player)
	if data == nil or data.DiscoveredDistricts[districtId] == true then
		return
	end
	data.DiscoveredDistricts[districtId] = true
	Remotes.DistrictDiscovered:FireClient(player, districtId, countDiscovered(data), totalDistricts)
	ZoneService.DistrictDiscovered:Fire(player, districtId)
end

local function updatePlayer(player: Player, zones: { Zones.ZoneVolume })
	local character = player.Character
	if character ~= nil and Characters.IsBeingPlaced(character) then
		-- A respawned character waiting to be moved to its district respawn point
		-- is not where it will play yet: keep the previous district until then.
		return
	end

	local newId: string? = nil
	local root = Characters.GetRootPart(player)
	if root ~= nil then
		local zone = Zones.Resolve(zones, root.Position)
		if zone ~= nil then
			newId = zone.DistrictId
		end
	end

	local oldId = currentDistrict[player]
	if newId ~= oldId then
		currentDistrict[player] = newId
		player:SetAttribute(Attributes.PlayerDistrict, newId)
		ZoneService.DistrictChanged:Fire(player, newId, oldId)
	end

	if newId ~= nil then
		tryDiscover(player, newId)
	end
end

local function step()
	local zones = WorldService:GetZones()
	for _, player in Players:GetPlayers() do
		-- Own thread per player: an error is reported (with its traceback) without
		-- stopping district tracking for everyone else.
		task.spawn(updatePlayer, player, zones)
	end
end

-- The district the player is in right now (nil: none, or no character).
function ZoneService.GetDistrict(_self: ZoneService, player: Player): string?
	return currentDistrict[player]
end

-- True if the player's loaded save has discovered this district. False while
-- their data is not loaded.
function ZoneService.IsDiscovered(_self: ZoneService, player: Player, districtId: string): boolean
	local data = DataService:GetData(player)
	return data ~= nil and data.DiscoveredDistricts[districtId] == true
end

function ZoneService.Init(_self: ZoneService) end

function ZoneService.Start(_self: ZoneService)
	Players.PlayerRemoving:Connect(function(player: Player)
		currentDistrict[player] = nil
	end)
	while true do
		task.wait(WorldConfig.ZoneCheckInterval)
		step()
	end
end

export type ZoneService = typeof(ZoneService)

return ZoneService
