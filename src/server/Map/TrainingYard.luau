--!strict
--[[
	TrainingYard: the practice range in the Rail Yard, east of the main spawn
	(MapLayout.TrainingYard). A low post-and-rail fence open toward the
	highway, a painted firing line on a dirt strip with a mark for each lane,
	a straw-bale backstop, a "PRACTICE RANGE" sign, and the invisible
	TrainingDummySpot parts where DummyService stands the practice targets
	(facing west, toward the firing line).

	Swapping in a real model: keep the TrainingDummySpot parts, or move their
	tag onto your own invisible parts (the dummy stands on the part's bottom
	face and faces its LookVector).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TagsModule = require(ReplicatedStorage.Shared.Util.Tags)

local MapLayout = require(script.Parent.MapLayout)
local MapPalette = require(script.Parent.MapPalette)
local Props = require(script.Parent.Props)
local Shapes = require(script.Parent.Shapes)

type Frame = Shapes.Frame
type Style = Shapes.Style

local Tags = TagsModule.Tags

-- Invisible, non-interactive marker part (like the district respawn points).
local HIDDEN: Style = {
	Material = Enum.Material.SmoothPlastic,
	Color = Color3.fromRGB(255, 255, 255),
	Transparency = 1,
	CanCollide = false,
	CastShadow = false,
}

-- Fence post width and rail thickness / height (studs).
local POST = 0.5
local RAIL = 0.25
local RAIL_HEIGHT = 0.3
-- Square straw bales: length (along the backstop), height, depth.
local BALE_LENGTH, BALE_HEIGHT, BALE_DEPTH = 4, 2, 2.6
local BALE_GAP = 0.1
-- Surface tops (see MapLayout): dirt 0.1, paint on the dirt up to 0.15.
local DIRT_TOP, PAINT_TOP = 0.1, 0.15

local TrainingYard = {}

-- A straight fence run along X or Z from (x0, z0) to (x1, z1): evenly spaced
-- posts (the first one left out where a corner post already stands) and two rails.
local function fenceRun(
	frame: Frame,
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	height: number,
	spacing: number,
	skipFirst: boolean
)
	local length = math.abs(x1 - x0) + math.abs(z1 - z0)
	local segments = math.max(1, math.floor(length / spacing + 0.5))
	for index = if skipFirst then 1 else 0, segments do
		local t = index / segments
		local x, z = x0 + (x1 - x0) * t, z0 + (z1 - z0) * t
		frame:Span("Post", x - POST / 2, x + POST / 2, 0, height, z - POST / 2, z + POST / 2, MapPalette.WoodDark)
	end
	for _, level in { 0.45, 0.85 } do
		local y = height * level
		if x0 == x1 then
			frame:Span(
				"Rail",
				x0 - RAIL / 2,
				x0 + RAIL / 2,
				y - RAIL_HEIGHT / 2,
				y + RAIL_HEIGHT / 2,
				z0,
				z1,
				MapPalette.Wood
			)
		else
			frame:Span(
				"Rail",
				x0,
				x1,
				y - RAIL_HEIGHT / 2,
				y + RAIL_HEIGHT / 2,
				z0 - RAIL / 2,
				z0 + RAIL / 2,
				MapPalette.Wood
			)
		end
	end
end

local function buildFence(frame: Frame)
	local layout = MapLayout.TrainingYard
	local rect = layout.Rect
	local height, spacing = layout.FenceHeight, layout.PostSpacing
	-- North, east, south; the west side stays open toward the highway.
	fenceRun(frame, rect.X0, rect.Z0, rect.X1, rect.Z0, height, spacing, false)
	fenceRun(frame, rect.X1, rect.Z0, rect.X1, rect.Z1, height, spacing, true)
	fenceRun(frame, rect.X1, rect.Z1, rect.X0, rect.Z1, height, spacing, true)
end

local function buildFiringLine(frame: Frame)
	local layout = MapLayout.TrainingYard
	local rect = layout.Rect
	local x = layout.FiringLineX
	local half = layout.FiringPadWidth / 2
	frame:Span("FiringPad", x - half, x + half, 0, DIRT_TOP, rect.Z0 + 2, rect.Z1 - 2, MapPalette.DirtRoad)
	frame:Span("FiringLine", x - 0.3, x + 0.3, DIRT_TOP, PAINT_TOP, rect.Z0 + 3, rect.Z1 - 3, MapPalette.LineWhite)
	-- A short mark toward each target's lane (beside the line, so paint never overlaps paint).
	for _, spot in layout.DummySpots do
		frame:Span("LaneMark", x + 0.3, x + 2.3, DIRT_TOP, PAINT_TOP, spot.Z - 0.3, spot.Z + 0.3, MapPalette.LineWhite)
	end
end

-- Two staggered rows of straw bales behind the targets: beams that miss end here.
local function buildBackstop(frame: Frame)
	local layout = MapLayout.TrainingYard
	local rect = layout.Rect
	local x = layout.BackstopX
	local z0, z1 = rect.Z0 + 3, rect.Z1 - 3
	local pitch = BALE_LENGTH + BALE_GAP
	local count = math.floor((z1 - z0 + BALE_GAP) / pitch)
	local start = (z0 + z1) / 2 - (count * pitch - BALE_GAP) / 2
	for row = 0, 1 do
		-- The top row is half a bale along and a little narrower, so no faces line up.
		local shift = row * pitch / 2
		local inset = row * 0.15
		for index = 0, count - 1 - row do
			local z = start + shift + index * pitch
			frame:Span(
				"Bale",
				x - BALE_DEPTH / 2 + inset,
				x + BALE_DEPTH / 2 - inset,
				row * BALE_HEIGHT,
				(row + 1) * BALE_HEIGHT,
				z,
				z + BALE_LENGTH,
				MapPalette.Hay
			)
		end
	end
end

local function buildSign(model: Model)
	local sign = MapLayout.TrainingYard.Sign
	local width = sign.Width
	local frame = Shapes.FrameFor(model, sign.X, sign.Z, width, 1, "West")
	local top = 4.8
	for _, postX in { -width * 0.35, width * 0.35 } do
		frame:Span("Post", postX - POST / 2, postX + POST / 2, 0, top, 0, POST, MapPalette.WoodDark)
	end
	frame:Sign(
		"Board",
		-width / 2,
		width / 2,
		2.4,
		top,
		-0.3,
		0.3,
		sign.Text,
		MapPalette.SignCream,
		{ Color = MapPalette.SignText.Dark, Font = MapPalette.Fonts.Bold }
	)
	-- Ring-green strip under the board.
	frame:Span("Stripe", -width / 2, width / 2, 2.0, 2.4, -0.3, 0, MapPalette.SignGreen)
end

local function buildSpots(model: Model)
	local layout = MapLayout.TrainingYard
	for index, point in layout.DummySpots do
		Shapes.Cylinder(
			model,
			"TargetPatch",
			CFrame.new(point.X, DIRT_TOP / 2, point.Z),
			DIRT_TOP,
			layout.SpotPatchDiameter,
			MapPalette.DirtRoad
		)
		-- Resting on the ground; turned a quarter so its front (LookVector) faces west.
		local spot = Shapes.Part(
			model,
			`DummySpot{index}`,
			CFrame.new(point.X, 0.5, point.Z) * Shapes.Turn(90),
			Vector3.new(2, 1, 2),
			HIDDEN
		)
		spot:AddTag(Tags.TrainingDummySpot)
	end
end

-- Builds the training yard into the Rail Yard district folder.
function TrainingYard.Build(parent: Instance): Model
	local model = Props.Extra(parent, "Training Yard", "RailYard")
	local frame = Shapes.Frame(model, CFrame.identity, 0, 0)
	buildFence(frame)
	buildFiringLine(frame)
	buildBackstop(frame)
	buildSign(model)
	buildSpots(model)
	return model
end

return TrainingYard
