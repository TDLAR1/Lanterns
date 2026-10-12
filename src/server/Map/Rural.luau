--!strict
--[[
	Rural: gabled houses and farm buildings (houses, the Calloway Home,
	farmhouse, barn, silos, water tower) plus the farmyard and town trees.

	All of these are solid at ground level. Houses face their street; each one
	gets a front walk out to the street and a mailbox.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.Game)
local World = require(ReplicatedStorage.Shared.Config.World)

local MapLayout = require(script.Parent.MapLayout)
local MapPalette = require(script.Parent.MapPalette)
local Props = require(script.Parent.Props)
local Shapes = require(script.Parent.Shapes)

type Element = MapLayout.Element
type Frame = Shapes.Frame
type Style = Shapes.Style
type Rect = MapLayout.Rect

local Rural = {}

local INVISIBLE: Style = {
	Material = Enum.Material.SmoothPlastic,
	Color = Color3.new(1, 1, 1),
	Transparency = 1,
	CanCollide = false,
	CastShadow = false,
}

local CALLOWAY_SIDING: Style = { Material = Enum.Material.WoodPlanks, Color = Color3.fromRGB(88, 106, 128) }

local function frameFor(model: Model, element: Element): Frame
	return Shapes.FrameFor(model, element.X, element.Z, element.SizeX, element.SizeZ, element.Facing or "North")
end

local function pick<T>(list: { T }, index: number): T
	return list[(index - 1) % #list + 1]
end

-- Street edges a front walk can reach (every residential street).
local function streetRects(): { Rect }
	local rects = { MapLayout.BirchLane }
	for _, name in { "Elm Ave", "Oak St" } do
		local road = MapLayout.Find(name)
		table.insert(rects, {
			X0 = road.X - road.SizeX / 2,
			X1 = road.X + road.SizeX / 2,
			Z0 = road.Z - road.SizeZ / 2,
			Z1 = road.Z + road.SizeZ / 2,
		})
	end
	return rects
end

-- Studs from the frame-local point (x, 0, z) straight out of the front (-Z) to the nearest street.
local function distanceToStreet(frame: Frame, x: number, z: number): number?
	local start = frame:Point(x, 0, z)
	local ahead = frame:Point(x, 0, z - 1) - start
	local best: number? = nil
	for _, rect in streetRects() do
		-- Walk out in 1-stud steps (houses are at most a few dozen studs from a street).
		for distance = 0, 60 do
			local point = start + ahead * distance
			if point.X >= rect.X0 and point.X <= rect.X1 and point.Z >= rect.Z0 and point.Z <= rect.Z1 then
				if best == nil or distance < best then
					best = distance
				end
				break
			end
		end
	end
	return best
end

-- Concrete front walk from the footprint's front edge to the street, plus a mailbox.
local function frontWalk(frame: Frame, x: number, depth: number)
	local front = -depth / 2
	local distance = distanceToStreet(frame, x, front)
	if distance == nil or distance < 1 then
		return
	end
	frame:Span("Walk", x - 1.4, x + 1.4, 0, 0.12, front - distance, front, MapPalette.Sidewalk)
	local postX = x + 3.2
	frame:Span(
		"MailboxPost",
		postX - 0.2,
		postX + 0.2,
		0,
		3.4,
		front - distance + 1.4,
		front - distance + 1.8,
		MapPalette.WoodDark
	)
	frame:Span(
		"Mailbox",
		postX - 0.5,
		postX + 0.5,
		3.4,
		4.2,
		front - distance + 0.6,
		front - distance + 2.4,
		MapPalette.SteelDark
	)
end

-- Typical two-bedroom house: porch, door, windows, chimney, gable roof.
-- Even variants turn the gable to face the street.
function Rural.House(model: Model, element: Element)
	local frame = frameFor(model, element)
	local variant = element.Variant or 1
	local siding = pick(MapPalette.HouseSidings, variant)
	local roof = pick(MapPalette.HouseRoofs, variant)
	local door = pick({ MapPalette.Door, MapPalette.DoorGreen, MapPalette.DoorRed }, variant)
	local halfW = frame.Width / 2 - 1
	local front = -frame.Depth / 2 + 4
	local back = frame.Depth / 2 - 1
	local wallTop = 9
	local ridge: "X" | "Z" = if variant % 2 == 0 then "Z" else "X"

	frame:Span("Foundation", -halfW, halfW, 0, 0.8, front, back, MapPalette.ConcreteDark)
	frame:Span("Walls", -halfW, halfW, 0.8, wallTop, front, back, siding)
	frame:GableRoof("", -halfW, halfW, front, back, wallTop, element.Height - wallTop - 0.8, ridge, siding, roof, 1)
	frame:Span("Chimney", halfW - 4, halfW - 2, 6, element.Height - 0.3, back - 5, back - 3, MapPalette.BrickRed)

	-- Porch across the middle of the front.
	local porchFront = -frame.Depth / 2 + 0.5
	frame:Span("Porch", -8, 8, 0, 0.9, porchFront, front, MapPalette.WoodGrey)
	frame:Span("PorchRoof", -8.5, 8.5, 7.6, 8.0, porchFront - 0.3, front, roof)
	for _, postX in { -7.6, 7.6 } do
		frame:Span("PorchPost", postX - 0.3, postX + 0.3, 0.9, 7.6, porchFront + 0.2, porchFront + 0.8, MapPalette.Trim)
	end

	frame:Panel("Door", "Front", front, -1.8, 1.8, 0.9, 7.2, 0.2, door)
	for _, side in { -1, 1 } do
		frame:Window(
			"Front",
			front,
			side * 7.5 - 1.8,
			side * 7.5 + 1.8,
			3.2,
			6.6,
			MapPalette.WindowDark,
			MapPalette.Trim
		)
	end
	local midZ = (front + back) / 2
	frame:Window("Left", -halfW, midZ - 1.8, midZ + 1.8, 3.2, 6.6, MapPalette.WindowDark, MapPalette.Trim)
	frame:Window("Right", halfW, midZ - 1.8, midZ + 1.8, 3.2, 6.6, MapPalette.WindowDark, MapPalette.Trim)
	frame:Window("Back", back, -2, 2, 3.4, 6.4, MapPalette.WindowDark, MapPalette.Trim)

	frontWalk(frame, 0, frame.Depth)
end

-- The partner's house: bigger two-storey with a front cross gable, a porch
-- across the whole front, a brick chimney and a garage at the back.
function Rural.CallowayHome(model: Model, element: Element)
	local frame = frameFor(model, element)
	local halfW = frame.Width / 2
	local depth = frame.Depth
	local front, back = -depth / 2 + 8, depth / 2 - 12
	local bodyHalf = halfW - 2
	local wallTop = 13
	local siding = CALLOWAY_SIDING
	local roof = MapPalette.RoofShingle

	frame:Span("Foundation", -bodyHalf, bodyHalf, 0, 1, front, back, MapPalette.ConcreteDark)
	frame:Span("Walls", -bodyHalf, bodyHalf, 1, wallTop, front, back, siding)
	frame:GableRoof(
		"Main",
		-bodyHalf,
		bodyHalf,
		front,
		back,
		wallTop,
		element.Height - wallTop - 0.8,
		"X",
		siding,
		roof,
		1
	)
	-- Front bay with its own gable crossing the main roof.
	frame:Span("Bay", -6, 6, 1, wallTop, front - 2, front, siding)
	frame:GableRoof("Bay", -6, 6, front - 2, (front + back) / 2, wallTop, 4.5, "Z", siding, roof, 0.6)
	frame:Span("Chimney", bodyHalf - 0.5, bodyHalf + 2, 0, element.Height, -3, 1, MapPalette.BrickRed)

	-- Porch across the whole front.
	local porchFront = -depth / 2 + 0.6
	frame:Span("Porch", -halfW + 0.5, halfW - 0.5, 0, 1.1, porchFront, front - 2, MapPalette.WoodGrey)
	frame:Span("PorchStep", -2.5, 2.5, 0, 0.55, -depth / 2, porchFront, MapPalette.WoodGrey)
	frame:Span("PorchRoof", -halfW + 0.2, halfW - 0.2, 8.4, 8.9, porchFront - 0.4, front - 2, roof)
	for _, postX in { -halfW + 1.2, -7, 7, halfW - 1.2 } do
		frame:Span(
			"PorchPost",
			postX - 0.35,
			postX + 0.35,
			1.1,
			8.4,
			porchFront + 0.2,
			porchFront + 0.9,
			MapPalette.Trim
		)
	end
	for _, run in { { -halfW + 1.2, -2.5 }, { 2.5, halfW - 1.2 } } do
		frame:Span("Railing", run[1], run[2], 3.6, 3.9, porchFront + 0.4, porchFront + 0.7, MapPalette.Trim)
	end

	local bayFront = front - 2
	frame:Panel("Door", "Front", bayFront, -2, 2, 1.1, 8, 0.2, MapPalette.DoorGreen)
	frame:Window("Front", bayFront, -1.5, 1.5, 14.2, 16.4, MapPalette.WindowDark, MapPalette.Trim)
	for _, side in { -1, 1 } do
		local x = side * 11
		frame:Window("Front", front, x - 2.5, x + 2.5, 3.2, 7.4, MapPalette.WindowDark, MapPalette.Trim)
		frame:Window("Front", front, x - 2, x + 2, 9.6, 12.2, MapPalette.WindowDark, MapPalette.Trim)
		frame:Window(
			"Front",
			bayFront,
			side * 3.6 - 0.9,
			side * 3.6 + 0.9,
			9.6,
			12.2,
			MapPalette.WindowDark,
			MapPalette.Trim
		)
	end
	for _, z in { front + 6, back - 6 } do
		frame:Window("Left", -bodyHalf, z - 2, z + 2, 3.2, 7.4, MapPalette.WindowDark, MapPalette.Trim)
		frame:Window("Right", bodyHalf, z - 2, z + 2, 9.6, 12.2, MapPalette.WindowDark, MapPalette.Trim)
	end

	-- Kitchen + garage wing behind, with a shed roof and the garage door on the side.
	frame:Span("Wing", -bodyHalf, 2, 0, 9, back, depth / 2 - 0.5, siding)
	frame:Wedge("WingRoof", -bodyHalf - 0.5, 2.5, 9, 11, back, depth / 2, "-Z", roof)
	frame:Panel("GarageDoor", "Left", -bodyHalf, back + 1.5, depth / 2 - 2, 0.2, 7.6, 0.2, MapPalette.Trim)

	frontWalk(frame, 0, depth)
	-- Driveway from the street along the garage side.
	local driveFront = -depth / 2
	local distance = distanceToStreet(frame, -bodyHalf - 4, driveFront) or 0
	frame:Span(
		"Driveway",
		-bodyHalf - 7.5,
		-bodyHalf - 0.5,
		0,
		0.12,
		driveFront - distance,
		back + 10,
		MapPalette.Sidewalk
	)
end

function Rural.Farmhouse(model: Model, element: Element)
	local frame = frameFor(model, element)
	local siding = MapPalette.ClapboardWhite
	local roof = MapPalette.RoofShingle
	local halfW = frame.Width / 2
	local x0, x1 = -halfW + 2, 6
	local front, back = -frame.Depth / 2 + 10, frame.Depth / 2 - 2
	local wallTop = 13

	frame:Span("Foundation", x0, x1, 0, 1, front, back, MapPalette.ConcreteDark)
	frame:Span("Walls", x0, x1, 1, wallTop, front, back, siding)
	frame:GableRoof("Main", x0, x1, front, back, wallTop, element.Height - wallTop - 0.8, "X", siding, roof, 1)
	frame:Span("Chimney", x0 + 4, x0 + 6.5, 8, element.Height - 0.2, back - 6, back - 3.5, MapPalette.BrickRed)

	-- Single-storey kitchen wing to the east.
	local wingFront, wingBack = front + 4, back - 4
	frame:Span("Wing", x1, halfW - 3, 0, 8.5, wingFront, wingBack, siding)
	frame:GableRoof("Wing", x1, halfW - 3, wingFront, wingBack, 8.5, 4.2, "Z", siding, roof, 0.8)

	-- Covered porch along the front of the main block.
	local porchFront = -frame.Depth / 2 + 1
	frame:Span("Porch", x0, x1, 0, 1.1, porchFront, front, MapPalette.WoodGrey)
	frame:Span("PorchRoof", x0 - 0.3, x1 + 0.3, 8.2, 8.6, porchFront - 0.5, front, MapPalette.RoofMetal)
	local doorX = (x0 + x1) / 2
	-- Posts at the corners and either side of the steps, never in front of the door.
	for _, postX in { x0 + 1, doorX - 4.5, doorX + 4.5, x1 - 1 } do
		frame:Span(
			"PorchPost",
			postX - 0.35,
			postX + 0.35,
			1.1,
			8.2,
			porchFront + 0.2,
			porchFront + 0.9,
			MapPalette.Trim
		)
	end

	frame:Panel("Door", "Front", front, doorX - 2, doorX + 2, 1.1, 8.4, 0.2, MapPalette.Door)
	for _, offset in { -9, 9 } do
		local x = doorX + offset
		frame:Window("Front", front, x - 2, x + 2, 3.4, 7.6, MapPalette.WindowDark, MapPalette.Trim)
		frame:Window("Front", front, x - 2, x + 2, 9.4, 12, MapPalette.WindowDark, MapPalette.Trim)
	end
	frame:Window("Front", front, doorX - 1.6, doorX + 1.6, 9.4, 12, MapPalette.WindowDark, MapPalette.Trim)
	frame:Window("Left", x0, -2, 2, 3.4, 7.6, MapPalette.WindowDark, MapPalette.Trim)
	frame:Window("Left", x0, -2, 2, 9.4, 12, MapPalette.WindowDark, MapPalette.Trim)
	frame:Window("Front", wingFront, x1 + 4, x1 + 8, 3.2, 6.6, MapPalette.WindowDark, MapPalette.Trim)
end

-- Red barn with a gambrel roof (gable ends north/south), big sliding doors,
-- hay loft door and a cupola.
function Rural.Barn(model: Model, element: Element)
	local frame = frameFor(model, element)
	local red = MapPalette.BarnRed
	local roof = MapPalette.BarnRoof
	local half = frame.Width / 2 - 2
	local front, back = -frame.Depth / 2 + 2.5, frame.Depth / 2 - 2.5
	local eave, knuckle, peak = 14, 21, element.Height - 1.6
	local knuckleX = half - 12

	frame:Span("Walls", -half, half, 0, eave, front, back, red)
	frame:Wedge("Gable", -half, -knuckleX, eave, knuckle, front, back, "+X", red)
	frame:Wedge("Gable", knuckleX, half, eave, knuckle, front, back, "-X", red)
	frame:Span("Gable", -knuckleX, knuckleX, eave, knuckle, front, back, red)
	frame:Wedge("Gable", -knuckleX, 0, knuckle, peak, front, back, "+X", red)
	frame:Wedge("Gable", 0, knuckleX, knuckle, peak, front, back, "-X", red)

	-- Roof skins; the lower ones run 1.6 studs past the eaves as an overhang.
	local lowerRun = half - knuckleX
	local lowerRise = knuckle - eave
	local lowerLength = math.sqrt(lowerRun * lowerRun + lowerRise * lowerRise)
	local overX = 1.6 * lowerRun / lowerLength
	local overY = 1.6 * lowerRise / lowerLength
	for _, side in { -1, 1 } do
		frame:Slope(
			"Roof",
			side * (half + overX),
			eave - overY,
			side * knuckleX,
			knuckle,
			front - 1,
			back + 1,
			0.6,
			roof
		)
		frame:Slope("Roof", side * knuckleX, knuckle, side * -0.3, peak + 0.03, front - 1, back + 1, 0.6, roof)
	end

	-- Cupola on the ridge.
	frame:Span("Cupola", -3, 3, peak - 1, peak + 1.2, -3, 3, MapPalette.Trim)
	frame:Span("CupolaRoof", -3.6, 3.6, peak + 1.2, element.Height, -3.6, 3.6, roof)

	-- Front: sliding doors with white X bracing, hay loft door and hoist beam.
	frame:Panel("DoorFrame", "Front", front, -9, 9, 0, 13, 0.15, MapPalette.Trim)
	for _, side in { -1, 1 } do
		local d0, d1 = side * 0.15, side * 8.4
		local lo, hi = math.min(d0, d1), math.max(d0, d1)
		frame:Panel("Door", "Front", front, lo, hi, 0, 12.4, 0.3, red)
		frame:Beam(
			"Brace",
			Vector3.new(lo + 0.6, 0.8, front - 0.35),
			Vector3.new(hi - 0.6, 11.6, front - 0.35),
			0.5,
			MapPalette.Trim
		)
		frame:Beam(
			"Brace",
			Vector3.new(lo + 0.6, 11.6, front - 0.35),
			Vector3.new(hi - 0.6, 0.8, front - 0.35),
			0.5,
			MapPalette.Trim
		)
	end
	frame:Panel("LoftDoor", "Front", front, -3.5, 3.5, eave + 1.5, eave + 6.5, 0.25, MapPalette.WoodDark)
	frame:Span("HoistBeam", -0.4, 0.4, peak - 3.6, peak - 2.8, front - 3, front + 0.5, MapPalette.WoodDark)
	frame:Panel("BackDoor", "Back", back, -5, 5, 0, 10, 0.25, MapPalette.WoodDark)

	for _, z in { front + 12, back - 12 } do
		frame:Window("Left", -half, z - 1.6, z + 1.6, 6, 9, MapPalette.WindowDark, MapPalette.Trim)
		frame:Window("Right", half, z - 1.6, z + 1.6, 6, 9, MapPalette.WindowDark, MapPalette.Trim)
	end
end

-- Galvanised grain silo with a domed cap, corrugation bands and a ladder.
-- The middle silo also gets a grain auger slanting down to the yard.
function Rural.Silo(model: Model, element: Element)
	local frame = Shapes.Frame(model, CFrame.new(element.X, 0, element.Z), 0, 0)
	local diameter = element.SizeX
	local radius = diameter / 2
	local dome = element.Height - radius
	frame:Cylinder("Pad", 0, 0, 0, 0.4, diameter + 3, MapPalette.Concrete)
	frame:Cylinder("Body", 0, 0, 0, dome, diameter, MapPalette.Galvanized)
	frame:Ball("Dome", 0, dome, 0, diameter, MapPalette.Galvanized)
	for _, y in { dome * 0.3, dome * 0.6, dome - 1 } do
		frame:Cylinder("Band", 0, 0, y - 0.3, y + 0.3, diameter + 0.4, MapPalette.SteelDark)
	end
	for _, x in { -0.8, 0.8 } do
		frame:Span("Ladder", x - 0.12, x + 0.12, 1, dome + 2, -radius - 0.6, -radius - 0.35, MapPalette.SteelDark)
	end
	if element.Name == "Silo B" then
		frame:Beam(
			"Auger",
			Vector3.new(0, 2.5, radius + 15),
			Vector3.new(0, dome + 4, radius - 1),
			1.4,
			MapPalette.Rust
		)
		frame:Span("Hopper", -1.6, 1.6, 0, 2.6, radius + 14, radius + 17.5, MapPalette.Rust)
	end
end

-- Water tower: tank on four braced legs with a stepped conical roof and the
-- town name painted on four sides; a climbable truss runs up one leg.
function Rural.WaterTower(model: Model, element: Element)
	local frame = Shapes.Frame(model, CFrame.new(element.X, 0, element.Z), 0, 0)
	local paint = MapPalette.Steel
	local legTop, tankBottom, tankTop = 46, 46, 62
	local leg = 11

	local corners = { { -leg, -leg }, { leg, -leg }, { leg, leg }, { -leg, leg } }
	for _, corner in corners do
		frame:Span(
			"Footing",
			corner[1] - 1.5,
			corner[1] + 1.5,
			0,
			1.5,
			corner[2] - 1.5,
			corner[2] + 1.5,
			MapPalette.Concrete
		)
		frame:Cylinder("Leg", corner[1], corner[2], 1.5, legTop, 1.6, paint)
	end
	for index, corner in corners do
		local nextCorner = corners[index % 4 + 1]
		local a = Vector3.new(corner[1], 0, corner[2])
		local b = Vector3.new(nextCorner[1], 0, nextCorner[2])
		frame:Beam("Ring", a + Vector3.new(0, 24, 0), b + Vector3.new(0, 24, 0), 0.6, paint)
		for _, band in { { 2, 24 }, { 24, legTop - 1 } } do
			frame:Beam(
				"Brace",
				a + Vector3.new(0, band[1], 0),
				b + Vector3.new(0, band[2], 0),
				0.35,
				MapPalette.SteelDark
			)
			frame:Beam(
				"Brace",
				a + Vector3.new(0, band[2], 0),
				b + Vector3.new(0, band[1], 0),
				0.35,
				MapPalette.SteelDark
			)
		end
	end
	frame:Cylinder("Riser", 0, 0, 0, tankBottom, 3, paint)
	frame:Cylinder("Balcony", 0, 0, tankBottom - 0.6, tankBottom, 33, MapPalette.SteelDark)
	frame:Cylinder("Handrail", 0, 0, tankBottom + 2.6, tankBottom + 2.9, 32.6, MapPalette.SteelDark)
	frame:Cylinder("Tank", 0, 0, tankBottom, tankTop, 30, paint)
	frame:Cylinder("Roof", 0, 0, tankTop, tankTop + 2.5, 26, paint)
	frame:Cylinder("Roof", 0, 0, tankTop + 2.5, tankTop + 4.8, 16, paint)
	frame:Cylinder("Roof", 0, 0, tankTop + 4.8, tankTop + 6.6, 7, paint)
	frame:Ball("Finial", 0, element.Height - 0.8, 0, 1.6, MapPalette.SteelDark)
	frame:Truss("Ladder", -leg - 2, -leg, 0, legTop, MapPalette.SteelDark)

	-- Painted name: invisible panels tangent to the tank carry the lettering.
	local town = string.upper(GameConfig.TownName)
	local label = { Color = MapPalette.SignText.WaterTower, Font = MapPalette.Fonts.Bold }
	for _, turn in { 0, 90, 180, 270 } do
		local side = frame:Child(0, 0, turn)
		side:Sign("Name", -7.5, 7.5, 50, 57.5, -15.3, 0.1, town, INVISIBLE, label)
	end
end

-- Farmyard dirt, the farmhouse drive and hay bales.
function Rural.BuildFarmyard(folder: Instance)
	local model = Props.Extra(folder, "Farmyard", "Farmstead")
	local frame = Shapes.Frame(model, CFrame.identity, 0, 0)
	local yard = MapLayout.Farmyard.Yard
	frame:Span("Yard", yard.X0, yard.X1, 0, 0.1, yard.Z0, yard.Z1, MapPalette.DirtRoad)
	local drive = MapLayout.Farmyard.Drive
	frame:Span("Drive", drive.X0, drive.X1, 0, 0.1, drive.Z0, drive.Z1, MapPalette.DirtRoad)
	for index, bale in MapLayout.Farmyard.HayBales do
		local axis: "X" | "Z" = if index % 2 == 0 then "X" else "Z"
		frame:Pipe("HayBale", bale[1], 2.1, bale[2], 4, 4, axis, MapPalette.Hay)
	end
end

-- Town trees, one "Trees" model per district folder.
function Rural.BuildTrees(folders: { [string]: Instance })
	local index = 0
	-- Walk districts in their fixed config order (not dictionary order) so every
	-- runtime numbers the trees, and so picks their greens, identically.
	for _, district in World.Districts do
		local districtId = district.Id
		local trees = MapLayout.Trees[districtId]
		local folder: Instance? = folders[districtId]
		if trees ~= nil and folder ~= nil then
			local model = Props.Extra(folder, "Trees", districtId)
			for _, tree in trees do
				index += 1
				Props.Tree(model, tree[1], tree[2], tree[3], index)
			end
		end
	end
end

return Rural
