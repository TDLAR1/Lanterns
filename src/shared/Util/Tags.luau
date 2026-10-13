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

	-- A Model with a Humanoid that ring powers may damage (training dummies, and
	-- the enemies added with missions). Players are never tagged: whether powers
	-- hurt other players is Config.Combat.PvPEnabled.
	Damageable = "Damageable",

	-- Where a training dummy stands (an invisible Part; the dummy faces the
	-- part's LookVector).
	TrainingDummySpot = "TrainingDummySpot",

	-- Every hard-light construct Model the server creates (wall, hammer, cage).
	-- Attributes: ConstructId, OwnerUserId.
	Construct = "Construct",

	-- The ring Part welded to a character's hand; beams start here.
	PowerRing = "PowerRing",

	-- On every top-level blockout Model; lets tools find what still needs its final model.
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

	-- Ring state, set by the server on each Player (read-only for clients; the
	-- HUD and effects read them). Numbers are rounded to 0.1 to limit traffic.
	Willpower = "Willpower",
	WillpowerMax = "WillpowerMax",
	RingCharge = "RingCharge",
	RingChargeMax = "RingChargeMax",
	-- True while the server has the player flying / boosting / shielded /
	-- firing the beam / recharging at the battery.
	Flying = "Flying",
	Boosting = "Boosting",
	Shielding = "Shielding",
	BeamActive = "BeamActive",
	Recharging = "Recharging",
	-- Cooldowns: "CooldownEnd_<PowerId>" holds the server time
	-- (Workspace:GetServerTimeNow()) when that power is ready again.
	CooldownPrefix = "CooldownEnd_",

	-- On construct Models.
	ConstructId = "ConstructId",
	OwnerUserId = "OwnerUserId",
}

return {
	Tags = Tags,
	Attributes = Attributes,
}
