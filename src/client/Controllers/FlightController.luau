--!strict
--[[
	FlightController: flying, on the client.

	The client moves its own character (no input lag); the server decides who
	may fly and boost and pays for it (FlightService). The handshake:
	  * Fly (ToggleFlight, bound for the whole session) first runs a quick
	    check of the replicated ring attributes (alive, ring ready, not
	    recharging, charge left, enough willpower). A refusal fires .Refused and
	    nothing else happens. Otherwise the character takes off AT ONCE and
	    Remotes.SetFlying(true) asks the server.
	  * It lands again if the server says no: a PowerRejected("Flight") while the
	    takeoff is unconfirmed, the Flying attribute turning false while flying,
	    or Flying still not true Config.Flight.ServerAckTimeout seconds later.
	    One subtlety: taking off again before the server heard the last landing
	    means Flying first turns false (that landing) and then true; that one
	    false is expected and ignored.
	  * Boost works the same way while flying (Remotes.SetBoosting). A refused
	    boost (PowerRejected("Flight", "NoWillpower") once the takeoff is
	    confirmed), Boosting turning false (the server ran out of willpower for
	    it) or no confirmation in time ends the boost, never the flight.
	  * After a landing the server's Flying attribute is checked once more after
	    the same timeout, and the landing re-sent if it was lost.

	THE FEEL. While flying the Humanoid is PlatformStand (no walking, no default
	animations) and a LinearVelocity plus an AlignOrientation on an Attachment in
	the root part carry and pose the body. Every physics step (PreSimulation):
	  * Movement input comes from Roblox's PlayerModule (keyboard, thumbstick and
	    gamepad alike) and is mapped through the camera in 3D: forward flies where
	    the camera looks (except within LevelFlightDeadZone degrees of the
	    horizon, which flies level), right strafes. Ascend / Descend (bound only
	    while flying; Roblox's jump button climbs too) add VerticalSpeed.
	  * The velocity eases toward CruiseSpeed or BoostSpeed by exponential
	    smoothing (Acceleration, BoostAcceleration, Deceleration): weighty, never
	    sluggish. Hitting something bleeds speed off instead of grinding into it.
	  * The body faces where it travels (the camera's yaw while hovering or firing
	    the beam), pitches into the flying pose with speed and follows climbs and
	    dives head-first, banks into turns, and bobs gently while hovering.
	  * Near the ground a dive brakes into a skim; holding Descend there lands.
	  * At the edge of the play area the flight bends back inward ahead of time
	    (looking BoundaryLookAhead seconds ahead) instead of hitting a wall.
	  * Camera: combat mode ("Flight": shoulder view, crosshair, mouse steering
	    on PC), extra field of view with speed and boost, a kick of shake on
	    takeoff and boost.
	  * Config.Assets.Animations.FlyIdle / FlyForward play blended by speed when
	    set (skipped when empty).
	Boost is held on the keyboard and toggled on gamepad and touch
	(Config.Flight.BoostToggle). Death, respawning and losing the character all
	land and clean up.

	Sounds and effects are not played here: SoundController and VFXController
	follow the signals below and the replicated attributes.

	API:
	  FlightController:IsFlying(): boolean
	  FlightController:IsBoosting(): boolean
	  FlightController:GetVelocity(): Vector3     (the flight velocity; the root's
	                                               velocity when not flying)
	  FlightController.TookOff       Signal()
	  FlightController.Landed        Signal()
	  FlightController.BoostChanged  Signal(boosting)
	  FlightController.Refused       Signal(reason)   (a client-side check refused
	                                                   takeoff or boost)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local AssetsConfig = require(Shared.Config.Assets)
local Boundary = require(Shared.Util.Boundary)
local FlightConfig = require(Shared.Config.Flight)
local InputConfig = require(Shared.Config.Input)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Util.Signal)
local TagsModule = require(Shared.Util.Tags)
local Text = require(Shared.Config.Text)
local Types = require(Shared.Types)

local BoundaryController = require(script.Parent.BoundaryController)
local CameraController = require(script.Parent.CameraController)
local InputController = require(script.Parent.InputController)

-- The part of Roblox's ControlModule used here (PlayerModule:GetControls()).
type Controls = {
	GetMoveVector: (self: Controls) -> Vector3,
}

type Body = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
}

type Flight = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	-- The movers live under the attachment: destroying it removes them all.
	attachment: Attachment,
	mover: LinearVelocity,
	aligner: AlignOrientation,
	connections: { RBXScriptConnection },
	idleTrack: AnimationTrack?,
	forwardTrack: AnimationTrack?,
	forwardWeight: number,
	savedAutoRotate: boolean,
	-- Root height above the feet when standing (ground checks measure the feet).
	standingHeight: number,
	groundParams: RaycastParams,
	startedAt: number,

	-- Motion. velocity is the smoothed flight velocity; lift is the part of its
	-- Y that came from Ascend / Descend and the takeoff kick, which move the
	-- body without tilting it; commanded is what the mover was last told.
	velocity: Vector3,
	lift: number,
	commanded: Vector3,
	-- Pose, in radians: heading, forward pitch (0 upright, pi/2 level), bank.
	yaw: number,
	pitch: number,
	bank: number,

	ascendHeld: boolean,
	descendHeld: boolean,
	lastMoveAt: number,

	-- Server handshake (see the header).
	takeoffPending: boolean,
	takeoffSentAt: number,
	awaitingLandEcho: boolean,
	boosting: boolean,
	boostToggled: boolean,
	boostPending: boolean,
	boostSentAt: number,
}

local LocalPlayer = Players.LocalPlayer
local Attributes = TagsModule.Attributes
local cameraConfig = FlightConfig.Camera

-- Every standard Humanoid rig (R15, R6, custom StarterCharacter) names its root this.
local ROOT_PART_NAME = "HumanoidRootPart"
local COMBAT_REASON = "Flight"
local BOOST_FOV_SOURCE = "Boost"
local SPEED_FOV_SOURCE = "FlightSpeed"
local FLIGHT_ACTIONS = { "Ascend", "Descend", "Boost" }
local HALF_PI = math.pi / 2
-- Longest step simulated at once: after a hitch the flight eases on instead of jumping.
local MAX_STEP = 0.1
-- Movement input below this (0..1 stick deflection) counts as none.
local MOVE_DEADZONE = 0.05
-- Extra studs the ground probe looks below what braking and landing need.
local GROUND_PROBE_MARGIN = 2
-- An R6 rig has no HipHeight: its 2-stud legs hold the root up.
local R6_LEG_HEIGHT = 2
-- Changes of an animation weight smaller than this are not sent.
local WEIGHT_STEP = 0.02
local NEUTRAL = Vector3.zero

local current: Flight? = nil
local controls: Controls? = nil
-- os.clock() of the last Fly press that took off or landed, and of the last
-- landing told to the server.
local lastToggleAt = -math.huge
local lastLandSentAt = -math.huge

local FlightController = {
	TookOff = Signal.new() :: Signal.Signal<()>,
	Landed = Signal.new() :: Signal.Signal<()>,
	BoostChanged = Signal.new() :: Signal.Signal<boolean>,
	Refused = Signal.new() :: Signal.Signal<Types.PowerRejectReason>,
}

-- Helpers ---------------------------------------------------------------------

-- Exponential smoothing factor for `rate` (1/s) over `deltaTime` seconds.
local function smoothing(rate: number, deltaTime: number): number
	return 1 - math.exp(-rate * deltaTime)
end

local function wrapAngle(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

-- Yaw (radians about +Y) that makes CFrame.Angles(0, yaw, 0) look along `direction`.
local function yawOf(direction: Vector3): number
	return math.atan2(-direction.X, -direction.Z)
end

local function touchLabel(actionName: string): string
	local touch = InputConfig.Actions[actionName].Touch
	return if touch ~= nil then touch.Label else actionName
end

-- The local character while it is alive and in the world.
local function getBody(): Body?
	local character = LocalPlayer.Character
	if character == nil or not character:IsDescendantOf(Workspace) then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild(ROOT_PART_NAME)
	if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
		return nil
	end
	return { character = character, humanoid = humanoid, root = root }
end

local function standingHeight(humanoid: Humanoid, root: BasePart): number
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		return humanoid.HipHeight + root.Size.Y / 2
	end
	return root.Size.Y / 2 + R6_LEG_HEIGHT
end

-- Client mirror of the server's takeoff check (RingService:CanUse), for instant
-- feedback only: the server decides.
local function takeoffRefusal(body: Body?): Types.PowerRejectReason?
	local willpower = LocalPlayer:GetAttribute(Attributes.Willpower)
	local charge = LocalPlayer:GetAttribute(Attributes.RingCharge)
	if body == nil or type(willpower) ~= "number" or type(charge) ~= "number" then
		return "NotReady"
	end
	if LocalPlayer:GetAttribute(Attributes.Recharging) == true or body.root.Anchored then
		return "Busy"
	end
	if charge <= 0 then
		return "NoCharge"
	end
	local readyAt = LocalPlayer:GetAttribute(Attributes.CooldownPrefix .. "Flight")
	if type(readyAt) == "number" and readyAt > Workspace:GetServerTimeNow() then
		return "Cooldown"
	end
	if willpower < FlightConfig.MinWillpowerToTakeOff then
		return "NoWillpower"
	end
	return nil
end

-- Raw movement input: X right, -Z forward, magnitude at most 1.
local function readMoveVector(humanoid: Humanoid, forward: Vector3, right: Vector3): Vector3
	local controlModule = controls
	local move: Vector3
	if controlModule ~= nil then
		move = controlModule:GetMoveVector()
	else
		-- Without the PlayerModule: Humanoid.MoveDirection is the same input
		-- already turned by the camera's yaw, so turn it back.
		local direction = humanoid.MoveDirection
		move = Vector3.new(direction:Dot(right), 0, -direction:Dot(forward))
	end
	-- The keyboard reports diagonals longer than 1.
	return if move.Magnitude > 1 then move.Unit else move
end

local function loadControls()
	local playerScripts = LocalPlayer:WaitForChild("PlayerScripts", 10)
	local playerModule = if playerScripts ~= nil then playerScripts:WaitForChild("PlayerModule", 10) else nil
	if playerModule == nil or not playerModule:IsA("ModuleScript") then
		warn("[FlightController] No PlayerModule found; flight steers from Humanoid.MoveDirection")
		return
	end
	-- Roblox's own module, untyped here: checked by shape before use.
	local loaded, module = pcall(require, playerModule)
	if not loaded or type(module) ~= "table" or type(module.GetControls) ~= "function" then
		return
	end
	local found, controlModule = pcall(module.GetControls, module)
	if found and type(controlModule) == "table" and type(controlModule.GetMoveVector) == "function" then
		controls = controlModule :: Controls
	end
end

-- Animations ------------------------------------------------------------------

local function playTrack(animator: Animator?, animationId: string, weight: number): AnimationTrack?
	if animator == nil or animationId == "" then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	local loaded, track = pcall(animator.LoadAnimation, animator, animation)
	if not loaded then
		return nil
	end
	track.Looped = true
	-- Below Action, so a power's pose (e.g. the beam arm) plays over it.
	track.Priority = Enum.AnimationPriority.Movement
	track:Play(FlightConfig.AnimationFadeTime, math.max(weight, WEIGHT_STEP))
	return track
end

local function stopTrack(track: AnimationTrack?)
	if track == nil then
		return
	end
	local fadeTime = FlightConfig.AnimationFadeTime
	track:Stop(fadeTime)
	task.delay(fadeTime, function()
		track:Destroy()
	end)
end

local function updateAnimations(flight: Flight, speed: number)
	local idle, forward = flight.idleTrack, flight.forwardTrack
	-- With only one of the two set, it plays at full weight all the time.
	if idle == nil or forward == nil then
		return
	end
	local weight = math.clamp(speed / FlightConfig.CruiseSpeed, 0, 1)
	if math.abs(weight - flight.forwardWeight) < WEIGHT_STEP then
		return
	end
	flight.forwardWeight = weight
	-- A weight of exactly 0 can stop a track on some rigs; keep both alive.
	forward:AdjustWeight(math.max(weight, WEIGHT_STEP), 0.1)
	idle:AdjustWeight(math.max(1 - weight, WEIGHT_STEP), 0.1)
end

-- Boost -----------------------------------------------------------------------

local function setBoosting(flight: Flight, on: boolean, tellServer: boolean, toggled: boolean)
	if flight.boosting == on then
		return
	end
	flight.boosting = on
	flight.boostToggled = on and toggled
	if on then
		flight.boostPending = true
		flight.boostSentAt = os.clock()
		flight.lastMoveAt = os.clock()
		Remotes.SetBoosting:Fire(true)
		CameraController:SetFovOffset(BOOST_FOV_SOURCE, cameraConfig.BoostFov - cameraConfig.NormalFov)
		CameraController:Shake(cameraConfig.BoostShake.Intensity, cameraConfig.BoostShake.Duration)
	else
		flight.boostPending = false
		if tellServer then
			Remotes.SetBoosting:Fire(false)
		end
		CameraController:SetFovOffset(BOOST_FOV_SOURCE, 0)
	end
	InputController:SetTouchLabel("Boost", if flight.boostToggled then Text.Flight.CruiseLabel else touchLabel("Boost"))
	FlightController.BoostChanged:Fire(on)
end

local function onBoost(phase: Types.ActionPhase)
	local flight = current
	if flight == nil then
		return
	end
	local toggleMode = FlightConfig.BoostToggle.Devices[InputController:GetDevice()] == true
	if phase == "End" then
		-- A held boost ends on release; a toggled one only on the next press.
		if flight.boosting and not flight.boostToggled then
			setBoosting(flight, false, true, false)
		end
		return
	end
	if flight.boosting then
		if toggleMode or flight.boostToggled then
			setBoosting(flight, false, true, false)
		end
		return
	end
	local willpower = LocalPlayer:GetAttribute(Attributes.Willpower)
	if type(willpower) ~= "number" then
		FlightController.Refused:Fire("NotReady")
		return
	end
	if willpower < FlightConfig.MinWillpowerToBoost then
		FlightController.Refused:Fire("NoWillpower")
		return
	end
	setBoosting(flight, true, true, toggleMode)
end

-- Landing ---------------------------------------------------------------------

-- Re-sends a landing the server may never have received (rate limited or lost
-- in a burst of presses): it still has this player flying and draining.
local function verifyLanded()
	if current ~= nil or LocalPlayer:GetAttribute(Attributes.Flying) ~= true then
		return
	end
	if os.clock() - lastLandSentAt >= FlightConfig.ServerAckTimeout then
		lastLandSentAt = os.clock()
		Remotes.SetFlying:Fire(false)
		task.delay(FlightConfig.ServerAckTimeout, verifyLanded)
	end
end

-- Ends the flight (if any). notifyServer: the client chose to land, so the
-- server must hear it; when the server landed us (or never let us fly) it
-- already knows.
local function land(notifyServer: boolean)
	local flight = current
	if flight == nil then
		return
	end
	-- Cleared first: the unbinds below send "End" to handlers that check it.
	current = nil

	for _, connection in flight.connections do
		connection:Disconnect()
	end
	table.clear(flight.connections)
	for _, actionName in FLIGHT_ACTIONS do
		InputController:UnbindAction(actionName)
	end
	InputController:SetTouchLabel("ToggleFlight", touchLabel("ToggleFlight"))

	stopTrack(flight.idleTrack)
	stopTrack(flight.forwardTrack)
	flight.attachment:Destroy()

	local humanoid, root = flight.humanoid, flight.root
	if humanoid.Parent ~= nil then
		humanoid.PlatformStand = false
		humanoid.AutoRotate = flight.savedAutoRotate
		if humanoid.Health > 0 and root.Parent ~= nil and not root.Anchored then
			-- Upright at the current heading, then falling: the Humanoid lands
			-- normally from wherever flight ended.
			root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, flight.yaw, 0)
			root.AssemblyAngularVelocity = Vector3.zero
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		end
	end

	if flight.boosting then
		CameraController:SetFovOffset(BOOST_FOV_SOURCE, 0)
		FlightController.BoostChanged:Fire(false)
	end
	CameraController:SetFovOffset(SPEED_FOV_SOURCE, 0)
	CameraController:SetCombatMode(COMBAT_REASON, false)

	if notifyServer then
		lastLandSentAt = os.clock()
		Remotes.SetFlying:Fire(false)
		task.delay(FlightConfig.ServerAckTimeout, verifyLanded)
	end
	FlightController.Landed:Fire()
end

-- Steering --------------------------------------------------------------------

-- Bends `target` back into the play area near its edge: the outward part is
-- cut down the deeper the flight would be in BoundaryLookAhead seconds (or is
-- now, if deeper), and an inward pull of up to BoundaryBendSpeed is added.
-- Smoothing toward the bent target turns the flight around in a curve.
local function bendAtBoundary(position: Vector3, velocity: Vector3, target: Vector3, speed: number): Vector3
	local predicted = Boundary.Evaluate(position + velocity * FlightConfig.BoundaryLookAhead)
	local depth, inward = predicted.Depth, predicted.Inward
	local now = BoundaryController:GetState()
	if now ~= nil and now.Depth > depth then
		depth, inward = now.Depth, now.Inward
	end
	if depth <= 0 or inward.Magnitude < 0.5 then
		return target
	end
	local fraction = math.min(depth, 1)
	local outward = -target:Dot(inward)
	local maxOutward = speed * (1 - fraction)
	if outward > maxOutward then
		target += inward * (outward - maxOutward)
	end
	local wantedInward = FlightConfig.BoundaryBendSpeed * fraction
	local inwardSpeed = target:Dot(inward)
	if inwardSpeed < wantedInward then
		target += inward * (wantedInward - inwardSpeed)
	end
	return target
end

-- Height of the feet above the ground below the root (nil: nothing within `reach`).
local function groundHeight(flight: Flight, reach: number): number?
	local origin = flight.root.Position
	local result = Workspace:Raycast(origin, Vector3.new(0, -(flight.standingHeight + reach), 0), flight.groundParams)
	if result == nil then
		return nil
	end
	return origin.Y - result.Position.Y - flight.standingHeight
end

local function updatePose(flight: Flight, cameraYaw: number, deltaTime: number)
	local poseVelocity = flight.velocity - Vector3.yAxis * flight.lift
	local flat = Vector3.new(poseVelocity.X, 0, poseVelocity.Z)
	local flatSpeed = flat.Magnitude
	local speed = poseVelocity.Magnitude
	-- While firing the beam the body keeps facing the crosshair.
	local aiming = LocalPlayer:GetAttribute(Attributes.BeamActive) == true

	-- Heading: the camera's yaw while hovering, blending into the direction of
	-- travel between FaceTravelMinSpeed and FaceTravelFullSpeed.
	local targetYaw = cameraYaw
	if not aiming and flatSpeed > FlightConfig.FaceTravelMinSpeed then
		local weight = math.clamp(
			(flatSpeed - FlightConfig.FaceTravelMinSpeed)
				/ (FlightConfig.FaceTravelFullSpeed - FlightConfig.FaceTravelMinSpeed),
			0,
			1
		)
		targetYaw = cameraYaw + wrapAngle(yawOf(flat) - cameraYaw) * weight
	end
	local turn = wrapAngle(targetYaw - flight.yaw) * smoothing(FlightConfig.TurnResponsiveness, deltaTime)
	flight.yaw = wrapAngle(flight.yaw + turn)

	-- Pitch: level flight leans MaxForwardPitch forward, a climb turns the body
	-- upright, a dive tips it head-first toward MaxDivePitch; all scaled by speed.
	local speedFactor = math.clamp(speed / FlightConfig.FullPitchSpeed, 0, 1)
	local elevation = if speed > 0.01 then math.asin(math.clamp(poseVelocity.Y / speed, -1, 1)) else 0
	local level = math.rad(FlightConfig.MaxForwardPitch)
	local pitchTarget = if elevation >= 0
		then level * (1 - elevation / HALF_PI)
		else level + (math.rad(FlightConfig.MaxDivePitch) - level) * (-elevation / HALF_PI)
	if aiming then
		-- Facing the crosshair: lean only as much as the travel is toward it
		-- (none when backing away while firing).
		local facing = Vector3.new(-math.sin(flight.yaw), 0, -math.cos(flight.yaw))
		pitchTarget *= if flatSpeed > 0.01 then math.clamp(flat:Dot(facing) / flatSpeed, 0, 1) else 0
	end
	pitchTarget *= speedFactor
	flight.pitch += (pitchTarget - flight.pitch) * smoothing(FlightConfig.PitchResponsiveness, deltaTime)

	-- Bank into turns, from how fast the heading turns, more at speed.
	local turnRate = math.deg(turn / deltaTime)
	local maxBank = FlightConfig.MaxBankAngle
	local bankTarget = math.rad(math.clamp(turnRate * FlightConfig.BankPerTurnRate, -maxBank, maxBank)) * speedFactor
	flight.bank += (bankTarget - flight.bank) * smoothing(FlightConfig.BankResponsiveness, deltaTime)

	-- Heading, then the roll about the horizontal heading, then the forward
	-- pitch (negative X rotation tips the head forward).
	flight.aligner.CFrame = CFrame.Angles(0, flight.yaw, 0)
		* CFrame.Angles(0, 0, flight.bank)
		* CFrame.Angles(-flight.pitch, 0, 0)
end

-- The flight step -------------------------------------------------------------

local function step(deltaTime: number)
	local flight = current
	if flight == nil then
		return
	end
	local root, humanoid = flight.root, flight.humanoid
	if root.Parent ~= flight.character or humanoid.Health <= 0 or not flight.character:IsDescendantOf(Workspace) then
		land(false)
		return
	end
	local dt = math.min(deltaTime, MAX_STEP)
	if dt <= 0 then
		return
	end
	local now = os.clock()

	-- Server handshake: a takeoff or boost it never confirmed is undone.
	if flight.takeoffPending and now - flight.takeoffSentAt > FlightConfig.ServerAckTimeout then
		if LocalPlayer:GetAttribute(Attributes.Flying) ~= true then
			land(true)
			return
		end
		flight.takeoffPending = false
		flight.awaitingLandEcho = false
	end
	if flight.boostPending and now - flight.boostSentAt > FlightConfig.ServerAckTimeout then
		if LocalPlayer:GetAttribute(Attributes.Boosting) == true then
			flight.boostPending = false
		else
			setBoosting(flight, false, true, false)
		end
	end

	-- Steering frame from the crosshair ray (no camera shake in it).
	local look = CameraController:GetAimRay().Direction
	local right = look:Cross(Vector3.yAxis)
	if right.Magnitude < 0.01 then
		-- Looking straight up or down: the camera's own right is still level.
		local camera = Workspace.CurrentCamera
		local cameraRight = if camera ~= nil then camera.CFrame.RightVector else Vector3.xAxis
		right = Vector3.new(cameraRight.X, 0, cameraRight.Z)
		if right.Magnitude < 0.01 then
			right = Vector3.xAxis
		end
	end
	right = right.Unit
	-- Level forward, a quarter turn left of right.
	local flatForward = Vector3.new(right.Z, 0, -right.X)
	-- "Fly where you look", with a level band around the horizon so cruising
	-- does not slowly sink under the default camera's downward tilt.
	local deadZone = math.rad(FlightConfig.LevelFlightDeadZone)
	local lookPitch = math.asin(math.clamp(look.Y, -1, 1))
	local steerPitch = math.sign(lookPitch)
		* math.max(0, math.abs(lookPitch) - deadZone)
		* HALF_PI
		/ (HALF_PI - deadZone)
	local forward = flatForward * math.cos(steerPitch) + Vector3.yAxis * math.sin(steerPitch)

	local move = readMoveVector(humanoid, flatForward, right)
	if move.Magnitude > MOVE_DEADZONE then
		flight.lastMoveAt = now
	end
	if flight.boostToggled and now - flight.lastMoveAt > FlightConfig.BoostToggle.IdleStop then
		setBoosting(flight, false, true, false)
	end
	-- Humanoid.Jump mirrors Roblox's jump input (Space, controller A, the touch
	-- jump button), which climbs too.
	local climb = if flight.ascendHeld or humanoid.Jump then 1 else 0
	local vertical = climb - (if flight.descendHeld then 1 else 0)

	local speed = if flight.boosting then FlightConfig.BoostSpeed else FlightConfig.CruiseSpeed
	local steer = forward * -move.Z + right * move.X
	if steer.Magnitude > 1 then
		steer = steer.Unit
	end
	local verticalSpeed = vertical * FlightConfig.VerticalSpeed
	local velocity = flight.velocity
	local target = bendAtBoundary(root.Position, velocity, steer * speed + Vector3.yAxis * verticalSpeed, speed)

	-- Blocked by something last step: bleed speed toward what really happened,
	-- so sliding along a wall never fires you off it at full speed.
	local actual = root.AssemblyLinearVelocity
	if (flight.commanded - actual).Magnitude > FlightConfig.CollisionTolerance then
		velocity += (actual - velocity) * smoothing(FlightConfig.CollisionResponsiveness, dt)
	end

	local rate = if target.Magnitude < velocity.Magnitude - 1
		then FlightConfig.Deceleration
		elseif flight.boosting then FlightConfig.BoostAcceleration
		else FlightConfig.Acceleration
	local alpha = smoothing(rate, dt)
	velocity += (target - velocity) * alpha
	flight.lift += (verticalSpeed - flight.lift) * alpha

	-- Ground: brake a descent so it stops GroundSkimHeight above standing
	-- height (v^2 = 2 a d), and land when Descend is held close to it.
	if velocity.Y < 0 or flight.descendHeld then
		local brakeDistance = velocity.Y * velocity.Y / (2 * FlightConfig.GroundBrake)
		local reach = FlightConfig.GroundSkimHeight
			+ math.max(brakeDistance, FlightConfig.AutoLandDistance)
			+ GROUND_PROBE_MARGIN
		local height = groundHeight(flight, reach)
		if height ~= nil then
			if flight.descendHeld and height <= FlightConfig.AutoLandDistance then
				land(true)
				return
			end
			local maxDescent =
				math.sqrt(2 * FlightConfig.GroundBrake * math.max(0, height - FlightConfig.GroundSkimHeight))
			if -velocity.Y > maxDescent then
				velocity = Vector3.new(velocity.X, -maxDescent, velocity.Z)
			end
		end
	end

	-- Hard stop: at (or past) the edge no speed may carry further out.
	local edge = BoundaryController:GetState()
	if edge ~= nil and edge.Depth >= 1 then
		local outward = -velocity:Dot(edge.Inward)
		if outward > 0 then
			velocity += edge.Inward * outward
		end
	end

	-- lift is the share of the vertical speed that Ascend / Descend asked for;
	-- whatever stopped the body (ground, ceiling) stopped that share too.
	flight.lift = math.clamp(flight.lift, math.min(velocity.Y, 0), math.max(velocity.Y, 0))
	flight.velocity = velocity
	updatePose(flight, yawOf(flatForward), dt)

	-- Hover bob: a slow sine on top of the velocity, fading out as you move.
	local omega = 2 * math.pi * FlightConfig.HoverBobFrequency
	local idle = 1 - math.clamp(velocity.Magnitude / FlightConfig.FaceTravelMinSpeed, 0, 1)
	local bob = FlightConfig.HoverBobAmplitude * omega * math.cos(omega * (now - flight.startedAt)) * idle
	local commanded = velocity + Vector3.yAxis * bob
	flight.mover.VectorVelocity = commanded
	flight.commanded = commanded

	local speedFraction = math.clamp(velocity.Magnitude / FlightConfig.CruiseSpeed, 0, 1)
	CameraController:SetFovOffset(SPEED_FOV_SOURCE, cameraConfig.SpeedFovBonus * speedFraction)
	updateAnimations(flight, velocity.Magnitude)
end

-- Takeoff ---------------------------------------------------------------------

local function buildMovers(
	root: BasePart,
	velocity: Vector3,
	yaw: number
): (Attachment, LinearVelocity, AlignOrientation)
	local attachment = Instance.new("Attachment")
	attachment.Name = "FlightAttachment"

	local mover = Instance.new("LinearVelocity")
	mover.Name = "FlightVelocity"
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	mover.MaxForce = FlightConfig.ForcePerMass * root.AssemblyMass
	mover.VectorVelocity = velocity
	mover.Parent = attachment

	local aligner = Instance.new("AlignOrientation")
	aligner.Name = "FlightOrientation"
	aligner.Mode = Enum.OrientationAlignmentMode.OneAttachment
	aligner.Attachment0 = attachment
	aligner.RigidityEnabled = false
	aligner.Responsiveness = FlightConfig.AlignResponsiveness
	aligner.MaxTorque = math.huge
	aligner.CFrame = CFrame.Angles(0, yaw, 0)
	aligner.Parent = attachment

	attachment.Parent = root
	return attachment, mover, aligner
end

local function takeOff()
	local body = getBody()
	local refusal: Types.PowerRejectReason? = takeoffRefusal(body)
	if refusal ~= nil then
		FlightController.Refused:Fire(refusal)
		return
	end
	-- (takeoffRefusal already refuses a missing body; this narrows the type.)
	if body == nil then
		return
	end
	local character, humanoid, root = body.character, body.humanoid, body.root
	local now = os.clock()
	lastToggleAt = now

	-- Combat mode first, so the camera saves the walking AutoRotate before it
	-- is switched off here.
	CameraController:SetCombatMode(COMBAT_REASON, true)
	if humanoid.SeatPart ~= nil then
		humanoid.Sit = false
	end
	local savedAutoRotate = humanoid.AutoRotate
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true

	-- Keep the run-up's momentum and kick upward.
	local before = root.AssemblyLinearVelocity
	local velocity = Vector3.new(before.X, FlightConfig.TakeoffImpulse, before.Z)
	local yaw = yawOf(root.CFrame.LookVector)
	local attachment, mover, aligner = buildMovers(root, velocity, yaw)

	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Exclude
	groundParams.FilterDescendantsInstances = { character }
	-- Crops, light beams and other walk-through parts are not ground.
	groundParams.RespectCanCollide = true

	local animator = humanoid:FindFirstChildOfClass("Animator")
	local animations = AssetsConfig.Animations
	local flight: Flight = {
		character = character,
		humanoid = humanoid,
		root = root,
		attachment = attachment,
		mover = mover,
		aligner = aligner,
		connections = {},
		idleTrack = playTrack(animator, animations.FlyIdle, 1),
		-- Blended in with speed, or always on when it is the only one set.
		forwardTrack = playTrack(animator, animations.FlyForward, if animations.FlyIdle == "" then 1 else 0),
		forwardWeight = 0,
		savedAutoRotate = savedAutoRotate,
		standingHeight = standingHeight(humanoid, root),
		groundParams = groundParams,
		startedAt = now,
		velocity = velocity,
		lift = FlightConfig.TakeoffImpulse,
		-- The run-up velocity: the first step must not read the kick as a collision.
		commanded = before,
		yaw = yaw,
		pitch = 0,
		bank = 0,
		ascendHeld = false,
		descendHeld = false,
		lastMoveAt = now,
		takeoffPending = true,
		takeoffSentAt = now,
		-- The server has not heard our last landing yet: its Flying will turn
		-- false for that before it turns true for this takeoff.
		awaitingLandEcho = LocalPlayer:GetAttribute(Attributes.Flying) == true,
		boosting = false,
		boostToggled = false,
		boostPending = false,
		boostSentAt = 0,
	}
	current = flight

	table.insert(
		flight.connections,
		humanoid.Died:Connect(function()
			if current == flight then
				land(false)
			end
		end)
	)
	table.insert(
		flight.connections,
		character.AncestryChanged:Connect(function()
			if current == flight and not character:IsDescendantOf(Workspace) then
				land(false)
			end
		end)
	)
	table.insert(flight.connections, RunService.PreSimulation:Connect(step))

	-- Bound only while flying, so on foot Space still jumps.
	for _, actionName in FLIGHT_ACTIONS do
		InputController:UnbindAction(actionName)
	end
	InputController:BindAction("Ascend", function(phase: Types.ActionPhase)
		flight.ascendHeld = phase == "Begin"
	end)
	InputController:BindAction("Descend", function(phase: Types.ActionPhase)
		flight.descendHeld = phase == "Begin"
	end)
	InputController:BindAction("Boost", onBoost)
	InputController:SetTouchLabel("ToggleFlight", Text.Flight.LandLabel)

	Remotes.SetFlying:Fire(true)
	CameraController:Shake(cameraConfig.TakeoffShake.Intensity, cameraConfig.TakeoffShake.Duration)
	FlightController.TookOff:Fire()
end

-- Server messages -------------------------------------------------------------

local function onFlyingChanged()
	local serverFlying = LocalPlayer:GetAttribute(Attributes.Flying) == true
	local flight = current
	if flight == nil then
		-- The server has us flying but we are not (a landing it never got).
		if serverFlying then
			verifyLanded()
		end
		return
	end
	if serverFlying then
		flight.takeoffPending = false
		flight.awaitingLandEcho = false
	elseif flight.awaitingLandEcho then
		-- Our previous landing reaching the server; this takeoff's answer follows.
		flight.awaitingLandEcho = false
	else
		-- Landed by the server: out of charge, the battery, the speed check.
		land(false)
	end
end

local function onBoostingChanged()
	local flight = current
	if flight == nil then
		return
	end
	if LocalPlayer:GetAttribute(Attributes.Boosting) == true then
		flight.boostPending = false
	elseif flight.boosting and not flight.boostPending then
		-- The server ended the boost (willpower ran low). A false while our
		-- request is pending is only the echo of an earlier release.
		setBoosting(flight, false, false, false)
	end
end

local function onPowerRejected(powerId: Types.PowerId, _reason: Types.PowerRejectReason)
	local flight = current
	if powerId ~= "Flight" or flight == nil then
		return
	end
	-- The server answers in order and only boosts a flight it accepted, so a
	-- refusal before the takeoff is confirmed is the takeoff's.
	if flight.takeoffPending then
		land(false)
	elseif flight.boosting then
		setBoosting(flight, false, false, false)
	end
end

local function onToggleFlight(phase: Types.ActionPhase)
	if phase ~= "Begin" then
		return
	end
	local now = os.clock()
	if now - lastToggleAt < FlightConfig.ToggleCooldown then
		return
	end
	if current ~= nil then
		lastToggleAt = now
		land(true)
	else
		takeOff()
	end
end

-- API -------------------------------------------------------------------------

function FlightController.IsFlying(_self: FlightController): boolean
	return current ~= nil
end

function FlightController.IsBoosting(_self: FlightController): boolean
	local flight = current
	return flight ~= nil and flight.boosting
end

function FlightController.GetVelocity(_self: FlightController): Vector3
	local flight = current
	if flight ~= nil then
		return flight.velocity
	end
	local character = LocalPlayer.Character
	local root = if character ~= nil then character:FindFirstChild(ROOT_PART_NAME) else nil
	if root ~= nil and root:IsA("BasePart") then
		return root.AssemblyLinearVelocity
	end
	return NEUTRAL
end

function FlightController.Init(_self: FlightController)
	Remotes.PowerRejected:Connect(onPowerRejected)
	LocalPlayer:GetAttributeChangedSignal(Attributes.Flying):Connect(onFlyingChanged)
	LocalPlayer:GetAttributeChangedSignal(Attributes.Boosting):Connect(onBoostingChanged)
	-- Backstop for the per-flight hooks: a new character never inherits a flight.
	LocalPlayer.CharacterAdded:Connect(function(character: Model)
		local flight = current
		if flight ~= nil and flight.character ~= character then
			land(false)
		end
	end)
end

function FlightController.Start(_self: FlightController)
	InputController:BindAction("ToggleFlight", onToggleFlight)
	-- May yield; until it finishes, steering reads Humanoid.MoveDirection.
	loadControls()
end

export type FlightController = typeof(FlightController)

return FlightController
