--!strict
-- UI look: colours, fonts, animation timings. Original palette (ring green on dark glass).

local Theme = {
	RingGreen = Color3.fromRGB(64, 255, 128),
	RingGreenDim = Color3.fromRGB(30, 150, 75),
	PanelColor = Color3.fromRGB(10, 18, 14),
	PanelTransparency = 0.2,
	TextPrimary = Color3.fromRGB(236, 246, 239),
	TextSecondary = Color3.fromRGB(160, 186, 170),
	Warning = Color3.fromRGB(255, 196, 64),
	Success = Color3.fromRGB(64, 255, 128),
	Info = Color3.fromRGB(150, 210, 255),
	-- An empty ring (no charge left): the HUD's charge meter turns this dark red.
	Danger = Color3.fromRGB(235, 82, 70),
	DangerDim = Color3.fromRGB(70, 18, 16),

	Font = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Regular),
	FontBold = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold),
	-- The oath lines at the ring battery: a calm serif.
	FontOath = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Regular),

	CornerRadius = UDim.new(0, 10),

	-- Seconds
	FadeTime = 0.35,
	BannerHoldTime = 2.5,
	ToastHoldTime = 4,

	-- UI is designed at this viewport height and scaled to the real one.
	ReferenceHeight = 720,
	-- Phones in landscape are always short enough to bottom out here, so this
	-- keeps 52 px tap targets at 44 px or more and 13 px text at 11 px or more.
	MinScale = 0.85,
	MaxScale = 1.35,
}

return Theme
