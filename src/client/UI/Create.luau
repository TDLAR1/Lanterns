--!strict
--[[
	Create: small helpers for building UI in code.

	Each helper returns a fully configured instance; the caller sets the layout
	(size/position) and parents it last, so the engine never lays out a
	half-built element. Decorations (corner, stroke, padding, layouts) are
	parented immediately because they are meaningless on their own.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local Create = {}

-- A Frame with no background or border (set BackgroundTransparency to show one).
function Create.frame(name: string): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	return frame
end

-- A Frame drawn as a Theme glass panel.
function Create.panel(name: string): Frame
	local frame = Create.frame(name)
	frame.BackgroundColor3 = Theme.PanelColor
	frame.BackgroundTransparency = Theme.PanelTransparency
	return frame
end

-- A single-style text label with a transparent background.
function Create.label(name: string, text: string, font: Font, textSize: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Text = text
	label.FontFace = font
	label.TextSize = textSize
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	return label
end

function Create.corner(parent: GuiObject, radius: UDim?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or Theme.CornerRadius
	corner.Parent = parent
	return corner
end

-- Outline around a frame or button's border.
function Create.stroke(parent: GuiObject, color: Color3, thickness: number, transparency: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Transparency = transparency or 0
	stroke.Parent = parent
	return stroke
end

-- Outline around the glyphs of a text label, for contrast over the 3D world.
function Create.textStroke(parent: TextLabel, color: Color3, thickness: number, transparency: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Transparency = transparency
	stroke.Parent = parent
	return stroke
end

function Create.padding(parent: GuiObject, horizontal: number, top: number, bottom: number?): UIPadding
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, horizontal)
	padding.PaddingRight = UDim.new(0, horizontal)
	padding.PaddingTop = UDim.new(0, top)
	padding.PaddingBottom = UDim.new(0, bottom or top)
	padding.Parent = parent
	return padding
end

-- Children are laid out in LayoutOrder order.
function Create.list(parent: GuiObject, direction: Enum.FillDirection, spacing: number): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, spacing)
	layout.Parent = parent
	return layout
end

-- Caps a scale-sized element (e.g. "full width minus margins") at a maximum
-- pixel size, so it fills small screens but stops growing on large ones.
function Create.maxSize(parent: GuiObject, width: number, height: number?): UISizeConstraint
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(width, height or math.huge)
	constraint.Parent = parent
	return constraint
end

return Create
