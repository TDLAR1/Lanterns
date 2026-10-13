--!strict
--[[
	Camera tuning: combat mode, the crosshair, aiming and camera shake.
	(Field of view lives in Config/Flight.luau, Camera.)

	COMBAT MODE is on while a power aims at the crosshair or the player flies:
	the camera moves over the right shoulder so the crosshair in the middle of
	the screen is never hidden behind the character, the character on foot turns
	to face where the camera looks, the crosshair shows and, on PC, the mouse is
	locked to the middle of the screen so moving it turns the camera.

	Distances are studs, angles degrees. "Responsiveness" values are rates (1/s)
	for exponential smoothing: about 1/value seconds to cover most of the way.
]]

local Theme = require(script.Parent.Theme)

local Camera = {
	-- Seconds combat mode stays on after its last reason ends, so quick beam
	-- taps (or landing and taking off again) never swing the camera in and out.
	CombatLinger = 0.6,

	Combat = {
		-- Camera shift while aiming, in camera space: right, up, back.
		ShoulderOffset = Vector3.new(2.1, 0.45, 0),
		-- How quickly the shoulder offset and the crosshair blend in and out.
		BlendResponsiveness = 9,
		-- How quickly a character on foot turns to face where the camera looks.
		TurnResponsiveness = 18,
		-- The offset fades out as the camera zooms in (first person has none):
		-- none at or below OffsetMinZoom studs from the focus, full from OffsetFullZoom.
		OffsetMinZoom = 1.5,
		OffsetFullZoom = 6,
		-- Studs kept between the shifted camera and a wall beside it.
		WallPadding = 0.6,
	},

	Crosshair = {
		-- Pixels at UI scale 1: a centre dot and four short ticks around it.
		DotSize = 4,
		TickLength = 7,
		TickThickness = 2,
		-- Gap between the centre and the inner end of each tick.
		TickGap = 5,
		Color = Theme.RingGreen,
		-- Thin dark outline so it reads against a bright sky.
		OutlineColor = Theme.PanelColor,
		OutlineThickness = 1,
		OutlineTransparency = 0.4,
		-- ScreenGui stacking: under the HUD (Config.UI.DisplayOrder.Hud) and the
		-- touch buttons, above the boundary warning.
		DisplayOrder = 5,
	},

	Aim = {
		-- The aim ray looks through parts at least this transparent, and through
		-- parts you can walk through (light beams, effects, crops), unless they
		-- belong to a character (a dummy's limbs never collide but must be hit).
		IgnoreTransparency = 0.95,
		-- Most such parts one aim ray looks through before it stops at the next.
		MaxPassThrough = 8,
	},

	-- Touch: a finger holding one of these actions' buttons turns the camera as
	-- it drags (a touch that starts on a button never reaches Roblox's camera),
	-- so you can aim while firing. Sensitivity is radians per pixel dragged
	-- (horizontal, vertical); MaxPitch (degrees) keeps the view off the poles.
	TouchAim = {
		Actions = { "FireBeam" },
		Sensitivity = Vector2.new(0.008, 0.006),
		MaxPitch = 80,
	},

	Shake = {
		-- Rotation (degrees) and position jitter (studs) at intensity 1.
		MaxAngle = 2.2,
		MaxOffset = 0.2,
		-- How fast the shake wobbles (noise cycles per second).
		Frequency = 14,
		-- The sum of every active shake is capped at this intensity.
		MaxIntensity = 2,
		-- Multiplies every shake; 0 turns camera shake off.
		Scale = 1,
	},
}

return Camera
