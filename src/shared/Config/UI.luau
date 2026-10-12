--!strict
--[[
	Client UI layout: sizes, spacing and opacities. Colours, fonts and timings
	live in Theme.luau.

	Every size is in pixels at UI scale 1, i.e. on a viewport Theme.ReferenceHeight
	tall; the HUD's UIScale resizes everything for the real screen. Keep text at
	13 px or more and anything tappable at 52 px or more (at scale 1), so on
	phones, which always run at Theme.MinScale, text stays at 11 px or more and
	tap targets at 44 px or more.
]]

local UI = {
	-- ScreenGui stacking order (higher draws on top). Touch buttons sit above the
	-- HUD so a toast or panel can never cover the button that closes it.
	DisplayOrder = {
		BoundaryWarning = 1,
		Hud = 10,
		TouchControls = 20,
	},

	-- Space kept between HUD elements and the edges of the safe area.
	ScreenMargin = 16,

	-- Easing for every fade.
	FadeEasingStyle = Enum.EasingStyle.Quad,

	-- Large district title shown under the top bar when entering a district.
	Banner = {
		Top = 6,
		MaxWidth = 560,
		TitleTextSize = 40,
		TitleHeight = 46,
		SubtitleTextSize = 20,
		SubtitleHeight = 24,
		-- Thin ring-green line between title and subtitle.
		AccentWidth = 96,
		AccentHeight = 3,
		Spacing = 4,
		PaddingY = 8,
		-- Dark band behind the text, faded out toward both ends, so the title
		-- stays readable against a bright sky.
		BackdropTransparency = 0.45,
		BackdropFadeWidth = 0.25,
		TextStrokeThickness = 1.5,
		TextStrokeTransparency = 0.5,
	},

	-- Toast notifications, stacked below the banner (newest on top).
	Toasts = {
		Top = 110,
		MaxWidth = 380,
		MaxVisible = 3,
		Spacing = 6,
		TextSize = 18,
		PaddingX = 14,
		PaddingY = 10,
		-- Coloured dot showing the kind (info / success / warning).
		DotSize = 10,
		DotGap = 10,
		StrokeThickness = 1.5,
		StrokeTransparency = 0.35,
	},

	-- Round on-screen action buttons (TouchControls).
	TouchButton = {
		TextSize = 16,
		StrokeThickness = 2,
		PressedTransparency = 0.05,
	},

	DistrictsPanel = {
		-- Drawn above the banner and toasts (all children of the HUD).
		ZIndex = 2,
		MaxWidth = 400,
		MaxHeight = 620,
		Padding = 16,
		StrokeThickness = 1.5,
		TitleTextSize = 24,
		TitleHeight = 28,
		ProgressTextSize = 16,
		ProgressHeight = 20,
		ProgressBarHeight = 4,
		ProgressBarTransparency = 0.8,
		-- Room for the title, progress text and bar, HeaderSpacing apart.
		HeaderHeight = 64,
		HeaderSpacing = 4,
		SectionGap = 8,
		RowSpacing = 6,
		RowPaddingX = 12,
		RowPaddingTop = 6,
		RowPaddingBottom = 8,
		RowTransparency = 0.94,
		CurrentRowTransparency = 0.88,
		CurrentStrokeThickness = 2,
		-- Discovered / undiscovered badge left of each name. The name line is the
		-- same height so the badge lines up with it.
		BadgeSize = 26,
		BadgeGap = 12,
		BadgeStrokeThickness = 1.5,
		CheckThickness = 3,
		NameTextSize = 18,
		SubtitleTextSize = 15,
		TagTextSize = 14,
		TagWidth = 96,
		TagHeight = 22,
		ScrollBarThickness = 6,
		CloseButtonHeight = 52,
		CloseTextSize = 18,
		-- Controller button glyph at the right end of the Close button (gamepad only).
		CloseGlyphSize = 28,
		CloseGlyphInset = 12,
		-- The panel grows from this scale to full size as it opens.
		OpenFromScale = 0.94,
	},

	-- Warning overlay near the edge of the play area (Config.World.Boundary).
	Boundary = {
		-- Thickness of the edge glow, as a fraction of the screen.
		VignetteSize = 0.22,
		-- Glow opacity at the hard edge (it grows with depth into the soft band).
		VignetteMaxOpacity = 0.55,
		-- Depth into the soft band at which the warning text is fully visible.
		TextFullDepth = 0.25,
		-- Vertical position of the warning text (fraction of the screen height):
		-- below the character, between the touch thumbstick and jump button.
		TextPositionY = 0.72,
		TitleTextSize = 28,
		TitleHeight = 34,
		HintTextSize = 18,
		HintHeight = 22,
		MaxWidth = 520,
		TextStrokeThickness = 1.5,
		TextStrokeTransparency = 0.35,
	},
}

return UI
