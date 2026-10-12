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

	Font = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Regular),
	FontBold = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold),

	CornerRadius = UDim.new(0, 10),

	-- Seconds
	FadeTime = 0.35,
	BannerHoldTime = 2.5,
	ToastHoldTime = 4,

	-- UI is designed at this viewport height and scaled to the real one.
	ReferenceHeight = 720,
	MinScale = 0.75,
	MaxScale = 1.35,
}

return Theme
