--!strict
--[[
	NotificationController: toasts and the district banner.

	Toasts are short messages stacked under the banner, newest on top. At most
	Config.UI.Toasts.MaxVisible show at once: a new one pushes the oldest out
	early. Each fades in, holds for Theme.ToastHoldTime, then fades out. The
	server sends them with Remotes.Notify; client code calls Notify directly.

	The banner is a large centred title (e.g. a district name) right under the
	top bar. It fades in, holds for Theme.BannerHoldTime and fades out; a new
	banner replaces the current one immediately.

	API:
	  NotificationController:Notify(message, kind)
	  NotificationController:ShowBanner(title, subtitle)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Theme = require(Shared.Config.Theme)
local Types = require(Shared.Types)
local UIConfig = require(Shared.Config.UI)

local Create = require(script.Parent.Parent.UI.Create)
local Fader = require(script.Parent.Parent.UI.Fader)
local HudController = require(script.Parent.HudController)

type Toast = {
	frame: Frame,
	fader: Fader.Fader,
	dismissed: boolean,
	expireThread: thread?,
}

type Banner = {
	title: TextLabel,
	subtitle: TextLabel,
	fader: Fader.Fader,
}

local KIND_COLORS: { [Types.NotifyKind]: Color3 } = {
	Info = Theme.Info,
	Success = Theme.Success,
	Warning = Theme.Warning,
}

local toastStack: Frame? = nil
-- Oldest first.
local toasts: { Toast } = {}
-- Counts down so each new toast sorts above the previous ones.
local nextLayoutOrder = 0

local banner: Banner? = nil
local bannerHideThread: thread? = nil

local NotificationController = {}

local function cancelThread(thread: thread?)
	-- A thread cannot cancel itself, and finished threads need no cancelling.
	if thread ~= nil and thread ~= coroutine.running() and coroutine.status(thread) == "suspended" then
		task.cancel(thread)
	end
end

local function buildToastStack(parent: ScreenGui): Frame
	local config = UIConfig.Toasts
	local stack = Create.frame("Toasts")
	stack.AnchorPoint = Vector2.new(0.5, 0)
	stack.Position = UDim2.new(0.5, 0, 0, config.Top)
	stack.Size = UDim2.new(1, -2 * UIConfig.ScreenMargin, 0, 0)
	stack.AutomaticSize = Enum.AutomaticSize.Y
	Create.maxSize(stack, config.MaxWidth)
	local layout = Create.list(stack, Enum.FillDirection.Vertical, config.Spacing)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	stack.Parent = parent
	return stack
end

local function buildToast(message: string, kind: Types.NotifyKind, layoutOrder: number): Frame
	local config = UIConfig.Toasts
	local color = KIND_COLORS[kind]

	local frame = Create.panel("Toast")
	frame.Size = UDim2.fromScale(1, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.LayoutOrder = layoutOrder
	Create.corner(frame)
	Create.stroke(frame, color, config.StrokeThickness, config.StrokeTransparency)
	Create.padding(frame, config.PaddingX, config.PaddingY)

	-- Kind dot, vertically centred on the message.
	local dot = Create.frame("Kind")
	dot.BackgroundColor3 = color
	dot.BackgroundTransparency = 0
	dot.AnchorPoint = Vector2.new(0, 0.5)
	dot.Position = UDim2.fromScale(0, 0.5)
	dot.Size = UDim2.fromOffset(config.DotSize, config.DotSize)
	Create.corner(dot, UDim.new(0.5, 0))
	dot.Parent = frame

	local textOffset = config.DotSize + config.DotGap
	local label = Create.label("Message", message, Theme.Font, config.TextSize, Theme.TextPrimary)
	label.Position = UDim2.fromOffset(textOffset, 0)
	label.Size = UDim2.new(1, -textOffset, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = frame

	return frame
end

local function dismiss(toast: Toast)
	if toast.dismissed then
		return
	end
	toast.dismissed = true
	cancelThread(toast.expireThread)
	toast.fader:Hide(Theme.FadeTime)
	task.delay(Theme.FadeTime, function()
		local index = table.find(toasts, toast)
		if index ~= nil then
			table.remove(toasts, index)
		end
		toast.frame:Destroy()
	end)
end

local function buildBanner(parent: ScreenGui): Banner
	local config = UIConfig.Banner
	local height = config.PaddingY * 2
		+ config.TitleHeight
		+ config.AccentHeight
		+ config.SubtitleHeight
		+ config.Spacing * 2

	local frame = Create.frame("Banner")
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, config.Top)
	frame.Size = UDim2.new(1, -2 * UIConfig.ScreenMargin, 0, height)
	Create.maxSize(frame, config.MaxWidth)

	-- Dark band behind the text that fades out toward both ends.
	local backdrop = Create.frame("Backdrop")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.PanelColor
	backdrop.BackgroundTransparency = config.BackdropTransparency
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(config.BackdropFadeWidth, 0),
		NumberSequenceKeypoint.new(1 - config.BackdropFadeWidth, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = backdrop
	backdrop.Parent = frame

	local content = Create.frame("Content")
	content.Size = UDim2.fromScale(1, 1)
	local layout = Create.list(content, Enum.FillDirection.Vertical, config.Spacing)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center

	local title = Create.label("Title", "", Theme.FontBold, config.TitleTextSize, Theme.TextPrimary)
	title.Size = UDim2.new(1, 0, 0, config.TitleHeight)
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.LayoutOrder = 1
	Create.textStroke(title, Theme.PanelColor, config.TextStrokeThickness, config.TextStrokeTransparency)
	title.Parent = content

	local accent = Create.frame("Accent")
	accent.Size = UDim2.fromOffset(config.AccentWidth, config.AccentHeight)
	accent.BackgroundColor3 = Theme.RingGreen
	accent.BackgroundTransparency = 0
	accent.LayoutOrder = 2
	Create.corner(accent, UDim.new(0.5, 0))
	accent.Parent = content

	local subtitle = Create.label("Subtitle", "", Theme.Font, config.SubtitleTextSize, Theme.TextSecondary)
	subtitle.Size = UDim2.new(1, 0, 0, config.SubtitleHeight)
	subtitle.TextTruncate = Enum.TextTruncate.AtEnd
	subtitle.LayoutOrder = 3
	Create.textStroke(subtitle, Theme.PanelColor, config.TextStrokeThickness, config.TextStrokeTransparency)
	subtitle.Parent = content

	content.Parent = frame
	-- Wrap before parenting so the banner never appears for a frame on join.
	local fader = Fader.new(frame)
	frame.Parent = parent
	return { title = title, subtitle = subtitle, fader = fader }
end

-- Shows a short message. kind picks the colour: "Info", "Success" or "Warning".
function NotificationController.Notify(_self: NotificationController, message: string, kind: Types.NotifyKind)
	local stack = toastStack
	if stack == nil then
		warn(`[NotificationController] Notify before Init: {message}`)
		return
	end

	-- Make room first, so at most MaxVisible toasts are ever showing.
	local active: { Toast } = {}
	for _, toast in toasts do
		if not toast.dismissed then
			table.insert(active, toast)
		end
	end
	for index = 1, #active - UIConfig.Toasts.MaxVisible + 1 do
		dismiss(active[index])
	end

	nextLayoutOrder -= 1
	local frame = buildToast(message, kind, nextLayoutOrder)
	local toast: Toast = {
		frame = frame,
		fader = Fader.new(frame),
		dismissed = false,
		expireThread = nil,
	}
	frame.Parent = stack
	table.insert(toasts, toast)
	toast.fader:Show(Theme.FadeTime)
	toast.expireThread = task.delay(Theme.FadeTime + Theme.ToastHoldTime, dismiss, toast)
end

-- Shows a large centred title under the top bar, replacing any current one.
function NotificationController.ShowBanner(_self: NotificationController, title: string, subtitle: string)
	local current = banner
	if current == nil then
		return
	end
	cancelThread(bannerHideThread)
	current.title.Text = title
	current.subtitle.Text = subtitle
	current.fader:HideNow()
	current.fader:Show(Theme.FadeTime)
	bannerHideThread = task.delay(Theme.FadeTime + Theme.BannerHoldTime, function()
		bannerHideThread = nil
		current.fader:Hide(Theme.FadeTime)
	end)
end

function NotificationController.Init(self: NotificationController)
	local root = HudController:GetRoot()
	banner = buildBanner(root)
	toastStack = buildToastStack(root)

	Remotes.Notify:Connect(function(message: string, kind: Types.NotifyKind)
		-- From the server, so trusted; still never let a malformed message break the UI.
		if type(message) ~= "string" then
			return
		end
		local safeKind: Types.NotifyKind = if kind == "Success" or kind == "Warning" then kind else "Info"
		self:Notify(message, safeKind)
	end)
end

function NotificationController.Start(_self: NotificationController) end

export type NotificationController = typeof(NotificationController)

return NotificationController
