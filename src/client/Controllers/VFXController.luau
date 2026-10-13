--!strict
--[[
	VFXController: everything the ring powers look (and sound) like on this
	client: glowing green hard light.

	  * The local beam (SetLocalBeam, driven by PowerController): drawn every
	    frame from the local character's ring (the part tagged PowerRing) toward
	    CameraController:GetAimPoint(Beam.Range), stopping at the first thing in
	    the way, exactly as the server traces it: own constructs and cages are
	    passed through.
	  * Other players' beams (Remotes.BeamVisual: caster, from, to): the same
	    look, gliding between the server's updates, and hidden after
	    Config.Powers.Beam.VisualTimeout without one or as soon as the caster's
	    BeamActive attribute turns false.
	  * One-shot effects (Remotes.PowerEffect) for every Types.EffectId, see
	    VFX/Effects.luau.
	  * Flight: trails and a glow on every flying player (the Flying attribute;
	    for the local player FlightController, which knows at once), stronger
	    while boosting, with the FlightLoop sound pitched by speed; BoostStart
	    and Land sounds; screen-edge speed streaks while the local player boosts.
	  * A soft glow around anyone whose shield is up.
	  * The local ring's light follows willpower (local-only change).
	  * Floating hit numbers (Remotes.HitConfirmed).
	  * The HammerSwing sound when a hammer construct appears.

	Effects at positions never assume that far-away parts exist (streaming):
	anything they need is looked up and skipped when missing.

	API:
	  VFXController:SetLocalBeam(active)
	  VFXController:IsLocalBeamVisible(): boolean
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local FlightConfig = require(Shared.Config.Flight)
local PowersConfig = require(Shared.Config.Powers)
local Remotes = require(Shared.Remotes)
local RingConfig = require(Shared.Config.Ring)
local TagsModule = require(Shared.Util.Tags)
local Types = require(Shared.Types)
local UIConfig = require(Shared.Config.UI)
local VFXConfig = require(Shared.Config.VFX)

local VFX = script.Parent.Parent.VFX
local BeamRenderer = require(VFX.BeamRenderer)
local Effects = require(VFX.Effects)
local FlightTrails = require(VFX.FlightTrails)
local HitNumbers = require(VFX.HitNumbers)
local Parts = require(VFX.Parts)
local SpeedStreaks = require(VFX.SpeedStreaks)

local CameraController = require(script.Parent.CameraController)
local FlightController = require(script.Parent.FlightController)
local HudController = require(script.Parent.HudController)
local RingController = require(script.Parent.RingController)
local SoundController = require(script.Parent.SoundController)

local Tags = TagsModule.Tags
local Attributes = TagsModule.Attributes
local LocalPlayer = Players.LocalPlayer

local BeamConfig = PowersConfig.Beam

-- Every standard Humanoid rig (R6, R15, custom StarterCharacter) names its root this.
local ROOT_PART_NAME = "HumanoidRootPart"
-- Shorter than this (studs), a beam has no direction (the aim point is on the ring).
local MIN_DIRECTION = 0.05
-- A remote beam this much shorter than its full range stopped at something
-- (the server always traces the full range); covers rounding in transit.
local HIT_MARGIN = 0.5
-- After the camera has moved this frame, so the beam follows the crosshair exactly.
local RENDER_STEP_NAME = "RingVFX"
local RENDER_PRIORITY = Enum.RenderPriority.Camera.Value + 10
local LOCAL_BEAM_LOOP = "BeamLocal"

type RemoteBeam = {
	renderer: BeamRenderer.BeamRenderer,
	-- The server's latest ends, and the ends drawn (gliding toward them).
	targetFrom: Vector3,
	targetTo: Vector3,
	from: Vector3,
	to: Vector3,
	-- os.clock() of the last update.
	updatedAt: number,
	loopId: string,
}

type Flyer = {
	character: Model,
	root: BasePart,
	trails: FlightTrails.FlightTrails?,
	boosting: boolean,
	loopId: string,
}

type Aura = {
	root: BasePart,
	-- An invisible ball the size of the shield bubble that follows the root;
	-- the glow and sparkles hang on it.
	holder: BasePart,
}

type WallRecord = {
	info: Effects.WallInfo,
	-- os.clock() when it left this client (destroyed or streamed out); nil while standing.
	removedAt: number?,
}

local localBeamActive = false
local localBeam: BeamRenderer.BeamRenderer? = nil
local localBeamVisible = false
local remoteBeams: { [Player]: RemoteBeam } = {}
local flyers: { [Player]: Flyer } = {}
local auras: { [Player]: Aura } = {}
local walls: { [Model]: WallRecord } = {}
local streaks: SpeedStreaks.SpeedStreaks? = nil

local beamParams = RaycastParams.new()
beamParams.FilterType = Enum.RaycastFilterType.Exclude
beamParams.IgnoreWater = true

-- The local ring part and its light, looked up again only when they change.
local cachedRing: BasePart? = nil
local cachedRingLight: PointLight? = nil
local lastRingBrightness = -1

local VFXController = {}

-- Lookups --------------------------------------------------------------------------

local function findRoot(character: Model?): BasePart?
	if character == nil or not character:IsDescendantOf(Workspace) then
		return nil
	end
	local root = character:FindFirstChild(ROOT_PART_NAME)
	if root ~= nil and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- The ring part (tagged PowerRing) on `character`, if it has streamed in.
local function findRing(character: Model?): BasePart?
	if character == nil then
		return nil
	end
	for _, instance in CollectionService:GetTagged(Tags.PowerRing) do
		if instance:IsA("BasePart") and instance:IsDescendantOf(character) then
			return instance
		end
	end
	return nil
end

local function localRing(): BasePart?
	local character = LocalPlayer.Character
	local ring = cachedRing
	if ring ~= nil and character ~= nil and ring:IsDescendantOf(character) then
		return ring
	end
	ring = findRing(character)
	cachedRing = ring
	cachedRingLight = if ring ~= nil then ring:FindFirstChildOfClass("PointLight") else nil
	lastRingBrightness = -1
	return ring
end

local function isAlive(character: Model?): boolean
	if character == nil then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- Constructs a player's beam passes through, as the server traces it: their
-- own, and every cage.
local function passableConstructs(userId: number): { Instance }
	local list: { Instance } = {}
	for _, instance in CollectionService:GetTagged(Tags.Construct) do
		if
			instance:GetAttribute(Attributes.OwnerUserId) == userId
			or instance:GetAttribute(Attributes.ConstructId) == "Cage"
		then
			table.insert(list, instance)
		end
	end
	return list
end

-- Walls ------------------------------------------------------------------------------

local function wallInfo(model: Model): Effects.WallInfo?
	local primary = model.PrimaryPart
	if primary ~= nil then
		return { CFrame = primary.CFrame, Size = primary.Size }
	end
	if #model:GetChildren() == 0 then
		return nil
	end
	local cframe, size = model:GetBoundingBox()
	return { CFrame = cframe, Size = size }
end

local function trackConstruct(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	local constructId = instance:GetAttribute(Attributes.ConstructId)
	if constructId == "Hammer" then
		-- It appears raised and swings straight away.
		SoundController:Play("HammerSwing", instance:GetPivot().Position)
	elseif constructId == "Wall" then
		-- Walls never move, so where it stands is read once its parts are in.
		task.defer(function()
			if instance.Parent == nil then
				return
			end
			local info = wallInfo(instance)
			if info ~= nil then
				walls[instance] = { info = info, removedAt = nil }
			end
		end)
	end
end

local function untrackConstruct(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	local record = walls[instance]
	if record ~= nil and record.removedAt == nil then
		-- Kept a moment: its WallShatter effect may arrive just after it went.
		record.removedAt = os.clock()
		task.delay(VFXConfig.Walls.RememberTime, function()
			if walls[instance] == record then
				walls[instance] = nil
			end
		end)
	end
end

local function findWall(position: Vector3): Effects.WallInfo?
	local config = VFXConfig.Walls
	local now = os.clock()
	local best: Effects.WallInfo? = nil
	local bestDistance = config.MatchDistance
	for model, record in walls do
		local removedAt = record.removedAt
		if removedAt ~= nil and now - removedAt > config.RememberTime then
			walls[model] = nil
		else
			local distance = (record.info.CFrame.Position - position).Magnitude
			if distance <= bestDistance then
				best = record.info
				bestDistance = distance
			end
		end
	end
	if best ~= nil then
		return best
	end
	-- The effect can arrive before the new wall was recorded (that waits a
	-- frame for its parts): look at the walls standing here right now.
	for _, instance in CollectionService:GetTagged(Tags.Construct) do
		if
			instance:IsA("Model")
			and walls[instance] == nil
			and instance:GetAttribute(Attributes.ConstructId) == "Wall"
		then
			local info = wallInfo(instance)
			if info ~= nil then
				walls[instance] = { info = info, removedAt = nil }
				local distance = (info.CFrame.Position - position).Magnitude
				if distance <= bestDistance then
					best = info
					bestDistance = distance
				end
			end
		end
	end
	return best
end

-- Effects context ----------------------------------------------------------------------

local effectContext: Effects.Context = {
	shake = function(intensity: number, duration: number)
		CameraController:Shake(intensity, duration)
	end,
	listenerPosition = function(): Vector3?
		local root = findRoot(LocalPlayer.Character)
		if root ~= nil then
			return root.Position
		end
		local camera = Workspace.CurrentCamera
		return if camera ~= nil then camera.Focus.Position else nil
	end,
	findWall = findWall,
	playSound = function(soundKey: string, position: Vector3)
		SoundController:Play(soundKey, position)
	end,
}

local function onPowerEffect(effectId: Types.EffectId, position: Vector3, scale: number)
	-- From the server, so trusted; still never let a malformed message throw.
	if type(effectId) ~= "string" or typeof(position) ~= "Vector3" then
		return
	end
	local safeScale = if type(scale) == "number" and scale == scale then scale else 1
	Effects.play(effectId, position, safeScale, effectContext)
end

local function onHitConfirmed(position: Vector3, amount: number)
	if typeof(position) ~= "Vector3" or type(amount) ~= "number" or not (amount > 0) then
		return
	end
	HitNumbers.show(position, amount)
end

-- Beams -------------------------------------------------------------------------------

local function hideLocalBeam()
	if not localBeamVisible then
		return
	end
	localBeamVisible = false
	local renderer = localBeam
	if renderer ~= nil then
		renderer:SetVisible(false)
	end
	SoundController:StopLoop(LOCAL_BEAM_LOOP)
end

local function newLocalBeam(): BeamRenderer.BeamRenderer
	local renderer = BeamRenderer.new("LocalBeam")
	localBeam = renderer
	return renderer
end

local function stepLocalBeam()
	if not localBeamActive then
		hideLocalBeam()
		return
	end
	local character = LocalPlayer.Character
	local root = findRoot(character)
	if character == nil or root == nil or not isAlive(character) then
		hideLocalBeam()
		return
	end
	local ring = localRing()
	local origin = if ring ~= nil then ring.Position else root.Position
	local offset = CameraController:GetAimPoint(BeamConfig.Range) - origin
	if offset.Magnitude < MIN_DIRECTION then
		return
	end
	-- Traced like the server's beam: the full range along the aim direction,
	-- stopping at the first thing in the way.
	local direction = offset.Unit * BeamConfig.Range
	local exclude = passableConstructs(LocalPlayer.UserId)
	table.insert(exclude, character)
	table.insert(exclude, Parts.folder())
	beamParams.FilterDescendantsInstances = exclude
	local result = Workspace:Raycast(origin, direction, beamParams)
	local endPoint = if result ~= nil then result.Position else origin + direction

	local renderer = localBeam or newLocalBeam()
	renderer:Update(origin, endPoint, result ~= nil)
	if not localBeamVisible then
		localBeamVisible = true
		renderer:SetVisible(true)
		SoundController:StartLoop(LOCAL_BEAM_LOOP, "BeamLoop", renderer:GetMuzzle())
	end
end

local function removeRemoteBeam(caster: Player)
	local beam = remoteBeams[caster]
	if beam == nil then
		return
	end
	remoteBeams[caster] = nil
	SoundController:StopLoop(beam.loopId)
	beam.renderer:Destroy()
end

local function onBeamVisual(caster: Player, from: Vector3, to: Vector3)
	if
		typeof(caster) ~= "Instance"
		or not caster:IsA("Player")
		or caster == LocalPlayer
		or typeof(from) ~= "Vector3"
		or typeof(to) ~= "Vector3"
	then
		return
	end
	local beam = remoteBeams[caster]
	if beam == nil then
		-- An unreliable update can arrive after the beam already ended.
		if caster:GetAttribute(Attributes.BeamActive) == false then
			return
		end
		local renderer = BeamRenderer.new("Beam_" .. caster.UserId)
		renderer:Update(from, to, false)
		beam = {
			renderer = renderer,
			targetFrom = from,
			targetTo = to,
			from = from,
			to = to,
			updatedAt = os.clock(),
			loopId = "Beam_" .. caster.UserId,
		}
		remoteBeams[caster] = beam
		renderer:SetVisible(true)
		SoundController:StartLoop(beam.loopId, "BeamLoop", renderer:GetMuzzle())
	end
	beam.targetFrom = from
	beam.targetTo = to
	beam.updatedAt = os.clock()
end

local function stepRemoteBeams(deltaTime: number)
	local now = os.clock()
	local alpha = 1 - math.exp(-VFXConfig.Beam.RemoteResponsiveness * deltaTime)
	for caster, beam in table.clone(remoteBeams) do
		if
			caster.Parent ~= Players
			or now - beam.updatedAt > BeamConfig.VisualTimeout
			or caster:GetAttribute(Attributes.BeamActive) == false
		then
			removeRemoteBeam(caster)
			continue
		end
		beam.from = beam.from:Lerp(beam.targetFrom, alpha)
		beam.to = beam.to:Lerp(beam.targetTo, alpha)
		-- Start at the caster's ring as this client draws it, when it is here:
		-- it moves smoothly every frame, unlike the server's 10 updates a second.
		local ring = findRing(caster.Character)
		local origin = if ring ~= nil then ring.Position else beam.from
		-- The server traces the full range: anything shorter stopped at something.
		local hit = (beam.targetTo - beam.targetFrom).Magnitude < BeamConfig.Range - HIT_MARGIN
		beam.renderer:Update(origin, beam.to, hit)
	end
end

-- Flight & shield ------------------------------------------------------------------

local function removeFlyer(player: Player, landed: boolean)
	local flyer = flyers[player]
	if flyer == nil then
		return
	end
	flyers[player] = nil
	local trails = flyer.trails
	if trails ~= nil then
		trails:Destroy()
	end
	SoundController:StopLoop(flyer.loopId)
	if landed and flyer.root.Parent ~= nil then
		SoundController:Play("Land", flyer.root)
	end
end

local function isPlayerFlying(player: Player): (boolean, boolean, number?)
	-- The local player's own flight is known at once; everyone else's comes from
	-- the server's attributes.
	if player == LocalPlayer then
		local flying = FlightController:IsFlying()
		return flying, flying and FlightController:IsBoosting(), FlightController:GetVelocity().Magnitude
	end
	return player:GetAttribute(Attributes.Flying) == true, player:GetAttribute(Attributes.Boosting) == true, nil
end

local function startFlyer(player: Player, character: Model, root: BasePart): Flyer
	local flyer: Flyer = {
		character = character,
		root = root,
		trails = FlightTrails.new(character),
		boosting = false,
		loopId = "Flight_" .. player.UserId,
	}
	flyers[player] = flyer
	SoundController:StartLoop(flyer.loopId, "FlightLoop", root)
	return flyer
end

local function stepFlyer(player: Player)
	local flying, boosting, speed = isPlayerFlying(player)
	local character = player.Character
	local root = if flying then findRoot(character) else nil
	local existing = flyers[player]
	if character == nil or root == nil then
		if existing ~= nil then
			-- Alive and still in the world: it landed (else it died, despawned or
			-- streamed out).
			local landed = not flying and existing.root:IsDescendantOf(Workspace) and isAlive(existing.character)
			removeFlyer(player, landed)
		end
		return
	end
	if existing ~= nil and (existing.character ~= character or existing.root ~= root) then
		-- A new character (respawned mid-flight): start over on it.
		removeFlyer(player, false)
	end
	local current = flyers[player] or startFlyer(player, character, root)

	if boosting ~= current.boosting then
		current.boosting = boosting
		if boosting then
			SoundController:Play("BoostStart", root)
		end
	end
	local trails = current.trails
	if trails ~= nil then
		trails:SetBoosting(boosting)
	end

	local loop = SoundController:GetLoop(current.loopId)
	if loop ~= nil then
		local config = VFXConfig.Flight
		local travel = speed or root.AssemblyLinearVelocity.Magnitude
		local t = math.clamp(travel / FlightConfig.BoostSpeed, 0, 1)
		loop.PlaybackSpeed = config.MinPitch + (config.MaxPitch - config.MinPitch) * t
	end
end

local function removeAura(player: Player)
	local aura = auras[player]
	if aura == nil then
		return
	end
	auras[player] = nil
	aura.holder:Destroy()
end

local function startAura(player: Player, root: BasePart): Aura
	local config = VFXConfig.ShieldAura
	local holder = Parts.neon(
		"ShieldAura",
		Vector3.one * (PowersConfig.Shield.Radius * 2),
		root.CFrame,
		VFXConfig.Color,
		1,
		Enum.PartType.Ball
	)
	Parts.light(holder, config.LightRange, config.LightBrightness)
	local sparkles = Parts.emitter(holder, config.Sparkles)
	-- Over the bubble's surface rather than inside the body.
	sparkles.Shape = Enum.ParticleEmitterShape.Sphere
	sparkles.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	sparkles.Rate = config.SparkRate
	holder.Parent = Parts.folder()
	local aura: Aura = { root = root, holder = holder }
	auras[player] = aura
	return aura
end

local function stepAura(player: Player)
	local shielded = player:GetAttribute(Attributes.Shielding) == true
	local root = if shielded then findRoot(player.Character) else nil
	local existing = auras[player]
	if existing ~= nil and existing.root ~= root then
		removeAura(player)
	end
	if root == nil then
		return
	end
	local aura = auras[player] or startAura(player, root)
	aura.holder.CFrame = root.CFrame
end

local function stepPlayers()
	for _, player in Players:GetPlayers() do
		stepFlyer(player)
		stepAura(player)
	end
end

local function onPlayerRemoving(player: Player)
	removeFlyer(player, false)
	removeAura(player)
	removeRemoteBeam(player)
end

-- Local glow and streaks ----------------------------------------------------------------

local function stepRingGlow()
	local ring = localRing()
	local light = cachedRingLight
	if ring == nil or light == nil or light.Parent ~= ring then
		return
	end
	local config = VFXConfig.RingGlow
	local visual = RingConfig.Visual
	local fraction = math.clamp(RingController:GetWillpower() / RingController:GetWillpowerMax(), 0, 1)
	local brightness: number
	local range: number
	if RingController:IsReady() and RingController:GetCharge() <= 0 then
		brightness = visual.LightBrightness * config.DepletedBrightness
		range = visual.LightRange * config.MinWillpowerRange
	else
		brightness = visual.LightBrightness
			* (config.MinWillpowerBrightness + (1 - config.MinWillpowerBrightness) * fraction)
		range = visual.LightRange * (config.MinWillpowerRange + (1 - config.MinWillpowerRange) * fraction)
	end
	if localBeamVisible then
		brightness *= config.FiringBoost
	end
	-- Only written when it changes: willpower updates ten times a second at most.
	if math.abs(brightness - lastRingBrightness) > 0.01 then
		lastRingBrightness = brightness
		light.Brightness = brightness
		light.Range = range
	end
end

local function stepStreaks(deltaTime: number)
	local current = streaks
	if current == nil then
		return
	end
	local intensity = 0
	if FlightController:IsFlying() and FlightController:IsBoosting() then
		local full = FlightConfig.BoostSpeed * VFXConfig.SpeedStreaks.FullAtSpeedFraction
		intensity = math.clamp(FlightController:GetVelocity().Magnitude / math.max(full, 1), 0, 1)
	end
	current:Update(deltaTime, intensity)
end

local function renderStep(deltaTime: number)
	stepLocalBeam()
	stepRemoteBeams(deltaTime)
	stepPlayers()
	stepRingGlow()
	stepStreaks(deltaTime)
end

-- API -----------------------------------------------------------------------------------

-- Draws (true) or hides (false) the local player's beam. Called by
-- PowerController when the beam starts and stops.
function VFXController.SetLocalBeam(_self: VFXController, active: boolean)
	localBeamActive = active
	if not active then
		hideLocalBeam()
	end
end

function VFXController.IsLocalBeamVisible(_self: VFXController): boolean
	return localBeamVisible
end

function VFXController.Init(_self: VFXController)
	Parts.folder()
	streaks = SpeedStreaks.new(HudController:CreateScreenGui("SpeedStreaks", {
		DisplayOrder = UIConfig.DisplayOrder.SpeedStreaks,
		FullScreen = true,
	}))

	Remotes.PowerEffect:Connect(onPowerEffect)
	Remotes.BeamVisual:Connect(onBeamVisual)
	Remotes.HitConfirmed:Connect(onHitConfirmed)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	CollectionService:GetInstanceAddedSignal(Tags.Construct):Connect(trackConstruct)
	CollectionService:GetInstanceRemovedSignal(Tags.Construct):Connect(untrackConstruct)
	-- Walls already standing when this client started (no sound for those).
	for _, instance in CollectionService:GetTagged(Tags.Construct) do
		if instance:IsA("Model") and instance:GetAttribute(Attributes.ConstructId) == "Wall" then
			local info = wallInfo(instance)
			if info ~= nil then
				walls[instance] = { info = info, removedAt = nil }
			end
		end
	end
end

function VFXController.Start(_self: VFXController)
	RunService:BindToRenderStep(RENDER_STEP_NAME, RENDER_PRIORITY, renderStep)
end

export type VFXController = typeof(VFXController)

return VFXController
