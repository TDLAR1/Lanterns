--!strict
--[[
	Props: small repeated objects used across the map (trees, street lamps,
	utility poles, parked cars, roadside signs, the rail siding).

	Each function builds into the given parent at a world position. Extras
	that are not in the PDF build table are grouped into Models tagged
	Blockout (no Footprint: they are not spec elements).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.Game)
local TagsModule = require(ReplicatedStorage.Shared.Util.Tags)

local MapPalette = require(script.Parent.MapPalette)
local Shapes = require(script.Parent.Shapes)

type Style = Shapes.Style
type Facing = Shapes.Facing

local Tags = TagsModule.Tags
local Attributes = TagsModule.Attributes

local Props = {}

-- A Model for blockout extras that are not spec elements (tagged so tools still list them as blockout).
function Props.Extra(parent: Instance, name: string, districtId: string?): Model
	local model = Shapes.Group(parent, name)
	model:AddTag(Tags.Blockout)
	model:SetAttribute(Attributes.BlockoutOf, name)
	if districtId ~= nil then
		model:SetAttribute(Attributes.DistrictId, districtId)
	end
	return model
end

local LEAF_STYLES = { MapPalette.Leaves, MapPalette.LeavesDark, MapPalette.LeavesLight }

-- Deciduous tree: trunk plus two overlapping canopy balls. `index` varies the green.
function Props.Tree(parent: Instance, x: number, z: number, diameter: number, index: number)
	local frame = Shapes.Frame(parent, CFrame.new(x, 0, z), 0, 0)
	local trunkHeight = diameter * 0.45 + 2
	frame:Cylinder("Trunk", 0, 0, 0, trunkHeight + 2, math.max(1.2, diameter * 0.1), MapPalette.TreeTrunk)
	local leaves = LEAF_STYLES[(index - 1) % #LEAF_STYLES + 1]
	frame:Ball("Canopy", 0, trunkHeight + diameter * 0.45, 0, diameter, leaves)
	-- Second, smaller ball off to one side breaks up the perfect sphere silhouette.
	local side = if index % 2 == 0 then 1 else -1
	frame:Ball("Canopy", side * diameter * 0.25, trunkHeight + diameter * 0.3, diameter * 0.2, diameter * 0.7, leaves)
end

-- Dense shelterbelt cedar: one ball resting on the ground (cheap, reads as a tree line from afar).
function Props.Cedar(parent: Instance, x: number, z: number, diameter: number, style: Style)
	Shapes.Ball(parent, "Cedar", CFrame.new(x, diameter * 0.46, z), diameter, style)
end

-- Street lamp on a sidewalk (top 0.4); the arm reaches toward `facing`.
function Props.StreetLamp(parent: Instance, x: number, z: number, facing: Facing)
	local frame = Shapes.FrameFor(parent, x, z, 1, 1, facing)
	frame:Cylinder("Pole", 0, 0, 0.4, 15, 0.6, MapPalette.TrimDark)
	frame:Span("Arm", -0.25, 0.25, 14.4, 14.9, 0.3, -3.6, MapPalette.TrimDark)
	frame:Span("Lamp", -0.6, 0.6, 13.9, 14.4, -2.4, -3.8, MapPalette.LampGlow)
end

-- Row of wooden utility poles along a line of constant X, with two wires per span.
function Props.PoleLine(parent: Instance, x: number, z0: number, z1: number, spacing: number)
	local frame = Shapes.Frame(parent, CFrame.identity, 0, 0)
	local count = math.floor(math.abs(z1 - z0) / spacing + 0.5)
	local step = if z1 >= z0 then spacing else -spacing
	local wire = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(34, 34, 36), CanCollide = false }
	for index = 0, count do
		local z = z0 + step * index
		frame:Cylinder("Pole", x, z, 0, 24, 1.2, MapPalette.WoodDark)
		frame:Span("Crossarm", x - 4, x + 4, 21.6, 22.3, z - 0.35, z + 0.35, MapPalette.WoodDark)
		if index > 0 then
			for _, offset in { -3.4, 3.4 } do
				frame:Beam(
					"Wire",
					Vector3.new(x + offset, 22.5, z - step),
					Vector3.new(x + offset, 22.5, z),
					0.15,
					wire
				)
			end
		end
	end
end

-- Parked car (or pickup) pointing toward `facing`.
function Props.Car(parent: Instance, x: number, z: number, facing: Facing, paint: Style, pickup: boolean?)
	local model = Props.Extra(parent, if pickup then "Pickup" else "Car")
	-- Cars are modelled along their frame's Z axis with the nose at -Z (the "front").
	local frame = Shapes.FrameFor(model, x, z, 6, 13, facing)
	frame:Span("Body", -3, 3, 0.9, 3.1, -6.5, 6.5, paint)
	if pickup then
		frame:Span("Cab", -2.8, 2.8, 3.1, 5.2, -2.6, 1.4, MapPalette.WindowDark)
		frame:Span("Roof", -2.8, 2.8, 5.2, 5.5, -2.6, 1.4, paint)
		frame:Span("BedFloor", -2.6, 2.6, 3.0, 3.2, 1.6, 6.3, MapPalette.SteelDark)
	else
		frame:Span("Cabin", -2.7, 2.7, 3.1, 4.9, -2.4, 3.2, MapPalette.WindowDark)
		frame:Span("Roof", -2.7, 2.7, 4.9, 5.2, -1.9, 2.8, paint)
	end
	for _, wheelZ in { -4.2, 4.2 } do
		for _, wheelX in { -2.75, 2.75 } do
			frame:Pipe("Wheel", wheelX, 1.1, wheelZ, 0.9, 2.2, "X", MapPalette.Black)
		end
	end
end

-- The case-HQ patrol car: white with a green stripe, light bar and SHERIFF on the doors.
function Props.PatrolCar(parent: Instance, x: number, z: number, facing: Facing)
	local model = Props.Extra(parent, "Patrol Car")
	local frame = Shapes.FrameFor(model, x, z, 6, 13, facing)
	frame:Span("Body", -3, 3, 0.9, 3.1, -6.5, 6.5, MapPalette.PatrolCar)
	frame:Span("Cabin", -2.7, 2.7, 3.1, 4.9, -2.4, 3.2, MapPalette.WindowDark)
	frame:Span("Roof", -2.7, 2.7, 4.9, 5.2, -1.9, 2.8, MapPalette.PatrolCar)
	frame:Span("LightRed", -1.8, 0, 5.2, 5.7, 0, 0.9, MapPalette.NeonRed)
	frame:Span("LightBlue", 0, 1.8, 5.2, 5.7, 0, 0.9, {
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(70, 120, 255),
	})
	-- Door stripes; their outer faces carry the lettering (faces turned to the car's sides).
	local label = { Color = MapPalette.SignText.White, Font = MapPalette.Fonts.Bold }
	local left = frame:Span("Stripe", -3.15, -2.95, 1.5, 2.7, -3.5, 3.5, MapPalette.PatrolStripe)
	Shapes.Label(left, Enum.NormalId.Left, "SHERIFF", label)
	local right = frame:Span("Stripe", 2.95, 3.15, 1.5, 2.7, -3.5, 3.5, MapPalette.PatrolStripe)
	Shapes.Label(right, Enum.NormalId.Right, "SHERIFF", label)
	for _, wheelZ in { -4.2, 4.2 } do
		for _, wheelX in { -2.75, 2.75 } do
			frame:Pipe("Wheel", wheelX, 1.1, wheelZ, 0.9, 2.2, "X", MapPalette.Black)
		end
	end
end

-- Roadside sign on two posts; the text faces `facing`.
function Props.RoadSign(
	parent: Instance,
	x: number,
	z: number,
	facing: Facing,
	width: number,
	height: number,
	title: string,
	subtitle: string,
	board: Style,
	color: Color3
)
	local frame = Shapes.FrameFor(parent, x, z, width, 1, facing)
	local bottom = 4
	for _, postX in { -width * 0.35, width * 0.35 } do
		frame:Span("Post", postX - 0.4, postX + 0.4, 0, bottom + height, 0.1, 0.9, MapPalette.WoodDark)
	end
	local font = MapPalette.Fonts.Serif
	frame:Sign(
		"Board",
		-width / 2,
		width / 2,
		bottom + height * 0.35,
		bottom + height,
		-0.4,
		0.5,
		title,
		board,
		{ Color = color, Font = font }
	)
	frame:Sign(
		"Board",
		-width * 0.42,
		width * 0.42,
		bottom,
		bottom + height * 0.33,
		-0.4,
		0.5,
		subtitle,
		board,
		{ Color = color, Font = font }
	)
end

-- "Welcome to <town>" sign by the main spawn.
function Props.WelcomeSign(parent: Instance, x: number, z: number, width: number, height: number)
	local model = Props.Extra(parent, "Welcome Sign", "RailYard")
	local town = string.upper(GameConfig.TownName)
	Props.RoadSign(
		model,
		x,
		z,
		"South",
		width,
		height,
		`WELCOME TO {town}`,
		"A GOOD PLACE TO CALL HOME",
		MapPalette.SignGreen,
		MapPalette.SignText.Cream
	)
end

-- Short rail siding along X at `z` with old boxcars parked on it.
function Props.Siding(parent: Instance, x0: number, x1: number, z: number, boxcars: { number })
	local model = Props.Extra(parent, "Siding", "RailYard")
	local frame = Shapes.Frame(model, CFrame.identity, 0, 0)
	frame:Span("Ballast", x0, x1, 0, 0.4, z - 4, z + 4, MapPalette.Ballast)
	for tieX = x0 + 2, x1 - 2, 5 do
		frame:Span("Tie", tieX - 0.6, tieX + 0.6, 0.3, 0.6, z - 4.2, z + 4.2, MapPalette.Tie)
	end
	for _, side in { -2.35, 2.35 } do
		frame:Span("Rail", x0, x1, 0.6, 1.05, z + side - 0.2, z + side + 0.2, MapPalette.Rail)
	end
	frame:Span("Bumper", x1 - 1.5, x1 + 0.3, 0.4, 3.5, z - 3.5, z + 3.5, MapPalette.RustDark)

	for index, centerX in boxcars do
		local car = Props.Extra(model, "Boxcar")
		local body = if index % 2 == 0 then MapPalette.Rust else MapPalette.RustDark
		local f = Shapes.Frame(car, CFrame.new(centerX, 0, z), 0, 0)
		f:Span("Body", -18, 18, 2.8, 12.5, -4.6, 4.6, body)
		f:Span("Roof", -18.3, 18.3, 12.5, 13, -4.9, 4.9, MapPalette.RustGrey)
		for _, truckX in { -12, 12 } do
			f:Span("Truck", truckX - 3.5, truckX + 3.5, 1.05, 2.8, -3.2, 3.2, MapPalette.Black)
		end
		for _, side in { -1, 1 } do
			f:Span("Door", -4, 4, 3.5, 11.5, side * 4.5, side * 4.8, MapPalette.RustGrey)
		end
	end
end

return Props
