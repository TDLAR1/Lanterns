--!strict
--[[
	Roads: the ground plate, streets, railroad and the street-level extras
	(sidewalks, crosswalks, Birch Lane).

	Coplanar overlapping parts flicker (z-fighting), so streets are split where
	they cross (Center Street stops at Main St's edges, Oak St stops at Elm
	Ave's, Main St stops at the level crossing) and paint sits a hair above the
	asphalt. Each road Model's Footprint still covers its full spec box.
]]

local MapLayout = require(script.Parent.MapLayout)
local MapPalette = require(script.Parent.MapPalette)
local Props = require(script.Parent.Props)
local Shapes = require(script.Parent.Shapes)

type Element = MapLayout.Element
type Frame = Shapes.Frame
type Style = Shapes.Style
type Range = { number }

local ROAD_TOP = 0.2
-- Paint lies on the road's top face (0.2): sharing that plane is harmless because the
-- faces point opposite ways, and it keeps paint ends off the asphalt's end faces.
local PAINT_BOTTOM, PAINT_TOP = 0.2, 0.25
local SIDEWALK_TOP = 0.4
local DASH, GAP = 8, 12

local Roads = {}

-- Frame whose local space is world space (roads are axis-aligned).
local function worldFrame(parent: Instance): Frame
	return Shapes.Frame(parent, CFrame.identity, 0, 0)
end

local function overlapsAny(a0: number, a1: number, skips: { Range }): boolean
	for _, skip in skips do
		if a0 < skip[2] and a1 > skip[1] then
			return true
		end
	end
	return false
end

-- Dashed paint line along `axis` at cross position `at`, from a0 to a1, leaving out `skips`.
local function dashedLine(
	frame: Frame,
	axis: "X" | "Z",
	at: number,
	a0: number,
	a1: number,
	width: number,
	skips: { Range },
	style: Style
)
	local a = a0
	while a + DASH <= a1 do
		if not overlapsAny(a, a + DASH, skips) then
			if axis == "X" then
				frame:Span("Dash", a, a + DASH, PAINT_BOTTOM, PAINT_TOP, at - width / 2, at + width / 2, style)
			else
				frame:Span("Dash", at - width / 2, at + width / 2, PAINT_BOTTOM, PAINT_TOP, a, a + DASH, style)
			end
		end
		a += DASH + GAP
	end
end

-- Zebra crosswalk: `count` stripes, each running along `axis`, spread across the other axis.
local function crosswalk(frame: Frame, axis: "X" | "Z", a0: number, a1: number, b0: number, b1: number, count: number)
	local pitch = (b1 - b0) / count
	for index = 0, count - 1 do
		local s0 = b0 + pitch * index + pitch * 0.25
		local s1 = s0 + pitch * 0.5
		if axis == "Z" then
			frame:Span("Crosswalk", s0, s1, PAINT_BOTTOM, PAINT_TOP, a0, a1, MapPalette.LineWhite)
		else
			frame:Span("Crosswalk", a0, a1, PAINT_BOTTOM, PAINT_TOP, s0, s1, MapPalette.LineWhite)
		end
	end
end

function Roads.Ground(model: Model, element: Element)
	local frame = worldFrame(model)
	local halfX, halfZ = element.SizeX / 2, element.SizeZ / 2
	frame:Span(
		"Grass",
		element.X - halfX,
		element.X + halfX,
		-element.Height,
		0,
		element.Z - halfZ,
		element.Z + halfZ,
		MapPalette.Grass
	)
end

-- Main St / highway: asphalt in two runs around the level crossing, white edge
-- lines, a dashed yellow centre line and crosswalks at Center Street.
function Roads.MainStreet(model: Model, element: Element)
	local frame = worldFrame(model)
	local half = element.SizeX / 2
	local z0, z1 = element.Z - element.SizeZ / 2, element.Z + element.SizeZ / 2
	local railroad = MapLayout.Find("Railroad")
	local railZ0, railZ1 = railroad.Z - railroad.SizeZ / 2, railroad.Z + railroad.SizeZ / 2
	local crossing = MapLayout.Find("Center Street")
	local streetHalf = crossing.SizeZ / 2
	local spawn = MapLayout.MainSpawn

	frame:Span("Asphalt", -half, half, 0, ROAD_TOP, z0, railZ0, MapPalette.Asphalt)
	frame:Span("Asphalt", -half, half, 0, ROAD_TOP, railZ1, z1, MapPalette.Asphalt)

	-- Edge lines stop at the intersection, the crosswalks and the level crossing.
	local walk = streetHalf + 12
	local runs = { { z0, -walk }, { walk, railZ0 - 2 }, { railZ1 + 2, z1 } }
	for _, run in runs do
		for _, side in { -1, 1 } do
			local x = side * (half - 2.5)
			frame:Span("EdgeLine", x - 0.25, x + 0.25, PAINT_BOTTOM, PAINT_TOP, run[1], run[2], MapPalette.LineWhite)
		end
	end

	dashedLine(frame, "Z", 0, z0 + 4, z1 - 4, 0.6, {
		{ -walk, walk },
		{ railZ0 - 6, railZ1 + 6 },
		{ spawn.Z - spawn.Size / 2 - 2, spawn.Z + spawn.Size / 2 + 2 },
	}, MapPalette.LineYellow)

	-- Crosswalks across Main St, just north and south of Center Street.
	crosswalk(frame, "Z", -walk, -streetHalf - 2, -half + 1, half - 1, 8)
	crosswalk(frame, "Z", streetHalf + 2, walk, -half + 1, half - 1, 8)
end

-- Center Street: two halves either side of Main St, dashed centre line, crosswalks.
function Roads.CenterStreet(model: Model, element: Element)
	local frame = worldFrame(model)
	local main = MapLayout.Find("Main St")
	local mainHalf = main.SizeX / 2
	local x0, x1 = element.X - element.SizeX / 2, element.X + element.SizeX / 2
	local half = element.SizeZ / 2

	frame:Span("Asphalt", x0, -mainHalf, 0, ROAD_TOP, -half, half, MapPalette.Asphalt)
	frame:Span("Asphalt", mainHalf, x1, 0, ROAD_TOP, -half, half, MapPalette.Asphalt)

	local walk = mainHalf + 12
	dashedLine(frame, "X", 0, x0 + 4, -walk - 2, 0.6, {}, MapPalette.LineYellow)
	dashedLine(frame, "X", 0, walk + 2, x1 - 4, 0.6, {}, MapPalette.LineYellow)

	crosswalk(frame, "X", -walk, -mainHalf - 2, -half + 1, half - 1, 8)
	crosswalk(frame, "X", mainHalf + 2, walk, -half + 1, half - 1, 8)
end

-- Dirt county road with two darker wheel ruts.
function Roads.CountyRoad(model: Model, element: Element)
	local frame = worldFrame(model)
	local x0, x1 = element.X - element.SizeX / 2, element.X + element.SizeX / 2
	local z0, z1 = element.Z - element.SizeZ / 2, element.Z + element.SizeZ / 2
	frame:Span("Dirt", x0, x1, 0, ROAD_TOP, z0, z1, MapPalette.DirtRoad)
	for _, offset in { -5, 5 } do
		local z = element.Z + offset
		frame:Span("Rut", x0, x1 - 2, PAINT_BOTTOM, PAINT_TOP, z - 1.2, z + 1.2, MapPalette.SoilDark)
	end
end

function Roads.ElmAve(model: Model, element: Element)
	local frame = worldFrame(model)
	frame:Span(
		"Asphalt",
		element.X - element.SizeX / 2,
		element.X + element.SizeX / 2,
		0,
		ROAD_TOP,
		element.Z - element.SizeZ / 2,
		element.Z + element.SizeZ / 2,
		MapPalette.AsphaltLight
	)
end

-- Oak St: two runs, north and south of Elm Ave.
function Roads.OakSt(model: Model, element: Element)
	local frame = worldFrame(model)
	local elm = MapLayout.Find("Elm Ave")
	local elmZ0, elmZ1 = elm.Z - elm.SizeZ / 2, elm.Z + elm.SizeZ / 2
	local x0, x1 = element.X - element.SizeX / 2, element.X + element.SizeX / 2
	local z0, z1 = element.Z - element.SizeZ / 2, element.Z + element.SizeZ / 2
	frame:Span("Asphalt", x0, x1, 0, ROAD_TOP, z0, elmZ0, MapPalette.AsphaltLight)
	frame:Span("Asphalt", x0, x1, 0, ROAD_TOP, elmZ1, z1, MapPalette.AsphaltLight)
end

-- Crossbuck sign: post plus two crossed boards, readable from `facing`.
local function crossbuck(parent: Instance, x: number, z: number, facing: Shapes.Facing)
	local frame = Shapes.FrameFor(parent, x, z, 1, 1, facing)
	frame:Cylinder("Post", 0, 0, 0, 12, 0.5, MapPalette.Steel)
	local label = { Color = MapPalette.SignText.Dark, Font = MapPalette.Fonts.Highway }
	local first = frame:Turned("Crossbuck", 0, 10, -0.35, 8, 1.2, 0.2, 0, 0, 45, MapPalette.SignWhite)
	Shapes.Label(first, Enum.NormalId.Front, "RAILROAD", label)
	local second = frame:Turned("Crossbuck", 0, 10, -0.6, 8, 1.2, 0.2, 0, 0, -45, MapPalette.SignWhite)
	Shapes.Label(second, Enum.NormalId.Front, "CROSSING", label)
end

-- Railroad: two-tier gravel ballast, wooden ties (town only), two steel rails,
-- a plank level crossing flush with Main St and crossbuck signs.
function Roads.Railroad(model: Model, element: Element)
	local frame = worldFrame(model)
	local main = MapLayout.Find("Main St")
	local roadHalf = main.SizeX / 2
	local x0, x1 = element.X - element.SizeX / 2, element.X + element.SizeX / 2
	local z, half = element.Z, element.SizeZ / 2
	local top = element.Height

	for _, run in { { x0, -roadHalf }, { roadHalf, x1 } } do
		-- The wide shoulder stops short of the bed's ends so their end faces never share a plane.
		frame:Span("Ballast", run[1] + 0.5, run[2] - 0.5, 0, 0.3, z - half, z + half, MapPalette.Ballast)
		frame:Span("BallastBed", run[1], run[2], 0, top, z - half + 2, z + half - 2, MapPalette.Ballast)
		for _, side in { -2.35, 2.35 } do
			frame:Span("Rail", run[1], run[2], top + 0.2, top + 0.7, z + side - 0.2, z + side + 0.2, MapPalette.Rail)
		end
	end
	-- Ties sit slightly sunk into the ballast so their bottoms never share its top plane.
	local tieX = x0 + 2
	while tieX <= x1 - 2 do
		if math.abs(tieX) > roadHalf + 1 then
			frame:Span("Tie", tieX - 0.6, tieX + 0.6, top - 0.1, top + 0.2, z - 4.2, z + 4.2, MapPalette.Tie)
		end
		tieX += 3.5
	end

	-- Level crossing: planks flush with the asphalt, rails just proud of them.
	frame:Span("CrossingPlanks", -roadHalf, roadHalf, 0, ROAD_TOP, z - half, z + half, MapPalette.CrossingPlank)
	for _, side in { -2.35, 2.35 } do
		frame:Span(
			"Rail",
			-roadHalf + 0.05,
			roadHalf - 0.05,
			0.12,
			0.32,
			z + side - 0.2,
			z + side + 0.2,
			MapPalette.Rail
		)
	end
	crossbuck(model, -roadHalf - 5, z - half - 6, "North")
	crossbuck(model, roadHalf + 5, z + half + 6, "South")
end

-- Sidewalks, Birch Lane and street lamps (extras that are not spec elements).
function Roads.BuildExtras(roads: Instance, downtown: Instance)
	local sidewalks = Props.Extra(roads, "Sidewalks", "Downtown")
	local frame = worldFrame(sidewalks)
	for _, rect in MapLayout.Sidewalks do
		frame:Span("Sidewalk", rect.X0, rect.X1, 0, SIDEWALK_TOP, rect.Z0, rect.Z1, MapPalette.Sidewalk)
	end

	local lane = MapLayout.BirchLane
	local birch = Props.Extra(roads, "Birch Lane", "Residential")
	worldFrame(birch):Span("Gravel", lane.X0, lane.X1, 0, 0.15, lane.Z0, lane.Z1, MapPalette.Gravel)

	local lamps = Props.Extra(downtown, "Street Lamps", "Downtown")
	for _, lamp in MapLayout.StreetLamps do
		Props.StreetLamp(lamps, lamp.X, lamp.Z, lamp.Facing)
	end
end

return Roads
