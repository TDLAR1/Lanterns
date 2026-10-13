--!strict
--[[
	Parts: building blocks for the ring's visual effects (VFXController and the
	other modules in this folder).

	Every effect part is local to this client (parts a client creates never
	replicate) and lives in one Workspace folder (Config.VFX.FolderName). Effect
	parts are anchored and invisible to physics and raycasts (CanCollide,
	CanQuery and CanTouch off), so an effect can never block a beam, an aim ray
	or a character. Everything made here removes itself when it is done.

	API:
	  Parts.folder(): Folder
	  Parts.neon(name, size, cframe, color, transparency, shape?): Part      (not parented)
	  Parts.anchor(name, position, size?): Part                             (invisible, parented)
	  Parts.light(parent, range, brightness, color?): PointLight
	  Parts.emitter(parent, spec): ParticleEmitter                           (Rate 0)
	  Parts.burst(position, spec)                                            (emit once, clean up)
	  Parts.tween(instance, time, goals, style?, direction?): Tween
	  Parts.fadeLight(light, time, holder?)                                  (dim out, then destroy)
	  Parts.animate(duration, step(alpha, deltaTime), finished?)            (per-frame, until done)
	  Parts.flashSphere(position, fromSize, toSize, time, transparency, color?)
	  Parts.shockwave(position, fromDiameter, toDiameter, time, color?)
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local VFXConfig = require(ReplicatedStorage.Shared.Config.VFX)

export type BurstSpec = VFXConfig.BurstSpec

type Animation = {
	duration: number,
	elapsed: number,
	step: (alpha: number, deltaTime: number) -> (),
	finished: (() -> ())?,
}

local folder: Folder? = nil
local animations: { Animation } = {}
local animationConnection: RBXScriptConnection? = nil

local Parts = {}

function Parts.folder(): Folder
	local current = folder
	if current ~= nil and current.Parent == Workspace then
		return current
	end
	local created = Instance.new("Folder")
	created.Name = VFXConfig.FolderName
	created.Parent = Workspace
	folder = created
	return created
end

-- A glowing effect part. The caller sets anything else and parents it.
function Parts.neon(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	transparency: number,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Name = name
	if shape ~= nil then
		part.Shape = shape
	end
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency
	part.Size = size
	part.CFrame = cframe
	return part
end

-- An invisible part at `position` to hold emitters, lights and sounds.
function Parts.anchor(name: string, position: Vector3, size: Vector3?): Part
	local part = Parts.neon(name, size or Vector3.one * 0.2, CFrame.new(position), VFXConfig.Color, 1)
	part.Parent = Parts.folder()
	return part
end

function Parts.light(parent: Instance, range: number, brightness: number, color: Color3?): PointLight
	local light = Instance.new("PointLight")
	light.Color = color or VFXConfig.Color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = parent
	return light
end

-- A ParticleEmitter set up from `spec` with Rate 0: call :Emit for bursts or
-- set Rate for a stream.
function Parts.emitter(parent: Instance, spec: BurstSpec): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = spec.Texture or VFXConfig.Textures.Sparkle
	emitter.Color = ColorSequence.new(spec.Color or VFXConfig.Color)
	emitter.LightEmission = spec.LightEmission or 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, spec.Size),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, spec.Transparency or 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(spec.Lifetime * 0.6, spec.Lifetime)
	emitter.Speed = NumberRange.new(spec.Speed * 0.5, spec.Speed)
	local spread = spec.Spread or 180
	emitter.SpreadAngle = Vector2.new(spread, spread)
	emitter.Acceleration = spec.Acceleration or Vector3.zero
	emitter.Drag = spec.Drag or 0
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-180, 180)
	emitter.Rate = 0
	emitter.Parent = parent
	return emitter
end

-- Emits one burst of particles at `position` and cleans up after they die.
function Parts.burst(position: Vector3, spec: BurstSpec)
	if spec.Count <= 0 then
		return
	end
	local holder = Parts.anchor("Burst", position)
	local emitter = Parts.emitter(holder, spec)
	emitter:Emit(spec.Count)
	Debris:AddItem(holder, spec.Lifetime + 0.2)
end

function Parts.tween(
	instance: Instance,
	time: number,
	goals: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		goals
	)
	tween:Play()
	return tween
end

-- Dims a light to nothing over `time`, then destroys `holder` (or the light).
function Parts.fadeLight(light: PointLight, time: number, holder: Instance?)
	Parts.tween(light, time, { Brightness = 0 })
	Debris:AddItem(holder or light, time + 0.05)
end

local function stepAnimations(deltaTime: number)
	-- Walk a snapshot: a step may start another animation.
	for _, animation in table.clone(animations) do
		animation.elapsed += deltaTime
		local alpha = math.min(animation.elapsed / animation.duration, 1)
		-- An effect whose parts vanished must not stop every other effect.
		local ok, err = pcall(function()
			animation.step(alpha, deltaTime)
		end)
		if not ok then
			warn(`[VFX] An effect stopped early: {err}`)
		end
		if alpha >= 1 or not ok then
			local index = table.find(animations, animation)
			if index ~= nil then
				table.remove(animations, index)
			end
			local finished = animation.finished
			if finished ~= nil then
				local finishedOk, finishedErr = pcall(function()
					finished()
				end)
				if not finishedOk then
					warn(`[VFX] An effect failed to clean up: {finishedErr}`)
				end
			end
		end
	end
	if #animations == 0 then
		local connection = animationConnection
		if connection ~= nil then
			connection:Disconnect()
			animationConnection = nil
		end
	end
end

-- Calls step(alpha, deltaTime) every frame for `duration` seconds (alpha runs
-- 0..1 and ends at exactly 1), then finished(). One shared frame connection
-- runs every animation and disconnects while none are playing.
function Parts.animate(duration: number, step: (alpha: number, deltaTime: number) -> (), finished: (() -> ())?)
	table.insert(animations, {
		duration = math.max(duration, 1e-3),
		elapsed = 0,
		step = step,
		finished = finished,
	})
	if animationConnection == nil then
		animationConnection = RunService.Heartbeat:Connect(stepAnimations)
	end
end

-- A glowing ball that grows from `fromSize` to `toSize` (diameters) while it
-- fades out from `transparency`.
function Parts.flashSphere(
	position: Vector3,
	fromSize: number,
	toSize: number,
	time: number,
	transparency: number,
	color: Color3?
)
	local ball = Parts.neon(
		"Flash",
		Vector3.one * fromSize,
		CFrame.new(position),
		color or VFXConfig.CoreColor,
		transparency,
		Enum.PartType.Ball
	)
	ball.Parent = Parts.folder()
	Parts.tween(ball, time, { Size = Vector3.one * toSize, Transparency = 1 })
	Debris:AddItem(ball, time + 0.05)
end

-- A flat ring of glowing segments around `position` (lying level) that grows
-- (or shrinks) from `fromDiameter` to `toDiameter` while it fades.
function Parts.shockwave(position: Vector3, fromDiameter: number, toDiameter: number, time: number, color: Color3?)
	local config = VFXConfig.Shockwave
	local count = math.max(6, math.floor(config.Segments))
	local container = Instance.new("Folder")
	container.Name = "Shockwave"
	local segments: { BasePart } = {}
	for index = 1, count do
		local segment = Parts.neon(
			"Segment",
			Vector3.one * config.Thickness,
			CFrame.new(position),
			color or VFXConfig.Color,
			config.Transparency
		)
		segment.Parent = container
		segments[index] = segment
	end
	container.Parent = Parts.folder()

	local cframes: { CFrame } = table.create(count)
	Parts.animate(time, function(alpha: number)
		-- Fast at first, settling at the end.
		local eased = 1 - (1 - alpha) ^ 3
		local radius = (fromDiameter + (toDiameter - fromDiameter) * eased) / 2
		-- A little longer than the arc so neighbouring segments overlap.
		local length = 2 * math.pi * radius / count * 1.15
		local transparency = config.Transparency + (1 - config.Transparency) * alpha ^ 1.5
		for index, segment in segments do
			local angle = (index - 1) / count * 2 * math.pi
			local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius
			local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
			local point = position + offset
			cframes[index] = CFrame.lookAt(point, point + tangent)
			segment.Size = Vector3.new(config.Thickness, config.Thickness, math.max(length, 0.05))
			segment.Transparency = transparency
		end
		Workspace:BulkMoveTo(segments, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end, function()
		container:Destroy()
	end)
end

return Parts
