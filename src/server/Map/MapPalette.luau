--!strict
--[[
	MapPalette: the blockout's materials, colours and sign fonts, by name.

	A muted, realistic small-town Midwest palette (sun-bleached paint, red
	brick, asphalt, ripe wheat). Restyle the whole map by editing values here.
	Slabs that lie flat on the ground do not cast shadows (CastShadow false).
]]

local Shapes = require(script.Parent.Shapes)

type Style = Shapes.Style

local function solid(material: Enum.Material, r: number, g: number, b: number): Style
	return { Material = material, Color = Color3.fromRGB(r, g, b) }
end

local function flat(material: Enum.Material, r: number, g: number, b: number): Style
	return { Material = material, Color = Color3.fromRGB(r, g, b), CastShadow = false }
end

-- Walk-through decoration (crops, tape, light beams).
local function ghost(material: Enum.Material, r: number, g: number, b: number, transparency: number?): Style
	return {
		Material = material,
		Color = Color3.fromRGB(r, g, b),
		CanCollide = false,
		Transparency = transparency,
	}
end

local M = Enum.Material

local Palette = {
	-- Ground & roads ---------------------------------------------------------
	Grass = flat(M.Grass, 108, 128, 70),
	Lawn = flat(M.Grass, 98, 132, 64),
	Asphalt = flat(M.Asphalt, 62, 62, 64),
	AsphaltLight = flat(M.Asphalt, 84, 84, 86),
	LineYellow = flat(M.SmoothPlastic, 222, 182, 52),
	LineWhite = flat(M.SmoothPlastic, 226, 226, 220),
	Sidewalk = flat(M.Concrete, 176, 172, 164),
	Curb = flat(M.Concrete, 150, 148, 142),
	DirtRoad = flat(M.Ground, 140, 112, 80),
	Gravel = flat(M.Pebble, 138, 130, 118),
	Ballast = flat(M.Pebble, 116, 108, 100),
	Tie = flat(M.Wood, 82, 62, 46),
	Rail = solid(M.Metal, 120, 118, 116),
	CrossingPlank = flat(M.WoodPlanks, 104, 84, 62),

	-- Fields -----------------------------------------------------------------
	Soil = flat(M.Ground, 104, 80, 56),
	SoilDark = flat(M.Ground, 84, 64, 46),
	Corn = ghost(M.Grass, 86, 124, 48),
	CornTassel = ghost(M.Grass, 196, 178, 104),
	Wheat = ghost(M.Grass, 212, 182, 104),
	WheatPale = ghost(M.Grass, 224, 200, 132),
	Trampled = flat(M.Grass, 186, 162, 104),
	Pasture = flat(M.Grass, 128, 150, 78),
	Soy = flat(M.Grass, 96, 128, 58),
	CornSlab = flat(M.Grass, 74, 106, 44),
	WheatSlab = flat(M.Grass, 204, 172, 98),
	Stubble = flat(M.Grass, 176, 156, 108),
	Plowed = flat(M.Ground, 98, 74, 52),

	-- Building materials -----------------------------------------------------
	BrickRed = solid(M.Brick, 146, 70, 52),
	BrickDark = solid(M.Brick, 104, 56, 46),
	BrickTan = solid(M.Brick, 184, 148, 108),
	Stucco = solid(M.Concrete, 206, 196, 176),
	Concrete = solid(M.Concrete, 172, 168, 160),
	ConcreteDark = solid(M.Concrete, 120, 116, 110),
	ConcreteStained = solid(M.Concrete, 146, 136, 120),
	ClapboardWhite = solid(M.WoodPlanks, 236, 232, 220),
	ClapboardCream = solid(M.WoodPlanks, 226, 214, 182),
	BarnRed = solid(M.WoodPlanks, 146, 44, 36),
	Wood = solid(M.WoodPlanks, 120, 88, 60),
	WoodDark = solid(M.WoodPlanks, 80, 58, 42),
	WoodGrey = solid(M.WoodPlanks, 120, 112, 100),
	Trim = solid(M.SmoothPlastic, 238, 234, 224),
	TrimDark = solid(M.SmoothPlastic, 52, 54, 58),
	Steel = solid(M.Metal, 196, 198, 202),
	SteelDark = solid(M.Metal, 86, 88, 92),
	Rust = solid(M.CorrodedMetal, 132, 78, 48),
	RustDark = solid(M.CorrodedMetal, 96, 60, 42),
	RustGrey = solid(M.CorrodedMetal, 128, 116, 104),
	Galvanized = solid(M.Metal, 176, 180, 182),
	RoofTar = flat(M.Slate, 66, 64, 62),
	RoofShingle = solid(M.Slate, 78, 70, 66),
	RoofShingleBrown = solid(M.Slate, 104, 80, 62),
	RoofMetal = solid(M.Metal, 128, 132, 134),
	BarnRoof = solid(M.Metal, 118, 48, 42),
	RoofGreen = solid(M.Slate, 70, 92, 76),
	Door = solid(M.WoodPlanks, 98, 66, 44),
	DoorGreen = solid(M.SmoothPlastic, 48, 84, 66),
	DoorRed = solid(M.SmoothPlastic, 128, 40, 38),
	-- Windows on solid buildings: opaque, reflective.
	WindowDark = { Material = M.Glass, Color = Color3.fromRGB(56, 72, 84), Reflectance = 0.15 } :: Style,
	-- Windows players can look through.
	WindowClear = { Material = M.Glass, Color = Color3.fromRGB(150, 180, 196), Transparency = 0.55 } :: Style,
	-- Broken / grimy glass on the derelict elevator.
	WindowGrimy = { Material = M.Glass, Color = Color3.fromRGB(96, 104, 92), Transparency = 0.35 } :: Style,
	FenceMesh = {
		Material = M.DiamondPlate,
		Color = Color3.fromRGB(150, 152, 150),
		Transparency = 0.55,
		CastShadow = false,
	} :: Style,
	Fabric = solid(M.Fabric, 60, 60, 64),

	-- Awnings / accents
	AwningGreen = solid(M.Fabric, 52, 98, 70),
	AwningRed = solid(M.Fabric, 136, 42, 44),
	AwningBlue = solid(M.Fabric, 48, 64, 104),
	AwningTan = solid(M.Fabric, 190, 160, 112),
	DinerRed = solid(M.SmoothPlastic, 176, 40, 40),
	DinerTeal = solid(M.SmoothPlastic, 70, 150, 146),
	Checker = flat(M.SmoothPlastic, 226, 222, 210),
	FloorWood = flat(M.WoodPlanks, 146, 110, 74),
	FloorTile = flat(M.Slate, 150, 146, 138),
	Carpet = flat(M.Fabric, 92, 70, 60),
	Leather = solid(M.Fabric, 150, 36, 36),
	SignBoard = solid(M.SmoothPlastic, 40, 42, 44),
	SignCream = solid(M.SmoothPlastic, 232, 222, 196),
	SignWhite = solid(M.SmoothPlastic, 240, 240, 236),
	SignGreen = solid(M.SmoothPlastic, 38, 92, 60),
	SignYellow = solid(M.SmoothPlastic, 236, 196, 44),
	Cork = solid(M.Fabric, 168, 128, 84),
	Paper = ghost(M.SmoothPlastic, 236, 232, 220),
	PhotoPaper = ghost(M.SmoothPlastic, 120, 128, 136),
	RedString = ghost(M.SmoothPlastic, 196, 30, 30),
	CrimeTape = ghost(M.SmoothPlastic, 240, 204, 30),
	EvidenceYellow = solid(M.SmoothPlastic, 242, 200, 40),
	Hay = solid(M.Grass, 206, 178, 108),
	TreeTrunk = solid(M.Wood, 90, 68, 50),
	Leaves = solid(M.Grass, 72, 100, 52),
	LeavesDark = solid(M.Grass, 56, 82, 46),
	LeavesLight = solid(M.Grass, 98, 122, 62),
	Headstone = solid(M.Granite, 150, 150, 148),
	Black = solid(M.SmoothPlastic, 30, 30, 32),
	FlagRed = ghost(M.Fabric, 170, 40, 46),
	FlagWhite = ghost(M.Fabric, 236, 236, 232),
	FlagBlue = ghost(M.Fabric, 40, 52, 104),
	NeonRed = solid(M.Neon, 255, 70, 60),
	LampGlow = solid(M.Neon, 255, 232, 180),

	-- Car paints
	CarPaints = {
		solid(M.SmoothPlastic, 120, 36, 34),
		solid(M.SmoothPlastic, 60, 82, 110),
		solid(M.SmoothPlastic, 206, 200, 184),
		solid(M.SmoothPlastic, 74, 92, 70),
	},
	PatrolCar = solid(M.SmoothPlastic, 236, 236, 232),
	PatrolStripe = solid(M.SmoothPlastic, 40, 60, 46),

	-- Houses cycle through these sidings and roofs.
	HouseSidings = {
		solid(M.WoodPlanks, 226, 214, 170),
		solid(M.WoodPlanks, 170, 192, 204),
		solid(M.WoodPlanks, 168, 180, 146),
		solid(M.WoodPlanks, 232, 230, 222),
		solid(M.WoodPlanks, 208, 186, 158),
		solid(M.WoodPlanks, 184, 186, 188),
	},
	HouseRoofs = {
		solid(M.Slate, 78, 70, 66),
		solid(M.Slate, 104, 80, 62),
		solid(M.Slate, 70, 74, 80),
	},

	-- Outer ring crop slabs (picked per field by the outer ring's PRNG).
	CropSlabs = {
		Corn = flat(M.Grass, 74, 106, 44),
		Soy = flat(M.Grass, 98, 128, 58),
		Wheat = flat(M.Grass, 204, 172, 98),
		Stubble = flat(M.Grass, 178, 158, 110),
		Plowed = flat(M.Ground, 98, 74, 52),
		Pasture = flat(M.Grass, 126, 148, 78),
	},
	-- Field slab top heights per crop (taller crops read as raised blocks from the air).
	CropHeights = {
		Corn = 0.7,
		Soy = 0.4,
		Wheat = 0.45,
		Stubble = 0.25,
		Plowed = 0.2,
		Pasture = 0.15,
	},

	Fonts = {
		Western = Font.new("rbxasset://fonts/families/RomanAntique.json"),
		Serif = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold),
		Bold = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold),
		Rounded = Font.new("rbxasset://fonts/families/FredokaOne.json"),
		Typewriter = Font.new("rbxasset://fonts/families/SpecialElite.json"),
		Highway = Font.new("rbxasset://fonts/families/HighwayGothic.json"),
	},

	SignText = {
		Cream = Color3.fromRGB(240, 230, 204),
		Dark = Color3.fromRGB(36, 36, 38),
		White = Color3.fromRGB(250, 250, 246),
		Red = Color3.fromRGB(196, 36, 36),
		NeonRed = Color3.fromRGB(255, 92, 80),
		Gold = Color3.fromRGB(232, 196, 92),
		WaterTower = Color3.fromRGB(46, 66, 104),
	},
}

return Palette
