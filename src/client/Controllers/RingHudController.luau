--!strict
--[[
	RingHudController: the ring's HUD.

	  * Willpower bar: glides to the server's value, leaves a pale "drain trail"
	    when willpower is spent, and glows. A notch marks
	    Config.Ring.Strength.FullAtWillpowerFraction: above it constructs are at
	    full strength; below it the bar dims (they are weaker).
	  * Ring charge meter with the percentage: pulses amber at or below
	    Config.Ring.Charge.LowThreshold; at zero it turns dark red and shows
	    where to recharge.
	  * Power slots (Beam, Shield, then the constructs in
	    Config.Powers.ConstructOrder): a cooldown overlay sweeping down with the
	    seconds left, dimmed while the power can't be used, lit while active
	    (beam firing, shield up); the selected construct is highlighted. Under
	    each slot, the key (keyboard) or button glyph (controller) that uses it;
	    none on touch, where the buttons themselves are on screen.
	  * A short feedback line under the crosshair when a power is refused
	    (PowerController.Feedback, which also carries FlightController.Refused).
	    A new message replaces the current one; it never stacks.

	Two layouts (Config.UI.RingHud): Full, centred at the bottom on keyboard and
	gamepad; Compact, at the top-left on touch, moved below the district banner
	on screens too narrow for it to fit beside it. The HUD stays hidden until the
	ring exists (its attributes arrived) and while anything asks it to hide
	(SetHidden; the oath moment does).

	API:
	  RingHudController:SetHidden(reason, hidden)
	  RingHudController:ShowFeedback(text)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local InputConfig = require(Shared.Config.Input)
local PowersConfig = require(Shared.Config.Powers)
local RingConfig = require(Shared.Config.Ring)
local TagsModule = require(Shared.Util.Tags)
local Text = require(Shared.Config.Text)
local Theme = require(Shared.Config.Theme)
local Types = require(Shared.Types)
local UIConfig = require(Shared.Config.UI)

local Create = require(script.Parent.Parent.UI.Create)
local HudController = require(script.Parent.HudController)
local InputController = require(script.Parent.InputController)
local PowerController = require(script.Parent.PowerController)
local RingController = require(script.Parent.RingController)

local Attributes = TagsModule.Attributes
local LocalPlayer = Players.LocalPlayer

local config = UIConfig.RingHud
type Layout = typeof(UIConfig.RingHud.Full)

local MOUSE_BUTTON_NAMES: { [string]: string } = Text.Ring.MouseButtons

type Bar = {
	track: Frame,
	fill: Frame,
	glow: UIStroke,
	trail: Frame?,
}

type IconPart = {
	object: GuiObject,
	-- Background transparency when fully lit.
	base: number,
	stroke: UIStroke?,
}

type Slot = {
	powerId: Types.PowerId,
	frame: Frame,
	stroke: UIStroke,
	icon: { IconPart },
	name: TextLabel?,
	cooldown: Frame,
	cooldownText: TextLabel,
	pip: Frame?,
	keyText: TextLabel?,
	keyGlyph: ImageLabel?,
	-- Last drawn state, so unchanged frames cost nothing.
	shownOpacity: number,
	shownCooldown: number,
	shownSelected: boolean?,
}

type View = {
	layout: Layout,
	root: Frame,
	willpower: Bar,
	willpowerValue: TextLabel,
	charge: Bar,
	chargeValue: TextLabel,
	hint: TextLabel,
	slotRow: Frame,
	slots: { Slot },
	previousGlyph: ImageLabel?,
	nextGlyph: ImageLabel?,
	-- Panel height without / with the recharge hint, and where the slot row sits.
	height: number,
	slotRowTop: number,
}

-- The slots in order. Constructs follow Config.Powers.ConstructOrder.
local function asConstruct(id: string): Types.ConstructId?
	if id == "Wall" then
		return "Wall"
	elseif id == "Hammer" then
		return "Hammer"
	elseif id == "Cage" then
		return "Cage"
	end
	return nil
end

local SLOT_POWERS: { Types.PowerId } = { "Beam", "Shield" }
for _, id in PowersConfig.ConstructOrder do
	local construct = asConstruct(id)
	if construct ~= nil then
		table.insert(SLOT_POWERS, construct)
	end
end

-- The input action whose key / button each slot shows.
local SLOT_ACTIONS: { [string]: string } = {
	Beam = "FireBeam",
	Shield = "ToggleShield",
	Wall = "CastWall",
	Hammer = "CastHammer",
	Cage = "CastCage",
}

type ChargeState = "Normal" | "Low" | "Empty"

local views: { [string]: View } = {}
local activeView: View? = nil
local hiddenReasons: { [string]: boolean } = {}

-- Shown (smoothed) values.
local shownWillpower = 1
local shownTrail = 1
local trailHoldUntil = 0
local shownCharge = 1
local shownChargeState: ChargeState? = nil
local shownBelowThreshold: boolean? = nil
local lastWillpowerText = ""
local lastChargeText = ""

local feedbackLabel: TextLabel? = nil
local feedbackStroke: UIStroke? = nil
local feedbackScale: UIScale? = nil
local feedbackThread: thread? = nil
local feedbackTweens: { Tween } = {}

local RingHudController = {}

-- Power facts ---------------------------------------------------------------------------

local function constructConfig(id: Types.PowerId): { Cooldown: number, MinWillpower: number, WillpowerCost: number }
	local constructs = PowersConfig.Constructs
	if id == "Wall" then
		return constructs.Wall
	elseif id == "Hammer" then
		return constructs.Hammer
	end
	return constructs.Cage
end

local function cooldownOf(id: Types.PowerId): number
	if id == "Beam" then
		return PowersConfig.Beam.Cooldown
	elseif id == "Shield" then
		return PowersConfig.Shield.Cooldown
	end
	return constructConfig(id).Cooldown
end

local function minWillpowerOf(id: Types.PowerId): number
	if id == "Beam" then
		return PowersConfig.Beam.MinWillpower
	elseif id == "Shield" then
		return PowersConfig.Shield.MinWillpower
	end
	local construct = constructConfig(id)
	return math.max(construct.MinWillpower, construct.WillpowerCost)
end

local function isConstruct(id: Types.PowerId): boolean
	return id == "Wall" or id == "Hammer" or id == "Cage"
end

-- Building ---------------------------------------------------------------------------------

local function newBar(name: string, height: number, withTrail: boolean): Bar
	local track = Create.frame(name)
	track.Size = UDim2.new(1, 0, 0, height)
	track.BackgroundColor3 = Theme.PanelColor
	track.BackgroundTransparency = config.TrackTransparency
	Create.corner(track, UDim.new(0.5, 0))

	local trail: Frame? = nil
	if withTrail then
		local trailFrame = Create.frame("Trail")
		trailFrame.Size = UDim2.fromScale(1, 1)
		trailFrame.BackgroundColor3 = Theme.TextPrimary
		trailFrame.BackgroundTransparency = config.TrailTransparency
		Create.corner(trailFrame, UDim.new(0.5, 0))
		trailFrame.Parent = track
		trail = trailFrame
	end

	local fill = Create.frame("Fill")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Theme.RingGreen
	fill.BackgroundTransparency = 0
	fill.ZIndex = 2
	Create.corner(fill, UDim.new(0.5, 0))
	-- A brighter top edge gives the bar some depth.
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Theme.TextPrimary, Theme.RingGreen)
	gradient.Transparency = NumberSequence.new(0)
	gradient.Parent = fill
	local glow = Create.stroke(fill, Theme.RingGreen, config.GlowThickness, config.GlowTransparency)
	fill.Parent = track

	return { track = track, fill = fill, glow = glow, trail = trail }
end

local function addMarker(bar: Bar, fraction: number)
	local marker = Create.frame("FullStrength")
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Position = UDim2.fromScale(fraction, 0.5)
	marker.Size = UDim2.new(0, config.MarkerWidth, 1, config.MarkerOverhang * 2)
	marker.BackgroundColor3 = Theme.TextPrimary
	marker.BackgroundTransparency = 0.15
	marker.ZIndex = 3
	marker.Parent = bar.track
end

-- One shape of a slot icon, in the icon's own 0..1 space.
local function iconPart(
	parent: Frame,
	parts: { IconPart },
	position: UDim2,
	size: UDim2,
	transparency: number,
	options: { rotation: number?, round: boolean?, outline: boolean? }?
): Frame
	local shape = Create.frame("Shape")
	shape.AnchorPoint = Vector2.new(0.5, 0.5)
	shape.Position = position
	shape.Size = size
	shape.BackgroundColor3 = Theme.RingGreen
	shape.BackgroundTransparency = transparency
	local stroke: UIStroke? = nil
	if options ~= nil then
		shape.Rotation = options.rotation or 0
		if options.round then
			Create.corner(shape, UDim.new(0.5, 0))
		end
		if options.outline then
			stroke = Create.stroke(shape, Theme.RingGreen, 2)
		end
	end
	shape.Parent = parent
	local part: IconPart = { object = shape :: GuiObject, base = transparency, stroke = stroke }
	table.insert(parts, part)
	return shape
end

-- Simple geometric icons drawn from frames (no image assets needed).
local function buildIcon(powerId: Types.PowerId, parent: Frame): { IconPart }
	local parts: { IconPart } = {}
	local center = UDim2.fromScale(0.5, 0.5)
	if powerId == "Beam" then
		iconPart(parent, parts, center, UDim2.fromScale(1, 0.16), 0, { rotation = -35, round = true })
		iconPart(parent, parts, UDim2.fromScale(0.12, 0.84), UDim2.fromScale(0.3, 0.3), 0, { round = true })
	elseif powerId == "Shield" then
		iconPart(parent, parts, center, UDim2.fromScale(0.95, 0.95), 0.75, { round = true, outline = true })
		iconPart(parent, parts, center, UDim2.fromScale(0.3, 0.3), 0, { round = true })
	elseif powerId == "Wall" then
		iconPart(parent, parts, center, UDim2.fromScale(1, 0.7), 0.55, { outline = true })
		iconPart(parent, parts, center, UDim2.fromScale(1, 0.08), 0.2)
	elseif powerId == "Hammer" then
		iconPart(parent, parts, UDim2.fromScale(0.5, 0.25), UDim2.fromScale(0.9, 0.42), 0)
		iconPart(parent, parts, UDim2.fromScale(0.5, 0.7), UDim2.fromScale(0.16, 0.6), 0)
	else
		for index = 0, 3 do
			iconPart(parent, parts, UDim2.fromScale(0.08 + index * 0.28, 0.5), UDim2.fromScale(0.1, 0.9), 0)
		end
		iconPart(parent, parts, UDim2.fromScale(0.5, 0.06), UDim2.fromScale(1, 0.1), 0)
		iconPart(parent, parts, UDim2.fromScale(0.5, 0.94), UDim2.fromScale(1, 0.1), 0)
	end
	return parts
end

local function buildSlot(powerId: Types.PowerId, layout: Layout, parent: Frame, x: number): Slot
	local size = layout.SlotSize
	local frame = Create.panel("Slot_" .. powerId)
	frame.Position = UDim2.fromOffset(x, 0)
	frame.Size = UDim2.fromOffset(size, size)
	Create.corner(frame, UDim.new(0, config.SlotCornerRadius))
	local stroke = Create.stroke(frame, Theme.RingGreen, config.SlotStrokeThickness, 0.5)

	local nameHeight = if layout.ShowSlotNames then layout.SlotNameTextSize + 2 else 0
	local iconSize = size * config.IconScale
	local icon = Create.frame("Icon")
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.new(0.5, 0, 0.5, -nameHeight / 2)
	icon.Size = UDim2.fromOffset(iconSize, iconSize)
	icon.Parent = frame
	local iconParts = buildIcon(powerId, icon)

	local name: TextLabel? = nil
	if layout.ShowSlotNames then
		local label = Create.label(
			"Name",
			PowerController:GetDisplayName(powerId),
			Theme.Font,
			layout.SlotNameTextSize,
			Theme.TextSecondary
		)
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = UDim2.new(0.5, 0, 1, -2)
		label.Size = UDim2.new(1, -4, 0, nameHeight)
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Parent = frame
		name = label
	end

	-- Dark overlay that shrinks downward as the cooldown runs out.
	local cooldown = Create.frame("Cooldown")
	cooldown.AnchorPoint = Vector2.new(0, 1)
	cooldown.Position = UDim2.fromScale(0, 1)
	cooldown.Size = UDim2.fromScale(1, 0)
	cooldown.BackgroundColor3 = Color3.new(0, 0, 0)
	cooldown.BackgroundTransparency = config.CooldownOverlayTransparency
	cooldown.ZIndex = 3
	cooldown.Visible = false
	Create.corner(cooldown, UDim.new(0, config.SlotCornerRadius))
	cooldown.Parent = frame
	local cooldownText = Create.label("Seconds", "", Theme.FontBold, layout.CooldownTextSize, Theme.TextPrimary)
	cooldownText.Size = UDim2.fromScale(1, 1)
	cooldownText.ZIndex = 4
	cooldownText.Visible = false
	Create.textStroke(cooldownText, Theme.PanelColor, 1, 0.3)
	cooldownText.Parent = frame

	local pip: Frame? = nil
	if isConstruct(powerId) then
		local selectedPip = Create.frame("Selected")
		selectedPip.AnchorPoint = Vector2.new(0.5, 0.5)
		selectedPip.Position = UDim2.fromScale(0.5, 0)
		selectedPip.Size = UDim2.new(0.45, 0, 0, 3)
		selectedPip.BackgroundColor3 = Theme.RingGreen
		selectedPip.BackgroundTransparency = 0
		selectedPip.ZIndex = 5
		selectedPip.Visible = false
		Create.corner(selectedPip, UDim.new(0.5, 0))
		selectedPip.Parent = frame
		pip = selectedPip
	end

	local keyText: TextLabel? = nil
	local keyGlyph: ImageLabel? = nil
	if layout.KeyHintHeight > 0 then
		local label = Create.label("Key", "", Theme.FontBold, layout.KeyHintTextSize, Theme.TextSecondary)
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.new(0.5, 0, 1, 2)
		label.Size = UDim2.new(1, 8, 0, layout.KeyHintHeight - 2)
		label.Parent = frame
		keyText = label
		local glyph = Instance.new("ImageLabel")
		glyph.Name = "Glyph"
		glyph.BackgroundTransparency = 1
		glyph.AnchorPoint = Vector2.new(0.5, 0)
		glyph.Position = UDim2.new(0.5, 0, 1, 1)
		glyph.Size = UDim2.fromOffset(layout.GlyphSize, layout.GlyphSize)
		glyph.ScaleType = Enum.ScaleType.Fit
		glyph.Visible = false
		glyph.Parent = frame
		keyGlyph = glyph
	end

	frame.Parent = parent
	return {
		powerId = powerId,
		frame = frame,
		stroke = stroke,
		icon = iconParts,
		name = name,
		cooldown = cooldown,
		cooldownText = cooldownText,
		pip = pip,
		keyText = keyText,
		keyGlyph = keyGlyph,
		shownOpacity = -1,
		shownCooldown = -1,
		shownSelected = nil,
	}
end

local function headerRow(
	parent: Frame,
	layout: Layout,
	labelText: string,
	x: number,
	y: number,
	width: number
): TextLabel
	local label = Create.label("Label", labelText, Theme.FontBold, layout.LabelTextSize, Theme.TextSecondary)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Position = UDim2.fromOffset(x, y)
	label.Size = UDim2.fromOffset(width, layout.HeaderHeight)
	label.Parent = parent
	local value = Create.label("Value", "", Theme.FontBold, layout.ValueTextSize, Theme.TextPrimary)
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.Position = UDim2.fromOffset(x, y)
	value.Size = UDim2.fromOffset(width, layout.HeaderHeight)
	value.Parent = parent
	return value
end

local function newGlyph(parent: Frame, size: number): ImageLabel
	local glyph = Instance.new("ImageLabel")
	glyph.Name = "Glyph"
	glyph.BackgroundTransparency = 1
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Size = UDim2.fromOffset(size, size)
	glyph.ScaleType = Enum.ScaleType.Fit
	glyph.Visible = false
	glyph.Parent = parent
	return glyph
end

local function buildView(name: string, layout: Layout, parent: ScreenGui): View
	local width = layout.Width
	local padding = layout.Padding
	local inner = width - padding * 2

	local root = Create.panel(name)
	root.BackgroundTransparency = config.PanelTransparency
	root.Visible = false
	Create.corner(root)
	Create.stroke(root, Theme.RingGreen, config.StrokeThickness, config.StrokeTransparency)

	local y = padding
	local willpowerWidth = if layout.Stacked then inner else inner - layout.ChargeWidth - layout.ColumnGap
	local willpowerValue = headerRow(root, layout, Text.Ring.WillpowerLabel, padding, y, willpowerWidth)
	local chargeValue: TextLabel
	local chargeBarTop: number
	local chargeX = if layout.Stacked then padding else padding + willpowerWidth + layout.ColumnGap
	local chargeWidth = if layout.Stacked then inner else layout.ChargeWidth
	if not layout.Stacked then
		chargeValue = headerRow(root, layout, Text.Ring.ChargeLabel, chargeX, y, chargeWidth)
	end
	y += layout.HeaderHeight

	local willpower = newBar("Willpower", layout.WillpowerBarHeight, true)
	willpower.track.Position = UDim2.fromOffset(padding, y)
	willpower.track.Size = UDim2.fromOffset(willpowerWidth, layout.WillpowerBarHeight)
	addMarker(willpower, RingConfig.Strength.FullAtWillpowerFraction)
	willpower.track.Parent = root

	if layout.Stacked then
		y += layout.WillpowerBarHeight + layout.RowGap
		chargeValue = headerRow(root, layout, Text.Ring.ChargeLabel, chargeX, y, chargeWidth)
		y += layout.HeaderHeight
		chargeBarTop = y
		y += layout.ChargeBarHeight
	else
		-- Centred on the willpower bar beside it.
		chargeBarTop = y + (layout.WillpowerBarHeight - layout.ChargeBarHeight) / 2
		y += layout.WillpowerBarHeight
	end
	local charge = newBar("Charge", layout.ChargeBarHeight, false)
	charge.track.Position = UDim2.fromOffset(chargeX, chargeBarTop)
	charge.track.Size = UDim2.fromOffset(chargeWidth, layout.ChargeBarHeight)
	charge.track.Parent = root

	local hint = Create.label("RechargeHint", Text.Ring.RechargeHint, Theme.Font, layout.HintTextSize, Theme.Danger)
	hint.Position = UDim2.fromOffset(padding, y + layout.RowGap / 2)
	hint.Size = UDim2.fromOffset(inner, layout.HintHeight)
	hint.TextWrapped = true
	hint.Visible = false
	hint.Parent = root

	y += layout.RowGap
	local slotRowTop = y
	local slotCount = #SLOT_POWERS
	local constructCount = math.max(slotCount - 2, 0)
	local rowWidth = slotCount * layout.SlotSize
		+ math.max(slotCount - 1 - (if constructCount > 0 then 1 else 0), 0) * layout.SlotGap
		+ (if constructCount > 0 then layout.GroupGap else 0)
	local slotRow = Create.frame("Slots")
	slotRow.AnchorPoint = Vector2.new(0.5, 0)
	slotRow.Position = UDim2.new(0.5, 0, 0, slotRowTop)
	slotRow.Size = UDim2.fromOffset(rowWidth, layout.SlotSize + layout.KeyHintHeight)
	slotRow.Parent = root

	local slots: { Slot } = {}
	local x = 0
	-- Indexed (not iterated): iterating an array of power ids widens them to strings.
	for index = 1, slotCount do
		table.insert(slots, buildSlot(SLOT_POWERS[index], layout, slotRow, x))
		x += layout.SlotSize + (if index == 2 then layout.GroupGap else layout.SlotGap)
	end

	-- Previous / next construct buttons flank the construct group (controller only).
	local previousGlyph: ImageLabel? = nil
	local nextGlyph: ImageLabel? = nil
	if layout.GlyphSize > 0 and constructCount > 0 then
		local firstConstruct = slots[3].frame
		local lastConstruct = slots[slotCount].frame
		local glyphY = layout.SlotSize / 2
		local previous = newGlyph(slotRow, layout.GlyphSize)
		previous.Position = UDim2.fromOffset(firstConstruct.Position.X.Offset - layout.GroupGap / 2, glyphY)
		local following = newGlyph(slotRow, layout.GlyphSize)
		following.Position =
			UDim2.fromOffset(lastConstruct.Position.X.Offset + layout.SlotSize + layout.GroupGap / 2, glyphY)
		previousGlyph = previous
		nextGlyph = following
	end

	local height = slotRowTop + layout.SlotSize + layout.KeyHintHeight + padding
	root.Size = UDim2.fromOffset(width, height)
	root.Parent = parent

	return {
		layout = layout,
		root = root,
		willpower = willpower,
		willpowerValue = willpowerValue,
		charge = charge,
		chargeValue = chargeValue,
		hint = hint,
		slotRow = slotRow,
		slots = slots,
		previousGlyph = previousGlyph,
		nextGlyph = nextGlyph,
		height = height,
		slotRowTop = slotRowTop,
	}
end

-- Layout ----------------------------------------------------------------------------------

-- Where the Compact panel goes: under the top bar at the left, or below the
-- district banner when the screen is too narrow for both side by side.
local function placeCompact(view: View)
	local hud = HudController:GetRoot()
	local scale = HudController:GetScale()
	local screenWidth = hud.AbsoluteSize.X / math.max(scale, 0.01)
	local banner = UIConfig.Banner
	local bannerWidth = math.min(screenWidth - 2 * UIConfig.ScreenMargin, banner.MaxWidth)
	local bannerLeft = (screenWidth - bannerWidth) / 2
	local bannerHeight = banner.PaddingY * 2
		+ banner.TitleHeight
		+ banner.AccentHeight
		+ banner.SubtitleHeight
		+ banner.Spacing * 2
	local right = UIConfig.ScreenMargin + view.layout.Width
	local top = UIConfig.ScreenMargin
	if right + UIConfig.ScreenMargin > bannerLeft then
		top = banner.Top + bannerHeight + UIConfig.ScreenMargin / 2
	end
	view.root.AnchorPoint = Vector2.new(0, 0)
	view.root.Position = UDim2.fromOffset(UIConfig.ScreenMargin, top)
end

local function placeFull(view: View)
	view.root.AnchorPoint = Vector2.new(0.5, 1)
	view.root.Position = UDim2.new(0.5, 0, 1, -UIConfig.ScreenMargin)
end

local function keyName(keyCode: Enum.KeyCode): string
	local name = UserInputService:GetStringForKeyCode(keyCode)
	return if name ~= "" then name else keyCode.Name
end

local function actionKeyText(actionName: string): string
	local action = InputConfig.Actions[actionName]
	if action == nil then
		return ""
	end
	local key = action.Keyboard[1]
	if key ~= nil then
		return keyName(key)
	end
	local mouse = action.Mouse
	local button = if mouse ~= nil then mouse[1] else nil
	if button ~= nil then
		return MOUSE_BUTTON_NAMES[button.Name] or button.Name
	end
	return ""
end

local function actionGlyph(actionName: string): string
	local action = InputConfig.Actions[actionName]
	local button = if action ~= nil then action.Gamepad[1] else nil
	if button == nil then
		return ""
	end
	return UserInputService:GetImageForKeyCode(button)
end

local function setGlyph(glyph: ImageLabel?, image: string)
	if glyph ~= nil then
		glyph.Image = image
		glyph.Visible = image ~= ""
	end
end

-- Key / button hints for the current device.
local function refreshHints(view: View)
	local device = InputController:GetDevice()
	local selected: Types.ConstructId = PowerController:GetSelectedConstruct()
	for _, slot in view.slots do
		local text = ""
		local image = ""
		if device == "KeyboardMouse" then
			text = actionKeyText(SLOT_ACTIONS[slot.powerId] or "")
		elseif device == "Gamepad" then
			-- Controllers cast the selected construct; the others have no button.
			if not isConstruct(slot.powerId) then
				image = actionGlyph(SLOT_ACTIONS[slot.powerId] or "")
			elseif slot.powerId == selected then
				image = actionGlyph("CastConstruct")
			end
		end
		local keyText = slot.keyText
		if keyText ~= nil then
			keyText.Text = text
			keyText.Visible = text ~= ""
		end
		setGlyph(slot.keyGlyph, image)
	end
	local gamepad = device == "Gamepad"
	setGlyph(view.previousGlyph, if gamepad then actionGlyph("PreviousConstruct") else "")
	setGlyph(view.nextGlyph, if gamepad then actionGlyph("NextConstruct") else "")
end

local function showView(view: View)
	local current = activeView
	if current ~= nil and current ~= view then
		current.root.Visible = false
	end
	activeView = view
	if view.layout.Stacked then
		placeCompact(view)
	else
		placeFull(view)
	end
	refreshHints(view)
	-- Redraw everything on the newly shown view.
	shownChargeState = nil
	shownBelowThreshold = nil
	lastWillpowerText = ""
	lastChargeText = ""
	for _, slot in view.slots do
		slot.shownOpacity = -1
		slot.shownCooldown = -1
		slot.shownSelected = nil
	end
end

local function chooseView()
	local view = if InputController:GetDevice() == "Touch" then views.Compact else views.Full
	if view ~= nil then
		showView(view)
	end
end

-- Updating ----------------------------------------------------------------------------------

local function smooth(current: number, target: number, rate: number, deltaTime: number): number
	return current + (target - current) * (1 - math.exp(-rate * deltaTime))
end

local function updateWillpower(view: View, deltaTime: number)
	local max = RingController:GetWillpowerMax()
	local willpower = RingController:GetWillpower()
	local fraction = math.clamp(willpower / max, 0, 1)
	local previous = shownWillpower
	shownWillpower = smooth(shownWillpower, fraction, config.Responsiveness, deltaTime)
	-- The trail holds where willpower was, then catches up.
	local now = os.clock()
	if shownWillpower < previous - 1e-4 and shownTrail <= previous + 1e-4 then
		trailHoldUntil = now + config.TrailDelay
	end
	if shownTrail < shownWillpower then
		shownTrail = shownWillpower
	elseif now >= trailHoldUntil then
		shownTrail = smooth(shownTrail, shownWillpower, config.TrailResponsiveness, deltaTime)
	end

	local bar = view.willpower
	bar.fill.Size = UDim2.fromScale(shownWillpower, 1)
	local trail = bar.trail
	if trail ~= nil then
		trail.Size = UDim2.fromScale(shownTrail, 1)
	end

	local below = fraction < RingConfig.Strength.FullAtWillpowerFraction
	if below ~= shownBelowThreshold then
		shownBelowThreshold = below
		bar.fill.BackgroundTransparency = if below then config.DimTransparency else 0
		bar.fill.BackgroundColor3 = if below then Theme.RingGreenDim else Theme.RingGreen
	end
	-- Breathing glow at full strength; none below it.
	bar.glow.Transparency = if below
		then 1
		else config.GlowTransparency + (1 - config.GlowTransparency) * 0.5 * (1 + math.sin(
			now * config.GlowPulseSpeed
		))
	bar.glow.Enabled = shownWillpower > 0.01

	local text = tostring(math.floor(willpower + 0.5))
	if text ~= lastWillpowerText then
		lastWillpowerText = text
		view.willpowerValue.Text = text
	end
end

local function updateCharge(view: View, deltaTime: number)
	local max = RingController:GetChargeMax()
	local charge = RingController:GetCharge()
	local fraction = math.clamp(charge / max, 0, 1)
	shownCharge = smooth(shownCharge, fraction, config.Responsiveness, deltaTime)
	local bar = view.charge
	bar.fill.Size = UDim2.fromScale(shownCharge, 1)

	local state: ChargeState = if charge <= 0
		then "Empty"
		elseif charge <= RingConfig.Charge.LowThreshold then "Low"
		else "Normal"
	if state ~= shownChargeState then
		shownChargeState = state
		local color = if state == "Normal" then Theme.RingGreen else Theme.Warning
		bar.fill.BackgroundColor3 = color
		bar.glow.Color = color
		bar.fill.BackgroundTransparency = 0
		bar.track.BackgroundColor3 = if state == "Empty" then Theme.DangerDim else Theme.PanelColor
		bar.track.BackgroundTransparency = if state == "Empty" then 0.1 else config.TrackTransparency
		view.chargeValue.TextColor3 = if state == "Empty"
			then Theme.Danger
			elseif state == "Low" then Theme.Warning
			else Theme.TextPrimary
		view.hint.Visible = state == "Empty"
		-- The hint takes its own row under the bars.
		local hintSpace = if state == "Empty" then view.layout.HintHeight else 0
		view.slotRow.Position = UDim2.new(0.5, 0, 0, view.slotRowTop + hintSpace)
		view.root.Size = UDim2.fromOffset(view.layout.Width, view.height + hintSpace)
	end
	if state == "Low" then
		-- Amber pulse.
		local pulse = 0.5 * (1 + math.sin(os.clock() * config.LowPulseSpeed))
		bar.fill.BackgroundTransparency = 0.45 * pulse
		bar.glow.Transparency = config.GlowTransparency + (1 - config.GlowTransparency) * pulse
	elseif state == "Normal" then
		bar.glow.Transparency = config.GlowTransparency
	end
	bar.glow.Enabled = state ~= "Empty"

	local text = string.format(Text.Ring.ChargeValue, math.floor(fraction * 100 + 0.5))
	if text ~= lastChargeText then
		lastChargeText = text
		view.chargeValue.Text = text
	end
end

local function setSlotOpacity(slot: Slot, opacity: number)
	for _, part in slot.icon do
		part.object.BackgroundTransparency = 1 - (1 - part.base) * opacity
		local stroke = part.stroke
		if stroke ~= nil then
			stroke.Transparency = 1 - opacity
		end
	end
	local name = slot.name
	if name ~= nil then
		name.TextTransparency = 1 - math.max(opacity, 0.5)
	end
end

local function updateSlot(slot: Slot, selected: Types.ConstructId)
	local powerId: Types.PowerId = slot.powerId
	local ok: boolean, reason: Types.PowerRejectReason? = RingController:CanAttempt(powerId, minWillpowerOf(powerId))
	local available = ok or reason == "Cooldown"
	local active = if powerId == "Beam"
		then PowerController:IsFiringBeam()
		elseif powerId == "Shield" then PowerController:IsShielding()
		else false

	local opacity = if active
		then 1
		elseif available then 1 - config.ActiveTransparency
		else 1 - config.UnavailableTransparency
	if opacity ~= slot.shownOpacity then
		slot.shownOpacity = opacity
		setSlotOpacity(slot, opacity)
		slot.frame.BackgroundColor3 = if active then Theme.RingGreenDim else Theme.PanelColor
	end

	local isSelected = isConstruct(powerId) and powerId == selected
	if isSelected ~= slot.shownSelected then
		slot.shownSelected = isSelected
		local pip = slot.pip
		if pip ~= nil then
			pip.Visible = isSelected
		end
	end
	local emphasised = isSelected or active
	slot.stroke.Thickness = if emphasised then config.SelectedStrokeThickness else config.SlotStrokeThickness
	slot.stroke.Transparency = if emphasised then 0 else 0.5

	local remaining = RingController:GetCooldownRemaining(powerId)
	-- Rounded to tenths so the text and overlay only change ten times a second.
	local shown = math.ceil(remaining * 10) / 10
	if shown ~= slot.shownCooldown then
		slot.shownCooldown = shown
		local cooling = shown > 0
		slot.cooldown.Visible = cooling
		slot.cooldownText.Visible = cooling
		if cooling then
			local fraction = math.clamp(remaining / math.max(cooldownOf(powerId), 0.01), 0, 1)
			slot.cooldown.Size = UDim2.fromScale(1, fraction)
			slot.cooldownText.Text = if shown >= 1 then tostring(math.ceil(shown)) else string.format("%.1f", shown)
		end
	end
end

local function isHidden(): boolean
	return next(hiddenReasons) ~= nil
end

local function step(deltaTime: number)
	local view = activeView
	if view == nil then
		return
	end
	local visible = not isHidden() and RingController:IsReady()
	if view.root.Visible ~= visible then
		view.root.Visible = visible
	end
	if not visible then
		return
	end
	updateWillpower(view, deltaTime)
	updateCharge(view, deltaTime)
	local selected: Types.ConstructId = PowerController:GetSelectedConstruct()
	for _, slot in view.slots do
		updateSlot(slot, selected)
	end
end

-- Feedback --------------------------------------------------------------------------------

local function buildFeedback(parent: ScreenGui)
	local feedbackConfig = config.Feedback
	local label = Create.label("PowerFeedback", "", Theme.FontBold, feedbackConfig.TextSize, Theme.Warning)
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0.5, feedbackConfig.OffsetY)
	label.Size = UDim2.new(1, -2 * UIConfig.ScreenMargin, 0, feedbackConfig.Height)
	label.TextTransparency = 1
	label.TextTruncate = Enum.TextTruncate.AtEnd
	Create.maxSize(label, feedbackConfig.MaxWidth)
	feedbackStroke = Create.textStroke(label, Theme.PanelColor, feedbackConfig.TextStrokeThickness, 1)
	local scale = Instance.new("UIScale")
	scale.Parent = label
	feedbackScale = scale
	label.Parent = parent
	feedbackLabel = label
end

local function stopFeedbackTweens()
	for _, tween in feedbackTweens do
		tween:Cancel()
	end
	table.clear(feedbackTweens)
end

local function hideFeedbackNow()
	stopFeedbackTweens()
	local thread = feedbackThread
	feedbackThread = nil
	if thread ~= nil and coroutine.status(thread) == "suspended" then
		task.cancel(thread)
	end
	local label = feedbackLabel
	local stroke = feedbackStroke
	if label ~= nil and stroke ~= nil then
		label.TextTransparency = 1
		stroke.Transparency = 1
	end
end

-- Shows a short message under the crosshair, replacing any current one.
function RingHudController.ShowFeedback(_self: RingHudController, text: string)
	local label = feedbackLabel
	local stroke = feedbackStroke
	local scale = feedbackScale
	if label == nil or stroke == nil or scale == nil or isHidden() then
		return
	end
	local feedbackConfig = config.Feedback
	hideFeedbackNow()
	label.Text = text
	label.TextTransparency = 0
	stroke.Transparency = feedbackConfig.TextStrokeTransparency
	scale.Scale = feedbackConfig.PopScale
	local pop = TweenService:Create(scale, TweenInfo.new(feedbackConfig.PopTime, Enum.EasingStyle.Back), { Scale = 1 })
	table.insert(feedbackTweens, pop)
	pop:Play()
	feedbackThread = task.delay(feedbackConfig.HoldTime, function()
		feedbackThread = nil
		local fade = TweenInfo.new(Theme.FadeTime, UIConfig.FadeEasingStyle, Enum.EasingDirection.Out)
		local textTween = TweenService:Create(label, fade, { TextTransparency = 1 })
		local strokeTween = TweenService:Create(stroke, fade, { Transparency = 1 })
		table.insert(feedbackTweens, textTween)
		table.insert(feedbackTweens, strokeTween)
		textTween:Play()
		strokeTween:Play()
	end)
end

-- Hides the HUD (and its feedback line) while any reason asks for it.
function RingHudController.SetHidden(_self: RingHudController, reason: string, hidden: boolean)
	if hidden then
		hiddenReasons[reason] = true
		hideFeedbackNow()
	else
		hiddenReasons[reason] = nil
	end
	local view = activeView
	if view ~= nil then
		view.root.Visible = not isHidden() and RingController:IsReady()
	end
end

function RingHudController.Init(self: RingHudController)
	local hud = HudController:GetRoot()
	views.Full = buildView("RingHud", config.Full, hud)
	views.Compact = buildView("RingHudCompact", config.Compact, hud)
	buildFeedback(hud)
	chooseView()

	InputController.DeviceChanged:Connect(chooseView)
	HudController.ScaleChanged:Connect(chooseView)
	hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local view = activeView
		if view ~= nil and view.layout.Stacked then
			placeCompact(view)
		end
	end)
	PowerController.SelectionChanged:Connect(function()
		local view = activeView
		if view ~= nil then
			refreshHints(view)
		end
	end)
	PowerController.Feedback:Connect(function(text: string)
		self:ShowFeedback(text)
	end)
	-- A fresh ring (or a rejoin) starts the bars full rather than gliding up from 0.
	LocalPlayer:GetAttributeChangedSignal(Attributes.WillpowerMax):Connect(function()
		shownWillpower = math.clamp(RingController:GetWillpower() / RingController:GetWillpowerMax(), 0, 1)
		shownTrail = shownWillpower
		shownCharge = math.clamp(RingController:GetCharge() / RingController:GetChargeMax(), 0, 1)
	end)
end

function RingHudController.Start(_self: RingHudController)
	RunService.RenderStepped:Connect(step)
end

export type RingHudController = typeof(RingHudController)

return RingHudController
