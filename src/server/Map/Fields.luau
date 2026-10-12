--!strict
--[[
	Fields: cornfields, wheat fields and the crime scene.

	Crops never collide (players and the camera pass through them) and stand on
	a soil slab whose top is 0.15. Corn grows in rows along the field's long
	axis, ~6 studs apart, as one tall stalk strip plus a tassel strip per row
	segment; paths are cut across the rows and some rows are left out as paths
	along them. Wheat is low strips separated by narrow tramlines.
]]

local MapLayout = require(script.Parent.MapLayout)
local MapPalette = require(script.Parent.MapPalette)
local Prng = require(script.Parent.Prng)
local Shapes = require(script.Parent.Shapes)

type Element = MapLayout.Element
type Frame = Shapes.Frame

local SOIL_TOP = 0.15
local ROW_PITCH = 6
local STALK_WIDTH = 1.6
local TASSEL_WIDTH = 0.9
local TASSEL_HEIGHT = 0.8
local CROSS_PATH_WIDTH = 8
local WHEAT_PITCH = 10.5
local WHEAT_WIDTH = 9

local Fields = {}

local function worldFrame(parent: Instance): Frame
	return Shapes.Frame(parent, CFrame.identity, 0, 0)
end

-- A generator seeded from the element's position, so each field varies differently but repeatably.
local function prngFor(element: Element): Prng.Prng
	return Prng.new(math.abs(element.X * 7919 + element.Z * 104729) + element.SizeX)
end

local function soil(frame: Frame, element: Element)
	frame:Span(
		"Soil",
		element.X - element.SizeX / 2,
		element.X + element.SizeX / 2,
		-0.05,
		SOIL_TOP,
		element.Z - element.SizeZ / 2,
		element.Z + element.SizeZ / 2,
		MapPalette.Soil
	)
end

-- Splits a0..a1 into the runs left after removing each cut (centre, width).
local function runsBetween(a0: number, a1: number, cuts: { number }, width: number): { { number } }
	local sorted = table.clone(cuts)
	table.sort(sorted)
	local runs = {}
	local cursor = a0
	for _, cut in sorted do
		local c0, c1 = cut - width / 2, cut + width / 2
		if c0 > cursor then
			table.insert(runs, { cursor, c0 })
		end
		cursor = math.max(cursor, c1)
	end
	if a1 > cursor then
		table.insert(runs, { cursor, a1 })
	end
	return runs
end

function Fields.Cornfield(model: Model, element: Element)
	local frame = worldFrame(model)
	local prng = prngFor(element)
	soil(frame, element)

	-- Rows run along the long axis; `along` is that axis, `across` the other one.
	local alongX = element.SizeX >= element.SizeZ
	local along0 = if alongX then element.X - element.SizeX / 2 else element.Z - element.SizeZ / 2
	local along1 = if alongX then element.X + element.SizeX / 2 else element.Z + element.SizeZ / 2
	local across0 = if alongX then element.Z - element.SizeZ / 2 else element.X - element.SizeX / 2
	local acrossSize = if alongX then element.SizeZ else element.SizeX

	local crossPaths: { number } = element.CrossPaths or {}
	local skipped: { number } = element.AlongPaths or {}
	local runs = runsBetween(along0 + 2, along1 - 2, crossPaths, CROSS_PATH_WIDTH)
	local tasselTop = element.Height
	local rowCount = math.floor((acrossSize - ROW_PITCH) / ROW_PITCH) + 1
	local margin = (acrossSize - (rowCount - 1) * ROW_PITCH) / 2

	for row = 0, rowCount - 1 do
		local across = across0 + margin + row * ROW_PITCH
		local isPath = false
		for _, pathAt in skipped do
			if math.abs(pathAt - across) < ROW_PITCH / 2 then
				isPath = true
			end
		end
		if not isPath then
			-- Rows vary a little in height so the field top is not perfectly flat.
			local stalkTop = tasselTop - TASSEL_HEIGHT - prng:Range(0, 0.6)
			for _, run in runs do
				local a0, a1 = run[1], run[2]
				if alongX then
					frame:Span(
						"Corn",
						a0,
						a1,
						SOIL_TOP,
						stalkTop,
						across - STALK_WIDTH / 2,
						across + STALK_WIDTH / 2,
						MapPalette.Corn
					)
					frame:Span(
						"Tassels",
						a0 + 0.5,
						a1 - 0.5,
						stalkTop,
						stalkTop + TASSEL_HEIGHT,
						across - TASSEL_WIDTH / 2,
						across + TASSEL_WIDTH / 2,
						MapPalette.CornTassel
					)
				else
					frame:Span(
						"Corn",
						across - STALK_WIDTH / 2,
						across + STALK_WIDTH / 2,
						SOIL_TOP,
						stalkTop,
						a0,
						a1,
						MapPalette.Corn
					)
					frame:Span(
						"Tassels",
						across - TASSEL_WIDTH / 2,
						across + TASSEL_WIDTH / 2,
						stalkTop,
						stalkTop + TASSEL_HEIGHT,
						a0 + 0.5,
						a1 - 0.5,
						MapPalette.CornTassel
					)
				end
			end
		end
	end
end

-- Wheat strips along X. A Clearing (another element's circle) is left open:
-- strips crossing it are split around the circle's chord.
function Fields.WheatField(model: Model, element: Element)
	local frame = worldFrame(model)
	soil(frame, element)

	local x0, x1 = element.X - element.SizeX / 2 + 1, element.X + element.SizeX / 2 - 1
	local z0 = element.Z - element.SizeZ / 2
	local stripCount = math.floor(element.SizeZ / WHEAT_PITCH)
	local margin = (element.SizeZ - stripCount * WHEAT_PITCH) / 2

	local clearingName = element.Clearing
	local clearing = if clearingName ~= nil then MapLayout.Find(clearingName) else nil

	for strip = 0, stripCount - 1 do
		local s0 = z0 + margin + strip * WHEAT_PITCH + (WHEAT_PITCH - WHEAT_WIDTH) / 2
		local s1 = s0 + WHEAT_WIDTH
		local style = if strip % 2 == 0 then MapPalette.Wheat else MapPalette.WheatPale
		local runs = { { x0, x1 } }
		if clearing ~= nil then
			local radius = clearing.SizeX / 2
			-- Distance from the circle's centre to the nearest edge of this strip.
			local dz = math.max(0, s0 - clearing.Z, clearing.Z - s1)
			if dz < radius then
				local halfChord = math.sqrt(radius * radius - dz * dz) + 1.5
				runs = runsBetween(x0, x1, { clearing.X }, halfChord * 2)
			end
		end
		for _, run in runs do
			frame:Span("Wheat", run[1], run[2], SOIL_TOP, element.Height, s0, s1, style)
		end
	end
end

-- Trampled circle in the wheat: flattened straw, numbered evidence markers and
-- crime-scene tape on posts (open on the east side, toward town).
function Fields.CrimeScene(model: Model, element: Element)
	local frame = Shapes.Frame(model, CFrame.new(element.X, 0, element.Z), 0, 0)
	local radius = element.SizeX / 2
	frame:Cylinder("Trampled", 0, 0, 0.1, 0.25, radius * 2, MapPalette.Trampled)
	-- Darker swirls of flattened stalks.
	frame:Turned("Flattened", -4, 0.27, 3, 22, 0.05, 2.5, 0, 35, 0, MapPalette.Stubble)
	frame:Turned("Flattened", 5, 0.27, -4, 18, 0.05, 2, 0, -50, 0, MapPalette.Stubble)

	local evidence = {
		{ -10, -4 },
		{ -6, 9 },
		{ 7, -10 },
		{ 11, 5 },
		{ -2, -13 },
	}
	local label = { Color = MapPalette.SignText.Dark, Font = MapPalette.Fonts.Highway }
	for index, spot in evidence do
		local marker = frame:Child(spot[1], spot[2], index * 50)
		local tent = marker:Span("Evidence", -0.5, 0.5, 0.25, 1.4, -0.35, 0.35, MapPalette.EvidenceYellow)
		Shapes.Label(tent, Enum.NormalId.Front, tostring(index), label)
		Shapes.Label(tent, Enum.NormalId.Back, tostring(index), label)
	end

	local postRadius = radius - 1.5
	local posts = {}
	for index = 0, 7 do
		local angle = math.rad(22.5 + index * 45)
		local px, pz = math.cos(angle) * postRadius, math.sin(angle) * postRadius
		frame:Cylinder("TapePost", px, pz, 0, 4, 0.35, MapPalette.WoodDark)
		table.insert(posts, Vector3.new(px, 3.4, pz))
	end
	for index = 1, #posts do
		local a, b = posts[index], posts[index % #posts + 1]
		-- Leave the span facing east (+X) open as the way in.
		if not (a.Z < 0 and b.Z > 0 and a.X > 0) then
			frame:Beam("Tape", a, b, 0.25, MapPalette.CrimeTape)
		end
	end
end

return Fields
