--!strict
--[[
	Effects: the one-shot effects the server asks every client to play
	(Remotes.PowerEffect: effectId, position, scale), with their sounds.

	  Takeoff       an expanding ring and spark spray around the feet
	  BeamImpact    sparks and a flash where a beam keeps hitting a target
	  ShieldUp      the bubble pulses outward from the body
	  ShieldDown    the bubble breaks outward into falling sparkles
	  WallSpawn     a scan line builds the wall up from the ground, shimmering
	  WallShatter   hard-light shards burst off the wall and fade
	  HammerImpact  a shockwave ring of radius = scale, dust, sparks and a camera
	                shake that fades with distance
	  CageClose     a ring snaps inward with a flash
	  CageRelease   a flash and sparkles drifting up
	  BatteryFlare  a big green flash and light burst at the battery
	  RingDepleted  dying sparks, a puff of smoke and a light stuttering out

	Every effect is placed by position only, so it works whether or not the
	parts it belongs to have streamed in (Workspace.StreamingEnabled). The wall
	effects ask the context for the wall's frame when it is known.

	API:
	  Effects.play(effectId, position, scale, context)
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local PowersConfig = require(Shared.Config.Powers)
local Types = require(Shared.Types)
local VFXConfig = require(Shared.Config.VFX)

local Parts = require(script.Parent.Parts)

-- Where a wall stands (its panel), when the client knows it.
export type WallInfo = {
	CFrame: CFrame,
	Size: Vector3,
}

export type Context = {
	-- Shakes the local camera (CameraController:Shake).
	shake: (intensity: number, duration: number) -> (),
	-- Where the local player is (for distance-scaled effects), if anywhere.
	listenerPosition: () -> Vector3?,
	-- The wall nearest `position` (standing, or removed a moment ago), if known.
	findWall: (position: Vector3) -> WallInfo?,
	-- Plays a Config.Assets.Sounds key at a position.
	playSound: (soundKey: string, position: Vector3) -> (),
}

type LightSpec = VFXConfig.LightSpec

local effects = VFXConfig.Effects

-- Turns a cylinder (axis X) to lie flat, its axis pointing up.
local LYING_FLAT = CFrame.Angles(0, 0, math.rad(90))

local random = Random.new()

-- A flat glowing disc on the ground that grows and fades.
local function groundDisc(
	position: Vector3,
	fromDiameter: number,
	toDiameter: number,
	time: number,
	transparency: number
)
	local thickness = VFXConfig.DiscThickness
	local disc = Parts.neon(
		"Disc",
		Vector3.new(thickness, fromDiameter, fromDiameter),
		CFrame.new(position) * LYING_FLAT,
		VFXConfig.Color,
		transparency,
		Enum.PartType.Cylinder
	)
	disc.Parent = Parts.folder()
	Parts.tween(disc, time, { Size = Vector3.new(thickness, toDiameter, toDiameter), Transparency = 1 })
	Debris:AddItem(disc, time + 0.05)
end

-- A light that flashes on and dims out.
local function lightPop(position: Vector3, spec: LightSpec)
	local holder = Parts.anchor("Light", position)
	local light = Parts.light(holder, spec.Range, spec.Brightness)
	Parts.fadeLight(light, spec.Time, holder)
end

-- The wall at `position`, or a stand-in facing the camera when it is unknown
-- (streamed out, or already gone).
local function wallAt(position: Vector3, context: Context): WallInfo
	local known = context.findWall(position)
	if known ~= nil then
		return known
	end
	local camera = Workspace.CurrentCamera
	local facing = if camera ~= nil then camera.CFrame.Position - position else Vector3.zAxis
	local flat = Vector3.new(facing.X, 0, facing.Z)
	local look = if flat.Magnitude > 0.05 then flat.Unit else Vector3.zAxis
	return {
		CFrame = CFrame.lookAt(position, position + look),
		Size = PowersConfig.Constructs.Wall.Size,
	}
end

-- Effects ---------------------------------------------------------------------

local function beamImpact(position: Vector3, context: Context)
	local config = effects.BeamImpact
	Parts.burst(position, config.Sparks)
	Parts.flashSphere(position, config.FlashFrom, config.FlashTo, config.FlashTime, config.FlashTransparency)
	lightPop(position, config.Light)
	context.playSound("BeamImpact", position)
end

local function takeoff(position: Vector3, context: Context)
	local config = effects.Takeoff
	local feet = position - Vector3.yAxis * config.FootOffset
	Parts.shockwave(feet, config.RingFrom, config.RingTo, config.Time)
	groundDisc(feet, config.RingFrom, config.DiscTo, config.Time, config.DiscTransparency)
	Parts.burst(feet, config.Sparks)
	lightPop(feet, config.Light)
	context.playSound("Takeoff", position)
end

local function shield(position: Vector3, raised: boolean, context: Context)
	local config = effects.Shield
	local diameter = PowersConfig.Shield.Radius * 2
	local from = if raised then config.UpFrom else config.DownFrom
	local to = if raised then config.UpTo else config.DownTo
	Parts.flashSphere(position, diameter * from, diameter * to, config.Time, config.StartTransparency, VFXConfig.Color)
	Parts.burst(position, if raised then config.UpSparks else config.DownSparks)
	lightPop(position, config.Light)
	context.playSound(if raised then "ShieldUp" else "ShieldDown", position)
end

local function wallSpawn(position: Vector3, context: Context)
	local config = effects.WallSpawn
	local wall = wallAt(position, context)
	local size = wall.Size
	local frame = wall.CFrame
	local bottom = frame * CFrame.new(0, -size.Y / 2, 0)
	local margin = config.Margin

	local scan = Parts.neon(
		"Scan",
		Vector3.new(size.X + margin, config.ScanThickness, size.Z + margin),
		bottom,
		VFXConfig.CoreColor,
		0
	)
	scan.Parent = Parts.folder()
	local panel = Parts.neon(
		"Shimmer",
		Vector3.new(size.X + margin, 0.05, size.Z + margin),
		bottom,
		VFXConfig.Color,
		config.ShimmerTransparency
	)
	panel.Parent = Parts.folder()

	-- Sparkles off the wall's surface while it builds.
	local sparkleSpec = config.Sparkles
	local sparkleHolder = Parts.anchor("Sparkles", frame.Position, size)
	sparkleHolder.CFrame = frame
	local sparkles = Parts.emitter(sparkleHolder, sparkleSpec)
	sparkles.Shape = Enum.ParticleEmitterShape.Box
	sparkles.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	sparkles.Rate = sparkleSpec.Count / math.max(config.ScanTime, 0.05)
	Debris:AddItem(sparkleHolder, config.ScanTime + sparkleSpec.Lifetime + 0.2)

	Parts.animate(config.ScanTime, function(alpha: number)
		local height = size.Y * alpha
		scan.CFrame = bottom * CFrame.new(0, height, 0)
		scan.Transparency = alpha * config.ScanEndTransparency
		panel.Size = Vector3.new(size.X + margin, math.max(height, 0.05), size.Z + margin)
		panel.CFrame = bottom * CFrame.new(0, height / 2, 0)
	end, function()
		scan:Destroy()
		sparkles.Rate = 0
		Parts.tween(panel, config.ShimmerTime, { Transparency = 1 })
		Debris:AddItem(panel, config.ShimmerTime + 0.05)
	end)
	lightPop(frame.Position, config.Light)
	context.playSound("WallSpawn", position)
end

type Shard = {
	part: BasePart,
	velocity: Vector3,
	spinAxis: Vector3,
	spin: number,
}

local function wallShatter(position: Vector3, context: Context)
	local config = effects.WallShatter
	local wall = wallAt(position, context)
	local size = wall.Size
	local frame = wall.CFrame
	local startTransparency = PowersConfig.ConstructTransparency
	local container = Instance.new("Folder")
	container.Name = "Shatter"

	local shards: { Shard } = {}
	local parts: { BasePart } = {}
	for index = 1, math.max(0, math.floor(config.ShardCount)) do
		local localPoint = Vector3.new(random:NextNumber(-0.5, 0.5) * size.X, random:NextNumber(-0.5, 0.5) * size.Y, 0)
		-- Wedges and slabs mixed read as broken hard light.
		local part: BasePart = if index % 2 == 0 then Instance.new("WedgePart") else Instance.new("Part")
		part.Name = "Shard"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Color = if index % 3 == 0 then VFXConfig.CoreColor else VFXConfig.Color
		part.Transparency = startTransparency
		part.Size = Vector3.new(
			random:NextNumber(config.ShardSizeMin, config.ShardSizeMax),
			random:NextNumber(config.ShardSizeMin, config.ShardSizeMax),
			random:NextNumber(config.ShardThicknessMin, config.ShardThicknessMax)
		)
		part.CFrame = frame
			* CFrame.new(localPoint)
			* CFrame.Angles(random:NextNumber(0, math.pi * 2), random:NextNumber(0, math.pi * 2), 0)
		part.Parent = container

		-- Out of either face, away from the centre, and a little up.
		local face = frame.LookVector * (if random:NextNumber() < 0.5 then -1 else 1)
		local outward = frame:VectorToWorldSpace(localPoint)
		local direction = face + (if outward.Magnitude > 0.01 then outward.Unit * 0.8 else Vector3.zero)
		local speed = random:NextNumber(config.SpeedMin, config.SpeedMax)
		table.insert(shards, {
			part = part,
			velocity = direction.Unit * speed + Vector3.yAxis * config.Upward,
			spinAxis = random:NextUnitVector(),
			spin = random:NextNumber(-config.Spin, config.Spin),
		})
		table.insert(parts, part)
	end
	container.Parent = Parts.folder()

	local cframes: { CFrame } = table.create(#parts)
	local gravity = Vector3.new(0, -config.Gravity, 0)
	Parts.animate(config.Lifetime, function(alpha: number, deltaTime: number)
		local transparency = startTransparency + (1 - startTransparency) * alpha * alpha
		for index, shard in shards do
			shard.velocity += gravity * deltaTime
			local current = shard.part.CFrame
			cframes[index] = CFrame.fromAxisAngle(shard.spinAxis, shard.spin * deltaTime) * current.Rotation
				+ current.Position
				+ shard.velocity * deltaTime
			shard.part.Transparency = transparency
		end
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end, function()
		container:Destroy()
	end)

	Parts.burst(frame.Position, config.Sparks)
	lightPop(frame.Position, config.Light)
	context.playSound("WallShatter", position)
end

local function hammerImpact(position: Vector3, radius: number, context: Context)
	local config = effects.HammerImpact
	-- Just above the ground so the rings never z-fight with it.
	local ground = position + Vector3.yAxis * VFXConfig.DiscThickness
	Parts.shockwave(ground, radius * 2 * config.StartFraction, radius * 2, config.Time)
	groundDisc(ground, radius * 2 * config.DiscFrom, radius * 2, config.Time, config.DiscTransparency)
	Parts.burst(position, config.Dust)
	Parts.burst(position, config.Sparks)
	lightPop(ground, {
		Range = radius * config.LightRangeScale,
		Brightness = config.LightBrightness,
		Time = config.LightTime,
	})

	-- Full shake within the blast, fading out to nothing at ShakeDistance.
	local listener = context.listenerPosition()
	if listener ~= nil then
		local distance = (listener - position).Magnitude
		local reach = math.max(config.ShakeDistance - radius, 1)
		local strength = if distance <= radius then 1 else math.clamp(1 - (distance - radius) / reach, 0, 1)
		if strength > 0 then
			context.shake(config.ShakeIntensity * strength, config.ShakeDuration)
		end
	end
	context.playSound("HammerImpact", position)
end

local function cageClose(position: Vector3, context: Context)
	local config = effects.CageClose
	Parts.shockwave(position, config.RingFrom, config.RingTo, config.Time)
	Parts.flashSphere(
		position,
		config.FlashSize,
		config.FlashSize * config.FlashEndScale,
		config.FlashTime,
		config.FlashTransparency
	)
	Parts.burst(position, config.Sparks)
	lightPop(position, config.Light)
	context.playSound("CageClose", position)
end

local function cageRelease(position: Vector3, context: Context)
	local config = effects.CageRelease
	Parts.flashSphere(
		position,
		config.FlashFrom,
		config.FlashTo,
		config.FlashTime,
		config.FlashTransparency,
		VFXConfig.Color
	)
	Parts.burst(position, config.Sparks)
	lightPop(position, config.Light)
	context.playSound("CageRelease", position)
end

local function batteryFlare(position: Vector3, context: Context)
	local config = effects.BatteryFlare
	Parts.flashSphere(position, config.FlashFrom, config.FlashTo, config.FlashTime, config.FlashTransparency)
	Parts.shockwave(position, config.FlashFrom, config.RingTo, config.FlashTime)
	Parts.burst(position, config.Sparks)
	Parts.burst(position, config.Bloom)
	lightPop(position, config.Light)
	context.playSound("BatteryFlare", position)
end

local function ringDepleted(position: Vector3, context: Context)
	local config = effects.RingDepleted
	Parts.burst(position, config.Sparks)
	Parts.burst(position, config.Smoke)
	-- The light stutters, weaker each time, then goes out.
	local holder = Parts.anchor("Light", position)
	local light = Parts.light(holder, config.LightRange, config.LightBrightness)
	Parts.animate(config.FlickerTime, function(alpha: number)
		local on = random:NextNumber() < config.FlickerOnChance
		light.Brightness = if on then config.LightBrightness * (1 - alpha) else 0
	end, function()
		holder:Destroy()
	end)
	context.playSound("RingDepleted", position)
end

local Effects = {}

function Effects.play(effectId: Types.EffectId, position: Vector3, scale: number, context: Context)
	if effectId == "BeamImpact" then
		beamImpact(position, context)
	elseif effectId == "Takeoff" then
		takeoff(position, context)
	elseif effectId == "ShieldUp" then
		shield(position, true, context)
	elseif effectId == "ShieldDown" then
		shield(position, false, context)
	elseif effectId == "WallSpawn" then
		wallSpawn(position, context)
	elseif effectId == "WallShatter" then
		wallShatter(position, context)
	elseif effectId == "HammerImpact" then
		hammerImpact(position, math.max(scale, 1), context)
	elseif effectId == "CageClose" then
		cageClose(position, context)
	elseif effectId == "CageRelease" then
		cageRelease(position, context)
	elseif effectId == "BatteryFlare" then
		batteryFlare(position, context)
	elseif effectId == "RingDepleted" then
		ringDepleted(position, context)
	end
end

return Effects
