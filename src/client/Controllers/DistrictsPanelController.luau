--!strict
--[[
	DistrictsPanelController: the "Districts" panel (exploration progress).

	Lists every district of Config.World.Districts in order. Discovered ones show
	their name and subtitle with a tick; undiscovered ones show "???". The
	district the player is in is highlighted, and the header shows "Discovered
	X / Y" with a progress bar. The panel updates live while open.

	Opened and closed with the "ToggleDistricts" action (M key, gamepad D-pad up,
	touch "Map" button). While open, the "CloseMenu" action (gamepad B) and the
	Close button at the bottom (tap or click) close it too. The Close button
	sits at the bottom, under the player's thumbs and away from the top-right
	Map button, and names the close key of the current device.

	Layout (HUD safe area, pixels at UI scale 1): a centred glass card filling
	the screen minus Config.UI.ScreenMargin on each side, capped at
	DistrictsPanel.MaxWidth x MaxHeight. Header (title, progress text, progress
	bar) on top, a scrolling list of rows in the middle, the Close button along
	the bottom. On short phone screens the list scrolls.

	API:
	  DistrictsPanelController:Open() / :Close() / :Toggle()
	  DistrictsPanelController:IsOpen(): boolean
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local InputConfig = require(Shared.Config.Input)
local Text = require(Shared.Config.Text)
local Theme = require(Shared.Config.Theme)
local Types = require(Shared.Types)
local UIConfig = require(Shared.Config.UI)
local WorldConfig = require(Shared.Config.World)

local Create = require(script.Parent.Parent.UI.Create)
local HudController = require(script.Parent.HudController)
local InputController = require(script.Parent.InputController)
local ZoneController = require(script.Parent.ZoneController)

type Row = {
	frame: Frame,
	stroke: UIStroke,
	discoveredBadge: Frame,
	undiscoveredBadge: Frame,
	name: TextLabel,
	subtitle: TextLabel,
	tag: TextLabel,
}

type Panel = {
	frame: Frame,
	openScale: UIScale,
	progressLabel: TextLabel,
	progressFill: Frame,
	closeButton: TextButton,
	closeGlyph: ImageLabel,
	rows: { [string]: Row },
}

local config = UIConfig.DistrictsPanel
local strings = Text.DistrictsPanel

local panel: Panel? = nil
local isOpen = false

local DistrictsPanelController = {}

-- One straight, round-ended bar from `from` to `to` (pixels inside `parent`).
local function addBar(parent: Frame, from: Vector2, to: Vector2, thickness: number)
	local delta = to - from
	local bar = Create.frame("Bar")
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Position = UDim2.fromOffset((from.X + to.X) / 2, (from.Y + to.Y) / 2)
	-- Lengthened by the thickness so the two legs of the tick overlap at the corner.
	bar.Size = UDim2.fromOffset(delta.Magnitude + thickness, thickness)
	-- GuiObject rotation is clockwise in degrees, like atan2 with screen Y pointing down.
	bar.Rotation = math.deg(math.atan2(delta.Y, delta.X))
	bar.BackgroundColor3 = Theme.PanelColor
	bar.BackgroundTransparency = 0
	Create.corner(bar, UDim.new(0.5, 0))
	bar.Parent = parent
end

-- Filled ring-green circle with a tick drawn from two bars, so it never depends
-- on the font having a check-mark glyph.
local function buildDiscoveredBadge(): Frame
	local size = config.BadgeSize
	local badge = Create.frame("Discovered")
	badge.Size = UDim2.fromOffset(size, size)
	badge.BackgroundColor3 = Theme.RingGreen
	badge.BackgroundTransparency = 0
	Create.corner(badge, UDim.new(0.5, 0))
	-- Tick corners as fractions of the badge size: a short leg down to the
	-- bottom point, then a long leg up to the right.
	local left = Vector2.new(0.28, 0.52) * size
	local bottom = Vector2.new(0.43, 0.67) * size
	local right = Vector2.new(0.73, 0.36) * size
	addBar(badge, left, bottom, config.CheckThickness)
	addBar(badge, bottom, right, config.CheckThickness)
	return badge
end

local function buildUndiscoveredBadge(): Frame
	local size = config.BadgeSize
	local badge = Create.frame("Undiscovered")
	badge.Size = UDim2.fromOffset(size, size)
	Create.corner(badge, UDim.new(0.5, 0))
	Create.stroke(badge, Theme.TextSecondary, config.BadgeStrokeThickness)
	local mark =
		Create.label("Mark", strings.UndiscoveredIcon, Theme.FontBold, config.NameTextSize, Theme.TextSecondary)
	mark.Size = UDim2.fromScale(1, 1)
	mark.Parent = badge
	return badge
end

local function buildRow(district: Types.DistrictInfo, layoutOrder: number, parent: ScrollingFrame): Row
	local frame = Create.frame(district.Id)
	frame.Size = UDim2.fromScale(1, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = Theme.TextPrimary
	frame.BackgroundTransparency = config.RowTransparency
	frame.LayoutOrder = layoutOrder
	Create.corner(frame)
	Create.padding(frame, config.RowPaddingX, config.RowPaddingTop, config.RowPaddingBottom)
	local stroke = Create.stroke(frame, Theme.RingGreen, config.CurrentStrokeThickness)
	stroke.Enabled = false

	-- Both badges exist; refresh shows one. They line up with the name line.
	local discoveredBadge = buildDiscoveredBadge()
	discoveredBadge.Parent = frame
	local undiscoveredBadge = buildUndiscoveredBadge()
	undiscoveredBadge.Parent = frame

	local textOffset = config.BadgeSize + config.BadgeGap
	local column = Create.frame("Text")
	column.Position = UDim2.fromOffset(textOffset, 0)
	column.Size = UDim2.new(1, -textOffset, 0, 0)
	column.AutomaticSize = Enum.AutomaticSize.Y
	Create.list(column, Enum.FillDirection.Vertical, 0)

	-- Name line: as tall as the badge, with the "You are here" tag on its right.
	local nameLine = Create.frame("NameLine")
	nameLine.Size = UDim2.new(1, 0, 0, config.BadgeSize)
	nameLine.LayoutOrder = 1

	local name = Create.label("Name", "", Theme.FontBold, config.NameTextSize, Theme.TextPrimary)
	name.Size = UDim2.fromScale(1, 1)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Parent = nameLine

	local tag = Create.label("Here", strings.CurrentTag, Theme.FontBold, config.TagTextSize, Theme.PanelColor)
	tag.AnchorPoint = Vector2.new(1, 0.5)
	tag.Position = UDim2.fromScale(1, 0.5)
	tag.Size = UDim2.fromOffset(config.TagWidth, config.TagHeight)
	tag.BackgroundColor3 = Theme.RingGreen
	tag.BackgroundTransparency = 0
	tag.Visible = false
	Create.corner(tag, UDim.new(0.5, 0))
	tag.Parent = nameLine
	nameLine.Parent = column

	-- Full width under the name and wrapped, so long subtitles are never cut off.
	local subtitle = Create.label("Subtitle", "", Theme.Font, config.SubtitleTextSize, Theme.TextSecondary)
	subtitle.Size = UDim2.fromScale(1, 0)
	subtitle.AutomaticSize = Enum.AutomaticSize.Y
	subtitle.TextWrapped = true
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.LayoutOrder = 2
	subtitle.Parent = column

	column.Parent = frame
	frame.Parent = parent

	return {
		frame = frame,
		stroke = stroke,
		discoveredBadge = discoveredBadge,
		undiscoveredBadge = undiscoveredBadge,
		name = name,
		subtitle = subtitle,
		tag = tag,
	}
end

-- The Close button names the real binding rather than a hard-coded key: on a
-- keyboard the ToggleDistricts key as printed on the player's layout (KeyCodes
-- are US-layout positions, so KeyCode.M is "," on AZERTY), on a controller the
-- CloseMenu button's own glyph (B on Xbox, Circle on PlayStation).
local function closeLabel(device: Types.InputDevice): string
	if device == "KeyboardMouse" then
		local key = InputConfig.Actions.ToggleDistricts.Keyboard[1]
		if key == nil then
			return strings.Close.Touch
		end
		-- Keys that type no character (e.g. Tab) have no layout string; use the key's name.
		local keyName = UserInputService:GetStringForKeyCode(key)
		return string.format(strings.Close.KeyboardMouse, if keyName ~= "" then keyName else key.Name)
	end
	return strings.Close[device]
end

local function showCloseHint(current: Panel, device: Types.InputDevice)
	current.closeButton.Text = closeLabel(device)
	local button = InputConfig.Actions.CloseMenu.Gamepad[1]
	if device == "Gamepad" and button ~= nil then
		-- Asked again on every change: the glyph follows the last controller connected.
		current.closeGlyph.Image = UserInputService:GetImageForKeyCode(button)
		current.closeGlyph.Visible = true
	else
		current.closeGlyph.Visible = false
	end
end

local function buildPanel(parent: ScreenGui, onClose: () -> ()): Panel
	local frame = Create.panel("DistrictsPanel")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.new(1, -2 * UIConfig.ScreenMargin, 1, -2 * UIConfig.ScreenMargin)
	frame.ZIndex = config.ZIndex
	-- Swallows touches and clicks so dragging on the panel never turns the camera.
	frame.Active = true
	frame.Visible = false
	Create.maxSize(frame, config.MaxWidth, config.MaxHeight)
	Create.corner(frame)
	Create.stroke(frame, Theme.RingGreenDim, config.StrokeThickness)
	Create.padding(frame, config.Padding, config.Padding)

	local openScale = Instance.new("UIScale")
	openScale.Parent = frame

	-- Header: title, "Discovered X / Y", progress bar.
	local header = Create.frame("Header")
	header.Size = UDim2.new(1, 0, 0, config.HeaderHeight)
	Create.list(header, Enum.FillDirection.Vertical, config.HeaderSpacing)

	local title = Create.label("Title", strings.Title, Theme.FontBold, config.TitleTextSize, Theme.TextPrimary)
	title.Size = UDim2.new(1, 0, 0, config.TitleHeight)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.LayoutOrder = 1
	title.Parent = header

	local progressLabel = Create.label("Progress", "", Theme.Font, config.ProgressTextSize, Theme.RingGreen)
	progressLabel.Size = UDim2.new(1, 0, 0, config.ProgressHeight)
	progressLabel.TextXAlignment = Enum.TextXAlignment.Left
	progressLabel.LayoutOrder = 2
	progressLabel.Parent = header

	local progressBar = Create.frame("ProgressBar")
	progressBar.Size = UDim2.new(1, 0, 0, config.ProgressBarHeight)
	progressBar.BackgroundColor3 = Theme.TextSecondary
	progressBar.BackgroundTransparency = config.ProgressBarTransparency
	progressBar.LayoutOrder = 3
	Create.corner(progressBar, UDim.new(0.5, 0))
	local progressFill = Create.frame("Fill")
	progressFill.Size = UDim2.fromScale(0, 1)
	progressFill.BackgroundColor3 = Theme.RingGreen
	progressFill.BackgroundTransparency = 0
	Create.corner(progressFill, UDim.new(0.5, 0))
	progressFill.Parent = progressBar
	progressBar.Parent = header
	header.Parent = frame

	-- Scrolling list between the header and the Close button.
	local listTop = config.HeaderHeight + config.SectionGap
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Position = UDim2.fromOffset(0, listTop)
	list.Size = UDim2.new(1, 0, 1, -(listTop + config.SectionGap + config.CloseButtonHeight))
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = config.ScrollBarThickness
	list.ScrollBarImageColor3 = Theme.RingGreenDim
	-- Rows shrink to make room for the scroll bar instead of running under it.
	list.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	Create.list(list, Enum.FillDirection.Vertical, config.RowSpacing)
	-- The current row's outline is drawn outside the row; keep it inside the
	-- list's clipping area.
	Create.padding(list, config.CurrentStrokeThickness, config.CurrentStrokeThickness)

	local rows: { [string]: Row } = {}
	for index, district in WorldConfig.Districts do
		rows[district.Id] = buildRow(district, index, list)
	end
	list.Parent = frame

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "Close"
	closeButton.AnchorPoint = Vector2.new(0.5, 1)
	closeButton.Position = UDim2.fromScale(0.5, 1)
	closeButton.Size = UDim2.new(1, 0, 0, config.CloseButtonHeight)
	closeButton.BackgroundColor3 = Theme.RingGreen
	closeButton.BorderSizePixel = 0
	-- The engine's own hover/press shading is enough feedback here.
	closeButton.AutoButtonColor = true
	closeButton.FontFace = Theme.FontBold
	closeButton.TextSize = config.CloseTextSize
	closeButton.TextColor3 = Theme.PanelColor
	Create.corner(closeButton)
	-- Activated fires once per click or tap on every device.
	closeButton.Activated:Connect(onClose)
	closeButton.Parent = frame

	local closeGlyph = Instance.new("ImageLabel")
	closeGlyph.Name = "Glyph"
	closeGlyph.BackgroundTransparency = 1
	closeGlyph.AnchorPoint = Vector2.new(1, 0.5)
	closeGlyph.Position = UDim2.new(1, -config.CloseGlyphInset, 0.5, 0)
	closeGlyph.Size = UDim2.fromOffset(config.CloseGlyphSize, config.CloseGlyphSize)
	closeGlyph.Visible = false
	closeGlyph.Parent = closeButton

	frame.Parent = parent

	local built: Panel = {
		frame = frame,
		openScale = openScale,
		progressLabel = progressLabel,
		progressFill = progressFill,
		closeButton = closeButton,
		closeGlyph = closeGlyph,
		rows = rows,
	}
	showCloseHint(built, InputController:GetDevice())
	return built
end

local function refresh()
	local current = panel
	if current == nil or not isOpen then
		return
	end
	local here = ZoneController:GetCurrentDistrict()
	for _, district in WorldConfig.Districts do
		local row = current.rows[district.Id]
		local known = ZoneController:IsDiscovered(district.Id)
		local isHere = district.Id == here

		row.discoveredBadge.Visible = known
		row.undiscoveredBadge.Visible = not known
		row.name.Text = if known then district.DisplayName else strings.UndiscoveredName
		row.name.TextColor3 = if known then Theme.TextPrimary else Theme.TextSecondary
		row.subtitle.Text = if known then district.Subtitle else strings.UndiscoveredSubtitle

		row.frame.BackgroundColor3 = if isHere then Theme.RingGreen else Theme.TextPrimary
		row.frame.BackgroundTransparency = if isHere then config.CurrentRowTransparency else config.RowTransparency
		row.stroke.Enabled = isHere
		row.tag.Visible = isHere
		-- Leave room for the tag so a long name never runs under it.
		row.name.Size = if isHere
			then UDim2.new(1, -(config.TagWidth + config.BadgeGap), 1, 0)
			else UDim2.fromScale(1, 1)
	end

	local count = ZoneController:GetDiscoveredCount()
	local total = #WorldConfig.Districts
	current.progressLabel.Text = string.format(strings.Progress, count, total)
	current.progressFill.Size = UDim2.fromScale(if total > 0 then count / total else 0, 1)
end

function DistrictsPanelController.IsOpen(_self: DistrictsPanelController): boolean
	return isOpen
end

function DistrictsPanelController.Open(self: DistrictsPanelController)
	local current = panel
	if current == nil or isOpen then
		return
	end
	isOpen = true
	refresh()
	current.frame.Visible = true
	current.openScale.Scale = config.OpenFromScale
	TweenService:Create(
		current.openScale,
		TweenInfo.new(Theme.FadeTime, UIConfig.FadeEasingStyle, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()
	InputController:BindAction("CloseMenu", function(phase: Types.ActionPhase)
		if phase == "Begin" then
			self:Close()
		end
	end)
end

function DistrictsPanelController.Close(_self: DistrictsPanelController)
	local current = panel
	if current == nil or not isOpen then
		return
	end
	isOpen = false
	current.frame.Visible = false
	InputController:UnbindAction("CloseMenu")
end

function DistrictsPanelController.Toggle(self: DistrictsPanelController)
	if isOpen then
		self:Close()
	else
		self:Open()
	end
end

function DistrictsPanelController.Init(self: DistrictsPanelController)
	local built = buildPanel(HudController:GetRoot(), function()
		self:Close()
	end)
	panel = built

	InputController:BindAction("ToggleDistricts", function(phase: Types.ActionPhase)
		if phase == "Begin" then
			self:Toggle()
		end
	end)
	InputController.DeviceChanged:Connect(function(device: Types.InputDevice)
		showCloseHint(built, device)
	end)
	ZoneController.DistrictChanged:Connect(refresh)
	ZoneController.DiscoveredChanged:Connect(refresh)
end

function DistrictsPanelController.Start(_self: DistrictsPanelController) end

export type DistrictsPanelController = typeof(DistrictsPanelController)

return DistrictsPanelController
