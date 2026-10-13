--!strict
--[[
	SpeedStreaks: thin light streaks rushing outward past the screen edges while
	the local player boosts (Config.VFX.SpeedStreaks). The middle of the screen,
	where the player aims, stays clear.

	Streaks live on an ellipse that fits the screen (positions are fractions of
	half the screen on each axis), so they hug the edges of any aspect ratio.
	The overlay switches itself off whenever the streaks have faded out.

	API:
	  SpeedStreaks.new(gui): SpeedStreaks     (a full-screen ScreenGui to draw in)
	  streaks:Update(deltaTime, intensity)    (intensity 0..1; call every frame)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VFXConfig = require(ReplicatedStorage.Shared.Config.VFX)

export type SpeedStreaks = {
	Update: (self: SpeedStreaks, deltaTime: number, intensity: number) -> (),
}

type Streak = {
	frame: Frame,
	-- Unit direction from the centre, in "half screens".
	direction: Vector2,
	radius: number,
	age: number,
	lifetime: number,
}

local config = VFXConfig.SpeedStreaks
local random = Random.new()

-- Below this intensity the overlay is off.
local MIN_VISIBLE = 0.01

local SpeedStreaks = {}

function SpeedStreaks.new(gui: ScreenGui): SpeedStreaks
	local streaks: { Streak } = {}
	for index = 1, math.max(0, math.floor(config.Count)) do
		local frame = Instance.new("Frame")
		frame.Name = "Streak"
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = VFXConfig.CoreColor
		frame.BackgroundTransparency = 1
		-- Tapered at both ends.
		local gradient = Instance.new("UIGradient")
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.6, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = frame
		frame.Parent = gui
		-- Start spread over their lives so they never all respawn together.
		streaks[index] = {
			frame = frame,
			direction = Vector2.xAxis,
			radius = 0,
			age = math.huge,
			lifetime = index / config.Count * config.LifetimeMax,
		}
	end
	gui.Enabled = false

	local current = 0

	local function respawn(streak: Streak)
		local angle = random:NextNumber(0, math.pi * 2)
		streak.direction = Vector2.new(math.cos(angle), math.sin(angle))
		streak.radius = config.StartRadius + random:NextNumber(0, config.StartSpread)
		streak.age = 0
		streak.lifetime = random:NextNumber(config.LifetimeMin, config.LifetimeMax)
		local length = random:NextNumber(config.LengthMin, config.LengthMax)
		streak.frame.Size = UDim2.fromOffset(length, config.Thickness)
	end

	local result = {} :: SpeedStreaks

	function result.Update(_self: SpeedStreaks, deltaTime: number, intensity: number)
		local alpha = 1 - math.exp(-config.Responsiveness * deltaTime)
		current += (math.clamp(intensity, 0, 1) - current) * alpha
		local visible = current > MIN_VISIBLE
		if gui.Enabled ~= visible then
			gui.Enabled = visible
		end
		if not visible then
			return
		end

		local size = gui.AbsoluteSize
		for _, streak in streaks do
			streak.age += deltaTime
			if streak.age >= streak.lifetime then
				respawn(streak)
			end
			streak.radius += config.Speed * deltaTime
			local life = streak.age / streak.lifetime
			-- Fades in and out over its short life.
			local fade = math.sin(math.clamp(life, 0, 1) * math.pi)
			local offset = streak.direction * streak.radius / 2
			local frame = streak.frame
			frame.Position = UDim2.fromScale(0.5 + offset.X, 0.5 + offset.Y)
			-- Pointing outward on screen (the ellipse stretches with the aspect ratio).
			frame.Rotation = math.deg(math.atan2(streak.direction.Y * size.Y, streak.direction.X * size.X))
			frame.BackgroundTransparency = 1 - config.MaxOpacity * current * fade
		end
	end

	return result
end

return SpeedStreaks
