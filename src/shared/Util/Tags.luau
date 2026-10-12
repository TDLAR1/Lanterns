--!strict
--[[
	CollectionService tag and attribute names shared by the map builder and the
	gameplay code.

	Gameplay code finds important map objects by TAG, never by path or name, so
	you can replace any blockout model with a real one as long as the tagged
	marker parts (zones, spawns, mission markers, battery spot) keep their tags
	and attributes.
]]

local Tags = {
	-- Invisible box volume that defines a district.
	-- Attributes: DistrictId (string), Priority (number; higher wins where zones overlap).
	DistrictZone = "DistrictZone",

	-- The single SpawnLocation where new players appear (south end of Main St).
	MainSpawn = "MainSpawn",

	-- Respawn point for a district (a small invisible Part).
	-- Attributes: DistrictId (string).
	DistrictSpawn = "DistrictSpawn",

	-- Where a mission can be started. Missions refer to markers by MarkerId.
	-- Attributes: MarkerId (string), DistrictId (string).
	MissionMarker = "MissionMarker",

	-- Where players recharge their ring (Sheriff's Office back room).
	-- Attributes: DistrictId (string).
	RingBatterySpot = "RingBatterySpot",

	-- On every top-level blockout Model; lets tools find what is still a placeholder.
	-- Attributes: BlockoutOf (string; the building/landmark name).
	Blockout = "Blockout",
}

local Attributes = {
	DistrictId = "DistrictId",
	Priority = "Priority",
	MarkerId = "MarkerId",
	BlockoutOf = "BlockoutOf",

	-- Set by the server on each Player: the district they are currently in
	-- (a DistrictId string, or nil while they have no character).
	PlayerDistrict = "District",
}

return {
	Tags = Tags,
	Attributes = Attributes,
}
