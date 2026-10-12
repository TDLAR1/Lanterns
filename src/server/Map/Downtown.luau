--!strict
--[[
	Downtown: the solid shop buildings along Center Street (General Store,
	Hardware, Bar), the Motel, Post Office, Church and Gas Station, plus the
	churchyard. The Diner and Sheriff's Office have walk-in interiors and live
	in Interiors.luau.

	Downtown buildings stand back 3 studs inside their footprint so awnings and
	signs stay within it, over the 8-stud sidewalk.
]]

local MapLayout = require(script.Parent.MapLayout)
local MapPalette = require(script.Parent.MapPalette)
local Prng = require(script.Parent.Prng)
local Props = require(script.Parent.Props)
local Shapes = require(script.Parent.Shapes)

type Element = MapLayout.Element
type Frame = Shapes.Frame
type Style = Shapes.Style

type StorefrontLook = {
	Wall: Style,
	Trim: Style,
	Door: Style,
	Awning: Style?,
	Board: Style,
	Text: Color3,
	Font: Font,
	-- Two storeys get a row of upper windows; one storey gets a tall false front.
	Storeys: number,
	-- Bar style: small high windows and a glowing neon sign.
	Neon: boolean,
}

local LOOKS: { [string]: StorefrontLook } = {
	["General Store"] = {
		Wall = MapPalette.BrickTan,
		Trim = MapPalette.Trim,
		Door = MapPalette.DoorGreen,
		Awning = MapPalette.AwningGreen,
		Board = MapPalette.SignGreen,
		Text = MapPalette.SignText.Cream,
		Font = MapPalette.Fonts.Western,
		Storeys = 2,
		Neon = false,
	},
	Hardware = {
		Wall = MapPalette.BrickRed,
		Trim = MapPalette.ClapboardCream,
		Door = MapPalette.Door,
		Awning = MapPalette.AwningRed,
		Board = MapPalette.SignBoard,
		Text = MapPalette.SignText.Cream,
		Font = MapPalette.Fonts.Bold,
		Storeys = 1,
		Neon = false,
	},
	Bar = {
		Wall = MapPalette.BrickDark,
		Trim = MapPalette.TrimDark,
		Door = MapPalette.WoodDark,
		Awning = nil,
		Board = MapPalette.Black,
		Text = MapPalette.SignText.NeonRed,
		Font = MapPalette.Fonts.Bold,
		Storeys = 1,
		Neon = true,
	},
}

local INSET = 3
local SIDEWALK_TOP = 0.4

local Downtown = {}

local function frameFor(model: Model, element: Element): Frame
	return Shapes.FrameFor(model, element.X, element.Z, element.SizeX, element.SizeZ, element.Facing or "North")
end

-- Flat roof behind a 2-stud parapet with a trim cornice on the front.
local function flatRoof(
	frame: Frame,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	top: number,
	wall: Style,
	trim: Style
)
	local base = top - 2
	frame:Span("Parapet", x0, x1, base, top - 0.5, z0, z0 + 1, wall)
	frame:Span("Parapet", x0, x1, base, top - 0.5, z1 - 1, z1, wall)
	frame:Span("Parapet", x0, x0 + 1, base, top - 0.5, z0 + 1, z1 - 1, wall)
	frame:Span("Parapet", x1 - 1, x1, base, top - 0.5, z0 + 1, z1 - 1, wall)
	frame:Span("Cornice", x0 - 0.4, x1 + 0.4, top - 0.5, top, z0 - 0.5, z0 + 1.2, trim)
	-- Coping caps on the side and back parapets (the cornice caps the front).
	frame:Span("Coping", x0, x1, top - 0.5, top - 0.3, z1 - 1, z1, trim)
	frame:Span("Coping", x0, x0 + 1, top - 0.5, top - 0.3, z0 + 1.2, z1 - 1, trim)
	frame:Span("Coping", x1 - 1, x1, top - 0.5, top - 0.3, z0 + 1.2, z1 - 1, trim)
	frame:Span("Roof", x0 + 1, x1 - 1, base, base + 0.15, z0 + 1, z1 - 1, MapPalette.RoofTar)
end

-- Solid shop with storefront windows, door, awning, sign and flat roof.
function Downtown.Storefront(model: Model, element: Element)
	local frame = frameFor(model, element)
	local look = LOOKS[element.Name] or LOOKS["General Store"]
	local half = frame.Width / 2
	local front, back = -frame.Depth / 2 + INSET, frame.Depth / 2
	local height = element.Height

	frame:Span("Body", -half, half, 0, height - 2, front, back, look.Wall)
	flatRoof(frame, -half, half, front, back, height, look.Wall, look.Trim)
	frame:Span("RoofUnit", half - 14, half - 6, height - 2, height - 0.6, back - 12, back - 6, MapPalette.Galvanized)

	if look.Neon then
		-- Bar: small high windows either side of a recessed door, neon sign above.
		frame:Panel("Door", "Front", front, -2.5, 2.5, 0, 8, 0.2, look.Door)
		frame:Panel("DoorFrame", "Front", front, -3.2, 3.2, 0, 8.7, 0.1, look.Trim)
		for _, x in { -24, -15, 15, 24 } do
			frame:Window("Front", front, x - 2, x + 2, 4.5, 7.5, MapPalette.WindowDark, look.Trim)
		end
		frame:Sign(
			"Sign",
			-9,
			9,
			9.4,
			height - 2.6,
			front - 0.6,
			0.6,
			element.Sign or "",
			look.Board,
			{ Color = look.Text, Font = look.Font, Glow = true }
		)
		-- Neon tube outline around the board.
		local tube = MapPalette.NeonRed
		frame:Span("Neon", -9.3, 9.3, height - 2.6, height - 2.35, front - 0.75, front - 0.6, tube)
		frame:Span("Neon", -9.3, 9.3, 9.15, 9.4, front - 0.75, front - 0.6, tube)
		frame:Span("Neon", -9.3, -9.05, 9.4, height - 2.6, front - 0.75, front - 0.6, tube)
		frame:Span("Neon", 9.05, 9.3, 9.4, height - 2.6, front - 0.75, front - 0.6, tube)
	else
		-- Kickplate, two display windows, door with transom.
		frame:Panel("Kickplate", "Front", front, -half + 2, half - 2, 0, 1.6, 0.15, look.Trim)
		frame:Window("Front", front, -half + 4, -4.5, 1.6, 7.8, MapPalette.WindowDark, look.Trim)
		frame:Window("Front", front, 4.5, half - 4, 1.6, 7.8, MapPalette.WindowDark, look.Trim)
		frame:Panel("Door", "Front", front, -2.4, 2.4, 0, 7.8, 0.2, look.Door)
		frame:Window("Front", front, -2.4, 2.4, 8.2, 8.9, MapPalette.WindowDark, look.Trim)
		local awning = look.Awning
		if awning ~= nil then
			frame:SlopeZ("Awning", front, 9.6, front - INSET + 0.2, 8.2, -half + 2, half - 2, 0.25, awning)
		end
		local signTop = if look.Storeys >= 2 then 12 else height - 2.6
		frame:Sign(
			"Sign",
			-half + 6,
			half - 6,
			9.8,
			signTop,
			front - 0.5,
			0.5,
			element.Sign or "",
			look.Board,
			{ Color = look.Text, Font = look.Font }
		)
		if look.Storeys >= 2 then
			local count = 4
			local pitch = (frame.Width - 12) / count
			for index = 0, count - 1 do
				local x = -half + 6 + pitch * (index + 0.5)
				frame:Window("Front", front, x - 2.2, x + 2.2, 12.8, height - 3, MapPalette.WindowDark, look.Trim)
			end
		end
	end

	-- Side and back windows, back door.
	for _, z in { front + 10, back - 12 } do
		frame:Window("Left", -half, z - 2, z + 2, 4, 8, MapPalette.WindowDark, look.Trim)
		frame:Window("Right", half, z - 2, z + 2, 4, 8, MapPalette.WindowDark, look.Trim)
	end
	frame:Panel("BackDoor", "Back", back, half - 12, half - 8, 0, 7.5, 0.2, MapPalette.SteelDark)
end

-- L-shaped two-storey motel around a parking lot: rear wing, side wing with
-- the office at the street, upper walkways, pole sign at the corner.
function Downtown.Motel(model: Model, element: Element)
	local frame = frameFor(model, element)
	local half = frame.Width / 2
	local front, back = -frame.Depth / 2, frame.Depth / 2
	local wall = MapPalette.Stucco
	local trim = MapPalette.DinerTeal
	local roof = MapPalette.RoofGreen
	local top = element.Height - 1
	local level = 8.5
	local rearFront = back - 20
	local sideX = -half + 20
	local officeBack = front + 9

	-- Wings and office.
	frame:Span("RearWing", -half, half, 0, top, rearFront, back, wall)
	frame:Span("SideWing", -half, sideX, 0, top, officeBack, rearFront, wall)
	frame:Span("Office", -half, sideX, 0, 10, front, officeBack, wall)
	frame:Span("OfficeRoof", -half - 0.5, sideX + 0.5, 10, 10.8, front - 0.5, officeBack, roof)
	frame:Span("Roof", -half, half, top, element.Height, rearFront - 3, back, roof)
	frame:Span("Roof", -half, sideX + 3, top, element.Height, officeBack, rearFront - 3, roof)

	-- Upper walkways with railings, posts from the lot up to the roof.
	frame:Span("Walkway", sideX + 3, half, level - 0.5, level, rearFront - 3, rearFront, MapPalette.Concrete)
	frame:Span("Walkway", sideX, sideX + 3, level - 0.5, level, officeBack, rearFront, MapPalette.Concrete)
	-- The rear railing has a gap where the stairs arrive.
	local stairX0, stairX1 = half - 8, half - 5
	frame:Span("Railing", sideX + 3, stairX0 - 0.5, level + 3, level + 3.3, rearFront - 3, rearFront - 2.7, trim)
	frame:Span("Railing", stairX1 + 0.5, half, level + 3, level + 3.3, rearFront - 3, rearFront - 2.7, trim)
	frame:Span("Railing", sideX + 2.7, sideX + 3, level + 3, level + 3.3, officeBack, rearFront - 3, trim)
	-- Posts stand a little proud of the walkway and railing edges so no faces share a plane.
	for x = sideX + 3.5, half - 0.5, 10 do
		frame:Span("Post", x, x + 0.5, 0, top, rearFront - 3.25, rearFront - 2.65, trim)
	end
	for z = officeBack + 1, rearFront - 4, 10 do
		frame:Span("Post", sideX + 2.65, sideX + 3.25, 0, top, z, z + 0.5, trim)
	end
	frame:Wedge("Stairs", stairX0, stairX1, 0, level, rearFront - 20, rearFront - 3, "+Z", MapPalette.Concrete)

	-- Room doors and windows on both levels.
	local doorStyles = { MapPalette.DinerTeal, MapPalette.DoorRed }
	local index = 0
	for x = sideX + 6, half - 8, 12 do
		for _, base in { 0, level } do
			index += 1
			frame:Panel("Door", "Front", rearFront, x, x + 3, base + 0.2, base + 7, 0.2, doorStyles[index % 2 + 1])
			frame:Window(
				"Front",
				rearFront,
				x + 4.5,
				x + 8,
				base + 2.6,
				base + 6,
				MapPalette.WindowDark,
				MapPalette.Trim
			)
		end
	end
	for z = officeBack + 4, rearFront - 10, 12 do
		for _, base in { 0, level } do
			index += 1
			frame:Panel("Door", "Right", sideX, z, z + 3, base + 0.2, base + 7, 0.2, doorStyles[index % 2 + 1])
			frame:Window("Right", sideX, z + 4.5, z + 8, base + 2.6, base + 6, MapPalette.WindowDark, MapPalette.Trim)
		end
	end

	-- Office front.
	frame:Window("Front", front, -half + 3, -half + 11, 2, 7.5, MapPalette.WindowClear, MapPalette.Trim)
	frame:Panel("Door", "Front", front, -half + 13, -half + 16.5, 0, 7.5, 0.2, trim)
	frame:Sign(
		"OfficeSign",
		-half + 3,
		sideX - 2,
		8,
		9.8,
		front - 0.5,
		0.5,
		"OFFICE",
		MapPalette.SignCream,
		{ Color = MapPalette.SignText.Dark, Font = MapPalette.Fonts.Rounded }
	)

	-- Parking lot with stall lines in front of the rear wing.
	frame:Span("Lot", sideX, half, 0, 0.2, front, rearFront, MapPalette.Asphalt)
	for x = sideX + 2.5, half - 2, 10 do
		frame:Span("StallLine", x - 0.2, x + 0.2, 0.2, 0.25, rearFront - 14, rearFront - 4, MapPalette.LineWhite)
	end

	-- Pole sign at the street corner, readable along Center Street both ways.
	local pole = frame:Child(half - 5, front + 4, 90)
	pole:Cylinder("SignPole", 0, 0, 0, 16, 0.9, MapPalette.SteelDark)
	local text = element.Sign or "MOTEL"
	pole:Sign(
		"Sign",
		-5,
		5,
		11,
		element.Height - 0.2,
		-0.4,
		0.8,
		text,
		MapPalette.DinerTeal,
		{ Color = MapPalette.SignText.White, Font = MapPalette.Fonts.Rounded, Glow = true },
		text
	)
	pole:Sign(
		"Vacancy",
		-4,
		4,
		8.4,
		10.4,
		-0.3,
		0.6,
		"VACANCY",
		MapPalette.Black,
		{ Color = MapPalette.SignText.NeonRed, Font = MapPalette.Fonts.Bold, Glow = true },
		"VACANCY"
	)
end

-- Brick post office set back behind a plaza with a flagpole and a columned entrance.
function Downtown.PostOffice(model: Model, element: Element)
	local frame = frameFor(model, element)
	local half = frame.Width / 2
	local front, back = -frame.Depth / 2, frame.Depth / 2
	local bodyFront = front + 11
	local bodyHalf = half - 5
	local wall = MapPalette.BrickRed
	local trim = MapPalette.Trim

	frame:Span("Plaza", -half, half, 0, SIDEWALK_TOP, front, bodyFront, MapPalette.Sidewalk)
	frame:Span("Body", -bodyHalf, bodyHalf, 0, element.Height - 2, bodyFront, back - 2, wall)
	flatRoof(frame, -bodyHalf, bodyHalf, bodyFront, back - 2, element.Height, wall, trim)

	-- Portico: four columns, sign-carrying entablature and a pediment.
	local porticoFront = bodyFront - 4
	frame:Span("Steps", -9, 9, SIDEWALK_TOP, 0.9, porticoFront - 1, bodyFront, MapPalette.Concrete)
	for _, x in { -6.5, -2.2, 2.2, 6.5 } do
		frame:Cylinder("Column", x, porticoFront + 0.6, 0.9, 11, 1.6, trim)
	end
	frame:Sign(
		"Entablature",
		-8.5,
		8.5,
		11,
		13,
		porticoFront - 0.4,
		4.4,
		element.Sign or "POST OFFICE",
		trim,
		{ Color = MapPalette.SignText.Dark, Font = MapPalette.Fonts.Serif }
	)
	frame:Wedge("Pediment", -8.5, 0, 13, 15.6, porticoFront - 0.4, bodyFront, "+X", trim)
	frame:Wedge("Pediment", 0, 8.5, 13, 15.6, porticoFront - 0.4, bodyFront, "-X", trim)

	frame:Panel("Door", "Front", bodyFront, -2.6, 2.6, 0.9, 9, 0.2, MapPalette.WoodDark)
	for _, x in { -22, -12, 12, 22 } do
		frame:Window("Front", bodyFront, x - 2, x + 2, 2.4, 10.4, MapPalette.WindowDark, trim)
	end

	-- Flagpole with a simple striped flag.
	local poleX, poleZ = -half + 12, front + 5
	frame:Cylinder("Flagpole", poleX, poleZ, SIDEWALK_TOP, 26, 0.5, MapPalette.Steel)
	frame:Ball("Finial", poleX, 26.3, poleZ, 0.9, MapPalette.SignYellow)
	frame:Span("Flag", poleX + 0.3, poleX + 6.8, 21.6, 25.4, poleZ - 0.05, poleZ + 0.05, MapPalette.FlagRed)
	for _, y in { 22.7, 24.1 } do
		frame:Span(
			"FlagStripe",
			poleX + 0.32,
			poleX + 6.78,
			y,
			y + 0.55,
			poleZ - 0.08,
			poleZ + 0.08,
			MapPalette.FlagWhite
		)
	end
	frame:Span("FlagCanton", poleX + 0.35, poleX + 3.2, 23.4, 25.35, poleZ - 0.11, poleZ + 0.11, MapPalette.FlagBlue)
	frame:Span("MailDrop", 14, 16.4, SIDEWALK_TOP, 4.2, front + 3, front + 5, MapPalette.AwningBlue)
end

-- White clapboard church: nave with gable roof, front tower with an open
-- belfry and a tall spire (about 50 studs above the roof), stained-glass windows.
function Downtown.Church(model: Model, element: Element)
	local frame = frameFor(model, element)
	local white = MapPalette.ClapboardWhite
	local roof = MapPalette.RoofShingle
	local front, back = -frame.Depth / 2, frame.Depth / 2
	local naveHalf = 22
	local naveFront, naveBack = front + 13.5, back - 3.5
	local wallTop = 16
	local towerFront, towerBack = front + 1.5, front + 15.5
	local towerZ = (towerFront + towerBack) / 2
	local belfry, belfryTop, spireTop = 40, 48, element.Height + 48

	frame:Span("Foundation", -naveHalf, naveHalf, 0, 1.2, naveFront, naveBack, MapPalette.ConcreteDark)
	frame:Span("Nave", -naveHalf, naveHalf, 1.2, wallTop, naveFront, naveBack, white)
	frame:GableRoof(
		"Nave",
		-naveHalf,
		naveHalf,
		naveFront,
		naveBack,
		wallTop,
		element.Height - wallTop - 0.8,
		"Z",
		white,
		roof,
		1
	)

	frame:Span("Tower", -7, 7, 0, belfry, towerFront, towerBack, white)
	for _, cx in { -6, 6 } do
		for _, cz in { towerFront + 1, towerBack - 1 } do
			frame:Span("BelfryPost", cx - 1, cx + 1, belfry, belfryTop, cz - 1, cz + 1, white)
		end
	end
	frame:Ball(
		"Bell",
		0,
		belfry + 3.5,
		towerZ,
		3.4,
		{ Material = Enum.Material.Metal, Color = Color3.fromRGB(150, 116, 60) }
	)
	frame:Span("BelfryRoof", -7.5, 7.5, belfryTop, belfryTop + 1, towerFront - 0.5, towerBack + 0.5, white)
	-- Spire: octagonal tiers (a square plus the same square turned 45 degrees)
	-- shrinking to a point, so it tapers from every side.
	local spireBase = belfryTop + 1
	local tiers = 8
	local tierHeight = (spireTop - spireBase) / tiers
	for tier = 0, tiers - 1 do
		local width = 11 * (1 - tier / tiers) + 0.6
		local bottom = spireBase + tier * tierHeight
		local center = CFrame.new(0, bottom + tierHeight / 2, towerZ)
		Shapes.Part(model, "Spire", frame.Origin * center, Vector3.new(width, tierHeight, width), roof)
		-- The turned copy is a hair shorter so the two tops never share a plane.
		Shapes.Part(
			model,
			"Spire",
			frame.Origin * center * CFrame.new(0, -0.02, 0) * CFrame.Angles(0, math.rad(45), 0),
			Vector3.new(width, tierHeight - 0.04, width),
			roof
		)
	end
	frame:Span("Cross", -0.25, 0.25, spireTop - 0.5, spireTop + 4, towerZ - 0.25, towerZ + 0.25, MapPalette.SignYellow)
	frame:Span("Cross", -1.3, 1.3, spireTop + 2, spireTop + 2.5, towerZ - 0.2, towerZ + 0.2, MapPalette.SignYellow)

	-- Entrance and windows.
	frame:Span("Steps", -5, 5, 0, 0.6, front, towerFront, MapPalette.Concrete)
	frame:Span("Steps", -5, 5, 0.6, 1.2, front + 0.7, towerFront, MapPalette.Concrete)
	frame:Panel("Door", "Front", towerFront, -2.6, 2.6, 1.2, 10, 0.25, MapPalette.DoorRed)
	frame:Window("Front", towerFront, -2, 2, 18, 23, MapPalette.WindowDark, MapPalette.Trim)
	local amber: Style = { Material = Enum.Material.Glass, Color = Color3.fromRGB(196, 150, 70), Reflectance = 0.1 }
	local blue: Style = { Material = Enum.Material.Glass, Color = Color3.fromRGB(70, 96, 160), Reflectance = 0.1 }
	local windowIndex = 0
	for z = naveFront + 9, naveBack - 6, 12 do
		windowIndex += 1
		local glass = if windowIndex % 2 == 0 then amber else blue
		frame:Window("Left", -naveHalf, z - 1.6, z + 1.6, 4, 13, glass, MapPalette.Trim)
		frame:Window("Right", naveHalf, z - 1.6, z + 1.6, 4, 13, glass, MapPalette.Trim)
	end
end

-- Gas station facing Main St: forecourt, canopy over two pump islands, a small
-- market behind and a pole sign by the road.
function Downtown.GasStation(model: Model, element: Element)
	local frame = frameFor(model, element)
	local half = frame.Width / 2
	local front, back = -frame.Depth / 2, frame.Depth / 2
	local apron = MapLayout.Find("Main St").SizeX / 2
	local slab = 0.3

	frame:Span(
		"Forecourt",
		-half,
		half,
		0,
		slab,
		front,
		back,
		{ Material = Enum.Material.Concrete, Color = Color3.fromRGB(166, 162, 154), CastShadow = false }
	)
	-- Driveway aprons out to Main St (the footprint starts a few studs from the road).
	local toRoad = math.abs(element.X - element.SizeX / 2) - apron
	for _, run in { { -half + 3, -half + 15 }, { half - 15, half - 3 } } do
		frame:Span("Apron", run[1], run[2], 0, slab, front - toRoad, front, MapPalette.Sidewalk)
	end

	-- Canopy on four posts, red fascia carrying the GAS lettering.
	local c0, c1 = front + 4, front + 28
	local canopyHalf = 18
	local fascia = MapPalette.DinerRed
	frame:Span("Canopy", -canopyHalf, canopyHalf, element.Height - 1.2, element.Height - 0.1, c0, c1, MapPalette.Trim)
	frame:Sign(
		"Fascia",
		-canopyHalf - 0.2,
		canopyHalf + 0.2,
		element.Height - 1.6,
		element.Height,
		c0 - 0.2,
		0.25,
		element.Sign or "GAS",
		fascia,
		{ Color = MapPalette.SignText.White, Font = MapPalette.Fonts.Bold }
	)
	frame:Span(
		"Fascia",
		-canopyHalf - 0.2,
		canopyHalf + 0.2,
		element.Height - 1.6,
		element.Height,
		c1 - 0.05,
		c1 + 0.2,
		fascia
	)
	frame:Span(
		"Fascia",
		-canopyHalf - 0.2,
		-canopyHalf,
		element.Height - 1.6,
		element.Height,
		c0 + 0.05,
		c1 - 0.05,
		fascia
	)
	frame:Span(
		"Fascia",
		canopyHalf,
		canopyHalf + 0.2,
		element.Height - 1.6,
		element.Height,
		c0 + 0.05,
		c1 - 0.05,
		fascia
	)

	local pumpZ = (c0 + c1) / 2
	for _, x in { -8, 8 } do
		frame:Span("Island", x - 1.3, x + 1.3, slab, slab + 0.5, c0 + 4, c1 - 4, MapPalette.Concrete)
		frame:Span("Pump", x - 0.8, x + 0.8, slab + 0.5, slab + 5.3, pumpZ - 1.3, pumpZ + 1.3, MapPalette.SignWhite)
		frame:Span("PumpBand", x - 0.85, x + 0.85, slab + 4, slab + 4.8, pumpZ - 1.35, pumpZ + 1.35, fascia)
		for _, z in { c0 + 4.6, c1 - 4.6 } do
			frame:Cylinder("CanopyPost", x, z, slab + 0.5, element.Height - 1.2, 0.9, MapPalette.Steel)
		end
	end

	-- Market building at the back.
	local shopFront = back - 24
	frame:Span("Market", -20, 20, slab, 10, shopFront, back - 1, MapPalette.Stucco)
	frame:Span("MarketRoof", -20.5, 20.5, 10, 10.6, shopFront - 2, back - 0.5, MapPalette.RoofTar)
	frame:Window("Front", shopFront, -17, -3.5, 1.5, 7.5, MapPalette.WindowClear, MapPalette.Trim)
	frame:Window("Front", shopFront, 3.5, 17, 1.5, 7.5, MapPalette.WindowClear, MapPalette.Trim)
	frame:Panel("Door", "Front", shopFront, -2, 2, slab, 7.6, 0.2, MapPalette.SteelDark)
	frame:Sign(
		"MarketSign",
		-12,
		12,
		7.9,
		9.7,
		shopFront - 0.5,
		0.5,
		"MARKET",
		MapPalette.SignCream,
		{ Color = MapPalette.SignText.Red, Font = MapPalette.Fonts.Bold }
	)

	-- Pole sign by the road, readable along Main St in both directions.
	local pole = frame:Child(half - 3, front + 2, 90)
	pole:Cylinder("SignPole", 0, 0, 0, element.Height - 3.5, 0.7, MapPalette.SteelDark)
	pole:Sign(
		"Sign",
		-3,
		3,
		element.Height - 5,
		element.Height,
		-0.4,
		0.8,
		element.Sign or "GAS",
		fascia,
		{ Color = MapPalette.SignText.White, Font = MapPalette.Fonts.Bold },
		element.Sign or "GAS"
	)
end

-- Fenced churchyard south of the church, entered from the church path.
function Downtown.BuildChurchyard(folder: Instance)
	local settings = MapLayout.Churchyard
	local rect = settings.Rect
	local model = Props.Extra(folder, "Churchyard", "Downtown")
	local frame = Shapes.Frame(model, CFrame.identity, 0, 0)
	local prng = Prng.new(settings.Seed)
	local fence = MapPalette.WoodGrey
	local church = MapLayout.Find("Church")
	local churchBack = church.Z + church.SizeZ / 2
	local gateX = (settings.GateX0 + settings.GateX1) / 2

	frame:Span("Path", gateX - 2, gateX + 2, 0, 0.1, churchBack, rect.Z0, MapPalette.Gravel)
	frame:Span("Fence", rect.X0, settings.GateX0, 0, 3, rect.Z0, rect.Z0 + 0.4, fence)
	frame:Span("Fence", settings.GateX1, rect.X1, 0, 3, rect.Z0, rect.Z0 + 0.4, fence)
	frame:Span("Fence", rect.X0, rect.X1, 0, 3, rect.Z1 - 0.4, rect.Z1, fence)
	frame:Span("Fence", rect.X0, rect.X0 + 0.4, 0, 3, rect.Z0 + 0.4, rect.Z1 - 0.4, fence)
	frame:Span("Fence", rect.X1 - 0.4, rect.X1, 0, 3, rect.Z0 + 0.4, rect.Z1 - 0.4, fence)

	local width, depth = rect.X1 - rect.X0, rect.Z1 - rect.Z0
	for row = 1, settings.Rows do
		for column = 1, settings.Columns do
			local x = rect.X0 + width * (column - 0.5) / settings.Columns + prng:Range(-1.5, 1.5)
			local z = rect.Z0 + 8 + (depth - 12) * (row - 0.5) / settings.Rows
			-- Old stones lean a little; their feet are sunk so a lean never lifts them off the ground.
			local height = prng:Range(2.2, 3.4)
			frame:Turned(
				"Headstone",
				x,
				height / 2 - 0.3,
				z,
				2,
				height,
				0.6,
				prng:Range(-6, 6),
				prng:Range(-8, 8),
				0,
				MapPalette.Headstone
			)
		end
	end
end

-- Parked cars and the case-HQ patrol car.
function Downtown.BuildCars(folders: { [string]: Instance })
	for _, car in MapLayout.Cars do
		local folder: Instance? = folders[car.Folder]
		if folder ~= nil then
			Props.Car(
				folder,
				car.X,
				car.Z,
				car.Facing,
				MapPalette.CarPaints[(car.Paint - 1) % #MapPalette.CarPaints + 1],
				car.Pickup
			)
		end
	end
	local patrol = MapLayout.PatrolCar
	local folder: Instance? = folders[patrol.Folder]
	if folder ~= nil then
		Props.PatrolCar(folder, patrol.X, patrol.Z, patrol.Facing)
	end
end

return Downtown
