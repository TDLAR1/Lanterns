--!strict
--[[
	PowerService: the ring's combat powers on the server: the energy beam, the
	shield bubble and the hard-light constructs (wall, hammer, cage).

	Clients only REQUEST powers (Remotes BeamStart / BeamAim / BeamStop /
	SetShield / CastConstruct). Every request is checked with RingService
	(willpower, charge, cooldowns, blocks) and the rules below, using the
	server's view of the caster; refusals are answered with
	Remotes.PowerRejected(powerId, reason). Hits, damage, costs, cooldowns and
	how long things last are all decided here.

	  * Beam: hold to fire. One loop at Config.Powers.Beam.TickRate serves every
	    beam (and drains every shield): it raycasts from the caster's ring toward
	    their latest aim point, damages what it hits (CombatService), drains the
	    ring, and tells the other clients where to draw it (Remotes.BeamVisual).
	  * Shield: a bubble welded to the character. While it is up, damage taken
	    is reduced (CombatService reads Attributes.Shielding) and, with
	    Shield.BlocksAttacks, the beam and constructs are unavailable.
	  * Constructs are anchored Neon Models in Workspace.Constructs, tagged
	    Construct with ConstructId / OwnerUserId attributes. Their strength
	    (health, duration, damage) is the caster's RingService:GetStrength at the
	    moment of casting. They are removed when they expire or their owner leaves.
	      - Wall: stands on the ground under the aim point, facing the caster.
	        Attributes ConstructHealth / ConstructMaxHealth; DamageConstruct
	        wears it down.
	      - Hammer: appears raised over the aim point and slams down on it:
	        area damage and knockback.
	      - Cage: traps the nearest target near the aim point (it cannot move;
	        a trapped player is landed and cannot use powers). The target Model
	        carries the attribute Attributes.Caged while trapped.

	State mirrored on each Player for clients: Attributes.BeamActive, Attributes.Shielding.

	API:
	  PowerService:StopAll(player)                 stop the beam, drop the shield (no cooldowns)
	  PowerService:IsShielding(player): boolean
	  PowerService:IsFiringBeam(player): boolean
	  PowerService:DamageConstruct(model, amount)  wears down a wall; it shatters at 0
	  PowerService.ConstructCast  Signal(player, constructId, model)
	  PowerService.CagedAttribute                  (= Attributes.Caged)
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local CombatConfig = require(Shared.Config.Combat)
local PowersConfig = require(Shared.Config.Powers)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Util.Signal)
local TagsModule = require(Shared.Util.Tags)
local Types = require(Shared.Types)
local WorldConfig = require(Shared.Config.World)

local Characters = require(script.Parent.Characters)
local CombatService = require(script.Parent.CombatService)
local FlightService = require(script.Parent.FlightService)
local RingService = require(script.Parent.RingService)

local Tags = TagsModule.Tags
local Attributes = TagsModule.Attributes

local BeamConfig = PowersConfig.Beam
local ShieldConfig = PowersConfig.Shield
local ConstructConfigs = PowersConfig.Constructs

-- Workspace folder that holds every construct.
local CONSTRUCT_FOLDER_NAME = "Constructs"
-- Attributes on construct and target Models.
local CAGED_ATTRIBUTE = Attributes.Caged
local HEALTH_ATTRIBUTE = Attributes.ConstructHealth
local MAX_HEALTH_ATTRIBUTE = Attributes.ConstructMaxHealth
-- RingService block reason while a player is trapped in a cage (PvP only).
local CAGED_BLOCK_REASON = "Caged"

-- Shorter than this (studs), a direction is meaningless (e.g. the aim point is on the ring).
local MIN_DIRECTION = 0.05
-- The wall's ground probe starts this far above the cast point, so a point
-- lying exactly on the ground still finds it.
local GROUND_PROBE_LIFT = 1
-- The cage's floor ring sits this far below the target's feet.
local CAGE_SINK = 0.2

-- The cost and range fields every construct config shares.
type ConstructCost = {
	MinWillpower: number,
	WillpowerCost: number,
	ChargeCost: number,
	Cooldown: number,
	Range: number,
}

type BeamState = {
	-- Latest aim point from the client (world space).
	aim: Vector3,
	-- os.clock() of the last BeamImpact effect (throttled).
	lastImpactEffect: number,
}

type Construct = {
	id: Types.ConstructId,
	owner: Player,
	-- Removes the construct and undoes what it did. Safe to call more than once.
	finish: () -> (),
}

type PartStyle = {
	Shape: Enum.PartType?,
	-- Defaults to Config.Powers.ConstructTransparency.
	Transparency: number?,
	-- Blocks movement and raycasts. Defaults to false: decoration never gets in the way.
	Solid: boolean?,
}

local beams: { [Player]: BeamState } = {}
local shields: { [Player]: BasePart? } = {}
local constructs: { [Model]: Construct } = {}
local playerConnections: { [Player]: { RBXScriptConnection } } = {}
local constructFolder: Folder? = nil

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local EDGE_STYLE: PartStyle = { Transparency = PowersConfig.ConstructEdge.Transparency }

local PowerService = {
	-- A construct was created and placed in the world. (player, constructId, model)
	ConstructCast = Signal.new() :: Signal.Signal<Player, Types.ConstructId, Model>,
	-- Attribute set to true on a Model while a cage holds it.
	CagedAttribute = CAGED_ATTRIBUTE,
}

-- Helpers --------------------------------------------------------------------

local function getConstructFolder(): Folder
	local folder = constructFolder
	if folder ~= nil and folder.Parent == Workspace then
		return folder
	end
	local existing = Workspace:FindFirstChild(CONSTRUCT_FOLDER_NAME)
	if existing ~= nil and existing:IsA("Folder") then
		constructFolder = existing
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = CONSTRUCT_FOLDER_NAME
	created.Parent = Workspace
	constructFolder = created
	return created
end

local function reject(player: Player, powerId: Types.PowerId, reason: Types.PowerRejectReason?)
	if player.Parent == Players then
		Remotes.PowerRejected:FireClient(player, powerId, reason or "NotReady")
	end
end

local function playEffect(effect: Types.EffectId, position: Vector3, scale: number?)
	Remotes.PowerEffect:FireAll(effect, position, scale or 1)
end

local function cancel(thread: thread?)
	-- Not the running thread: a timer calling its own finish must not cancel itself.
	if thread ~= nil and coroutine.status(thread) == "suspended" then
		task.cancel(thread)
	end
end

-- `vector` flattened onto the ground plane as a unit vector, or nil if it is (nearly) vertical.
local function horizontal(vector: Vector3): Vector3?
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < MIN_DIRECTION then
		return nil
	end
	return flat.Unit
end

local function constructCost(id: Types.ConstructId): ConstructCost
	if id == "Wall" then
		return ConstructConfigs.Wall
	elseif id == "Hammer" then
		return ConstructConfigs.Hammer
	end
	return ConstructConfigs.Cage
end

local function allCharacters(): { Instance }
	local list: { Instance } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character ~= nil then
			table.insert(list, character)
		end
	end
	return list
end

-- Constructs `player`'s beam and aim pass through: their own, and every cage
-- (so a partner can keep firing at a caged target between the bars).
local function passableConstructs(player: Player): { Instance }
	local list: { Instance } = {}
	for model, construct in constructs do
		if construct.owner == player or construct.id == "Cage" then
			table.insert(list, model)
		end
	end
	return list
end

local function raycast(origin: Vector3, direction: Vector3, exclude: { Instance }): RaycastResult?
	rayParams.FilterDescendantsInstances = exclude
	return Workspace:Raycast(origin, direction, rayParams)
end

-- The construct Model a part belongs to, if any.
local function constructOf(part: BasePart): Model?
	local folder = constructFolder
	if folder == nil then
		return nil
	end
	local current: Instance? = part.Parent
	while current ~= nil and current ~= folder do
		if current:IsA("Model") and constructs[current] ~= nil then
			return current
		end
		current = current.Parent
	end
	return nil
end

-- Beam & shield --------------------------------------------------------------

-- Returns true if a beam was actually stopped.
local function stopBeam(player: Player, withCooldown: boolean): boolean
	if beams[player] == nil then
		return false
	end
	beams[player] = nil
	player:SetAttribute(Attributes.BeamActive, false)
	if withCooldown then
		RingService:StartCooldown(player, "Beam", BeamConfig.Cooldown)
	end
	return true
end

-- Returns true if a shield was actually dropped.
local function dropShield(player: Player, withCooldown: boolean): boolean
	local bubble = shields[player]
	if bubble == nil then
		return false
	end
	shields[player] = nil
	player:SetAttribute(Attributes.Shielding, false)
	playEffect("ShieldDown", bubble.Position)
	bubble:Destroy()
	if withCooldown then
		RingService:StartCooldown(player, "Shield", ShieldConfig.Cooldown)
	end
	return true
end

local function stopAll(player: Player)
	stopBeam(player, false)
	dropShield(player, false)
end

local function startBeam(player: Player, aimPoint: Vector3)
	local beam = beams[player]
	if beam ~= nil then
		beam.aim = aimPoint
		return
	end
	if shields[player] ~= nil and ShieldConfig.BlocksAttacks then
		reject(player, "Beam", "Busy")
		return
	end
	local ok: boolean, reason: Types.PowerRejectReason? = RingService:CanUse(player, "Beam", BeamConfig.MinWillpower)
	if not ok then
		reject(player, "Beam", reason)
		return
	end
	beams[player] = { aim = aimPoint, lastImpactEffect = 0 }
	player:SetAttribute(Attributes.BeamActive, true)
end

local function raiseShield(player: Player)
	if shields[player] ~= nil then
		return
	end
	local ok: boolean, reason: Types.PowerRejectReason? =
		RingService:CanUse(player, "Shield", ShieldConfig.MinWillpower)
	if not ok then
		reject(player, "Shield", reason)
		return
	end
	local character = player.Character
	local root = Characters.GetRootPart(player, true)
	if character == nil or root == nil then
		reject(player, "Shield", "NotReady")
		return
	end

	local bubble = Instance.new("Part")
	bubble.Name = "ShieldBubble"
	bubble.Shape = Enum.PartType.Ball
	bubble.Size = Vector3.one * (ShieldConfig.Radius * 2)
	bubble.Material = Enum.Material.ForceField
	bubble.Color = ShieldConfig.Color
	bubble.Transparency = ShieldConfig.Transparency
	bubble.CanCollide = false
	bubble.CanQuery = false
	bubble.CanTouch = false
	bubble.CastShadow = false
	-- Welded to the root: massless so it never changes how the character moves or flies.
	bubble.Massless = true
	bubble.CFrame = root.CFrame
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = bubble
	weld.Parent = bubble
	bubble.Parent = character

	shields[player] = bubble
	player:SetAttribute(Attributes.Shielding, true)
	playEffect("ShieldUp", root.Position)

	if ShieldConfig.BlocksAttacks and stopBeam(player, true) then
		-- Tells the client its beam ended (it may still be holding the button).
		reject(player, "Beam", "Busy")
	end
end

local function damageConstruct(model: Model, amount: number)
	local construct = constructs[model]
	if construct == nil or not (amount > 0) then
		return
	end
	local health = model:GetAttribute(HEALTH_ATTRIBUTE)
	if type(health) ~= "number" then
		return
	end
	local remaining = math.max(0, health - amount)
	model:SetAttribute(HEALTH_ATTRIBUTE, remaining)
	if remaining <= 0 then
		construct.finish()
	end
end

local function tickBeam(player: Player, beam: BeamState)
	local root = Characters.GetRootPart(player, true)
	if root == nil then
		-- Died or despawned (the Died hook normally gets here first).
		stopBeam(player, false)
		return
	end
	if RingService:IsBlocked(player) then
		if stopBeam(player, false) then
			reject(player, "Beam", "Busy")
		end
		return
	end
	local rate = BeamConfig.TickRate
	if not RingService:Drain(player, BeamConfig.WillpowerPerSecond / rate, BeamConfig.ChargePerSecond / rate) then
		-- RingService.Depleted may already have stopped it (and said why).
		if stopBeam(player, true) then
			reject(player, "Beam", if RingService:GetCharge(player) <= 0 then "NoCharge" else "NoWillpower")
		end
		return
	end

	local ring = RingService:GetRingPart(player)
	local origin = if ring ~= nil then ring.Position else root.Position
	local offset = beam.aim - origin
	if offset.Magnitude < MIN_DIRECTION then
		return
	end
	local direction = offset.Unit * BeamConfig.Range

	local exclude = passableConstructs(player)
	local character = player.Character
	if character ~= nil then
		table.insert(exclude, character)
	end
	local result = raycast(origin, direction, exclude)
	local endPoint = if result ~= nil then result.Position else origin + direction

	if result ~= nil then
		local damage = BeamConfig.DamagePerSecond / rate
		local target = CombatService:ResolveTarget(result.Instance, player)
		if target ~= nil then
			local dealt = CombatService:ApplyDamage(player, target, damage, "Beam")
			local now = os.clock()
			if dealt > 0 and now - beam.lastImpactEffect >= BeamConfig.ImpactEffectInterval then
				beam.lastImpactEffect = now
				playEffect("BeamImpact", endPoint)
			end
		elseif CombatConfig.PvPEnabled then
			-- With PvP on, beams also wear down other players' walls.
			local model = constructOf(result.Instance)
			if model ~= nil and constructs[model].owner ~= player then
				damageConstruct(model, damage)
			end
		end
	end

	Remotes.BeamVisual:FireAllExcept(player, player, origin, endPoint)
end

local function tickShield(player: Player, bubble: BasePart)
	if bubble.Parent == nil or Characters.GetRootPart(player, true) == nil then
		dropShield(player, false)
		return
	end
	if RingService:IsBlocked(player) then
		if dropShield(player, false) then
			reject(player, "Shield", "Busy")
		end
		return
	end
	local rate = BeamConfig.TickRate
	if not RingService:Drain(player, ShieldConfig.WillpowerPerSecond / rate, ShieldConfig.ChargePerSecond / rate) then
		if dropShield(player, true) then
			reject(player, "Shield", if RingService:GetCharge(player) <= 0 then "NoCharge" else "NoWillpower")
		end
	end
end

-- One tick for every active beam and shield (each in its own thread, so one
-- player's error never stops the others).
local function tickAll()
	for player, beam in table.clone(beams) do
		if beams[player] == beam then
			task.spawn(tickBeam, player, beam)
		end
	end
	for player, bubble in table.clone(shields) do
		if bubble ~= nil and shields[player] == bubble then
			task.spawn(tickShield, player, bubble)
		end
	end
end

local function startTickLoop()
	local interval = 1 / BeamConfig.TickRate
	local elapsed = 0
	RunService.Heartbeat:Connect(function(deltaTime: number)
		elapsed += deltaTime
		if elapsed < interval then
			return
		end
		-- At most one tick per frame: after a server hitch, carry on rather than
		-- firing a burst of catch-up ticks.
		elapsed = math.min(elapsed - interval, interval)
		tickAll()
	end)
end

-- Construct building blocks -----------------------------------------------------

local function constructPart(model: Model, name: string, cframe: CFrame, size: Vector3, style: PartStyle?): Part
	local options: PartStyle = style or {}
	local part = Instance.new("Part")
	part.Name = name
	if options.Shape ~= nil then
		part.Shape = options.Shape
	end
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Material = Enum.Material.Neon
	part.Color = PowersConfig.ConstructColor
	part.Transparency = options.Transparency or PowersConfig.ConstructTransparency
	part.CastShadow = false
	local solid = options.Solid == true
	part.CanCollide = solid
	part.CanQuery = solid
	part.CanTouch = false
	part.Parent = model
	return part
end

local function addGlow(part: BasePart)
	local light = Instance.new("PointLight")
	light.Color = PowersConfig.ConstructColor
	light.Range = PowersConfig.ConstructLight.Range
	light.Brightness = PowersConfig.ConstructLight.Brightness
	light.Shadows = false
	light.Parent = part
end

local function newConstructModel(player: Player, id: Types.ConstructId): Model
	local model = Instance.new("Model")
	model.Name = id
	-- Streams to a client whole or not at all, never as a few loose bars.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:AddTag(Tags.Construct)
	model:SetAttribute(Attributes.ConstructId, id)
	model:SetAttribute(Attributes.OwnerUserId, player.UserId)
	return model
end

-- Puts a finished construct into the world and starts tracking it.
local function register(player: Player, id: Types.ConstructId, model: Model, finish: () -> ())
	constructs[model] = { id = id, owner = player, finish = finish }
	model.Parent = getConstructFolder()
	PowerService.ConstructCast:Fire(player, id, model)
end

-- Where a construct aimed at `aimPoint` goes: the aim point, or the first
-- thing in the way of the line from the caster's head to it.
local function castPoint(player: Player, character: Model, root: BasePart, aimPoint: Vector3): Vector3
	local head = character:FindFirstChild("Head")
	local eye = if head ~= nil and head:IsA("BasePart") then head.Position else root.Position
	local offset = aimPoint - eye
	if offset.Magnitude < MIN_DIRECTION then
		return aimPoint
	end
	local exclude = passableConstructs(player)
	for _, other in allCharacters() do
		table.insert(exclude, other)
	end
	local result = raycast(eye, offset, exclude)
	return if result ~= nil then result.Position else aimPoint
end

-- The nearest target within the cage's capture radius of `point` that is not caged already.
local function findCageTarget(player: Player, point: Vector3): Model?
	local best: Model? = nil
	local bestDistance = math.huge
	for _, target in CombatService:GetTargetsInRadius(point, ConstructConfigs.Cage.CaptureRadius, player) do
		if target:GetAttribute(CAGED_ATTRIBUTE) ~= true then
			local root = CombatService:GetTargetRoot(target)
			local position = if root ~= nil then root.Position else target:GetPivot().Position
			local distance = (position - point).Magnitude
			if distance < bestDistance then
				best = target
				bestDistance = distance
			end
		end
	end
	return best
end

-- Wall ---------------------------------------------------------------------------

local function castWall(player: Player, root: BasePart, point: Vector3, strength: number)
	local config = ConstructConfigs.Wall
	local size = config.Size

	-- Facing the caster horizontally (the way they look if the point is right
	-- under them), and never so close that it would stand on them.
	local toCaster = root.Position - point
	local facing = horizontal(toCaster) or horizontal(-root.CFrame.LookVector) or Vector3.zAxis
	if Vector3.new(toCaster.X, 0, toCaster.Z).Magnitude < config.MinDistance then
		point = Vector3.new(root.Position.X, point.Y, root.Position.Z) - facing * config.MinDistance
	end

	-- Stand on the ground below the point. Characters, targets and constructs are not ground.
	local exclude = allCharacters()
	table.insert(exclude, getConstructFolder())
	for _, target in CollectionService:GetTagged(Tags.Damageable) do
		table.insert(exclude, target)
	end
	local depth = config.GroundSnapDistance + GROUND_PROBE_LIFT
	local ground = raycast(point + Vector3.yAxis * GROUND_PROBE_LIFT, Vector3.yAxis * -depth, exclude)
	local bottom = if ground ~= nil
		then ground.Position - Vector3.yAxis * config.GroundSink
		else point - Vector3.yAxis * (size.Y / 2)
	local center = bottom + Vector3.yAxis * (size.Y / 2)
	-- The panel's front (-Z) faces the caster; X is its width.
	local cframe = CFrame.lookAt(center, center + facing)

	local model = newConstructModel(player, "Wall")
	local panel = constructPart(model, "Panel", cframe, size, { Solid = true })
	addGlow(panel)
	-- Bright outline: top and bottom edges, then the two sides (between them).
	local edge = PowersConfig.ConstructEdge.Thickness
	local edgeDepth = size.Z + edge
	for _, side in { -1, 1 } do
		constructPart(
			model,
			"Edge",
			cframe * CFrame.new(0, side * size.Y / 2, 0),
			Vector3.new(size.X + edge, edge, edgeDepth),
			EDGE_STYLE
		)
		constructPart(
			model,
			"Edge",
			cframe * CFrame.new(side * size.X / 2, 0, 0),
			Vector3.new(edge, size.Y - edge, edgeDepth),
			EDGE_STYLE
		)
	end
	model.PrimaryPart = panel
	local health = config.Health * strength
	model:SetAttribute(HEALTH_ATTRIBUTE, health)
	model:SetAttribute(MAX_HEALTH_ATTRIBUTE, health)

	local expiry: thread? = nil
	local function finish()
		if constructs[model] == nil then
			return
		end
		constructs[model] = nil
		cancel(expiry)
		playEffect("WallShatter", panel.Position)
		model:Destroy()
	end
	register(player, "Wall", model, finish)
	playEffect("WallSpawn", center)
	expiry = task.delay(config.Duration * strength, finish)
end

-- Hammer -------------------------------------------------------------------------

local function castHammer(player: Player, root: BasePart, point: Vector3, strength: number)
	local config = ConstructConfigs.Hammer
	local headSize = config.HeadSize
	local forward = horizontal(point - root.Position) or horizontal(root.CFrame.LookVector) or -Vector3.zAxis

	-- The hammer swings about the far end of its handle (the "hinge"), placed
	-- so that in the impact pose the handle lies level, pointing away from the
	-- caster, and the head's lower face rests on the aim point. Hinge-local -Z
	-- runs down the handle to the head; +Y is up at impact.
	local reach = config.HandleLength + headSize.Z / 2
	local hinge = point - forward * reach + Vector3.yAxis * (headSize.Y / 2)
	local impactPose = CFrame.lookAt(hinge, hinge + forward)
	local raised = math.rad(config.RaiseAngle)
	-- Turning about hinge-local X by a positive angle lifts the head up and back.
	local startPose = impactPose * CFrame.Angles(raised, 0, 0)

	local model = newConstructModel(player, "Hammer")
	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}
	local function piece(name: string, offset: CFrame, size: Vector3, style: PartStyle?): Part
		local part = constructPart(model, name, startPose * offset, size, style)
		table.insert(parts, part)
		table.insert(offsets, offset)
		return part
	end

	local handle = config.HandleDiameter
	local edge = PowersConfig.ConstructEdge.Thickness
	-- Cylinders run along their X axis: turned a quarter about Y to run along the handle.
	local alongHandle = CFrame.Angles(0, math.rad(90), 0)
	piece(
		"Handle",
		CFrame.new(0, 0, -config.HandleLength / 2) * alongHandle,
		Vector3.new(config.HandleLength, handle, handle),
		{ Shape = Enum.PartType.Cylinder }
	)
	piece(
		"Pommel",
		CFrame.new(0, 0, handle * 0.3),
		Vector3.one * (handle * 1.8),
		{ Shape = Enum.PartType.Ball, Transparency = EDGE_STYLE.Transparency }
	)
	piece(
		"Collar",
		CFrame.new(0, 0, -(config.HandleLength - edge)) * alongHandle,
		Vector3.new(edge * 2, handle * 1.7, handle * 1.7),
		{ Shape = Enum.PartType.Cylinder, Transparency = EDGE_STYLE.Transparency }
	)
	local headOffset = CFrame.new(0, 0, -reach)
	local head = piece("Head", headOffset, headSize)
	addGlow(head)
	-- Bright bands just inside both striking faces.
	for _, side in { -1, 1 } do
		piece(
			"Band",
			headOffset * CFrame.new(0, side * (headSize.Y / 2 - edge * 2), 0),
			Vector3.new(headSize.X + edge, edge * 2, headSize.Z + edge),
			EDGE_STYLE
		)
	end
	model.PrimaryPart = head

	local function finish()
		if constructs[model] == nil then
			return
		end
		constructs[model] = nil
		model:Destroy()
	end
	register(player, "Hammer", model, finish)

	-- The swing: the angle falls with the square of time, like a dropped weight.
	local started = os.clock()
	while true do
		if constructs[model] == nil then
			-- Removed mid-swing (the owner left): no impact.
			return
		end
		local alpha = math.min((os.clock() - started) / config.SwingTime, 1)
		local frame = impactPose * CFrame.Angles(raised * (1 - alpha * alpha), 0, 0)
		local cframes = table.create(#offsets)
		for index, offset in offsets do
			cframes[index] = frame * offset
		end
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		if alpha >= 1 then
			break
		end
		RunService.Heartbeat:Wait()
	end

	for _, target in CombatService:GetTargetsInRadius(point, config.Radius, player) do
		CombatService:ApplyDamage(player, target, config.Damage * strength, "Hammer")
		local targetRoot = CombatService:GetTargetRoot(target)
		local outward = if targetRoot ~= nil then horizontal(targetRoot.Position - point) else nil
		CombatService:Knockback(target, ((outward or forward) + Vector3.yAxis).Unit * config.Knockback)
	end
	playEffect("HammerImpact", point, config.Radius)
	task.delay(config.LingerTime, finish)
end

-- Cage ---------------------------------------------------------------------------

local function castCage(player: Player, target: Model, strength: number)
	local config = ConstructConfigs.Cage
	-- A ring of bars around the target's bounding box (measured upright, so the
	-- horizontal diagonal is the widest it can be whichever way it faces).
	local boxCFrame, boxSize = target:GetBoundingBox()
	local radius = math.sqrt(boxSize.X * boxSize.X + boxSize.Z * boxSize.Z) / 2 + config.Padding
	local height = boxSize.Y + config.Padding + CAGE_SINK
	local base = boxCFrame.Position - Vector3.yAxis * (boxSize.Y / 2 + CAGE_SINK)
	local center = base + Vector3.yAxis * (height / 2)

	local model = newConstructModel(player, "Cage")
	local core = constructPart(model, "Core", CFrame.new(center), Vector3.one, { Transparency = 1 })
	addGlow(core)
	model.PrimaryPart = core

	local count = math.clamp(math.floor(config.BarCount), 3, 24)
	local bar = config.BarThickness
	local edge = PowersConfig.ConstructEdge.Thickness
	local corners: { Vector3 } = {}
	for index = 1, count do
		local angle = (index - 1) / count * math.pi * 2
		corners[index] = base + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	end
	for index, corner in corners do
		-- Upright bar: a cylinder (axis X) turned a quarter about Z to stand up.
		constructPart(
			model,
			"Bar",
			CFrame.new(corner + Vector3.yAxis * (height / 2)) * CFrame.Angles(0, 0, math.rad(90)),
			Vector3.new(height, bar, bar),
			{ Shape = Enum.PartType.Cylinder, Solid = true }
		)
		-- Floor and top rings, one segment per pair of neighbouring bars.
		local nextCorner = corners[index % count + 1]
		for _, y in { 0, height } do
			local from = corner + Vector3.yAxis * y
			local to = nextCorner + Vector3.yAxis * y
			constructPart(
				model,
				"Ring",
				CFrame.lookAt((from + to) / 2, to),
				Vector3.new(edge, edge, (to - from).Magnitude + edge),
				EDGE_STYLE
			)
		end
	end

	-- Trap the target: no walking or jumping, root held in place, and (for a
	-- player) no powers. Everything changed is put back on release.
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	local walkSpeed, jumpPower, jumpHeight = 0, 0, 0
	if humanoid ~= nil then
		walkSpeed, jumpPower, jumpHeight = humanoid.WalkSpeed, humanoid.JumpPower, humanoid.JumpHeight
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
	end
	local targetRoot = CombatService:GetTargetRoot(target)
	local anchoredByCage = targetRoot ~= nil and not targetRoot.Anchored
	if targetRoot ~= nil and anchoredByCage then
		targetRoot.Anchored = true
	end
	target:SetAttribute(CAGED_ATTRIBUTE, true)
	local victim = Players:GetPlayerFromCharacter(target)
	if victim ~= nil then
		-- Blocked first, so nothing can start again in between. A flyer is landed
		-- too: the anchored root would otherwise hang in the air still "flying"
		-- (and paying for it) until the cage opens.
		RingService:SetBlocked(victim, CAGED_BLOCK_REASON, true)
		stopAll(victim)
		FlightService:ForceLand(victim)
	end

	local connections: { RBXScriptConnection } = {}
	local expiry: thread? = nil
	local function finish()
		if constructs[model] == nil then
			return
		end
		constructs[model] = nil
		cancel(expiry)
		for _, connection in connections do
			connection:Disconnect()
		end
		if humanoid ~= nil then
			humanoid.WalkSpeed = walkSpeed
			humanoid.JumpPower = jumpPower
			humanoid.JumpHeight = jumpHeight
		end
		if targetRoot ~= nil and anchoredByCage then
			targetRoot.Anchored = false
		end
		target:SetAttribute(CAGED_ATTRIBUTE, nil)
		if victim ~= nil then
			RingService:SetBlocked(victim, CAGED_BLOCK_REASON, false)
		end
		playEffect("CageRelease", center)
		model:Destroy()
	end

	-- Released early if the target dies or leaves the world.
	if humanoid ~= nil then
		table.insert(connections, humanoid.Died:Connect(finish))
	end
	table.insert(
		connections,
		target.AncestryChanged:Connect(function()
			if not target:IsDescendantOf(Workspace) then
				finish()
			end
		end)
	)
	register(player, "Cage", model, finish)
	playEffect("CageClose", center)
	expiry = task.delay(config.Duration * strength, finish)
end

-- Casting --------------------------------------------------------------------------

local function castConstruct(player: Player, id: Types.ConstructId, aimPoint: Vector3)
	local cost = constructCost(id)
	if shields[player] ~= nil and ShieldConfig.BlocksAttacks then
		reject(player, id, "Busy")
		return
	end
	local character = player.Character
	local root = Characters.GetRootPart(player, true)
	if character == nil or root == nil then
		reject(player, id, "NotReady")
		return
	end

	local aim = PowersConfig.Aim
	local tolerance = aim.RangeTolerance + root.AssemblyLinearVelocity.Magnitude * aim.LatencyAllowance
	if (aimPoint - root.Position).Magnitude > cost.Range + tolerance then
		reject(player, id, "OutOfRange")
		return
	end
	local point = castPoint(player, character, root, aimPoint)

	-- Looked for before paying, so a cage cast at nothing costs nothing.
	local cageTarget: Model? = nil
	if id == "Cage" then
		cageTarget = findCageTarget(player, point)
		if cageTarget == nil then
			reject(player, id, "NoTarget")
			return
		end
	end

	-- Strength comes from the willpower the caster had before paying for this cast.
	local strength = RingService:GetStrength(player)
	local ok: boolean, reason: Types.PowerRejectReason? =
		RingService:TrySpend(player, id, cost.MinWillpower, cost.WillpowerCost, cost.ChargeCost)
	if not ok then
		reject(player, id, reason)
		return
	end
	RingService:StartCooldown(player, id, cost.Cooldown)

	if id == "Wall" then
		castWall(player, root, point, strength)
	elseif id == "Hammer" then
		castHammer(player, root, point, strength)
	elseif cageTarget ~= nil then
		castCage(player, cageTarget, strength)
	end
end

-- Players ----------------------------------------------------------------------------

local function watchCharacter(player: Player, character: Model)
	local humanoid = Characters.WaitForHumanoid(character, WorldConfig.Spawning.CharacterLoadTimeout)
	if humanoid == nil or player.Character ~= character then
		return
	end
	humanoid.Died:Once(function()
		if player.Character == character then
			stopAll(player)
		end
	end)
end

local function onPlayerAdded(player: Player)
	-- PlayerAdded and the "already in game" pass in Start can both reach a player.
	if playerConnections[player] ~= nil then
		return
	end
	playerConnections[player] = {
		player.CharacterAdded:Connect(function(character: Model)
			watchCharacter(player, character)
		end),
		player.CharacterRemoving:Connect(function()
			stopAll(player)
		end),
	}
	local character = player.Character
	if character ~= nil then
		task.spawn(watchCharacter, player, character)
	end
end

local function onPlayerRemoving(player: Player)
	stopAll(player)
	local connections = playerConnections[player]
	if connections ~= nil then
		for _, connection in connections do
			connection:Disconnect()
		end
	end
	playerConnections[player] = nil
	-- Cloned: finishing a construct removes it from the table.
	for _, construct in table.clone(constructs) do
		if construct.owner == player then
			construct.finish()
		end
	end
end

-- API ------------------------------------------------------------------------------

-- Stops the beam and drops the shield without starting their cooldowns (the
-- battery, death, being caged).
function PowerService.StopAll(_self: PowerService, player: Player)
	stopAll(player)
end

function PowerService.IsShielding(_self: PowerService, player: Player): boolean
	return shields[player] ~= nil
end

function PowerService.IsFiringBeam(_self: PowerService, player: Player): boolean
	return beams[player] ~= nil
end

-- Wears down a construct that has health (a wall); it shatters at 0.
-- Constructs without health ignore damage.
function PowerService.DamageConstruct(_self: PowerService, model: Model, amount: number)
	damageConstruct(model, amount)
end

function PowerService.Init(_self: PowerService)
	Remotes.BeamStart:Connect(startBeam)
	Remotes.BeamAim:Connect(function(player: Player, aimPoint: Vector3)
		-- Unreliable: an aim update may arrive after BeamStop; then there is no beam to aim.
		local beam = beams[player]
		if beam ~= nil then
			beam.aim = aimPoint
		end
	end)
	Remotes.BeamStop:Connect(function(player: Player)
		stopBeam(player, true)
	end)
	Remotes.SetShield:Connect(function(player: Player, raised: boolean)
		if raised then
			raiseShield(player)
		else
			dropShield(player, true)
		end
	end)
	Remotes.CastConstruct:Connect(castConstruct)

	-- Willpower or charge hit zero (whatever spent it): held powers stop.
	RingService.Depleted:Connect(function(player: Player, resource: RingService.Resource)
		local reason: Types.PowerRejectReason = if resource == "Charge" then "NoCharge" else "NoWillpower"
		if stopBeam(player, true) then
			reject(player, "Beam", reason)
		end
		if dropShield(player, true) then
			reject(player, "Shield", reason)
		end
	end)
end

function PowerService.Start(_self: PowerService)
	getConstructFolder()
	startTickLoop()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

export type PowerService = typeof(PowerService)

return PowerService
