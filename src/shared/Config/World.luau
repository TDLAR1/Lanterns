--!strict
--[[
	World tuning: districts, play-area boundary, zone checks and lighting.

	Coordinates follow the map spec: origin (0, 0, 0) is the Main St × Center St
	intersection at ground level, +X is east, +Z is south, 1 unit = 1 stud.
	The town itself spans X -500..500, Z -350..350; the outer ring of farmland
	extends the flyable world out to the Boundary below.
]]

local Types = require(script.Parent.Parent.Types)

local World = {
	-- Name of the Folder in Workspace that holds the whole map.
	MapFolderName = "Map",

	-- Display order also defines the "discovered X / Y" total.
	Districts = {
		{ Id = "Downtown", DisplayName = "Downtown", Subtitle = "Main Street & Center Street" },
		{ Id = "Farmstead", DisplayName = "The Farmstead", Subtitle = "Farmhouse, barn & the north cornfield" },
		{ Id = "NorthFields", DisplayName = "North Fields", Subtitle = "Wheat as far as the water tower" },
		{ Id = "Residential", DisplayName = "Elm & Oak", Subtitle = "Residential streets" },
		{ Id = "SouthFields", DisplayName = "South Fields", Subtitle = "Where the body was found" },
		{ Id = "RailYard", DisplayName = "Rail Yard", Subtitle = "Tracks, gas station & the old grain elevator" },
		{ Id = "OuterRing", DisplayName = "County Farmland", Subtitle = "Open country beyond town" },
	} :: { Types.DistrictInfo },

	-- Seconds between server checks of which district each player is in.
	ZoneCheckInterval = 0.25,

	-- Play-area boundary (a box centred on the origin).
	Boundary = {
		-- Hard edge, in studs from the origin. Nobody goes past this.
		HalfSizeX = 2500,
		HalfSizeZ = 2500,
		-- Width of the band inside the edge where players are warned and pushed back.
		SoftMargin = 250,
		-- Flight ceiling (Y) and the soft band below it.
		Ceiling = 900,
		CeilingSoftMargin = 120,
		-- Strongest inward push (studs/s) applied by the client at the very edge.
		MaxPushSpeed = 60,
		-- The server only intervenes this far beyond the hard edge (lag allowance),
		-- then puts the character back inside.
		ServerTolerance = 150,
		-- Seconds between server boundary checks.
		ServerCheckInterval = 1,
	},

	Spawning = {
		-- After dying, respawn at the nearest *discovered* district respawn point
		-- instead of the main spawn on the highway.
		RespawnAtNearestDistrict = true,
	},

	-- Static blockout lighting (day/night cycle arrives in Milestone 2).
	Lighting = {
		ClockTime = 15.5,
		Brightness = 2.2,
		OutdoorAmbient = Color3.fromRGB(140, 140, 130),
		-- Atmosphere haze hides the hard edge of the world on the horizon.
		Atmosphere = {
			Density = 0.32,
			Offset = 0.2,
			Color = Color3.fromRGB(205, 200, 180),
			Decay = Color3.fromRGB(120, 125, 110),
			Glare = 0.15,
			Haze = 1.6,
		},
	},

	-- Show zone volumes as translucent boxes while testing in Studio.
	DebugShowZonesInStudio = false,
}

return World
