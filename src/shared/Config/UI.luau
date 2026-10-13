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
		-- Boost speed streaks around the screen edges (under the crosshair and HUD).
		SpeedStreaks = 2,
		Hud = 10,
		TouchControls = 20,
		-- The oath moment's letterbox and text cover everything (the HUD and
		-- touch buttons are hidden while it plays anyway).
		Oath = 30,
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

	--[[
		Ring HUD (RingHudController): willpower bar, ring charge meter and the
		power slots, plus a short feedback line under the crosshair.

		Keyboard / gamepad use the Full layout: a panel centred at the bottom of
		the screen (clear of the chat and player list at the top corners, the
		banner and toasts at the top-centre and the crosshair in the middle).
		Touch uses the Compact layout at the top-left, under the top bar: clear of
		the thumbstick (bottom-left), the power buttons (bottom-right) and the Map
		button (top-right). Where the screen is too narrow for it to fit left of
		the district banner, it moves down below the banner.
	]]
	RingHud = {
		Full = {
			Width = 360,
			Padding = 10,
			-- Willpower and charge sit side by side (Stacked = false): the charge
			-- column is ChargeWidth wide, ColumnGap from the willpower bar.
			Stacked = false,
			ChargeWidth = 96,
			ColumnGap = 16,
			HeaderHeight = 16,
			LabelTextSize = 13,
			ValueTextSize = 15,
			WillpowerBarHeight = 10,
			ChargeBarHeight = 6,
			HintHeight = 18,
			HintTextSize = 13,
			RowGap = 8,
			SlotSize = 50,
			SlotGap = 8,
			-- Space between Beam / Shield and the constructs. On a controller the
			-- previous / next construct buttons sit in it and just past the last
			-- construct, so keep it at least GlyphSize + 8.
			GroupGap = 30,
			ShowSlotNames = true,
			SlotNameTextSize = 13,
			-- Key or controller button under each slot (none on touch).
			KeyHintHeight = 20,
			KeyHintTextSize = 13,
			GlyphSize = 22,
			CooldownTextSize = 15,
		},
		Compact = {
			Width = 184,
			Padding = 8,
			Stacked = true,
			ChargeWidth = 0,
			ColumnGap = 0,
			HeaderHeight = 15,
			LabelTextSize = 13,
			ValueTextSize = 13,
			WillpowerBarHeight = 8,
			ChargeBarHeight = 5,
			HintHeight = 30,
			HintTextSize = 13,
			RowGap = 5,
			SlotSize = 28,
			SlotGap = 5,
			GroupGap = 8,
			ShowSlotNames = false,
			SlotNameTextSize = 13,
			KeyHintHeight = 0,
			KeyHintTextSize = 13,
			GlyphSize = 0,
			CooldownTextSize = 13,
		},
		PanelTransparency = 0.38,
		StrokeTransparency = 0.65,
		StrokeThickness = 1,
		-- Bars.
		TrackTransparency = 0.55,
		-- The shown values glide toward the real ones at this rate.
		Responsiveness = 10,
		-- A pale "drain trail" lingers where willpower just was, then catches up
		-- after TrailDelay seconds at TrailResponsiveness.
		TrailDelay = 0.35,
		TrailResponsiveness = 5,
		TrailTransparency = 0.55,
		-- Below the full-strength threshold the fill dims to this transparency.
		DimTransparency = 0.4,
		-- The full-strength marker: a thin notch overhanging the bar.
		MarkerWidth = 2,
		MarkerOverhang = 3,
		-- Glow around the fill (UIStroke) and its slow breathing.
		GlowThickness = 2,
		GlowTransparency = 0.55,
		GlowPulseSpeed = 2.4,
		-- Low charge pulses (radians per second of the pulse).
		LowPulseSpeed = 6,
		-- Slots.
		SlotCornerRadius = 8,
		SlotStrokeThickness = 1.2,
		SelectedStrokeThickness = 2.5,
		-- Icon size as a fraction of the slot.
		IconScale = 0.5,
		CooldownOverlayTransparency = 0.3,
		UnavailableTransparency = 0.65,
		ActiveTransparency = 0.15,

		-- Short message under the crosshair when a power is refused.
		Feedback = {
			-- Pixels below the centre of the screen.
			OffsetY = 72,
			Height = 24,
			MaxWidth = 440,
			TextSize = 18,
			HoldTime = 1.3,
			PopScale = 1.12,
			PopTime = 0.12,
			TextStrokeThickness = 1.5,
			TextStrokeTransparency = 0.35,
		},
	},

	-- The oath moment at the ring battery (OathController).
	Oath = {
		-- Black bars at the top and bottom (fraction of the screen height each),
		-- sliding in over LetterboxTime.
		LetterboxHeight = 0.11,
		LetterboxTime = 0.6,
		-- Darkened screen edges.
		VignetteSize = 0.3,
		VignetteOpacity = 0.6,
		-- The oath lines, one at a time, centred at LinePositionY (fraction of the
		-- screen height). Each fades in LineFadeTime seconds; the first appears
		-- LineLead seconds in.
		LinePositionY = 0.7,
		LineTextSize = 34,
		LineHeight = 46,
		LineMaxWidth = 820,
		LineFadeTime = 0.6,
		LineLead = 0.35,
		-- Pixels each line rises as it fades in.
		LineRise = 10,
		-- Soft green glow around the letters.
		LineGlowThickness = 3,
		LineGlowTransparency = 0.5,
		-- The charge meter just above the bottom bar.
		MeterWidth = 280,
		MeterHeight = 4,
		MeterGap = 10,
		MeterLabelTextSize = 14,
		MeterLabelHeight = 18,
		MeterLabelGap = 4,
		MeterTrackTransparency = 0.75,
		-- How quickly the meter's fill follows the charge.
		MeterResponsiveness = 8,
		-- Green flash when the oath completes / quick dark fade when interrupted.
		FlashTransparency = 0.15,
		FlashTime = 0.9,
		InterruptFadeTime = 0.35,
		InterruptFadeTransparency = 0.35,
		-- How long the overlay takes to fade away at the end.
		FadeOutTime = 0.5,
		-- If the end message never arrives, the moment ends this many seconds
		-- after its duration anyway.
		EndGrace = 3,

		-- The cinematic camera: a 3/4 shot from in front of the player, slowly
		-- pushing in from StartDistance to EndDistance (studs from the focus point,
		-- which sits FocusBlend of the way from the player's chest to the battery),
		-- Height studs above it, drifting OrbitDegrees around it on the way.
		Camera = {
			FocusBlend = 0.35,
			ChestHeight = 1.5,
			StartDistance = 12,
			EndDistance = 7.5,
			Height = 1.2,
			-- 45 = a true 3/4 view of the player's face.
			AngleDegrees = 45,
			OrbitDegrees = 8,
			-- Studs kept between the camera and any wall; shots with less room
			-- than MinDistance are skipped in favour of another angle.
			WallPadding = 0.8,
			MinDistance = 4,
			-- Never closer to the focus than this, however tight the room.
			NearestDistance = 0.5,
			StartFov = 60,
			EndFov = 52,
			-- Without a character to frame, the shot centres this many studs in
			-- front of the battery.
			FallbackDistance = 4,
		},
	},
}

return UI
