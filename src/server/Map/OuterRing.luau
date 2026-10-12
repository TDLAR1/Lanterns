--!strict
--[[
	OuterRing: cheap, low-detail county farmland from the town edge out to the
	play-area boundary (Config.World.Boundary), plus a plain "horizon skirt"
	beyond it so flying near the edge never shows the end of the world.

	  * Ground tiles with no gaps (each part under Roblox's 2048-stud limit).
	  * Main St continues north and south as the highway, the railroad east and
	    west, the County Road west; dirt section tracks on a mile-style grid.
	  * A patchwork of big flat crop slabs (no rows), split per grid cell by a
	    seeded PRNG, leaving room for farmsteads, shelterbelts and landmarks.
	  * Distant farmsteads, cedar windbreaks, a radio mast and a grain co-op
	    as tall silhouettes for orientation.

	Flat layers keep distinct heights (ground 0, tracks 0.1 / 0.12, crop slabs
	0.15-0.7, roads 0.2, ballast 0.5) so nothing z-fights.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.Game)
local World = require(ReplicatedStorage.Shared.Config.World)

local MapLayout = require(script.Parent.MapLayout)
local MapPalette = require(script.Parent.MapPalette)
local Prng = require(script.Parent.Prng)
local Props = require(script.Parent.Props)
local Shapes = require(script.Parent.Shapes)

type Frame = Shapes.Frame
type Style = Shapes.Style
type Rect = MapLayout.Rect
type Prng = Prng.Prng

-- Longest run for one road / track part (under the 2048-stud part limit).
local MAX_RUN = 2000
-- Paint lies on the road's top face (0.2): sharing that plane is harmless because the
-- faces point opposite ways, and it keeps paint ends off the asphalt's end faces.
local PAINT_BOTTOM, PAINT_TOP = 0.2, 0.25
local FARMSTEAD_WIDTH, FARMSTEAD_DEPTH = 90, 70

local OuterRing = {}

local function worldFrame(parent: Instance): Frame
	return Shapes.Frame(parent, CFrame.identity, 0, 0)
end

-- Splits a0..a1 into equal runs no longer than MAX_RUN.
local function runs(a0: number, a1: number): { { number } }
	local count = math.max(1, math.ceil(math.abs(a1 - a0) / MAX_RUN))
	local step = (a1 - a0) / count
	local list = {}
	for index = 0, count - 1 do
		local p0, p1 = a0 + step * index, a0 + step * (index + 1)
		table.insert(list, { math.min(p0, p1), math.max(p0, p1) })
	end
	return list
end

local function contains(list: { number }, value: number): boolean
	return table.find(list, value) ~= nil
end

-- Removes `hole` from `rect`, returning up to four rectangles around it.
local function subtract(rect: Rect, hole: Rect): { Rect }
	if hole.X0 >= rect.X1 or hole.X1 <= rect.X0 or hole.Z0 >= rect.Z1 or hole.Z1 <= rect.Z0 then
		return { rect }
	end
	local ix0, ix1 = math.max(rect.X0, hole.X0), math.min(rect.X1, hole.X1)
	local iz0, iz1 = math.max(rect.Z0, hole.Z0), math.min(rect.Z1, hole.Z1)
	local pieces = {}
	if ix0 > rect.X0 then
		table.insert(pieces, { X0 = rect.X0, X1 = ix0, Z0 = rect.Z0, Z1 = rect.Z1 })
	end
	if ix1 < rect.X1 then
		table.insert(pieces, { X0 = ix1, X1 = rect.X1, Z0 = rect.Z0, Z1 = rect.Z1 })
	end
	if iz0 > rect.Z0 then
		table.insert(pieces, { X0 = ix0, X1 = ix1, Z0 = rect.Z0, Z1 = iz0 })
	end
	if iz1 < rect.Z1 then
		table.insert(pieces, { X0 = ix0, X1 = ix1, Z0 = iz1, Z1 = rect.Z1 })
	end
	return pieces
end

local function townRect(): Rect
	local ground = MapLayout.Find("Ground")
	return {
		X0 = ground.X - ground.SizeX / 2,
		X1 = ground.X + ground.SizeX / 2,
		Z0 = ground.Z - ground.SizeZ / 2,
		Z1 = ground.Z + ground.SizeZ / 2,
	}
end

-- Ground ---------------------------------------------------------------------------

local function buildGround(folder: Instance, prng: Prng)
	local settings = MapLayout.OuterRing
	local town = townRect()
	local model = Shapes.Group(folder, "Ground")
	local frame = worldFrame(model)
	local cutsX, cutsZ = settings.GroundCutsX, settings.GroundCutsZ
	for i = 1, #cutsX - 1 do
		for j = 1, #cutsZ - 1 do
			local x0, x1, z0, z1 = cutsX[i], cutsX[i + 1], cutsZ[j], cutsZ[j + 1]
			local isTown = x0 >= town.X0 and x1 <= town.X1 and z0 >= town.Z0 and z1 <= town.Z1
			if not isTown then
				frame:Span("Grass", x0, x1, -1, 0, z0, z1, MapPalette.Grass)
			end
		end
	end

	-- Horizon skirt: muted farmland tiles beyond the boundary on all four sides.
	local halfX, halfZ = World.Boundary.HalfSizeX, World.Boundary.HalfSizeZ
	local skirt = settings.SkirtWidth
	local farX, farZ = halfX + skirt, halfZ + skirt
	local skirtStyles = {
		MapPalette.Grass,
		MapPalette.CropSlabs.Pasture,
		MapPalette.CropSlabs.Stubble,
		MapPalette.CropSlabs.Soy,
		MapPalette.CropSlabs.Wheat,
		MapPalette.CropSlabs.Plowed,
	}
	local function skirtTiles(x0: number, x1: number, z0: number, z1: number, tilesX: number, tilesZ: number)
		local stepX, stepZ = (x1 - x0) / tilesX, (z1 - z0) / tilesZ
		for i = 0, tilesX - 1 do
			for j = 0, tilesZ - 1 do
				local style = skirtStyles[prng:Int(1, #skirtStyles)]
				local a, c = x0 + stepX * i, z0 + stepZ * j
				frame:Span("Skirt", a, a + stepX, -1, 0, c, c + stepZ, style)
			end
		end
	end
	skirtTiles(-farX, farX, -farZ, -halfZ, 8, 1)
	skirtTiles(-farX, farX, halfZ, farZ, 8, 1)
	skirtTiles(-farX, -halfX, -halfZ, halfZ, 1, 5)
	skirtTiles(halfX, farX, -halfZ, halfZ, 1, 5)
end

-- Roads ------------------------------------------------------------------------------

local function buildHighway(folder: Instance)
	local main = MapLayout.Find("Main St")
	local half = main.SizeX / 2
	local townZ0, townZ1 = main.Z - main.SizeZ / 2, main.Z + main.SizeZ / 2
	local farZ = World.Boundary.HalfSizeZ + MapLayout.OuterRing.SkirtWidth
	local sides = {
		{ Name = "Highway North", From = -farZ, To = townZ0 },
		{ Name = "Highway South", From = townZ1, To = farZ },
	}
	for _, side in sides do
		local model = Shapes.Group(folder, side.Name)
		local frame = worldFrame(model)
		for _, run in runs(side.From, side.To) do
			frame:Span("Asphalt", -half, half, 0, 0.2, run[1], run[2], MapPalette.Asphalt)
			-- Solid double yellow centre line and white edge lines (cheap: one part each).
			for _, x in { -0.45, 0.45 } do
				frame:Span(
					"CentreLine",
					x - 0.15,
					x + 0.15,
					PAINT_BOTTOM,
					PAINT_TOP,
					run[1],
					run[2],
					MapPalette.LineYellow
				)
			end
			for _, x in { -(half - 2.5), half - 2.5 } do
				frame:Span(
					"EdgeLine",
					x - 0.25,
					x + 0.25,
					PAINT_BOTTOM,
					PAINT_TOP,
					run[1],
					run[2],
					MapPalette.LineWhite
				)
			end
		end
	end
end

local function buildRailroad(folder: Instance)
	local railroad = MapLayout.Find("Railroad")
	local z, half = railroad.Z, railroad.SizeZ / 2
	local top = railroad.Height
	local townX0, townX1 = railroad.X - railroad.SizeX / 2, railroad.X + railroad.SizeX / 2
	local farX = World.Boundary.HalfSizeX + MapLayout.OuterRing.SkirtWidth
	local sides = {
		{ Name = "Railroad West", From = -farX, To = townX0 },
		{ Name = "Railroad East", From = townX1, To = farX },
	}
	for _, side in sides do
		local model = Shapes.Group(folder, side.Name)
		local frame = worldFrame(model)
		for _, run in runs(side.From, side.To) do
			-- No ties out here: ballast and rails only.
			frame:Span("Ballast", run[1] + 0.5, run[2] - 0.5, 0, 0.3, z - half, z + half, MapPalette.Ballast)
			frame:Span("BallastBed", run[1], run[2], 0, top, z - half + 2, z + half - 2, MapPalette.Ballast)
			for _, offset in { -2.35, 2.35 } do
				frame:Span("Rail", run[1], run[2], top, top + 0.5, z + offset - 0.2, z + offset + 0.2, MapPalette.Rail)
			end
		end
	end
end

local function buildCountyRoad(folder: Instance)
	local road = MapLayout.Find("County Road")
	local townEnd = road.X - road.SizeX / 2
	local farX = World.Boundary.HalfSizeX + MapLayout.OuterRing.SkirtWidth
	local z0, z1 = road.Z - road.SizeZ / 2, road.Z + road.SizeZ / 2
	local model = Shapes.Group(folder, "County Road West")
	local frame = worldFrame(model)
	for _, run in runs(-farX, townEnd) do
		frame:Span("Dirt", run[1], run[2], 0, 0.2, z0, z1, MapPalette.DirtRoad)
		for _, offset in { -5, 5 } do
			frame:Span(
				"Rut",
				run[1],
				run[2],
				PAINT_BOTTOM,
				PAINT_TOP,
				road.Z + offset - 1.2,
				road.Z + offset + 1.2,
				MapPalette.SoilDark
			)
		end
	end
end

-- Dirt section tracks along the grid lines (inside the boundary only).
local function buildTracks(folder: Instance)
	local settings = MapLayout.OuterRing
	local halfX, halfZ = World.Boundary.HalfSizeX, World.Boundary.HalfSizeZ
	local half = settings.TrackWidth / 2
	local model = Shapes.Group(folder, "Tracks")
	local frame = worldFrame(model)
	for _, x in settings.TracksX do
		for _, run in runs(-halfZ, halfZ) do
			frame:Span("Track", x - half, x + half, 0, 0.1, run[1], run[2], MapPalette.DirtRoad)
		end
	end
	-- East-west tracks sit a hair higher so crossings never share a plane.
	for _, z in settings.TracksZ do
		for _, run in runs(-halfX, halfX) do
			frame:Span("Track", run[1], run[2], 0, 0.12, z - half, z + half, MapPalette.DirtRoad)
		end
	end
end

-- Farmsteads ----------------------------------------------------------------------------

-- Distance from the front edge of a farmstead to the nearest road or track it faces.
local function driveLength(placement: MapLayout.Placement): number
	local settings = MapLayout.OuterRing
	local front = FARMSTEAD_DEPTH / 2
	-- Only the fallback length when no road or track is within range; every listed
	-- farmstead has one closer than this (the farthest is 41 studs away).
	local best = 80
	local function consider(lineAt: number, center: number, sign: number, halfWidth: number)
		local distance = (lineAt - center) * sign - front - halfWidth
		if distance >= 0 and distance < best then
			best = distance
		end
	end
	local facing = placement.Facing
	if facing == "North" or facing == "South" then
		local sign = if facing == "South" then 1 else -1
		for _, z in settings.TracksZ do
			consider(z, placement.Z, sign, settings.TrackWidth / 2)
		end
		local railroad = MapLayout.Find("Railroad")
		consider(railroad.Z, placement.Z, sign, railroad.SizeZ / 2)
		local county = MapLayout.Find("County Road")
		if placement.X < county.X - county.SizeX / 2 then
			consider(county.Z, placement.Z, sign, county.SizeZ / 2)
		end
	else
		local sign = if facing == "East" then 1 else -1
		for _, x in settings.TracksX do
			consider(x, placement.X, sign, settings.TrackWidth / 2)
		end
		local main = MapLayout.Find("Main St")
		consider(main.X, placement.X, sign, main.SizeX / 2)
	end
	return best
end

local function buildFarmstead(folder: Instance, index: number, placement: MapLayout.Placement, prng: Prng)
	local model = Props.Extra(folder, `Farmstead {index}`, "OuterRing")
	local frame = Shapes.FrameFor(model, placement.X, placement.Z, FARMSTEAD_WIDTH, FARMSTEAD_DEPTH, placement.Facing)
	local halfW, halfD = FARMSTEAD_WIDTH / 2, FARMSTEAD_DEPTH / 2
	local siding = MapPalette.HouseSidings[prng:Int(1, #MapPalette.HouseSidings)]
	local roof = MapPalette.HouseRoofs[prng:Int(1, #MapPalette.HouseRoofs)]

	frame:Span("Yard", -halfW + 5, halfW - 5, 0, 0.1, -halfD + 5, halfD - 5, MapPalette.DirtRoad)
	local drive = driveLength(placement)
	frame:Span("Drive", -4, 4, 0, 0.1, -halfD - drive, -halfD + 5, MapPalette.DirtRoad)

	frame:Span("House", -36, -14, 0, 9, -24, -8, siding)
	frame:GableRoof("House", -36, -14, -24, -8, 9, 5, "X", siding, roof, 0.8)
	frame:Span("Barn", 6, 32, 0, 12, -16, 22, MapPalette.BarnRed)
	frame:GableRoof("Barn", 6, 32, -16, 22, 12, 7, "Z", MapPalette.BarnRed, MapPalette.RoofMetal, 0.8)
	frame:Panel("BarnDoor", "Front", -16, 14, 24, 0, 9, 0.2, MapPalette.Trim)
	frame:Cylinder("Silo", -22, 20, 0, 28, 11, MapPalette.Galvanized)
	frame:Ball("SiloDome", -22, 28, 20, 11, MapPalette.Galvanized)
	frame:Span("Shed", -39, -29, 0, 7, -2, 16, MapPalette.RoofMetal)
	-- Shelterbelt along the back of the yard.
	for tree = 0, 6 do
		local spot = frame:Point(-halfW + 8 + tree * (FARMSTEAD_WIDTH - 16) / 6, 0, halfD - 2)
		local leaves = if tree % 2 == 0 then MapPalette.LeavesDark else MapPalette.Leaves
		Props.Cedar(model, spot.X, spot.Z, prng:Range(13, 18), leaves)
	end
end

local function farmsteadRect(placement: MapLayout.Placement, margin: number): Rect
	local width, depth = FARMSTEAD_WIDTH, FARMSTEAD_DEPTH
	if placement.Facing == "East" or placement.Facing == "West" then
		width, depth = depth, width
	end
	return {
		X0 = placement.X - width / 2 - margin,
		X1 = placement.X + width / 2 + margin,
		Z0 = placement.Z - depth / 2 - margin,
		Z1 = placement.Z + depth / 2 + margin,
	}
end

-- Windbreaks and landmarks ------------------------------------------------------------------

local function buildWindbreaks(folder: Instance, prng: Prng)
	local settings = MapLayout.OuterRing
	local model = Shapes.Group(folder, "Windbreaks")
	for _, line in settings.Windbreaks do
		local a, b = Vector3.new(line.X0, 0, line.Z0), Vector3.new(line.X1, 0, line.Z1)
		local length = (b - a).Magnitude
		local count = math.floor(length / settings.WindbreakSpacing)
		local across = Vector3.new(-(b - a).Unit.Z, 0, (b - a).Unit.X)
		for tree = 0, count do
			local p = a + (b - a) * (tree / count) + across * prng:Range(-2, 2)
			Props.Cedar(
				model,
				p.X,
				p.Z,
				prng:Range(14, 20),
				if tree % 3 == 0 then MapPalette.Leaves else MapPalette.LeavesDark
			)
		end
	end
end

local function windbreakRect(line: MapLayout.Line, margin: number): Rect
	return {
		X0 = math.min(line.X0, line.X1) - margin,
		X1 = math.max(line.X0, line.X1) + margin,
		Z0 = math.min(line.Z0, line.Z1) - margin,
		Z1 = math.max(line.Z0, line.Z1) + margin,
	}
end

-- Guyed radio mast in aviation red and white bands with red beacons.
local function buildRadioMast(folder: Instance)
	local settings = MapLayout.OuterRing.RadioMast
	local model = Props.Extra(folder, "Radio Mast", "OuterRing")
	local frame = Shapes.Frame(model, CFrame.new(settings.X, 0, settings.Z), 0, 0)
	local red: Style = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(196, 64, 46) }
	local white = MapPalette.SignWhite
	local bands = 6
	local bandHeight = settings.Height / bands
	frame:Span("Pad", -6, 6, 0, 0.6, -6, 6, MapPalette.Concrete)
	for band = 0, bands - 1 do
		local width = 5 - band * 0.4
		frame:Span(
			"Mast",
			-width / 2,
			width / 2,
			0.6 + bandHeight * band,
			0.6 + bandHeight * (band + 1),
			-width / 2,
			width / 2,
			if band % 2 == 0 then red else white
		)
	end
	local beacon: Style = { Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 40, 30), CanCollide = false }
	frame:Ball("Beacon", 0, settings.Height + 1.6, 0, 2.4, beacon)
	frame:Ball("Beacon", 0, settings.Height / 2, 0, 3.4, beacon)
	local wire: Style =
		{ Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(60, 60, 62), CanCollide = false }
	for index = 0, 2 do
		local angle = math.rad(90 + index * 120)
		local anchor = Vector3.new(math.cos(angle) * settings.GuyRadius, 0.8, math.sin(angle) * settings.GuyRadius)
		frame:Span(
			"Anchor",
			anchor.X - 1.5,
			anchor.X + 1.5,
			0,
			1.5,
			anchor.Z - 1.5,
			anchor.Z + 1.5,
			MapPalette.Concrete
		)
		for _, height in { settings.Height * 0.55, settings.Height * 0.9 } do
			frame:Beam("GuyWire", anchor, Vector3.new(0, height, 0), 0.3, wire)
		end
	end
	frame:Span("Shed", 8, 18, 0, 6, -5, 5, MapPalette.Concrete)
end

-- Grain co-op by the railroad: a row of tall concrete silos, a head house,
-- a gallery across the tops, a siding with two hopper cars.
local function buildGrainCoop(folder: Instance): Rect
	local settings = MapLayout.OuterRing.GrainCoop
	local model = Props.Extra(folder, "Grain Co-op", "OuterRing")
	local frame = Shapes.Frame(model, CFrame.new(settings.X, 0, settings.Z), 0, 0)
	local concrete = MapPalette.Concrete
	local siloHeight = 110
	for index = 0, 5 do
		local x = -75 + index * 30
		frame:Cylinder("Silo", x, 0, 0, siloHeight, 26, concrete)
	end
	frame:Span("Gallery", -90, 90, siloHeight, siloHeight + 6, -5, 5, concrete)
	frame:Span("HeadHouse", -128, -102, 0, 150, -16, 18, concrete)
	frame:Span("HeadHouseTop", -124, -106, 150, 158, -10, 12, MapPalette.ConcreteDark)
	-- Conveyor bridge from the head house to the end of the gallery, at its height.
	frame:Span("Bridge", -102, -90, siloHeight + 0.5, siloHeight + 5.5, -3, 3, concrete)

	local railroad = MapLayout.Find("Railroad")
	local sidingZ = railroad.Z - railroad.SizeZ / 2 - 9 - settings.Z
	frame:Beam("Spout", Vector3.new(-115, 125, 18), Vector3.new(-115, 16, sidingZ - 2), 2, MapPalette.RustDark)
	frame:Span("SidingBallast", -180, 170, 0, 0.4, sidingZ - 4, sidingZ + 4, MapPalette.Ballast)
	for _, offset in { -2.35, 2.35 } do
		frame:Span("Rail", -180, 170, 0.4, 0.9, sidingZ + offset - 0.2, sidingZ + offset + 0.2, MapPalette.Rail)
	end
	for _, x in { -40, 6 } do
		frame:Span("Hopper", x - 18, x + 18, 2.5, 13, sidingZ - 4.6, sidingZ + 4.6, MapPalette.Galvanized)
		frame:Span("Trucks", x - 15, x + 15, 0.9, 2.5, sidingZ - 3, sidingZ + 3, MapPalette.Black)
	end
	return {
		X0 = settings.X - 200,
		X1 = settings.X + 190,
		Z0 = settings.Z - 40,
		Z1 = settings.Z + sidingZ + 8,
	}
end

local function buildHighwaySigns(folder: Instance)
	local model = Props.Extra(folder, "Highway Signs", "OuterRing")
	local town = string.upper(GameConfig.TownName)
	for _, sign in MapLayout.OuterRing.HighwaySigns do
		Props.RoadSign(
			model,
			sign.X,
			sign.Z,
			sign.Facing,
			20,
			9,
			town,
			"CITY LIMITS",
			MapPalette.SignGreen,
			MapPalette.SignText.White
		)
	end
end

local function buildPoles(folder: Instance)
	local settings = MapLayout.OuterRing
	local main = MapLayout.Find("Main St")
	local townZ0, townZ1 = main.Z - main.SizeZ / 2, main.Z + main.SizeZ / 2
	local halfZ = World.Boundary.HalfSizeZ
	local model = Shapes.Group(folder, "Utility Poles")
	local first = 75
	Props.PoleLine(model, settings.PoleOffsetX, townZ0 - first, -halfZ + first, settings.PoleSpacing)
	Props.PoleLine(model, settings.PoleOffsetX, townZ1 + first, halfZ - first, settings.PoleSpacing)
end

-- Fields --------------------------------------------------------------------------------------

-- Grass verge between a field and a cut line, by what runs along that line.
local function verge(axis: "X" | "Z", at: number, from: number, to: number): number
	local settings = MapLayout.OuterRing
	local verges = settings.Verges
	local town = townRect()
	local halfX, halfZ = World.Boundary.HalfSizeX, World.Boundary.HalfSizeZ
	local mid = (from + to) / 2
	if axis == "X" then
		-- Line of constant X; the cell spans Z from..to.
		if math.abs(at) >= halfX then
			return 0
		elseif at == MapLayout.Find("Main St").X then
			return verges.Highway
		elseif contains(settings.TracksX, at) then
			return verges.Track
		elseif (at == town.X0 or at == town.X1) and mid > town.Z0 and mid < town.Z1 then
			return verges.Town
		end
		return verges.Field
	end
	if math.abs(at) >= halfZ then
		return 0
	end
	local railroad = MapLayout.Find("Railroad")
	local county = MapLayout.Find("County Road")
	if at == railroad.Z then
		return verges.Railroad
	elseif at == county.Z and mid < county.X - county.SizeX / 2 then
		return verges.CountyRoad
	elseif contains(settings.TracksZ, at) then
		return verges.Track
	elseif (at == town.Z0 or at == town.Z1) and mid > town.X0 and mid < town.X1 then
		return verges.Town
	end
	return verges.Field
end

local function pickCrop(prng: Prng): string
	local crops = MapLayout.OuterRing.Crops
	local total = 0
	for _, entry in crops do
		total += entry.Weight
	end
	local roll = prng:Range(0, total)
	for _, entry in crops do
		roll -= entry.Weight
		if roll < 0 then
			return entry.Crop
		end
	end
	return crops[#crops].Crop
end

local function buildFields(folder: Instance, prng: Prng, exclusions: { Rect })
	local settings = MapLayout.OuterRing
	local town = townRect()
	local model = Shapes.Group(folder, "Fields")
	local frame = worldFrame(model)
	local slabs = MapPalette.CropSlabs :: { [string]: Style }
	local heights = MapPalette.CropHeights :: { [string]: number }
	local cutsX, cutsZ = settings.CellCutsX, settings.CellCutsZ
	local gap = 6

	for i = 1, #cutsX - 1 do
		for j = 1, #cutsZ - 1 do
			local cx0, cx1, cz0, cz1 = cutsX[i], cutsX[i + 1], cutsZ[j], cutsZ[j + 1]
			local isTown = cx0 >= town.X0 and cx1 <= town.X1 and cz0 >= town.Z0 and cz1 <= town.Z1
			if not isTown then
				local cell = {
					X0 = cx0 + verge("X", cx0, cz0, cz1),
					X1 = cx1 - verge("X", cx1, cz0, cz1),
					Z0 = cz0 + verge("Z", cz0, cx0, cx1),
					Z1 = cz1 - verge("Z", cz1, cx0, cx1),
				}
				-- Split the cell into 1-3 fields along its longer side.
				local alongX = cell.X1 - cell.X0 >= cell.Z1 - cell.Z0
				local length = if alongX then cell.X1 - cell.X0 else cell.Z1 - cell.Z0
				local count = if length > 260 then prng:Int(1, 3) else 1
				local weights, total = {}, 0
				for index = 1, count do
					weights[index] = prng:Range(0.6, 1.4)
					total += weights[index]
				end
				local cursor = if alongX then cell.X0 else cell.Z0
				local usable = length - gap * (count - 1)
				for index = 1, count do
					local size = usable * weights[index] / total
					local field: Rect = if alongX
						then { X0 = cursor, X1 = cursor + size, Z0 = cell.Z0, Z1 = cell.Z1 }
						else { X0 = cell.X0, X1 = cell.X1, Z0 = cursor, Z1 = cursor + size }
					cursor += size + gap
					local pieces = { field }
					for _, hole in exclusions do
						local kept = {}
						for _, piece in pieces do
							for _, remaining in subtract(piece, hole) do
								table.insert(kept, remaining)
							end
						end
						pieces = kept
					end
					local crop = pickCrop(prng)
					for _, piece in pieces do
						if piece.X1 - piece.X0 >= 20 and piece.Z1 - piece.Z0 >= 20 then
							frame:Span(
								"Field",
								piece.X0,
								piece.X1,
								-0.05,
								heights[crop],
								piece.Z0,
								piece.Z1,
								slabs[crop]
							)
						end
					end
				end
			end
		end
	end
end

function OuterRing.Build(folder: Instance)
	local settings = MapLayout.OuterRing
	-- Each part of the ring draws from its own generator so editing one never reshuffles another.
	buildGround(folder, Prng.new(settings.Seed))
	buildHighway(folder)
	buildRailroad(folder)
	buildCountyRoad(folder)
	buildTracks(folder)
	buildPoles(folder)
	buildHighwaySigns(folder)

	local exclusions: { Rect } = {}
	local farmPrng = Prng.new(settings.Seed + 1)
	for index, placement in settings.Farmsteads do
		buildFarmstead(folder, index, placement, farmPrng)
		table.insert(exclusions, farmsteadRect(placement, 8))
	end
	buildWindbreaks(folder, Prng.new(settings.Seed + 2))
	for _, line in settings.Windbreaks do
		table.insert(exclusions, windbreakRect(line, 12))
	end
	buildRadioMast(folder)
	local mast = settings.RadioMast
	local reach = mast.GuyRadius + 12
	table.insert(exclusions, { X0 = mast.X - reach, X1 = mast.X + reach, Z0 = mast.Z - reach, Z1 = mast.Z + reach })
	table.insert(exclusions, buildGrainCoop(folder))
	for _, sign in settings.HighwaySigns do
		table.insert(exclusions, { X0 = sign.X - 16, X1 = sign.X + 16, Z0 = sign.Z - 6, Z1 = sign.Z + 6 })
	end

	buildFields(folder, Prng.new(settings.Seed + 3), exclusions)
end

return OuterRing
