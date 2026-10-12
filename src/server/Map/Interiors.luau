--!strict
--[[
	Interiors: the buildings players can walk into in Milestone 0.

	  * Sheriff's Office - the duo's case HQ. Hollow 1-stud shell, door facing
	    Center Street, a front office with desks and the wall-mounted CaseBoard,
	    and a back room (behind a partition with a doorway) holding the
	    ring-battery spot and a holding cell.
	  * Diner - big front windows, counter with stools, booths, kitchen.
	  * Grain Elevator - derelict walk-in shell: broken opening on the north
	    side, three interior platforms with holes (ramps reach the first two;
	    the top one only through a hole in the roof), debris, and a broken
	    chain-link fence around it (a separate model).

	Interiors stay open at ground level (the map test needs most of each floor
	walkable), so furniture is kept low and sparse.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig = require(ReplicatedStorage.Shared.Config.Map)
local TagsModule = require(ReplicatedStorage.Shared.Util.Tags)

local MapLayout = require(script.Parent.MapLayout)
local MapPalette = require(script.Parent.MapPalette)
local Prng = require(script.Parent.Prng)
local Props = require(script.Parent.Props)
local Shapes = require(script.Parent.Shapes)

type Element = MapLayout.Element
type Frame = Shapes.Frame
type Style = Shapes.Style
type Column = Shapes.Column
type Rect = MapLayout.Rect

local Tags = TagsModule.Tags
local Attributes = TagsModule.Attributes

local FLOOR_TOP = 0.4

local LIMESTONE: Style = { Material = Enum.Material.Concrete, Color = Color3.fromRGB(196, 186, 160) }

local Interiors = {}

local function frameFor(model: Model, element: Element): Frame
	return Shapes.FrameFor(model, element.X, element.Z, element.SizeX, element.SizeZ, element.Facing or "North")
end

-- Window column helper: a strip a0..a1 with the given holes.
local function column(a0: number, a1: number, holes: { Shapes.Hole }): Column
	return { A0 = a0, A1 = a1, Holes = holes }
end

-- Floor slab over x0..x1 x z0..z1 with rectangular holes cut out. The area is
-- split into strips at every hole edge, so it needs only a handful of parts.
local function floorWithHoles(
	frame: Frame,
	name: string,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	y0: number,
	y1: number,
	holes: { Rect },
	style: Style
)
	local cuts = { x0, x1 }
	for _, hole in holes do
		table.insert(cuts, math.clamp(hole.X0, x0, x1))
		table.insert(cuts, math.clamp(hole.X1, x0, x1))
	end
	table.sort(cuts)
	for index = 1, #cuts - 1 do
		local a, b = cuts[index], cuts[index + 1]
		if b - a > 0.001 then
			local mid = (a + b) / 2
			local blocked = {}
			for _, hole in holes do
				if mid > hole.X0 and mid < hole.X1 then
					table.insert(blocked, hole)
				end
			end
			table.sort(blocked, function(p: Rect, q: Rect): boolean
				return p.Z0 < q.Z0
			end)
			local cursor = z0
			for _, hole in blocked do
				if hole.Z0 > cursor then
					frame:Span(name, a, b, y0, y1, cursor, hole.Z0, style)
				end
				cursor = math.max(cursor, hole.Z1)
			end
			if z1 > cursor then
				frame:Span(name, a, b, y0, y1, cursor, z1, style)
			end
		end
	end
end

-- Ceiling lamp panel with a soft light so interiors are not pitch dark.
local function ceilingLamp(frame: Frame, x: number, z: number, y: number, withLight: boolean)
	local lamp = frame:Span("CeilingLamp", x - 2, x + 2, y - 0.25, y, z - 1, z + 1, MapPalette.LampGlow)
	if withLight then
		local light = Instance.new("PointLight")
		light.Brightness = 0.8
		light.Range = 28
		light.Shadows = false
		light.Color = Color3.fromRGB(255, 236, 200)
		light.Parent = lamp
	end
end

-- Sheriff's Office --------------------------------------------------------------

-- Original-design ring-battery spot: a two-tier hexagonal plinth with a glowing
-- inlay, three slanted fins and a floating glowing core (the tagged part).
local function ringBattery(parent: Instance, frame: Frame, x: number, z: number, districtId: string)
	local model = Shapes.Group(parent, "RingBattery")
	local spot = frame:Into(model):Child(x, z, 0)
	local dark: Style = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(46, 50, 56) }
	local stone: Style = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(150, 152, 150) }
	local glow: Style = { Material = Enum.Material.Neon, Color = MapConfig.RingBattery.GlowColor, CastShadow = false }
	local base = FLOOR_TOP

	spot:Hexagon("FloorPlate", 0, 0, base - 0.05, base + 0.1, 5, dark)
	spot:Hexagon("Plinth", 0, 0, base + 0.1, base + 0.9, 3.2, dark)
	spot:Hexagon("Plinth", 0, 0, base + 0.9, base + 2.3, 2.4, stone)
	spot:Hexagon("Inlay", 0, 0, base + 2.3, base + 2.45, 1.6, glow)
	for index = 0, 2 do
		local fin = spot:Child(0, 0, index * 120)
		-- Leaning in toward the core.
		fin:Turned("Fin", 0, base + 3.6, -2.1, 0.3, 3.4, 1.1, 14, 0, 0, dark)
	end

	local core = spot:Ball("Core", 0, base + 4.4, 0, 1.6, {
		Material = Enum.Material.Neon,
		Color = MapConfig.RingBattery.GlowColor,
		CanCollide = false,
		CastShadow = false,
	})
	core:AddTag(Tags.RingBatterySpot)
	core:SetAttribute(Attributes.DistrictId, districtId)
	local light = Instance.new("PointLight")
	light.Color = MapConfig.RingBattery.GlowColor
	light.Brightness = MapConfig.RingBattery.LightBrightness
	light.Range = MapConfig.RingBattery.LightRange
	light.Shadows = false
	light.Parent = core
end

-- Cork case board with pinned papers, photos and red string.
local function caseBoard(frame: Frame, x0: number, x1: number, y0: number, y1: number, plane: number)
	frame:Span("CaseBoard", x0, x1, y0, y1, plane - 0.3, plane, MapPalette.Cork)
	local face = plane - 0.3
	local function pinned(name: string, cx: number, cy: number, w: number, h: number, style: Style): Part
		return frame:Span(name, cx - w / 2, cx + w / 2, cy - h / 2, cy + h / 2, face - 0.06, face, style)
	end
	local width, height = x1 - x0, y1 - y0
	-- Board-relative positions (0..1) of pinned photos and notes.
	local spots = {
		{ U = 0.12, V = 0.72, Photo = true },
		{ U = 0.3, V = 0.3, Photo = false },
		{ U = 0.5, V = 0.75, Photo = true },
		{ U = 0.68, V = 0.35, Photo = false },
		{ U = 0.86, V = 0.7, Photo = true },
		{ U = 0.88, V = 0.25, Photo = false },
		{ U = 0.12, V = 0.25, Photo = false },
	}
	local pins = {}
	for _, spot in spots do
		local cx, cy = x0 + width * spot.U, y0 + height * spot.V
		local isPhoto = spot.Photo
		pinned(
			if isPhoto then "Photo" else "Paper",
			cx,
			cy,
			if isPhoto then 1.6 else 1.4,
			if isPhoto then 1.3 else 1.8,
			if isPhoto then MapPalette.PhotoPaper else MapPalette.Paper
		)
		table.insert(pins, Vector3.new(cx, cy + 0.5, face - 0.1))
	end
	for _, link in { { 1, 3 }, { 3, 5 }, { 1, 2 }, { 2, 4 }, { 4, 5 }, { 4, 6 } } do
		frame:Beam("String", pins[link[1]], pins[link[2]], 0.08, MapPalette.RedString)
	end
	local title = pinned("Title", x0 + width * 0.5, y0 + height * 0.18, 4.2, 1.1, MapPalette.Paper)
	Shapes.Label(title, Enum.NormalId.Front, "OPEN CASE", {
		Color = MapPalette.SignText.Dark,
		Font = MapPalette.Fonts.Typewriter,
	})
end

local function desk(frame: Frame, x: number, z: number, width: number)
	frame:Span("Desk", x - width / 2, x + width / 2, FLOOR_TOP, 2.9, z - 1.3, z + 1.3, MapPalette.WoodDark)
	frame:Span("DeskTop", x - width / 2 - 0.2, x + width / 2 + 0.2, 2.9, 3.2, z - 1.5, z + 1.5, MapPalette.Wood)
	frame:Span("Chair", x - 1, x + 1, FLOOR_TOP, 2, z + 2.2, z + 4, MapPalette.Fabric)
	frame:Span("ChairBack", x - 1, x + 1, 2, 4.2, z + 3.7, z + 4, MapPalette.Fabric)
end

function Interiors.SheriffOffice(model: Model, element: Element)
	local frame = frameFor(model, element)
	local half = frame.Width / 2
	local front, back = -frame.Depth / 2, frame.Depth / 2
	local height = element.Height
	local wall = LIMESTONE
	local ceiling = 12
	local partition = 10
	local lowerWindow = { Y0 = 3.5, Y1 = 9.5, Glass = MapPalette.WindowClear }
	local upperWindow = { Y0 = 14.5, Y1 = 19.5, Glass = MapPalette.WindowDark }

	frame:Span("Floor", -half + 1, half - 1, 0, FLOOR_TOP, front + 1, back - 1, MapPalette.FloorTile)

	-- Front wall: centred doorway (8 x 10) and two rows of windows.
	local frontColumns = {}
	for _, x in { -48, -36, -24, -12 } do
		table.insert(frontColumns, column(x - 3, x + 3, { lowerWindow, upperWindow }))
	end
	table.insert(frontColumns, column(-4, 4, { { Y0 = FLOOR_TOP, Y1 = 10.4 }, upperWindow }))
	for _, x in { 12, 24, 36, 48 } do
		table.insert(frontColumns, column(x - 3, x + 3, { lowerWindow, upperWindow }))
	end
	frame:Wall("Wall", "X", front + 0.5, -half, half, 0, height, 1, frontColumns, wall)

	local backColumns = {
		column(-40, -34, { upperWindow }),
		column(-15, -9, { upperWindow }),
		column(9, 15, { { Y0 = 5, Y1 = 9, Glass = MapPalette.WindowClear }, upperWindow }),
		column(34, 40, { upperWindow }),
	}
	frame:Wall("Wall", "X", back - 0.5, -half, half, 0, height, 1, backColumns, wall)

	local sideColumns = {
		column(front + 7, front + 13, { lowerWindow, upperWindow }),
		column(front + 19, front + 25, { lowerWindow, upperWindow }),
		column(partition + 6, partition + 12, { { Y0 = 5, Y1 = 9, Glass = MapPalette.WindowClear }, upperWindow }),
	}
	frame:Wall("Wall", "Z", -half + 0.5, front + 1, back - 1, 0, height, 1, sideColumns, wall)
	frame:Wall("Wall", "Z", half - 0.5, front + 1, back - 1, 0, height, 1, sideColumns, wall)

	-- Ceiling (the upper storey is closed off), roof and front cornice.
	frame:Span("Ceiling", -half + 1, half - 1, ceiling, ceiling + 1, front + 1, back - 1, MapPalette.Concrete)
	frame:Span("Roof", -half + 1, half - 1, height - 1, height - 0.4, front + 1, back - 1, MapPalette.RoofTar)
	-- Cornices stop short of the wall's inner face and stand proud of its top,
	-- so none of their faces shares a plane with the wall.
	frame:Span("Cornice", -half - 0.4, half + 0.4, height - 1, height + 0.3, front - 0.5, front + 0.9, MapPalette.Trim)
	frame:Span(
		"Cornice",
		-half - 0.4,
		half + 0.4,
		ceiling + 0.6,
		ceiling + 1.2,
		front - 0.3,
		front + 0.9,
		MapPalette.Trim
	)

	-- Street front: sign, door frame and lamps.
	frame:Sign(
		"Sign",
		-12,
		12,
		10.9,
		ceiling + 0.4,
		front - 0.5,
		0.5,
		element.Sign or "SHERIFF",
		MapPalette.SignGreen,
		{ Color = MapPalette.SignText.Gold, Font = MapPalette.Fonts.Serif }
	)
	-- Jambs stand slightly into the opening (never flush with the wall's cut faces).
	frame:Span("DoorFrame", -4.4, -3.8, FLOOR_TOP, 10.6, front - 0.3, front + 0.9, MapPalette.Trim)
	frame:Span("DoorFrame", 3.8, 4.4, FLOOR_TOP, 10.6, front - 0.3, front + 0.9, MapPalette.Trim)
	for _, x in { -6, 6 } do
		frame:Span("WallLamp", x - 0.5, x + 0.5, 7.5, 8.7, front - 0.8, front, MapPalette.LampGlow)
	end

	-- Partition between the front office and the back room, with a doorway.
	frame:Wall(
		"Partition",
		"X",
		partition,
		-half + 1,
		half - 1,
		FLOOR_TOP,
		ceiling,
		1,
		{ column(28, 35, { { Y0 = FLOOR_TOP, Y1 = 9.5 } }) },
		wall
	)

	-- Front office.
	caseBoard(frame, -14, 2, 3.2, 10, partition - 0.5)
	desk(frame, -36, -14, 6)
	desk(frame, -20, -14, 6)
	desk(frame, -36, -2, 6)
	desk(frame, 20, -4, 9)
	frame:Span("Counter", 8, 22, FLOOR_TOP, 3.8, -22, -20.5, MapPalette.WoodDark)
	for index = 0, 2 do
		local z = index * 4
		frame:Span("FilingCabinet", -half + 1, -half + 2.8, FLOOR_TOP, 5.2, z - 1.4, z + 1.4, MapPalette.SteelDark)
	end
	frame:Span("Bench", -14, -8, FLOOR_TOP, 2.2, front + 1.4, front + 3, MapPalette.Wood)
	frame:Span("BenchBack", -14, -8, 2.2, 4.4, front + 1.1, front + 1.5, MapPalette.Wood)
	for _, spot in { { -30, -10 }, { 15, -10 } } do
		ceilingLamp(frame, spot[1], spot[2], ceiling, true)
	end

	-- Back room: holding cell (west) and the ring-battery spot (east).
	local cellX = -half + 24
	frame:Span("CellBench", -half + 1, -half + 3.5, FLOOR_TOP, 2, partition + 4, back - 2, MapPalette.SteelDark)
	for z = partition + 1.2, back - 1.5, 1.6 do
		frame:Cylinder("Bar", cellX, z, FLOOR_TOP, ceiling, 0.3, MapPalette.SteelDark)
	end
	frame:Span("CellRail", cellX - 0.25, cellX + 0.25, 8.5, 8.9, partition + 0.5, back - 1, MapPalette.SteelDark)
	frame:Span("EvidenceShelf", half - 2.5, half - 1, FLOOR_TOP, 7, partition + 2, back - 2, MapPalette.SteelDark)
	ceilingLamp(frame, -10, partition + 9, ceiling, false)
	ringBattery(model, frame, 16, partition + 10, element.Folder)
end

-- Diner ---------------------------------------------------------------------------

function Interiors.Diner(model: Model, element: Element)
	local frame = frameFor(model, element)
	local half = frame.Width / 2 - 0.5
	local front, back = -frame.Depth / 2 + 0.5, frame.Depth / 2 - 0.5
	local wallTop = element.Height - 2
	local steel = MapPalette.Steel
	local red = MapPalette.DinerRed
	local bigWindow = { Y0 = 2.6, Y1 = 10, Glass = MapPalette.WindowClear }

	frame:Span("Floor", -half + 1, half - 1, 0, FLOOR_TOP, front + 1, back - 1, MapPalette.Checker)
	frame:Span("FloorBand", -half + 1.5, half - 1.5, 0.3, FLOOR_TOP + 0.02, 7.5, 10.5, MapPalette.Black)

	frame:Wall("Wall", "X", front + 0.5, -half, half, 0, wallTop, 1, {
		column(-half + 3, -6, { bigWindow }),
		column(-4, 4, { { Y0 = FLOOR_TOP, Y1 = 10.4 } }),
		column(6, half - 3, { bigWindow }),
	}, steel)
	frame:Wall("Wall", "X", back - 0.5, -half, half, 0, wallTop, 1, {}, steel)
	local sideColumns = { column(front + 6, front + 18, { { Y0 = 3, Y1 = 9.5, Glass = MapPalette.WindowClear } }) }
	frame:Wall("Wall", "Z", -half + 0.5, front + 1, back - 1, 0, wallTop, 1, sideColumns, steel)
	frame:Wall("Wall", "Z", half - 0.5, front + 1, back - 1, 0, wallTop, 1, sideColumns, steel)

	frame:Span("Roof", -half - 0.5, half + 0.5, wallTop, wallTop + 0.6, front - 0.5, back + 0.5, MapPalette.RoofMetal)
	-- Retro trim: red band above the windows and around the sides, steel kickplate.
	frame:Panel("Stripe", "Front", front, -half - 0.1, half + 0.1, 10.5, 11.4, 0.15, red)
	-- Side stripes wrap 0.1 round the corners (short of the front stripe's face).
	frame:Panel("Stripe", "Left", -half, front - 0.1, back + 0.1, 10.5, 11.4, 0.15, red)
	frame:Panel("Stripe", "Right", half, front - 0.1, back + 0.1, 10.5, 11.4, 0.15, red)
	frame:Sign(
		"Sign",
		-13,
		13,
		wallTop + 0.6,
		element.Height,
		front - 0.6,
		0.6,
		element.Sign or "DINER",
		red,
		{ Color = MapPalette.SignText.White, Font = MapPalette.Fonts.Rounded, Glow = true }
	)
	frame:Panel("BackDoor", "Back", back, 20, 24, 0, 7.6, 0.2, MapPalette.SteelDark)

	-- Counter with stools; kitchen line behind it.
	local counterFront, counterBack = 12, 15
	frame:Span("Counter", -30, 18, FLOOR_TOP, 3.4, counterFront, counterBack, MapPalette.DinerTeal)
	frame:Span("CounterTop", -30.3, 18.3, 3.4, 3.7, counterFront - 0.3, counterBack, MapPalette.SignWhite)
	frame:Span("PieCase", 0, 4, 3.7, 5.2, counterFront + 0.4, counterBack - 0.4, MapPalette.WindowClear)
	for x = -27, 15, 6 do
		frame:Cylinder("StoolPost", x, counterFront - 1.8, FLOOR_TOP, 2.2, 0.5, steel)
		frame:Cylinder("Stool", x, counterFront - 1.8, 2.2, 2.6, 1.8, MapPalette.Leather)
	end
	frame:Span("Grill", -30, 10, FLOOR_TOP, 3.6, back - 3.5, back - 1, steel)
	frame:Span("Hood", -30, 10, 8, 9.6, back - 4, back - 1, MapPalette.SteelDark)

	-- Booths along the front windows.
	for _, bx in { -34, -23, -12, 12, 23, 34 } do
		local z0, z1 = front + 1.2, front + 6.6
		frame:Span("Table", bx - 1.5, bx + 1.5, 2.8, 3.1, z0, z1 - 0.6, MapPalette.SignWhite)
		frame:Cylinder("TableLeg", bx, (z0 + z1) / 2, FLOOR_TOP, 2.8, 0.5, steel)
		for _, side in { -1, 1 } do
			local inner, outer = bx + side * 2.2, bx + side * 4.6
			local backInner = bx + side * 3.9
			frame:Span("BoothSeat", inner, outer, FLOOR_TOP, 1.9, z0, z1, MapPalette.Leather)
			frame:Span("BoothBack", backInner, outer, 1.9, 4.6, z0, z1, MapPalette.Leather)
		end
	end
	frame:Span("Jukebox", half - 4.5, half - 1.5, FLOOR_TOP, 5, 18, 20.5, red)
	frame:Span("JukeboxGlow", half - 4.3, half - 1.7, 3, 4.6, 17.9, 18.05, MapPalette.LampGlow)
	for _, x in { -24, 0, 24 } do
		ceilingLamp(frame, x, 0, wallTop, x ~= 0)
	end
end

-- Grain Elevator --------------------------------------------------------------------

function Interiors.GrainElevator(model: Model, element: Element)
	local frame = frameFor(model, element)
	local half = frame.Width / 2
	local front, back = -frame.Depth / 2, frame.Depth / 2
	local concrete = MapPalette.ConcreteStained
	local rust = MapPalette.Rust
	local band = 8
	local roofBase = 47
	local inner = { X0 = -half + 1, X1 = half - 1, Z0 = front + 1, Z1 = back - 1 }
	local broken = { Y0 = 30, Y1 = 34 }

	-- North face: jagged broken opening through both bands, broken high windows.
	frame:Wall("Base", "X", front + 0.5, -half, half, 0, band, 1, {
		column(-9, -6, { { Y0 = 3.5, Y1 = band } }),
		column(-6, 5, { { Y0 = 0, Y1 = band } }),
		column(5, 8, { { Y0 = 0, Y1 = 5.5 } }),
	}, concrete)
	frame:Wall("Siding", "X", front + 0.5, -half, half, band, roofBase, 1, {
		column(-18, -14, { broken }),
		column(-9, -6, { { Y0 = band, Y1 = 10.5 } }),
		column(-6, -2, { { Y0 = band, Y1 = 15 } }),
		column(-2, 5, { { Y0 = band, Y1 = 13 } }),
		column(5, 8, { { Y0 = band, Y1 = 11.5 } }),
		column(14, 18, { broken }),
	}, rust)
	-- Torn sheets hanging off the edges of the hole.
	frame:Turned("TornSheet", -7.2, 12, front - 0.4, 2.6, 5, 0.15, 0, 0, 18, MapPalette.RustDark)
	frame:Turned("TornSheet", 6.4, 13.4, front - 0.3, 2.2, 3.6, 0.15, 12, 0, -24, MapPalette.RustDark)

	-- South face (rail side): boarded loading door, grain spout over the tracks.
	frame:Wall("Base", "X", back - 0.5, -half, half, 0, band, 1, { column(-6, 6, { { Y0 = 0, Y1 = band } }) }, concrete)
	frame:Wall("Siding", "X", back - 0.5, -half, half, band, roofBase, 1, {
		column(-6, 6, { { Y0 = band, Y1 = 12 } }),
		column(10, 14, { broken }),
	}, rust)
	for _, plank in { { 2.5, 6 }, { 6.5, -8 }, { 10.2, 4 } } do
		frame:Turned("Board", 0, plank[1], back + 0.3, 13.5, 1.4, 0.4, 0, 0, plank[2], MapPalette.WoodGrey)
	end
	frame:Beam("Spout", Vector3.new(0, 34, back), Vector3.new(0, 15, back + 8), 1.6, MapPalette.RustDark)

	-- Sides, a climbable truss up the east wall to the roof.
	for _, x in { -half + 0.5, half - 0.5 } do
		frame:Wall("Base", "Z", x, front + 1, back - 1, 0, band, 1, {}, concrete)
		frame:Wall("Siding", "Z", x, front + 1, back - 1, band, roofBase, 1, {
			column(-8, -4, { broken }),
			column(6, 10, { { Y0 = 18, Y1 = 21 } }),
		}, rust)
	end
	frame:Truss("Ladder", half + 1, 2, 0, roofBase + 1, MapPalette.RustDark)

	-- Roof with a hole, and the head house (cupola) on top.
	floorWithHoles(frame, "Roof", -half, half, front, back, roofBase, roofBase + 1, {
		{ X0 = 4, X1 = 14, Z0 = -14, Z1 = -6 },
	}, MapPalette.RustGrey)
	frame:Span("HeadHouse", -10, 10, roofBase + 1, element.Height - 2, -8, 8, rust)
	frame:Span("HeadHouseRoof", -11, 11, element.Height - 2, element.Height, -9, 9, MapPalette.RustGrey)
	frame:Window("Front", -8, -3, 3, 51, 55, MapPalette.WindowGrimy)

	-- Interior: dirt floor, platforms with holes, ramps, columns.
	frame:Span("Floor", inner.X0, inner.X1, 0, 0.2, inner.Z0, inner.Z1, MapPalette.DirtRoad)
	local wood = MapPalette.WoodGrey
	local stair1 = { X0 = inner.X0, X1 = inner.X0 + 6, Z0 = -14, Z1 = 12 }
	local stair2 = { X0 = inner.X1 - 6, X1 = inner.X1, Z0 = -12, Z1 = 14 }
	floorWithHoles(frame, "Platform", inner.X0, inner.X1, inner.Z0, inner.Z1, 14, 15, {
		stair1,
		{ X0 = 4, X1 = 14, Z0 = -6, Z1 = 6 },
	}, wood)
	floorWithHoles(frame, "Platform", inner.X0, inner.X1, inner.Z0, inner.Z1, 28, 29, {
		stair2,
		{ X0 = -16, X1 = -4, Z0 = -2, Z1 = 8 },
	}, wood)
	floorWithHoles(frame, "Platform", inner.X0, inner.X1, inner.Z0, 2, 41, 42, {
		{ X0 = -6, X1 = 2, Z0 = -14, Z1 = -8 },
	}, wood)
	frame:Wedge("Ramp", stair1.X0, stair1.X1, 0.2, 15, stair1.Z0, stair1.Z1, "+Z", wood)
	frame:Wedge("Ramp", stair2.X0, stair2.X1, 15, 29, stair2.Z0, stair2.Z1, "-Z", wood)
	for _, corner in { { -10, -10 }, { 10, -10 }, { -10, 10 }, { 10, 10 } } do
		frame:Span(
			"Column",
			corner[1] - 0.5,
			corner[1] + 0.5,
			0.2,
			roofBase,
			corner[2] - 0.5,
			corner[2] + 0.5,
			MapPalette.SteelDark
		)
	end
	-- Sagging planks at a hole edge and chains hanging in the dark.
	frame:Turned("Plank", 9, 13.2, 6.8, 9, 0.4, 1.2, 0, 0, -14, wood)
	frame:Turned("Plank", -10, 27.4, -2.8, 1.2, 0.4, 8, 18, 0, 0, wood)
	-- Chains hang from the roof where no platform is below them.
	for _, chain in { { -12, 4, 14 }, { 9, 5, 12 }, { 2, 14, 10 } } do
		frame:Span(
			"Chain",
			chain[1] - 0.1,
			chain[1] + 0.1,
			roofBase - chain[3],
			roofBase,
			chain[2] - 0.1,
			chain[2] + 0.1,
			MapPalette.SteelDark
		)
	end

	-- Debris inside, scattered with a fixed seed.
	local prng = Prng.new(MapLayout.ElevatorFence.DebrisSeed)
	for _, spot in { { 8, 15 }, { 15, 17 }, { -8, 16 }, { 14, -15 }, { -2, 4 }, { -14, -16 } } do
		local x = spot[1] + prng:Range(-1.5, 1.5)
		local z = spot[2] + prng:Range(-1.5, 1.5)
		local kind = prng:Int(1, 3)
		if kind == 1 then
			local size = prng:Range(2, 3.2)
			frame:Turned("Crate", x, 0.2 + size / 2, z, size, size, size, 0, prng:Range(0, 90), 0, MapPalette.WoodGrey)
		elseif kind == 2 then
			frame:Cylinder("Barrel", x, z, 0.2, 3.8, 2.4, MapPalette.RustDark)
		else
			frame:Turned("Sheet", x, 0.5, z, 5, 0.15, 3, prng:Range(-8, 8), prng:Range(0, 180), 6, MapPalette.Rust)
		end
	end
end

-- Broken chain-link fence around the elevator (posts, mesh panels, top rail),
-- with one panel missing, one leaning, one lying in the weeds, and warning signs.
function Interiors.BuildElevatorFence(folder: Instance)
	local settings = MapLayout.ElevatorFence
	local rect = settings.Rect
	local model = Props.Extra(folder, "Elevator Fence", "RailYard")
	local frame = Shapes.Frame(model, CFrame.identity, 0, 0)
	local height = settings.Height
	local post = MapPalette.Galvanized

	-- Each side as a list of corner-to-corner points; "West" holds the gap.
	local sides = {
		{ Name = "North", A = Vector3.new(rect.X0, 0, rect.Z0), B = Vector3.new(rect.X1, 0, rect.Z0) },
		{ Name = "East", A = Vector3.new(rect.X1, 0, rect.Z0), B = Vector3.new(rect.X1, 0, rect.Z1) },
		{ Name = "South", A = Vector3.new(rect.X1, 0, rect.Z1), B = Vector3.new(rect.X0, 0, rect.Z1) },
		{ Name = "West", A = Vector3.new(rect.X0, 0, rect.Z0), B = Vector3.new(rect.X0, 0, rect.Z1) },
	}
	local placedPosts: { [string]: boolean } = {}
	for _, side in sides do
		local length = (side.B - side.A).Magnitude
		local count = math.max(1, math.floor(length / settings.PostSpacing + 0.5))
		local step = (side.B - side.A) / count
		for index = 0, count do
			local p = side.A + step * index
			-- Corners are shared by two sides; place each post once.
			local key = `{math.floor(p.X * 10 + 0.5)},{math.floor(p.Z * 10 + 0.5)}`
			if not placedPosts[key] then
				placedPosts[key] = true
				frame:Cylinder("Post", p.X, p.Z, 0, height + 0.4, 0.4, post)
			end
		end
		for index = 1, count do
			local a = side.A + step * (index - 1)
			local b = side.A + step * index
			local mid = (a + b) / 2
			local along = (b - a).Unit
			local isGap = side.Name == "West" and index == settings.GapSegment
			local isLeaning = side.Name == "West" and index == settings.GapSegment + 1
			if not isGap then
				-- Panels are built in a small frame running along the segment.
				local turn = if math.abs(along.X) > 0.5 then 0 else 90
				local segment = Shapes.Frame(model, CFrame.new(mid.X, 0, mid.Z) * Shapes.Turn(turn), 0, 0)
				local span = (b - a).Magnitude / 2 - 0.2
				if isLeaning then
					-- Hinged at its foot, tipped outward (west) by 25 degrees.
					local tilt = CFrame.new(0, 0.3, 0) * CFrame.Angles(math.rad(-25), 0, 0)
					local leaning = Shapes.Frame(model, segment.Origin * tilt, 0, 0)
					leaning:Span("Mesh", -span, span, 0, height - 0.6, -0.08, 0.08, MapPalette.FenceMesh)
				else
					segment:Span("Mesh", -span, span, 0.3, height - 0.3, -0.08, 0.08, MapPalette.FenceMesh)
					segment:Span("TopRail", -span, span, height - 0.3, height, -0.12, 0.12, post)
				end
			end
		end
	end

	-- The missing panel lies flat in the weeds inside the fence, along the north side.
	local westSegments = math.max(1, math.floor((rect.Z1 - rect.Z0) / settings.PostSpacing + 0.5))
	local gapZ = rect.Z0 + (rect.Z1 - rect.Z0) / westSegments * (settings.GapSegment - 0.5)
	frame:Turned("FallenMesh", rect.X0 + 14, 0.15, rect.Z0 + 4, 10, 0.15, height - 0.6, 0, 3, 0, MapPalette.FenceMesh)

	local warning = { Color = MapPalette.SignText.Red, Font = MapPalette.Fonts.Bold }
	local north = Shapes.FrameFor(model, (rect.X0 + rect.X1) / 2 - 12, rect.Z0, 1, 1, "North")
	north:Sign("Warning", -3, 3, 3, 6, -0.35, 0.2, "NO TRESPASSING", MapPalette.SignWhite, warning)
	local west = Shapes.FrameFor(model, rect.X0, gapZ + 26, 1, 1, "West")
	west:Sign("Warning", -3, 3, 3, 6, -0.35, 0.2, "DANGER - KEEP OUT", MapPalette.SignWhite, warning)
	local east = Shapes.FrameFor(model, rect.X1, (rect.Z0 + rect.Z1) / 2, 1, 1, "East")
	east:Sign("Warning", -3, 3, 3, 6, -0.35, 0.2, "NO TRESPASSING", MapPalette.SignWhite, warning)
end

return Interiors
