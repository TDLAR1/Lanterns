--!strict
--[[
	Map gameplay hooks: how the gameplay objects that the map builder places
	(main spawn, district respawn points, mission markers, the ring-battery spot)
	look and behave.

	WHERE things are (all map geometry, including these objects' positions) lives
	in ServerScriptService.Server.Map.MapLayout, not here.
]]

local Theme = require(script.Parent.Theme)

local Map = {
	MainSpawn = {
		-- Seconds of spawn protection (ForceField) after appearing at the main spawn.
		Duration = 3,
	},

	-- Height (studs above the ground) of the centre of each district's invisible,
	-- 1-stud-tall DistrictSpawn part: 0.5 rests it on the ground. SpawnService
	-- puts a respawned character's root Config.World.Spawning.RespawnHeightOffset
	-- above the part's top.
	DistrictSpawnHeight = 0.5,

	MissionMarker = {
		-- Flat disc lying on the ground.
		Diameter = 10,
		Thickness = 0.2,
		Color = Theme.RingGreen,
		Transparency = 0.45,
		-- Faint vertical light pillar so markers can be spotted from a distance.
		BeamDiameter = 5,
		BeamHeight = 36,
		BeamTransparency = 0.88,
		-- Floating MarkerId label so developers can find markers while testing.
		ShowDevLabels = true,
		-- Also show those labels on live servers (outside Studio). Off so players
		-- in the published game never see them; turn on for a playtest build.
		DevLabelsOutsideStudio = false,
		DevLabelMaxDistance = 150,
		DevLabelHeight = 7,
	},

	RingBattery = {
		GlowColor = Theme.RingGreen,
		LightBrightness = 3,
		LightRange = 20,
	},
}

return Map
