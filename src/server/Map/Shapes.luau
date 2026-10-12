--!strict
--[[
	Shapes: the part-building primitives every map module uses.

	Rules that keep the map buildable everywhere (live server, Studio command
	bar in edit mode, the offline Lune tests):
	  * Geometry is set ONLY through CFrame and Size. Position / Orientation are
	    never assigned (the offline harness ignores them).
	  * Nothing here needs a running game: no PivotTo, Random, RunService,
	    CollectionService or tweens. Tags go on with instance:AddTag.

	Frames
	  Buildings are modelled in a local Frame so the same code works whichever
	  street a building faces:
	    origin = footprint centre at ground level (Y 0)
	    local -Z = the FRONT (street side; Roblox's NormalId.Front)
	    local +X = across the front, local +Y = up
	  A frame for a footprint of SizeX x SizeZ facing North/South has
	  Width = SizeX and Depth = SizeZ; facing East/West they swap. Quarter turns
	  use exact rotation matrices so nothing picks up floating-point drift.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TagsModule = require(ReplicatedStorage.Shared.Util.Tags)

local Tags = TagsModule.Tags
local Attributes = TagsModule.Attributes

export type Style = {
	Material: Enum.Material,
	Color: Color3,
	Transparency: number?,
	Reflectance: number?,
	-- Defaults to true. Non-colliding decoration is also made non-queryable so
	-- it never blocks the camera or mouse (walking through corn, crime tape).
	CanCollide: boolean?,
	-- Defaults to true. Flat slabs turn it off: their shadow is invisible anyway.
	CastShadow: boolean?,
}

-- Which way a building's front (door, shop window, sign) faces.
export type Facing = "North" | "South" | "East" | "West"

-- Which way a wedge's slope climbs, in frame-local axes.
export type Rise = "+X" | "-X" | "+Z" | "-Z"

-- An opening in a wall (see Frame:Wall). Holes are listed bottom to top.
export type Hole = {
	Y0: number,
	Y1: number,
	-- Fill the hole with a pane of this style; nil leaves it open (doorways, broken holes).
	Glass: Style?,
}

-- A vertical strip of wall between A0 and A1 (along the wall) that has holes.
export type Column = {
	A0: number,
	A1: number,
	Holes: { Hole },
}

export type LabelOptions = {
	Color: Color3,
	Font: Font,
	-- Unlit text that stays bright at night (neon signs, painted reflective letters).
	Glow: boolean?,
}

local Shapes = {}

-- Exact quarter-turn rotations about +Y. A turn of +90 turns a north-facing
-- front to face west (right-handed rotation seen from above).
local TURN_90 = CFrame.new(0, 0, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)
local TURN_180 = CFrame.new(0, 0, 0, -1, 0, 0, 0, 1, 0, 0, 0, -1)
local TURN_270 = CFrame.new(0, 0, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0)

-- Rotates a part's X axis onto +Y: Roblox cylinders run along X, so this stands them up.
local UPRIGHT = CFrame.new(0, 0, 0, 0, -1, 0, 1, 0, 0, 0, 0, 1)

local FACING_TURN: { [Facing]: number } = {
	North = 0,
	West = 90,
	South = 180,
	East = 270,
}

-- Rotation about +Y by `degrees`; exact for multiples of 90.
function Shapes.Turn(degrees: number): CFrame
	local normalized = degrees % 360
	if normalized == 0 then
		return CFrame.identity
	elseif normalized == 90 then
		return TURN_90
	elseif normalized == 180 then
		return TURN_180
	elseif normalized == 270 then
		return TURN_270
	end
	return CFrame.Angles(0, math.rad(normalized), 0)
end

local function applyStyle(part: BasePart, name: string, cframe: CFrame, size: Vector3, style: Style)
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Material = style.Material
	part.Color = style.Color
	part.Transparency = style.Transparency or 0
	part.Reflectance = style.Reflectance or 0
	local solid = style.CanCollide ~= false
	part.CanCollide = solid
	part.CanQuery = solid
	-- Nothing in the static map reacts to touches; skipping touch events saves physics work.
	part.CanTouch = false
	part.CastShadow = style.CastShadow ~= false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

function Shapes.Part(parent: Instance, name: string, cframe: CFrame, size: Vector3, style: Style): Part
	local part = Instance.new("Part")
	applyStyle(part, name, cframe, size, style)
	part.Parent = parent
	return part
end

function Shapes.Wedge(parent: Instance, name: string, cframe: CFrame, size: Vector3, style: Style): WedgePart
	local part = Instance.new("WedgePart")
	applyStyle(part, name, cframe, size, style)
	part.Parent = parent
	return part
end

-- Vertical cylinder whose centre is `center`.
function Shapes.Cylinder(
	parent: Instance,
	name: string,
	center: CFrame,
	height: number,
	diameter: number,
	style: Style
): Part
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	applyStyle(part, name, center * UPRIGHT, Vector3.new(height, diameter, diameter), style)
	part.Parent = parent
	return part
end

function Shapes.Ball(parent: Instance, name: string, center: CFrame, diameter: number, style: Style): Part
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	applyStyle(part, name, center, Vector3.new(diameter, diameter, diameter), style)
	part.Parent = parent
	return part
end

-- Climbable lattice. Roblox snaps truss sizes to multiples of 2 studs.
function Shapes.Truss(parent: Instance, name: string, cframe: CFrame, length: number, style: Style): TrussPart
	local part = Instance.new("TrussPart")
	part.Style = Enum.Style.AlternatingSupports
	applyStyle(part, name, cframe, Vector3.new(2, length, 2), style)
	part.Parent = parent
	return part
end

function Shapes.Folder(parent: Instance, name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

-- A plain Model used to group parts inside an element.
function Shapes.Group(parent: Instance, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

--[[
	A blockout element: a Model whose PrimaryPart is an invisible "Footprint"
	box (unrotated, centred on `center`). Its visible geometry goes in as
	separate parts. Swapping in a real model later: align it to the Footprint.
]]
function Shapes.Element(parent: Instance, name: string, center: Vector3, size: Vector3, districtId: string?): Model
	local model = Instance.new("Model")
	model.Name = name

	local footprint = Instance.new("Part")
	footprint.Name = "Footprint"
	footprint.Anchored = true
	footprint.Size = size
	footprint.CFrame = CFrame.new(center)
	footprint.Transparency = 1
	footprint.CanCollide = false
	footprint.CanQuery = false
	footprint.CanTouch = false
	footprint.CastShadow = false
	footprint.TopSurface = Enum.SurfaceType.Smooth
	footprint.BottomSurface = Enum.SurfaceType.Smooth
	footprint.Parent = model
	model.PrimaryPart = footprint

	model:AddTag(Tags.Blockout)
	model:SetAttribute(Attributes.BlockoutOf, name)
	if districtId ~= nil then
		model:SetAttribute(Attributes.DistrictId, districtId)
	end
	model.Parent = parent
	return model
end

-- Puts text on one face of a part (a sign board, a painted tank).
function Shapes.Label(part: BasePart, face: Enum.NormalId, text: string, options: LabelOptions): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Label" .. face.Name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	if options.Glow then
		gui.LightInfluence = 0
		gui.Brightness = 1.5
	else
		gui.LightInfluence = 1
	end
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.92, 0.8)
	label.TextScaled = true
	label.FontFace = options.Font
	label.TextColor3 = options.Color
	label.Text = text
	label.Parent = gui
	return gui
end

-- Frame ---------------------------------------------------------------------

local Frame = {}
Frame.__index = Frame

type FrameData = {
	Parent: Instance,
	Origin: CFrame,
	Width: number,
	Depth: number,
}

export type Frame = typeof(setmetatable({} :: FrameData, Frame))

function Shapes.Frame(parent: Instance, origin: CFrame, width: number, depth: number): Frame
	return setmetatable({ Parent = parent, Origin = origin, Width = width, Depth = depth }, Frame)
end

-- Frame for a footprint centred on (x, z), size sizeX x sizeZ, front facing `facing`.
function Shapes.FrameFor(parent: Instance, x: number, z: number, sizeX: number, sizeZ: number, facing: Facing): Frame
	local origin = CFrame.new(x, 0, z) * Shapes.Turn(FACING_TURN[facing])
	if facing == "East" or facing == "West" then
		return Shapes.Frame(parent, origin, sizeZ, sizeX)
	end
	return Shapes.Frame(parent, origin, sizeX, sizeZ)
end

-- Same frame, building into another container.
function Frame.Into(self: Frame, parent: Instance): Frame
	return Shapes.Frame(parent, self.Origin, self.Width, self.Depth)
end

-- A nested frame at local (x, z), turned by `turn` degrees (front -Z turns with it).
function Frame.Child(self: Frame, x: number, z: number, turn: number, width: number?, depth: number?): Frame
	return Shapes.Frame(
		self.Parent,
		self.Origin * CFrame.new(x, 0, z) * Shapes.Turn(turn),
		width or self.Width,
		depth or self.Depth
	)
end

-- World position of a frame-local point.
function Frame.Point(self: Frame, x: number, y: number, z: number): Vector3
	return self.Origin * Vector3.new(x, y, z)
end

-- Box by centre and size.
function Frame.Box(
	self: Frame,
	name: string,
	cx: number,
	cy: number,
	cz: number,
	sx: number,
	sy: number,
	sz: number,
	style: Style
): Part
	return Shapes.Part(self.Parent, name, self.Origin * CFrame.new(cx, cy, cz), Vector3.new(sx, sy, sz), style)
end

-- Box by extents (x0..x1, y0..y1, z0..z1); the order of each pair does not matter.
function Frame.Span(
	self: Frame,
	name: string,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	z0: number,
	z1: number,
	style: Style
): Part
	return self:Box(
		name,
		(x0 + x1) / 2,
		(y0 + y1) / 2,
		(z0 + z1) / 2,
		math.abs(x1 - x0),
		math.abs(y1 - y0),
		math.abs(z1 - z0),
		style
	)
end

--[[
	Wedge filling the box x0..x1, y0..y1, z0..z1 whose slope climbs toward
	`rise`. (A Roblox WedgePart's slope climbs toward its own +Z: full-height
	face at the back, sharp edge at the bottom front.)
]]
function Frame.Wedge(
	self: Frame,
	name: string,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	z0: number,
	z1: number,
	rise: Rise,
	style: Style
): WedgePart
	local sx, sy, sz = math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)
	local center = self.Origin * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
	if rise == "+Z" then
		return Shapes.Wedge(self.Parent, name, center, Vector3.new(sx, sy, sz), style)
	elseif rise == "-Z" then
		return Shapes.Wedge(self.Parent, name, center * TURN_180, Vector3.new(sx, sy, sz), style)
	elseif rise == "+X" then
		return Shapes.Wedge(self.Parent, name, center * TURN_90, Vector3.new(sz, sy, sx), style)
	end
	return Shapes.Wedge(self.Parent, name, center * TURN_270, Vector3.new(sz, sy, sx), style)
end

-- Upright cylinder standing on y0, reaching y1.
function Frame.Cylinder(
	self: Frame,
	name: string,
	cx: number,
	cz: number,
	y0: number,
	y1: number,
	diameter: number,
	style: Style
): Part
	return Shapes.Cylinder(
		self.Parent,
		name,
		self.Origin * CFrame.new(cx, (y0 + y1) / 2, cz),
		math.abs(y1 - y0),
		diameter,
		style
	)
end

-- Lying cylinder (pipe, hay bale) along the frame's X or Z axis.
function Frame.Pipe(
	self: Frame,
	name: string,
	cx: number,
	cy: number,
	cz: number,
	length: number,
	diameter: number,
	axis: "X" | "Z",
	style: Style
): Part
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	local turn = if axis == "X" then CFrame.identity else TURN_90
	applyStyle(part, name, self.Origin * CFrame.new(cx, cy, cz) * turn, Vector3.new(length, diameter, diameter), style)
	part.Parent = self.Parent
	return part
end

function Frame.Ball(self: Frame, name: string, cx: number, cy: number, cz: number, diameter: number, style: Style): Part
	return Shapes.Ball(self.Parent, name, self.Origin * CFrame.new(cx, cy, cz), diameter, style)
end

-- Box turned by arbitrary angles (degrees, about the frame's X, Y, Z axes in that order).
function Frame.Turned(
	self: Frame,
	name: string,
	cx: number,
	cy: number,
	cz: number,
	sx: number,
	sy: number,
	sz: number,
	rx: number,
	ry: number,
	rz: number,
	style: Style
): Part
	local rotation = CFrame.Angles(math.rad(rx), math.rad(ry), math.rad(rz))
	return Shapes.Part(
		self.Parent,
		name,
		self.Origin * CFrame.new(cx, cy, cz) * rotation,
		Vector3.new(sx, sy, sz),
		style
	)
end

--[[
	Tilted slab whose underside runs along the segment (x0, y0) -> (x1, y1) in
	the frame's XY plane, spanning z0..z1 and `thickness` thick on its upper
	side (roof skins on custom profiles such as the barn's gambrel).
]]
function Frame.Slope(
	self: Frame,
	name: string,
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	z0: number,
	z1: number,
	thickness: number,
	style: Style
): Part
	local dx, dy = x1 - x0, y1 - y0
	local length = math.sqrt(dx * dx + dy * dy)
	-- Upward normal of the segment: the slab sits on top of the line.
	local nx, ny = -dy / length, dx / length
	if ny < 0 then
		nx, ny = -nx, -ny
	end
	local center = CFrame.new((x0 + x1) / 2 + nx * thickness / 2, (y0 + y1) / 2 + ny * thickness / 2, (z0 + z1) / 2)
	return Shapes.Part(
		self.Parent,
		name,
		self.Origin * center * CFrame.Angles(0, 0, math.atan2(dy, dx)),
		Vector3.new(length, thickness, math.abs(z1 - z0)),
		style
	)
end

-- Same as Slope, but the segment (z0, y0) -> (z1, y1) lies in the frame's ZY
-- plane and the slab spans x0..x1 (awnings, porch roofs sloping toward the street).
function Frame.SlopeZ(
	self: Frame,
	name: string,
	z0: number,
	y0: number,
	z1: number,
	y1: number,
	x0: number,
	x1: number,
	thickness: number,
	style: Style
): Part
	local dz, dy = z1 - z0, y1 - y0
	local length = math.sqrt(dz * dz + dy * dy)
	local nz, ny = -dy / length, dz / length
	if ny < 0 then
		nz, ny = -nz, -ny
	end
	local center = CFrame.new((x0 + x1) / 2, (y0 + y1) / 2 + ny * thickness / 2, (z0 + z1) / 2 + nz * thickness / 2)
	return Shapes.Part(
		self.Parent,
		name,
		self.Origin * center * CFrame.Angles(math.atan2(-dy, dz), 0, 0),
		Vector3.new(math.abs(x1 - x0), thickness, length),
		style
	)
end

-- Thin square beam between two frame-local points (braces, wires, tape, string).
function Frame.Beam(self: Frame, name: string, a: Vector3, b: Vector3, thickness: number, style: Style): Part
	local worldA, worldB = self.Origin * a, self.Origin * b
	local direction = worldB - worldA
	-- lookAt needs an up vector that is not parallel to the beam.
	local up = if math.abs(direction.Unit.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
	local cframe = CFrame.lookAt((worldA + worldB) / 2, worldB, up)
	return Shapes.Part(self.Parent, name, cframe, Vector3.new(thickness, thickness, direction.Magnitude), style)
end

-- Climbable truss standing at (cx, cz) from y0 up `length` studs.
function Frame.Truss(
	self: Frame,
	name: string,
	cx: number,
	cz: number,
	y0: number,
	length: number,
	style: Style
): TrussPart
	return Shapes.Truss(self.Parent, name, self.Origin * CFrame.new(cx, y0 + length / 2, cz), length, style)
end

-- Wall face a Panel is attached to: Front/Back are the z = plane faces
-- (outward -Z / +Z), Left/Right the x = plane faces (outward -X / +X).
export type Face = "Front" | "Back" | "Left" | "Right"

--[[
	Thin panel stuck on a solid wall: covers a0..a1 along the wall and y0..y1,
	from 0.1 inside the wall plane to `out` outside it (so its outer face never
	shares the wall's plane). Doors, window glass, trims, stripes.
]]
function Frame.Panel(
	self: Frame,
	name: string,
	face: Face,
	plane: number,
	a0: number,
	a1: number,
	y0: number,
	y1: number,
	out: number,
	style: Style
): Part
	if face == "Front" then
		return self:Span(name, a0, a1, y0, y1, plane - out, plane + 0.1, style)
	elseif face == "Back" then
		return self:Span(name, a0, a1, y0, y1, plane - 0.1, plane + out, style)
	elseif face == "Left" then
		return self:Span(name, plane - out, plane + 0.1, y0, y1, a0, a1, style)
	end
	return self:Span(name, plane - 0.1, plane + out, y0, y1, a0, a1, style)
end

-- Window on a solid wall: optional trim frame and sill around a glass panel.
function Frame.Window(
	self: Frame,
	face: Face,
	plane: number,
	a0: number,
	a1: number,
	y0: number,
	y1: number,
	glass: Style,
	trim: Style?
)
	if trim ~= nil then
		self:Panel("WindowTrim", face, plane, a0 - 0.35, a1 + 0.35, y0 - 0.35, y1 + 0.35, 0.12, trim)
		self:Panel("Sill", face, plane, a0 - 0.6, a1 + 0.6, y0 - 0.55, y0 - 0.2, 0.4, trim)
	end
	self:Panel("Window", face, plane, a0, a1, y0, y1, 0.22, glass)
end

--[[
	Sign board covering x0..x1, y0..y1 whose front face is the plane z = front,
	extending `depth` studs back (toward +Z). The text is on the board's front
	(the frame's front direction); pass `backText` for a two-sided sign.
]]
function Frame.Sign(
	self: Frame,
	name: string,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	front: number,
	depth: number,
	text: string,
	board: Style,
	label: LabelOptions,
	backText: string?
): Part
	local part = self:Span(name, x0, x1, y0, y1, front, front + depth, board)
	Shapes.Label(part, Enum.NormalId.Front, text, label)
	if backText ~= nil then
		Shapes.Label(part, Enum.NormalId.Back, backText, label)
	end
	return part
end

--[[
	Hexagonal prism (flat sides at +/-Z) as three overlapping boxes turned 0,
	60 and 120 degrees. `radius` is the corner radius. The tops are staggered by
	a hair so the overlapping faces never z-fight.
]]
function Frame.Hexagon(
	self: Frame,
	name: string,
	cx: number,
	cz: number,
	y0: number,
	y1: number,
	radius: number,
	style: Style
): { Part }
	local apothem = radius * math.sqrt(3) / 2
	local parts = {}
	for index = 0, 2 do
		local top = y1 - index * 0.02
		local cframe = self.Origin * CFrame.new(cx, (y0 + top) / 2, cz) * CFrame.Angles(0, math.rad(60 * index), 0)
		table.insert(parts, Shapes.Part(self.Parent, name, cframe, Vector3.new(radius, top - y0, apothem * 2), style))
	end
	return parts
end

--[[
	Straight wall with openings. axis "X": the wall runs along local X at
	z = plane; axis "Z": it runs along local Z at x = plane. It spans a0..a1
	along its length, y0..y1 in height, `thickness` thick (centred on plane).
	Columns (sorted by A0, non-overlapping) are strips that contain holes;
	solid pieces are generated around them. Glass panes are 0.3 thick.
]]
function Frame.Wall(
	self: Frame,
	name: string,
	axis: "X" | "Z",
	plane: number,
	a0: number,
	a1: number,
	y0: number,
	y1: number,
	thickness: number,
	columns: { Column },
	style: Style
)
	local function piece(p0: number, p1: number, q0: number, q1: number, pieceStyle: Style, pieceThickness: number)
		if p1 - p0 < 0.001 or q1 - q0 < 0.001 then
			return
		end
		local half = pieceThickness / 2
		if axis == "X" then
			self:Span(name, p0, p1, q0, q1, plane - half, plane + half, pieceStyle)
		else
			self:Span(name, plane - half, plane + half, q0, q1, p0, p1, pieceStyle)
		end
	end

	local cursor = a0
	for _, column in columns do
		piece(cursor, column.A0, y0, y1, style, thickness)
		local level = y0
		for _, hole in column.Holes do
			piece(column.A0, column.A1, level, hole.Y0, style, thickness)
			local glass = hole.Glass
			if glass ~= nil then
				piece(column.A0, column.A1, hole.Y0, hole.Y1, glass, 0.3)
			end
			level = hole.Y1
		end
		piece(column.A0, column.A1, level, y1, style, thickness)
		cursor = column.A1
	end
	piece(cursor, a1, y0, y1, style, thickness)
end

--[[
	Gable roof over the rectangle x0..x1 x z0..z1, starting at height y0 and
	peaking `rise` higher along a ridge parallel to `ridge`. Wedges in
	`wallStyle` fill the triangular gable ends (so they read as wall), and two
	tilted `roofStyle` skins cover the slopes, overhanging by `overhang`.
]]
function Frame.GableRoof(
	self: Frame,
	name: string,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	y0: number,
	rise: number,
	ridge: "X" | "Z",
	wallStyle: Style,
	roofStyle: Style,
	overhang: number
)
	local thickness = 0.6
	local top = y0 + rise
	local xm, zm = (x0 + x1) / 2, (z0 + z1) / 2
	if ridge == "X" then
		self:Wedge(name .. "Gable", x0, x1, y0, top, z0, zm, "+Z", wallStyle)
		self:Wedge(name .. "Gable", x0, x1, y0, top, zm, z1, "-Z", wallStyle)
		local half = (z1 - z0) / 2
		local slope = math.sqrt(half * half + rise * rise)
		local angle = math.atan2(rise, half)
		local sin, cos = math.sin(angle), math.cos(angle)
		local size = Vector3.new(x1 - x0 + overhang * 2, thickness, slope + overhang + thickness)
		-- Centre of each skin: middle of the slope, slid down-slope by half the
		-- extra length (overhang at the eave minus the bit past the ridge) and
		-- lifted off the slope by half the skin thickness.
		local slide = (overhang - thickness) / 2
		local frontZ = (z0 + zm) / 2 - cos * slide - sin * thickness / 2
		local backZ = (zm + z1) / 2 + cos * slide + sin * thickness / 2
		local skinY = y0 + rise / 2 - sin * slide + cos * thickness / 2
		Shapes.Part(
			self.Parent,
			name .. "Roof",
			self.Origin * CFrame.new(xm, skinY, frontZ) * CFrame.Angles(-angle, 0, 0),
			size,
			roofStyle
		)
		Shapes.Part(
			self.Parent,
			name .. "Roof",
			self.Origin * CFrame.new(xm, skinY, backZ) * CFrame.Angles(angle, 0, 0),
			size,
			roofStyle
		)
	else
		self:Wedge(name .. "Gable", x0, xm, y0, top, z0, z1, "+X", wallStyle)
		self:Wedge(name .. "Gable", xm, x1, y0, top, z0, z1, "-X", wallStyle)
		local half = (x1 - x0) / 2
		local slope = math.sqrt(half * half + rise * rise)
		local angle = math.atan2(rise, half)
		local sin, cos = math.sin(angle), math.cos(angle)
		local size = Vector3.new(slope + overhang + thickness, thickness, z1 - z0 + overhang * 2)
		local slide = (overhang - thickness) / 2
		local leftX = (x0 + xm) / 2 - cos * slide - sin * thickness / 2
		local rightX = (xm + x1) / 2 + cos * slide + sin * thickness / 2
		local skinY = y0 + rise / 2 - sin * slide + cos * thickness / 2
		Shapes.Part(
			self.Parent,
			name .. "Roof",
			self.Origin * CFrame.new(leftX, skinY, zm) * CFrame.Angles(0, 0, angle),
			size,
			roofStyle
		)
		Shapes.Part(
			self.Parent,
			name .. "Roof",
			self.Origin * CFrame.new(rightX, skinY, zm) * CFrame.Angles(0, 0, -angle),
			size,
			roofStyle
		)
	end
end

return Shapes
