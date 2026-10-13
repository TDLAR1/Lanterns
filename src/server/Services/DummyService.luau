--!strict
--[[
	DummyService: practice targets for trying out ring powers.

	A dummy stands on every TrainingDummySpot part in Workspace (the training
	yard in the Rail Yard), facing the spot's LookVector. A dummy is a Model
	of anchored parts tagged Damageable, with a Humanoid so Roblox shows its
	name and health bar (Config.Combat.TrainingDummy), kept in the Workspace
	folder "TrainingDummies".

	  * Hits rock the dummy on its stand, away from the attacker, harder for
	    bigger hits (TrainingDummy.Wobble).
	  * At 0 health it tips over away from its last attacker, fades into the
	    ground and is destroyed; a fresh one rises at the same spot
	    RespawnTime seconds later. (PowerService releases a caged dummy when it dies.)
	  * Spots added or removed while the game runs (e.g. in Studio) gain or lose their dummy.

	All movement is server-side CFrame posing of the anchored parts (one
	Heartbeat loop for every dummy that is moving), so physics never touches them.

	No public API.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local CombatConfig = require(Shared.Config.Combat)
local TagsModule = require(Shared.Util.Tags)
local Text = require(Shared.Config.Text)

local Characters = require(script.Parent.Characters)
local CombatService = require(script.Parent.CombatService)

local Tags = TagsModule.Tags
local Attributes = TagsModule.Attributes

local DummyConfig = CombatConfig.TrainingDummy
local Look = DummyConfig.Look

local FOLDER_NAME = "TrainingDummies"

-- The look below is drawn for a dummy this tall and scaled to DummyConfig.Height.
local DESIGN_HEIGHT = 6
-- Radius of the iron base at the design height: the dummy rocks and tips on its rim.
local DESIGN_RIM_RADIUS = 1.6
-- Longest physics step for the wobble spring (a server hitch must not make it explode).
local MAX_STEP = 1 / 30
-- Below these the wobble counts as settled and the dummy stops being posed.
local SETTLED_LEAN = 0.002
local SETTLED_SPEED = 0.02

-- Cylinders run along their X axis; these turn that axis up / toward the front (-Z).
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))
local FACING_FRONT = CFrame.Angles(0, math.rad(90), 0)

type PartSpec = {
	Name: string,
	Shape: Enum.PartType,
	-- Centre at the design height, relative to the ground point under the dummy
	-- (+Y up, -Z toward the front).
	At: Vector3,
	Turn: CFrame,
	Size: Vector3,
	Color: Color3,
	Material: Enum.Material,
	Transparency: number,
}

local function spec(
	name: string,
	shape: Enum.PartType,
	at: Vector3,
	turn: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material
): PartSpec
	return {
		Name = name,
		Shape = shape,
		At = at,
		Turn = turn,
		Size = size,
		Color = color,
		Material = material,
		Transparency = 0,
	}
end

local BLOCK = Enum.PartType.Block
local CYLINDER = Enum.PartType.Cylinder
local BALL = Enum.PartType.Ball
local LEVEL = CFrame.identity
local M = Enum.Material

-- An original "practice target": an iron base, a wooden post with crossbar
-- arms, a burlap body with a painted target (glowing centre) and a round head.
-- Cylinder sizes are (length, diameter, diameter).
-- stylua: ignore start
local PARTS: { PartSpec } = {
	--   Name            Shape     Centre                         Turn          Size                           Colour            Material
	spec("Base",         CYLINDER, Vector3.new(0, 0.175, 0),      UPRIGHT,      Vector3.new(0.35, 3.2, 3.2),   Look.Base,        M.Metal),
	spec("Post",         CYLINDER, Vector3.new(0, 1.45, 0),       UPRIGHT,      Vector3.new(2.3, 0.55, 0.55),  Look.Wood,        M.Wood),
	spec("Body",         BLOCK,    Vector3.new(0, 3.5, 0),        LEVEL,        Vector3.new(2.2, 2.4, 1.1),    Look.Burlap,      M.Fabric),
	spec("Arms",         BLOCK,    Vector3.new(0, 4.1, 0.1),      LEVEL,        Vector3.new(4.2, 0.45, 0.45),  Look.Wood,        M.Wood),
	spec("TargetOuter",  CYLINDER, Vector3.new(0, 3.45, -0.58),   FACING_FRONT, Vector3.new(0.06, 1.8, 1.8),   Look.TargetOuter, M.SmoothPlastic),
	spec("TargetMiddle", CYLINDER, Vector3.new(0, 3.45, -0.63),   FACING_FRONT, Vector3.new(0.06, 1.15, 1.15), Look.TargetMiddle, M.SmoothPlastic),
	spec("TargetCentre", CYLINDER, Vector3.new(0, 3.45, -0.68),   FACING_FRONT, Vector3.new(0.06, 0.5, 0.5),   Look.TargetCentre, M.Neon),
	spec("Neck",         CYLINDER, Vector3.new(0, 4.82, 0),       UPRIGHT,      Vector3.new(0.3, 0.45, 0.45),  Look.Wood,        M.Wood),
	-- Roblox draws the Humanoid's name and health bar over the part named "Head".
	spec("Head",         BALL,     Vector3.new(0, 5.45, 0),       LEVEL,        Vector3.new(1.1, 1.1, 1.1),    Look.Burlap,      M.Fabric),
}
-- stylua: ignore end

-- The Humanoid needs a HumanoidRootPart; it is invisible and never blocks anything.
local ROOT_SPEC: PartSpec =
	spec("HumanoidRootPart", BLOCK, Vector3.new(0, 3.5, 0), LEVEL, Vector3.new(2, 2, 1), Look.Burlap, M.SmoothPlastic)
ROOT_SPEC.Transparency = 1

type Phase = "Rising" | "Standing" | "Dying"

type Dummy = {
	spot: BasePart,
	model: Model,
	-- Upright pose: the ground point under the dummy, facing the spot's way.
	rest: CFrame,
	-- The pose last written to the parts.
	pose: CFrame,
	parts: { BasePart },
	-- Each part's CFrame relative to the pose, and its own transparency.
	offsets: { CFrame },
	transparencies: { number },
	rimRadius: number,
	phase: Phase,
	phaseStarted: number,
	-- Wobble: a horizontal vector whose direction is the way the dummy leans and
	-- whose length is the lean angle (radians), and its rate of change.
	lean: Vector3,
	leanVelocity: Vector3,
	-- Horizontal direction the last hit pushed it (it falls this way).
	pushDirection: Vector3,
	-- Lean when it started to fall, and the lean it falls to.
	fallFrom: Vector3,
	fallTo: Vector3,
	connections: { RBXScriptConnection },
}

-- A freshly built dummy Model and the per-part data its Dummy record keeps.
type Built = {
	model: Model,
	humanoid: Humanoid,
	parts: { BasePart },
	offsets: { CFrame },
	transparencies: { number },
}

local dummiesBySpot: { [BasePart]: Dummy } = {}
local dummiesByModel: { [Model]: Dummy } = {}
local respawns: { [BasePart]: thread } = {}
-- Dummies that need posing every frame (rising, wobbling or dying).
local active: { [Dummy]: boolean } = {}
local folder: Folder? = nil

local DummyService = {}

-- Defined below; respawn timers need it first.
local spawnDummy: (spot: BasePart) -> ()

local function getFolder(): Folder
	local current = folder
	if current ~= nil and current.Parent == Workspace then
		return current
	end
	local existing = Workspace:FindFirstChild(FOLDER_NAME)
	if existing ~= nil and existing:IsA("Folder") then
		folder = existing
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = FOLDER_NAME
	created.Parent = Workspace
	folder = created
	return created
end

local function cancel(thread: thread?)
	if thread ~= nil and coroutine.status(thread) == "suspended" then
		task.cancel(thread)
	end
end

local function horizontal(vector: Vector3): Vector3?
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < 1e-3 then
		return nil
	end
	return flat.Unit
end

-- The pose for a lean vector: tipped on the rim of the base, toward the lean.
local function leanedPose(dummy: Dummy, lean: Vector3): CFrame
	local angle = lean.Magnitude
	if angle < 1e-4 then
		return dummy.rest
	end
	local direction = lean / angle
	local pivot = dummy.rest.Position + direction * dummy.rimRadius
	-- Turning about up x direction tips the top toward `direction` (lean is horizontal).
	local axis = Vector3.new(direction.Z, 0, -direction.X)
	local rotation = CFrame.fromAxisAngle(axis, angle)
	return CFrame.new(pivot) * rotation * CFrame.new(-pivot) * dummy.rest
end

local function setFade(dummy: Dummy, fade: number)
	for index, part in dummy.parts do
		local own = dummy.transparencies[index]
		part.Transparency = own + (1 - own) * fade
	end
end

-- Advances the wobble spring. Returns false once it has settled.
local function stepLean(dummy: Dummy, deltaTime: number): boolean
	local wobble = DummyConfig.Wobble
	local step = math.min(deltaTime, MAX_STEP)
	local acceleration = -dummy.lean * wobble.Stiffness - dummy.leanVelocity * wobble.Damping
	dummy.leanVelocity += acceleration * step
	dummy.lean += dummy.leanVelocity * step
	local angle = dummy.lean.Magnitude
	if angle > wobble.MaxLean then
		local unit = dummy.lean / angle
		dummy.lean = unit * wobble.MaxLean
		-- Stop at the limit: drop the part of the speed that pushes further out.
		local outward = dummy.leanVelocity:Dot(unit)
		if outward > 0 then
			dummy.leanVelocity -= unit * outward
		end
	end
	if dummy.lean.Magnitude < SETTLED_LEAN and dummy.leanVelocity.Magnitude < SETTLED_SPEED then
		dummy.lean = Vector3.zero
		dummy.leanVelocity = Vector3.zero
		return false
	end
	return true
end

-- The dummy's pose this frame, and whether it still needs posing next frame.
local function poseFor(dummy: Dummy, now: number, deltaTime: number): (CFrame, boolean)
	local elapsed = now - dummy.phaseStarted
	if dummy.phase == "Rising" then
		local t = math.clamp(elapsed / DummyConfig.RiseTime, 0, 1)
		if t >= 1 then
			dummy.phase = "Standing"
			dummy.phaseStarted = now
			return dummy.rest, dummy.leanVelocity.Magnitude > 0
		end
		-- Ease out: quick at first, settling gently into place.
		local eased = 1 - (1 - t) * (1 - t)
		return dummy.rest - Vector3.yAxis * (DummyConfig.Height * (1 - eased)), true
	elseif dummy.phase == "Standing" then
		local moving = stepLean(dummy, deltaTime)
		return leanedPose(dummy, dummy.lean), moving
	end

	-- Dying: tip over (accelerating like a falling weight), rest, then sink and fade.
	local t = math.clamp(elapsed / DummyConfig.FallTime, 0, 1)
	local pose = leanedPose(dummy, dummy.fallFrom:Lerp(dummy.fallTo, t * t))
	local fadeStart = DummyConfig.FallTime + DummyConfig.FallenTime
	local fade = math.clamp((elapsed - fadeStart) / DummyConfig.FadeTime, 0, 1)
	if fade > 0 then
		setFade(dummy, fade)
		pose -= Vector3.yAxis * (DummyConfig.SinkDepth * fade)
	end
	return pose, fade < 1
end

local function scheduleRespawn(spot: BasePart)
	cancel(respawns[spot])
	respawns[spot] = task.delay(DummyConfig.RespawnTime, function()
		respawns[spot] = nil
		-- The spot may have been removed while waiting.
		if spot:HasTag(Tags.TrainingDummySpot) then
			spawnDummy(spot)
		end
	end)
end

local function removeDummy(dummy: Dummy, respawn: boolean)
	if dummiesByModel[dummy.model] ~= dummy then
		return
	end
	dummiesByModel[dummy.model] = nil
	if dummiesBySpot[dummy.spot] == dummy then
		dummiesBySpot[dummy.spot] = nil
	end
	active[dummy] = nil
	for _, connection in dummy.connections do
		connection:Disconnect()
	end
	dummy.model:Destroy()
	if respawn then
		scheduleRespawn(dummy.spot)
	end
end

local function update(deltaTime: number)
	if next(active) == nil then
		return
	end
	local now = os.clock()
	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}
	local finished: { Dummy } = {}
	for dummy in active do
		if not dummy.model:IsDescendantOf(Workspace) then
			-- Removed by something else; its AncestryChanged handler cleans up.
			active[dummy] = nil
			continue
		end
		local pose, keep = poseFor(dummy, now, deltaTime)
		-- Lying still between the fall and the fade: nothing to send.
		if pose ~= dummy.pose then
			dummy.pose = pose
			for index, part in dummy.parts do
				table.insert(parts, part)
				table.insert(cframes, pose * dummy.offsets[index])
			end
		end
		if not keep then
			active[dummy] = nil
			if dummy.phase == "Dying" then
				table.insert(finished, dummy)
			end
		end
	end
	if #parts > 0 then
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
	for _, dummy in finished do
		removeDummy(dummy, true)
	end
end

local function onDeath(dummy: Dummy)
	if dummy.phase == "Dying" or dummiesByModel[dummy.model] ~= dummy then
		return
	end
	dummy.phase = "Dying"
	dummy.phaseStarted = os.clock()
	-- Falls from wherever the wobble had it, so there is no jump.
	dummy.fallFrom = dummy.lean
	dummy.fallTo = dummy.pushDirection * math.rad(DummyConfig.FallAngle)
	dummy.leanVelocity = Vector3.zero
	active[dummy] = true
end

local function onDamaged(attacker: Player, target: Model, amount: number)
	local dummy = dummiesByModel[target]
	if dummy == nil or dummy.phase == "Dying" then
		return
	end
	local attackerRoot = Characters.GetRootPart(attacker)
	local away = if attackerRoot ~= nil then horizontal(dummy.rest.Position - attackerRoot.Position) else nil
	-- Without an attacker position, it is pushed straight back.
	dummy.pushDirection = away or -dummy.rest.LookVector
	if dummy.phase ~= "Standing" then
		return
	end
	local wobble = DummyConfig.Wobble
	local impulse = wobble.Impulse + amount * wobble.ImpulsePerDamage
	if target:GetAttribute(Attributes.Caged) == true then
		impulse *= wobble.CagedScale
	end
	dummy.leanVelocity += dummy.pushDirection * impulse
	active[dummy] = true
end

-- Builds an (unparented) dummy Model posed at `startPose`.
local function buildModel(startPose: CFrame): Built
	local scale = DummyConfig.Height / DESIGN_HEIGHT
	local model = Instance.new("Model")
	model.Name = "PracticeTarget"
	-- Streams to a client whole, so nobody sees half a dummy.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local built: Built = {
		model = model,
		humanoid = Instance.new("Humanoid"),
		parts = {},
		offsets = {},
		transparencies = {},
	}

	local function addPart(partSpec: PartSpec): BasePart
		local offset = CFrame.new(partSpec.At * scale) * partSpec.Turn
		local part = Instance.new("Part")
		part.Name = partSpec.Name
		part.Shape = partSpec.Shape
		part.Size = partSpec.Size * scale
		part.CFrame = startPose * offset
		part.Anchored = true
		part.Color = partSpec.Color
		part.Material = partSpec.Material
		part.Transparency = partSpec.Transparency
		local visible = partSpec.Transparency < 1
		part.CanCollide = visible
		part.CanQuery = visible
		part.CanTouch = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = model
		table.insert(built.parts, part)
		table.insert(built.offsets, offset)
		table.insert(built.transparencies, partSpec.Transparency)
		return part
	end

	for _, partSpec in PARTS do
		addPart(partSpec)
	end
	model.PrimaryPart = addPart(ROOT_SPEC)

	local humanoid = built.humanoid
	humanoid.DisplayName = Text.Combat.DummyName
	humanoid.MaxHealth = DummyConfig.Health
	humanoid.Health = DummyConfig.Health
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	-- A post has no neck joint to lose, and its anchored parts have no joints to break.
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.Parent = model

	model:AddTag(Tags.Damageable)
	return built
end

-- Stands a fresh dummy on `spot` (rising out of the ground), unless it already has one.
function spawnDummy(spot: BasePart)
	if dummiesBySpot[spot] ~= nil or not spot:IsDescendantOf(Workspace) then
		return
	end
	cancel(respawns[spot])
	respawns[spot] = nil

	local bottom = spot.CFrame * Vector3.new(0, -spot.Size.Y / 2, 0)
	local facing = horizontal(spot.CFrame.LookVector) or -Vector3.zAxis
	local rest = CFrame.lookAt(bottom, bottom + facing)
	-- Starts fully below the ground and rises (see poseFor).
	local startPose = rest - Vector3.yAxis * DummyConfig.Height
	local built = buildModel(startPose)
	local model = built.model

	local dummy: Dummy = {
		spot = spot,
		model = model,
		rest = rest,
		pose = startPose,
		parts = built.parts,
		offsets = built.offsets,
		transparencies = built.transparencies,
		rimRadius = DESIGN_RIM_RADIUS * DummyConfig.Height / DESIGN_HEIGHT,
		phase = "Rising",
		phaseStarted = os.clock(),
		lean = Vector3.zero,
		leanVelocity = Vector3.zero,
		pushDirection = -facing,
		fallFrom = Vector3.zero,
		fallTo = Vector3.zero,
		connections = {},
	}
	dummiesBySpot[spot] = dummy
	dummiesByModel[model] = dummy
	table.insert(
		dummy.connections,
		built.humanoid.Died:Connect(function()
			onDeath(dummy)
		end)
	)
	table.insert(
		dummy.connections,
		model.AncestryChanged:Connect(function()
			-- Deleted by something else (e.g. in Studio): stand a new one up later.
			if not model:IsDescendantOf(Workspace) then
				removeDummy(dummy, true)
			end
		end)
	)
	model.Parent = getFolder()
	active[dummy] = true
end

local function onSpotAdded(instance: Instance)
	if instance:IsA("BasePart") then
		spawnDummy(instance)
	end
end

local function onSpotRemoved(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	cancel(respawns[instance])
	respawns[instance] = nil
	local dummy = dummiesBySpot[instance]
	if dummy ~= nil then
		removeDummy(dummy, false)
	end
end

function DummyService.Init(_self: DummyService)
	CombatService.Damaged:Connect(onDamaged)
	CombatService.Defeated:Connect(function(_attacker: Player, target: Model)
		local dummy = dummiesByModel[target]
		if dummy ~= nil then
			onDeath(dummy)
		end
	end)
end

function DummyService.Start(_self: DummyService)
	getFolder()
	RunService.Heartbeat:Connect(update)
	CollectionService:GetInstanceAddedSignal(Tags.TrainingDummySpot):Connect(onSpotAdded)
	CollectionService:GetInstanceRemovedSignal(Tags.TrainingDummySpot):Connect(onSpotRemoved)
	for _, spot in CollectionService:GetTagged(Tags.TrainingDummySpot) do
		onSpotAdded(spot)
	end
end

export type DummyService = typeof(DummyService)

return DummyService
