--!strict
--[[
	MapLayout: WHERE everything goes. Pure data: edit numbers here, the
	builders read everything from this module.

	Source: Rushville_Map_Layout.pdf (page 1 top-down plan, page 2 build
	table) plus the agreed changes noted on the rows.

	Coordinates: origin (0, 0, 0) is the Main St x Center St intersection at
	ground level, +X is east, +Z is south, 1 unit = 1 stud. X/Z are the CENTRE
	of an element's footprint, SizeX/SizeZ its footprint and Height its total
	height. Elements sit on the ground, so their centre Y is Height / 2 unless
	CenterY says otherwise. The ground's top surface is exactly Y = 0.

	Surface heights used across the map (tops), so flat layers never share a
	plane and flicker (z-fighting): ground 0, dirt 0.1, field soil 0.15,
	asphalt 0.2, lane paint 0.25, sidewalks / interior floors 0.4, rail ballast 0.5.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shapes = require(script.Parent.Shapes)
local Types = require(ReplicatedStorage.Shared.Types)

type Facing = Shapes.Facing
type DistrictId = Types.DistrictId

-- Which builder makes an element's visible geometry (see MapBuilder).
export type Kind =
	"Ground"
	| "MainStreet"
	| "CenterStreet"
	| "CountyRoad"
	| "ElmAve"
	| "OakSt"
	| "Railroad"
	| "Storefront"
	| "Diner"
	| "SheriffOffice"
	| "Motel"
	| "PostOffice"
	| "Church"
	| "GasStation"
	| "WaterTower"
	| "Farmhouse"
	| "Barn"
	| "Silo"
	| "GrainElevator"
	| "House"
	| "CallowayHome"
	| "Cornfield"
	| "WheatField"
	| "CrimeScene"

export type Element = {
	Name: string,
	-- "Rushville", "Roads" or a district id (the folder under Map/Rushville).
	Folder: string,
	X: number,
	Z: number,
	SizeX: number,
	SizeZ: number,
	Height: number,
	CenterY: number?,
	Kind: Kind,
	-- The side the front door / shop window / sign faces.
	Facing: Facing?,
	Sign: string?,
	-- Picks one of several looks (houses).
	Variant: number?,
	-- Wheat field: name of the element whose circle the crop must leave open.
	Clearing: string?,
	-- Crop fields: world X of paths cut across the rows / world Z of rows left out as paths.
	CrossPaths: { number }?,
	AlongPaths: { number }?,
}

type Extra = {
	Facing: Facing?,
	Sign: string?,
	CenterY: number?,
	Variant: number?,
	Clearing: string?,
	CrossPaths: { number }?,
	AlongPaths: { number }?,
}

export type Rect = { X0: number, X1: number, Z0: number, Z1: number }

export type Point = { X: number, Z: number }

-- A point plus the direction its front faces.
export type Placement = { X: number, Z: number, Facing: Facing }

export type ZoneBox = { DistrictId: DistrictId, X0: number, X1: number, Z0: number, Z1: number }

export type DistrictSpawn = {
	DistrictId: DistrictId,
	X: number,
	Z: number,
	-- Respawned characters face this point.
	LookX: number,
	LookZ: number,
}

export type MissionMarker = {
	Id: string,
	DistrictId: DistrictId,
	X: number,
	Z: number,
	-- Height of the walkable surface under the marker (0 grass, 0.4 sidewalk...).
	Surface: number,
}

export type Line = { X0: number, Z0: number, X1: number, Z1: number }

export type CarPlacement = {
	Folder: string,
	X: number,
	Z: number,
	Facing: Facing,
	-- Index into MapPalette.CarPaints.
	Paint: number,
	Pickup: boolean?,
}

local function element(
	name: string,
	folder: string,
	x: number,
	z: number,
	sizeX: number,
	sizeZ: number,
	height: number,
	kind: Kind,
	extra: Extra?
): Element
	local options: Extra = extra or {}
	return {
		Name = name,
		Folder = folder,
		X = x,
		Z = z,
		SizeX = sizeX,
		SizeZ = sizeZ,
		Height = height,
		CenterY = options.CenterY,
		Kind = kind,
		Facing = options.Facing,
		Sign = options.Sign,
		Variant = options.Variant,
		Clearing = options.Clearing,
		CrossPaths = options.CrossPaths,
		AlongPaths = options.AlongPaths,
	}
end

local MapLayout = {}

--[[
	The build table (PDF page 2), one row per element. Agreed changes:
	  * Farmhouse, Barn and silos moved 35 studs west so the silo row clears the
	    General Store (PDF: Farmhouse X -370, Barn X -285, silos X -230/-205/-180).
	  * "Stewart Home" is the "Calloway Home".
	  * The Grain Elevator is a derelict, fenced-off walk-in shell.
	  * The Sheriff's Office is the case HQ and holds the ring-battery spot.
]]
-- stylua: ignore start
MapLayout.Elements = {
	--      Name                 Folder        X       Z       SizeX  SizeZ  Height  Builder
	-- Roads & ground
	element("Ground",            "Rushville",  0,      0,      1000,  700,   1,      "Ground", { CenterY = -0.5 }),
	element("Main St",           "Roads",      0,      0,      40,    700,   0.2,    "MainStreet"),
	element("Center Street",     "Roads",      0,      0,      560,   40,    0.2,    "CenterStreet"),
	element("County Road",       "Roads",      -260,   -98,    480,   24,    0.2,    "CountyRoad"),
	element("Elm Ave",           "Roads",      380,    0,      200,   24,    0.2,    "ElmAve"),
	element("Oak St",            "Roads",      382,    45,     24,    330,   0.2,    "OakSt"),
	element("Railroad",          "Roads",      0,      256,    1000,  12,    0.5,    "Railroad"),

	-- Downtown (north side faces south onto Center Street, south side faces north)
	element("General Store",     "Downtown",   -165,   -54,    70,    52,    18,     "Storefront",    { Facing = "South", Sign = "GENERAL STORE" }),
	element("Diner",             "Downtown",   -77.5,  -54,    85,    52,    14,     "Diner",         { Facing = "South", Sign = "DINER" }),
	element("Sheriff's Office",  "Downtown",   90,     -58,    110,   60,    22,     "SheriffOffice", { Facing = "South", Sign = "SHERIFF" }),
	element("Hardware",          "Downtown",   190,    -54,    70,    52,    16,     "Storefront",    { Facing = "South", Sign = "HARDWARE" }),
	element("Bar",               "Downtown",   -162.5, 53,     75,    50,    14,     "Storefront",    { Facing = "North", Sign = "BAR" }),
	element("Motel",             "Downtown",   -72.5,  63,     85,    70,    18,     "Motel",         { Facing = "North", Sign = "MOTEL" }),
	element("Post Office",       "Downtown",   70,     53,     70,    50,    16,     "PostOffice",    { Facing = "North", Sign = "POST OFFICE" }),
	element("Church",            "Downtown",   150,    65.5,   70,    75,    28,     "Church",        { Facing = "North" }),
	element("Gas Station",       "Downtown",   65,     145,    70,    50,    12,     "GasStation",    { Facing = "West", Sign = "GAS" }),

	-- North fields
	element("Water Tower",       "NorthFields", 200,   -139,   40,    40,    70,     "WaterTower"),
	element("Wheat Field NE",    "NorthFields", 270,   -250,   420,   160,   3,      "WheatField"),

	-- Farm
	element("Farmhouse",         "Farmstead",  -405,   -47.5,  60,    45,    20,     "Farmhouse",     { Facing = "North" }),
	element("Barn",              "Farmstead",  -320,   -50.5,  70,    55,    26,     "Barn",          { Facing = "South" }),
	element("Silo A",            "Farmstead",  -270,   -50,    22,    22,    45,     "Silo"),
	element("Silo B",            "Farmstead",  -245,   -50,    22,    22,    45,     "Silo"),
	element("Silo C",            "Farmstead",  -220,   -50,    22,    22,    45,     "Silo"),
	element("Cornfield NW",      "Farmstead",  -270,   -230,   420,   200,   8,      "Cornfield",     { CrossPaths = { -270 }, AlongPaths = { -230 } }),

	-- Residential (houses face their street; Houses 9-10 face Birch Lane)
	element("Calloway Home",     "Residential", 429,   96,     50,    36,    20,     "CallowayHome",  { Facing = "West" }),
	element("House 1",           "Residential", 308,   -37,    30,    24,    16,     "House",         { Facing = "South", Variant = 1 }),
	element("House 2",           "Residential", 346,   -37,    30,    24,    16,     "House",         { Facing = "South", Variant = 2 }),
	element("House 3",           "Residential", 420,   -37,    30,    24,    16,     "House",         { Facing = "South", Variant = 3 }),
	element("House 4",           "Residential", 457,   -37,    30,    24,    16,     "House",         { Facing = "South", Variant = 4 }),
	element("House 5",           "Residential", 308,   34,     30,    24,    16,     "House",         { Facing = "North", Variant = 5 }),
	element("House 6",           "Residential", 346,   34,     30,    24,    16,     "House",         { Facing = "North", Variant = 6 }),
	element("House 7",           "Residential", 420,   34,     30,    24,    16,     "House",         { Facing = "North", Variant = 7 }),
	element("House 8",           "Residential", 457,   34,     30,    24,    16,     "House",         { Facing = "North", Variant = 8 }),
	element("House 9",           "Residential", 308,   105,    30,    24,    16,     "House",         { Facing = "North", Variant = 9 }),
	element("House 10",          "Residential", 346,   105,    30,    24,    16,     "House",         { Facing = "North", Variant = 10 }),

	-- South fields (the crop leaves the 40-stud crime scene circle open)
	element("South Wheat Field", "SouthFields", -350,  140,    260,   180,   3,      "WheatField",    { Clearing = "Crime Scene" }),
	element("Crime Scene",       "SouthFields", -320,  140,    40,    40,    1,      "CrimeScene"),

	-- Rail yard
	element("Grain Elevator",    "RailYard",   125,    217.5,  50,    45,    60,     "GrainElevator", { Facing = "North" }),
	element("Corn Strip SW",     "RailYard",   -260,   310,    440,   60,    8,      "Cornfield",     { CrossPaths = { -260 } }),
	element("Corn Strip SE",     "RailYard",   340,    310,    280,   60,    8,      "Cornfield",     { CrossPaths = { 340 } }),
}
-- stylua: ignore end

-- The element row named `name`. Errors on an unknown name (a typo in a builder).
function MapLayout.Find(name: string): Element
	for _, row in MapLayout.Elements do
		if row.Name == name then
			return row
		end
	end
	error(`MapLayout has no element named "{name}"`)
end

-- Town extras (not in the PDF table) -----------------------------------------

-- Concrete sidewalks (top 0.4) between the downtown streets and the shop fronts.
MapLayout.Sidewalks = {
	{ X0 = -205, X1 = -20, Z0 = -28, Z1 = -20 },
	{ X0 = 20, X1 = 230, Z0 = -28, Z1 = -20 },
	{ X0 = -205, X1 = -20, Z0 = 20, Z1 = 28 },
	{ X0 = 20, X1 = 190, Z0 = 20, Z1 = 28 },
	-- The Main St sidewalks stop just short of the County Road (Z -86).
	{ X0 = -28, X1 = -20, Z0 = -85, Z1 = -28 },
	{ X0 = 20, X1 = 28, Z0 = -85, Z1 = -28 },
	{ X0 = -28, X1 = -20, Z0 = 28, Z1 = 105 },
	{ X0 = 20, X1 = 28, Z0 = 28, Z1 = 110 },
} :: { Rect }

-- Gravel lane from Oak St to the fronts of Houses 9 and 10.
MapLayout.BirchLane = { X0 = 290, X1 = 370, Z0 = 74, Z1 = 82 } :: Rect

-- Street lamps on the downtown sidewalks; each lamp's arm reaches over the street it faces.
MapLayout.StreetLamps = {
	{ X = -190, Z = -21.5, Facing = "South" },
	{ X = -145, Z = -21.5, Facing = "South" },
	{ X = -105, Z = -21.5, Facing = "South" },
	{ X = -50, Z = -21.5, Facing = "South" },
	{ X = 50, Z = -21.5, Facing = "South" },
	{ X = 130, Z = -21.5, Facing = "South" },
	{ X = 175, Z = -21.5, Facing = "South" },
	{ X = 215, Z = -21.5, Facing = "South" },
	{ X = -190, Z = 21.5, Facing = "North" },
	{ X = -140, Z = 21.5, Facing = "North" },
	{ X = -95, Z = 21.5, Facing = "North" },
	{ X = -45, Z = 21.5, Facing = "North" },
	{ X = 45, Z = 21.5, Facing = "North" },
	{ X = 110, Z = 21.5, Facing = "North" },
	{ X = 150, Z = 21.5, Facing = "North" },
	{ X = 182, Z = 21.5, Facing = "North" },
} :: { Placement }

-- Wooden utility poles along Main St outside downtown (wires run pole to pole).
MapLayout.UtilityPoles = {
	North = { X = -30, Z0 = -130, Z1 = -340, Spacing = 60 },
	South = { X = -30, Z0 = 200, Z1 = 290, Spacing = 90 },
}

-- Parked cars. Facing is the way the car points; cars park on the right-hand side of the street.
MapLayout.Cars = {
	{ Folder = "Downtown", X = -165, Z = -16.5, Facing = "West", Paint = 1 },
	{ Folder = "Downtown", X = 195, Z = -16.5, Facing = "West", Paint = 2 },
	{ Folder = "Downtown", X = -150, Z = 16.5, Facing = "East", Paint = 3 },
	{ Folder = "Downtown", X = 75, Z = 16.5, Facing = "East", Paint = 4 },
	{ Folder = "Downtown", X = -67.5, Z = 68, Facing = "South", Paint = 1 },
	{ Folder = "Downtown", X = -47.5, Z = 68, Facing = "South", Paint = 4 },
	{ Folder = "Downtown", X = 46, Z = 141.5, Facing = "West", Paint = 2 },
	{ Folder = "Residential", X = 424, Z = 116, Facing = "West", Paint = 2 },
	{ Folder = "Farmstead", X = -372, Z = 4, Facing = "East", Paint = 3, Pickup = true },
} :: { CarPlacement }

-- The duo's patrol car, parked at the curb in front of the case HQ.
MapLayout.PatrolCar = { Folder = "Downtown", X = 112, Z = -16.5, Facing = "West" :: Facing }

-- Trees per district folder: { X, Z, canopy diameter }.
MapLayout.Trees = {
	Residential = {
		{ 300, -72, 16 },
		{ 352, -66, 14 },
		{ 414, -70, 17 },
		{ 468, -64, 15 },
		{ 296, 60, 15 },
		{ 356, 58, 13 },
		{ 432, 62, 16 },
		{ 478, 60, 14 },
		{ 482, 86, 15 },
		{ 484, 112, 17 },
		{ 298, 134, 16 },
		{ 330, 142, 14 },
		{ 360, 128, 15 },
		{ 412, 160, 18 },
		{ 452, 176, 16 },
		{ 362, 205, 15 },
		{ 300, 222, 17 },
		{ 470, 225, 14 },
	},
	Downtown = {
		{ -188, 120, 15 },
		{ -150, 142, 17 },
		{ -64, 128, 14 },
		{ 196, 132, 16 },
		{ 248, 60, 15 },
		{ 250, -70, 14 },
	},
	Farmstead = {
		{ -476, -58, 17 },
		{ -470, -24, 15 },
		{ -480, 18, 16 },
		{ -446, 32, 14 },
	},
	SouthFields = {
		{ -214, 236, 16 },
	},
	NorthFields = {
		{ 236, -118, 14 },
	},
} :: { [string]: { { number } } }

-- Farm extras: dirt yard south of the buildings, the farmhouse drive, hay bales.
MapLayout.Farmyard = {
	Yard = { X0 = -450, X1 = -280, Z0 = -18, Z1 = 18 } :: Rect,
	-- Centred on the farmhouse front door (world X -416), between the porch posts.
	Drive = { X0 = -420, X1 = -412, Z0 = -86, Z1 = -70 } :: Rect,
	HayBales = { { -352, -12 }, { -346, -4 }, { -358, -3 }, { -300, 12 } },
}

-- Small churchyard behind (south of) the church.
MapLayout.Churchyard = {
	Rect = { X0 = 120, X1 = 180, Z0 = 120, Z1 = 166 } :: Rect,
	-- Gap in the north fence, on the path from the church.
	GateX0 = 145,
	GateX1 = 155,
	Rows = 3,
	Columns = 5,
	Seed = 7,
}

-- "Welcome to <town>" roadside sign, facing south so the main spawn reads it.
MapLayout.WelcomeSign = { X = 46, Z = 300, Width = 26, Height = 12 }

-- Chain-link fence around the derelict Grain Elevator. One panel on the west
-- side is missing (the way in, next to the Story_GrainElevator marker), the
-- next one leans and another lies flat in the weeds.
MapLayout.ElevatorFence = {
	Rect = { X0 = 92, X1 = 158, Z0 = 187, Z1 = 247 } :: Rect,
	PostSpacing = 11,
	Height = 8,
	-- West-side panel left out, counted from the north end (1-based).
	GapSegment = 2,
	DebrisSeed = 31,
}

-- Rail siding with two old boxcars, south of the main line.
MapLayout.Siding = {
	X0 = 40,
	X1 = 230,
	Z = 270,
	Boxcars = { 92, 136 },
}

-- Practice range on the open grass east of the main spawn (Milestone 1): a
-- low post-and-rail fence on the north, east and south sides (open toward
-- the highway), a painted firing line on a dirt strip, a straw-bale backstop
-- behind the practice targets and a sign facing the highway. Training dummies
-- stand on the invisible spots, facing west toward the firing line.
MapLayout.TrainingYard = {
	Rect = { X0 = 70, X1 = 190, Z0 = 288, Z1 = 346 } :: Rect,
	FenceHeight = 3.4,
	PostSpacing = 8,
	-- The firing line runs north-south at this X, on a dirt strip this wide.
	FiringLineX = 100,
	FiringPadWidth = 12,
	-- Straw bales stacked two high, centred on this X.
	BackstopX = 177,
	-- Board facing west (toward the highway), just outside the open side.
	Sign = { X = 67, Z = 297, Width = 10, Text = "PRACTICE RANGE" },
	-- Where the practice targets stand, staggered near / far.
	DummySpots = {
		{ X = 148, Z = 298 },
		{ X = 160, Z = 308 },
		{ X = 148, Z = 318 },
		{ X = 160, Z = 328 },
		{ X = 148, Z = 338 },
	} :: { Point },
	-- Worn dirt circle under each target.
	SpotPatchDiameter = 5,
}

-- Gameplay hooks ---------------------------------------------------------------

-- District zone volumes. The town boxes tile the 1000 x 700 town exactly.
MapLayout.Zones = {
	{ DistrictId = "Farmstead", X0 = -500, X1 = 0, Z0 = -350, Z1 = -90 },
	{ DistrictId = "Farmstead", X0 = -500, X1 = -205, Z0 = -90, Z1 = 45 },
	{ DistrictId = "NorthFields", X0 = 0, X1 = 500, Z0 = -350, Z1 = -90 },
	{ DistrictId = "Downtown", X0 = -205, X1 = 280, Z0 = -90, Z1 = 185 },
	{ DistrictId = "Residential", X0 = 280, X1 = 500, Z0 = -90, Z1 = 250 },
	{ DistrictId = "SouthFields", X0 = -500, X1 = -205, Z0 = 45, Z1 = 250 },
	{ DistrictId = "RailYard", X0 = -205, X1 = 280, Z0 = 185, Z1 = 250 },
	{ DistrictId = "RailYard", X0 = -500, X1 = 500, Z0 = 250, Z1 = 350 },
} :: { ZoneBox }

MapLayout.ZoneSettings = {
	TownPriority = 10,
	-- The OuterRing zone covers the whole world (town zones win by priority). It
	-- is split into Tiles x Tiles parts because a part may be at most 2048 studs.
	OuterPriority = 0,
	OuterTiles = 3,
	-- Zones reach from below the ground to above the flight ceiling.
	Bottom = -50,
}

MapLayout.MainSpawn = { X = 0, Z = 330, Size = 12 }

MapLayout.DistrictSpawns = {
	{ DistrictId = "Downtown", X = 25, Z = -24, LookX = 100, LookZ = -24 },
	{ DistrictId = "Farmstead", X = -290, Z = 0, LookX = -400, LookZ = 0 },
	{ DistrictId = "NorthFields", X = 32, Z = -150, LookX = 200, LookZ = -139 },
	{ DistrictId = "Residential", X = 330, Z = 16, LookX = 420, LookZ = 16 },
	{ DistrictId = "SouthFields", X = -212, Z = 60, LookX = -320, LookZ = 140 },
	{ DistrictId = "RailYard", X = -35, Z = 315, LookX = -35, LookZ = 0 },
	{ DistrictId = "OuterRing", X = 32, Z = 420, LookX = 32, LookZ = 0 },
} :: { DistrictSpawn }

MapLayout.MissionMarkers = {
	{ Id = "Tutorial_Start", DistrictId = "RailYard", X = 35, Z = 322, Surface = 0 },
	{ Id = "Story_CaseHQ", DistrictId = "Downtown", X = 90, Z = -23, Surface = 0.4 },
	{ Id = "Story_Diner", DistrictId = "Downtown", X = -77.5, Z = -23, Surface = 0.4 },
	{ Id = "Story_CrimeScene", DistrictId = "SouthFields", X = -320, Z = 140, Surface = 0.25 },
	{ Id = "Story_PartnerHome", DistrictId = "Residential", X = 399, Z = 96, Surface = 0.15 },
	{ Id = "Story_GrainElevator", DistrictId = "RailYard", X = 84, Z = 205, Surface = 0 },
	{ Id = "Side_Farmstead", DistrictId = "Farmstead", X = -320, Z = -8, Surface = 0.1 },
	{ Id = "Side_WaterTower", DistrictId = "NorthFields", X = 200, Z = -110, Surface = 0 },
	{ Id = "Side_Church", DistrictId = "Downtown", X = 150, Z = 112, Surface = 0.1 },
	{ Id = "Side_GasStation", DistrictId = "Downtown", X = 46, Z = 178, Surface = 0 },
	{ Id = "Side_RailYard", DistrictId = "RailYard", X = -150, Z = 271, Surface = 0 },
	{ Id = "Side_Highway", DistrictId = "OuterRing", X = 0, Z = -1200, Surface = 0.25 },
} :: { MissionMarker }

-- Outer ring ---------------------------------------------------------------------

--[[
	Low-detail farmland from the town edge out to the play-area boundary
	(Config.World.Boundary), plus a "horizon skirt" of plain farmland beyond the
	boundary so the world never ends in a visible edge when flying high. Fields
	are laid out on a section grid: cells between consecutive cut lines are
	split into 1-3 fields with a seeded PRNG.
]]
MapLayout.OuterRing = {
	Seed = 1907,
	SkirtWidth = 1500,

	-- Ground tile cut lines (each tile stays under Roblox's 2048-stud part limit).
	GroundCutsX = { -2500, -1500, -500, 500, 1500, 2500 },
	GroundCutsZ = { -2500, -1425, -350, 350, 1425, 2500 },

	-- Field section grid.
	CellCutsX = { -2500, -2000, -1500, -1000, -500, 0, 500, 1000, 1500, 2000, 2500 },
	CellCutsZ = { -2500, -2000, -1500, -1000, -350, -98, 256, 350, 1000, 1500, 2000, 2500 },

	-- Dirt section tracks (8 wide) run along these grid lines.
	TrackWidth = 8,
	TracksX = { -2000, -1000, 1000, 2000 },
	TracksZ = { -2000, -1000, 1000, 2000 },

	-- Grass verge between a field and each kind of edge.
	Verges = {
		Highway = 34,
		Railroad = 20,
		CountyRoad = 22,
		Track = 8,
		Town = 14,
		Field = 3,
	},

	-- Weighted crop mix for the patchwork (see MapPalette.CropSlabs).
	Crops = {
		{ Crop = "Corn", Weight = 30 },
		{ Crop = "Soy", Weight = 20 },
		{ Crop = "Wheat", Weight = 18 },
		{ Crop = "Stubble", Weight = 10 },
		{ Crop = "Plowed", Weight = 12 },
		{ Crop = "Pasture", Weight = 10 },
	},

	-- Distant farmsteads (house + barn + silo + shelterbelt), front facing the nearest road.
	Farmsteads = {
		{ X = -1200, Z = -36, Facing = "North" },
		{ X = -700, Z = 1070, Facing = "North" },
		{ X = 650, Z = -1066, Facing = "South" },
		{ X = 1066, Z = 650, Facing = "West" },
		{ X = -2066, Z = -1300, Facing = "East" },
		{ X = 2066, Z = 1500, Facing = "West" },
		{ X = 96, Z = 1800, Facing = "West" },
		{ X = -96, Z = -1700, Facing = "East" },
	} :: { Placement },

	-- Shelterbelt tree lines (cedar rows) from (X0, Z0) to (X1, Z1).
	Windbreaks = {
		{ X0 = -1950, Z0 = -1016, X1 = -1550, Z1 = -1016 },
		{ X0 = 1016, Z0 = -1900, X1 = 1016, Z1 = -1500 },
		{ X0 = 1050, Z0 = 984, X1 = 1450, Z1 = 984 },
		{ X0 = -1016, Z0 = 420, X1 = -1016, Z1 = 900 },
		{ X0 = 560, Z0 = -1500, X1 = 960, Z1 = -1500 },
		{ X0 = 1500, Z0 = 1050, X1 = 1500, Z1 = 1450 },
		{ X0 = -950, Z0 = 1984, X1 = -550, Z1 = 1984 },
		{ X0 = -1984, Z0 = 1550, X1 = -1984, Z1 = 1950 },
		{ X0 = -460, Z0 = -1016, X1 = -60, Z1 = -1016 },
		{ X0 = 1980, Z0 = -700, X1 = 1980, Z1 = -260 },
	} :: { Line },
	WindbreakSpacing = 20,

	-- Tall silhouettes for orientation.
	RadioMast = { X = -1650, Z = -1650, Height = 320, GuyRadius = 110 },
	GrainCoop = { X = 1330, Z = 182 },

	-- Highway signs welcoming drivers from either direction.
	HighwaySigns = {
		{ X = -32, Z = -700, Facing = "North" },
		{ X = 32, Z = 700, Facing = "South" },
	} :: { Placement },

	-- Utility poles beside the highway outside town.
	PoleSpacing = 150,
	PoleOffsetX = -30,
}

return MapLayout
