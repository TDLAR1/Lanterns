--!strict
--[[
	PowerController: turns the power actions into requests to the server, with
	instant local feedback.

	The server (PowerService, RingService) decides everything: whether a power
	may be used, what it costs, what it hits, cooldowns. This controller checks
	the same rules first from the replicated ring state (RingController:
	CanAttempt), so a refusal shows at once (Feedback + the PowerRejected sound)
	instead of after a round trip, and draws the local beam immediately.

	  * FireBeam (hold): starts the beam at the crosshair (combat camera on, the
	    local beam drawn by VFXController), sends the aim point
	    Config.Powers.Beam.AimSendRate times a second while held, stops on
	    release. It also stops when the server ends it (BeamActive turning false
	    after it was confirmed, or PowerRejected("Beam")), or if the server never
	    confirms it within Config.Powers.Client.ConfirmTimeout.
	  * ToggleShield: raises / drops the shield, following the Shielding
	    attribute (and the request in flight, so quick presses never desync).
	  * CastConstruct casts the selected construct; CastWall / CastHammer /
	    CastCage cast that one and select it; NextConstruct / PreviousConstruct
	    change the selection (Config.Powers.ConstructOrder). The touch "Cast"
	    button shows the selected construct's name.
	  * Remotes.PowerRejected (any power, flight included) and
	    FlightController.Refused (its own takeoff / boost precheck) become
	    Feedback text (Config.Text.Ring.Rejected) and the PowerRejected sound.

	While the oath plays (Recharging) every precheck refuses with Busy.

	API:
	  PowerController:GetSelectedConstruct(): ConstructId
	  PowerController:SelectConstruct(constructId)
	  PowerController:IsFiringBeam(): boolean
	  PowerController:IsShielding(): boolean          (including a request in flight)
	  PowerController:DescribeRejection(powerId, reason): string
	  PowerController:GetDisplayName(powerId): string
	  PowerController.SelectionChanged  Signal(constructId)
	  PowerController.Feedback          Signal(text)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local AssetsConfig = require(Shared.Config.Assets)
local PowersConfig = require(Shared.Config.Powers)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Util.Signal)
local TagsModule = require(Shared.Util.Tags)
local Text = require(Shared.Config.Text)
local Types = require(Shared.Types)
local WorldConfig = require(Shared.Config.World)

local CameraController = require(script.Parent.CameraController)
local FlightController = require(script.Parent.FlightController)
local InputController = require(script.Parent.InputController)
local RingController = require(script.Parent.RingController)
local SoundController = require(script.Parent.SoundController)
local VFXController = require(script.Parent.VFXController)

local Attributes = TagsModule.Attributes
local LocalPlayer = Players.LocalPlayer

local BeamConfig = PowersConfig.Beam
local ShieldConfig = PowersConfig.Shield
local ClientConfig = PowersConfig.Client

-- Every standard Humanoid rig (R6, R15, custom StarterCharacter) names its root this.
local ROOT_PART_NAME = "HumanoidRootPart"
-- CameraController combat-mode reasons.
local BEAM_COMBAT = "Beam"
local CAST_COMBAT = "Cast"

local REJECT_TEXT: { [string]: string } = Text.Ring.Rejected
local POWER_NAMES: { [string]: string } = Text.Ring.PowerNames
local ANIMATION_IDS: { [string]: string } = AssetsConfig.Animations

-- The cost and range fields every construct config shares.
type ConstructConfig = {
	DisplayName: string,
	MinWillpower: number,
	WillpowerCost: number,
	Range: number,
}

type BeamState = {
	firing: boolean,
	-- The server confirmed this beam (BeamActive became true after it started).
	confirmed: boolean,
	startedAt: number,
	-- Seconds since the last aim update was sent.
	sinceAim: number,
	heartbeat: RBXScriptConnection?,
}

-- A shield toggle sent to the server and not yet reflected in the attribute.
type ShieldRequest = {
	raised: boolean,
	sentAt: number,
}

local constructOrder: { Types.ConstructId } = {}
for _, id in PowersConfig.ConstructOrder do
	if id == "Wall" or id == "Hammer" or id == "Cage" then
		table.insert(constructOrder, id)
	end
end
assert(#constructOrder > 0, "Config.Powers.ConstructOrder lists no constructs")

local selected: Types.ConstructId = constructOrder[1]
local beam: BeamState = { firing = false, confirmed = false, startedAt = 0, sinceAim = 0, heartbeat = nil }
local shieldRequest: ShieldRequest? = nil
-- Bumped by every cast, so only the latest cast's timer ends its combat camera.
local castToken = 0

-- Animation tracks loaded on the current character (Config.Assets.Animations).
local tracksCharacter: Model? = nil
local tracks: { [string]: AnimationTrack } = {}
local animations: { Animation } = {}

local PowerController = {
	-- The selected construct changed. (constructId)
	SelectionChanged = Signal.new() :: Signal.Signal<Types.ConstructId>,
	-- A short message for the player: a power was refused. (text)
	Feedback = Signal.new() :: Signal.Signal<string>,
}

-- Helpers ----------------------------------------------------------------------------

local function constructConfig(id: Types.ConstructId): ConstructConfig
	local constructs = PowersConfig.Constructs
	if id == "Wall" then
		return constructs.Wall
	elseif id == "Hammer" then
		return constructs.Hammer
	end
	return constructs.Cage
end

local function displayName(powerId: Types.PowerId): string
	if powerId == "Wall" or powerId == "Hammer" or powerId == "Cage" then
		return constructConfig(powerId).DisplayName
	end
	return POWER_NAMES[powerId] or powerId
end

local function describe(powerId: Types.PowerId, reason: Types.PowerRejectReason): string
	local template = REJECT_TEXT[reason] or REJECT_TEXT.NotReady
	if reason == "Cooldown" then
		return string.format(template, displayName(powerId))
	end
	return template
end

local function refuse(powerId: Types.PowerId, reason: Types.PowerRejectReason?)
	PowerController.Feedback:Fire(describe(powerId, reason or "NotReady"))
	SoundController:Play("PowerRejected")
end

local function localRoot(): BasePart?
	local character = LocalPlayer.Character
	local root = if character ~= nil then character:FindFirstChild(ROOT_PART_NAME) else nil
	if root ~= nil and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- The shield as the player last asked for it, until the server's attribute
-- agrees (or the request is old enough that the attribute is the truth).
local function isShielding(): boolean
	local attribute = LocalPlayer:GetAttribute(Attributes.Shielding) == true
	local request = shieldRequest
	if request ~= nil then
		if request.raised ~= attribute and os.clock() - request.sentAt < ClientConfig.ConfirmTimeout then
			return request.raised
		end
		shieldRequest = nil
	end
	return attribute
end

-- The shield blocks attacking powers (Config.Powers.Shield.BlocksAttacks).
local function checkAttack(powerId: Types.PowerId, minWillpower: number): (boolean, Types.PowerRejectReason?)
	local ok: boolean, reason: Types.PowerRejectReason? = RingController:CanAttempt(powerId, minWillpower)
	if ok and ShieldConfig.BlocksAttacks and isShielding() then
		return false, "Busy"
	end
	return ok, reason
end

-- Animations ---------------------------------------------------------------------------

local function releaseTracks()
	for _, track in tracks do
		track:Stop(0)
		track:Destroy()
	end
	table.clear(tracks)
	for _, animation in animations do
		animation:Destroy()
	end
	table.clear(animations)
	tracksCharacter = nil
end

-- The track for a Config.Assets.Animations key on the current character, or
-- nil when the id is empty or it cannot be loaded.
local function getTrack(key: string, looped: boolean): AnimationTrack?
	local id = ANIMATION_IDS[key]
	local character = LocalPlayer.Character
	if id == nil or id == "" or character == nil then
		return nil
	end
	if tracksCharacter ~= character then
		releaseTracks()
		tracksCharacter = character
	end
	local cached: AnimationTrack? = tracks[key]
	if cached ~= nil then
		return cached
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = if humanoid ~= nil then humanoid:FindFirstChildOfClass("Animator") else nil
	if animator == nil then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	table.insert(animations, animation)
	-- An id this game may not use fails to load; the power still works.
	local ok, result = pcall(function(): AnimationTrack
		return animator:LoadAnimation(animation)
	end)
	if not ok then
		warn(`[PowerController] Could not load the {key} animation ({id}): {result}`)
		return nil
	end
	local track = result
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = looped
	tracks[key] = track
	return track
end

local function playAnimation(key: string, looped: boolean)
	local track = getTrack(key, looped)
	if track ~= nil then
		track:Play(ClientConfig.AnimationFadeTime)
	end
end

local function stopAnimation(key: string)
	local track: AnimationTrack? = tracks[key]
	if track ~= nil and track.IsPlaying then
		track:Stop(ClientConfig.AnimationFadeTime)
	end
end

-- Beam -----------------------------------------------------------------------------------

-- Stops the local beam. notifyServer: also tell the server (it may still be firing).
local function endBeam(notifyServer: boolean)
	if not beam.firing then
		return
	end
	beam.firing = false
	beam.confirmed = false
	local heartbeat = beam.heartbeat
	if heartbeat ~= nil then
		heartbeat:Disconnect()
		beam.heartbeat = nil
	end
	if notifyServer then
		Remotes.BeamStop:Fire()
	end
	VFXController:SetLocalBeam(false)
	-- The camera lingers in combat mode a moment (Config.Camera.CombatLinger).
	CameraController:SetCombatMode(BEAM_COMBAT, false)
	stopAnimation("BeamPose")
end

local function stepBeam(deltaTime: number)
	if not beam.firing then
		return
	end
	if not beam.confirmed and os.clock() - beam.startedAt > ClientConfig.ConfirmTimeout then
		-- By now the attribute shows what the server is doing: firing (our beam,
		-- even if the change that said so was merged with an older one), or not
		-- (the request was dropped).
		if LocalPlayer:GetAttribute(Attributes.BeamActive) == true then
			beam.confirmed = true
		else
			endBeam(true)
			return
		end
	end
	beam.sinceAim += deltaTime
	local interval = 1 / BeamConfig.AimSendRate
	if beam.sinceAim >= interval then
		-- Keep the remainder for an even rate, but never build up a backlog.
		beam.sinceAim = math.min(beam.sinceAim - interval, interval)
		Remotes.BeamAim:Fire(CameraController:GetAimPoint(BeamConfig.Range))
	end
end

local function startBeam()
	if beam.firing then
		return
	end
	local ok: boolean, reason: Types.PowerRejectReason? = checkAttack("Beam", BeamConfig.MinWillpower)
	if not ok then
		refuse("Beam", reason)
		return
	end
	beam.firing = true
	beam.confirmed = false
	beam.startedAt = os.clock()
	beam.sinceAim = 0
	CameraController:SetCombatMode(BEAM_COMBAT, true)
	Remotes.BeamStart:Fire(CameraController:GetAimPoint(BeamConfig.Range))
	VFXController:SetLocalBeam(true)
	playAnimation("BeamPose", true)
	beam.heartbeat = RunService.Heartbeat:Connect(stepBeam)
end

local function onBeamActiveChanged()
	if not beam.firing then
		return
	end
	if LocalPlayer:GetAttribute(Attributes.BeamActive) == true then
		beam.confirmed = true
	elseif beam.confirmed then
		-- The server ended it (out of willpower or charge, the oath, ...). A
		-- "false" before confirmation is the previous beam's end arriving late.
		endBeam(false)
	end
end

-- Shield ---------------------------------------------------------------------------------

local function toggleShield()
	if isShielding() then
		shieldRequest = { raised = false, sentAt = os.clock() }
		Remotes.SetShield:Fire(false)
		return
	end
	local ok: boolean, reason: Types.PowerRejectReason? = RingController:CanAttempt("Shield", ShieldConfig.MinWillpower)
	if not ok then
		refuse("Shield", reason)
		return
	end
	shieldRequest = { raised = true, sentAt = os.clock() }
	Remotes.SetShield:Fire(true)
	if ShieldConfig.BlocksAttacks then
		-- The server ends the beam when the shield goes up; end it here at once.
		-- BeamStop too, in case the server refuses the shield: then the beam
		-- would otherwise keep firing there while it is gone here.
		endBeam(true)
	end
end

-- Constructs -----------------------------------------------------------------------------

local function setSelected(id: Types.ConstructId)
	InputController:SetTouchLabel("CastConstruct", displayName(id))
	if id == selected then
		return
	end
	selected = id
	PowerController.SelectionChanged:Fire(id)
end

local function cycleSelection(step: number)
	local index = table.find(constructOrder, selected) or 1
	setSelected(constructOrder[(index - 1 + step) % #constructOrder + 1])
end

-- Turns the combat camera on for a moment so the cast reads as aimed.
local function castCombatMode()
	castToken += 1
	local token = castToken
	CameraController:SetCombatMode(CAST_COMBAT, true)
	task.delay(ClientConfig.CastCombatTime, function()
		if castToken == token then
			CameraController:SetCombatMode(CAST_COMBAT, false)
		end
	end)
end

local function cast(id: Types.ConstructId)
	local config = constructConfig(id)
	local ok: boolean, reason: Types.PowerRejectReason? =
		checkAttack(id, math.max(config.MinWillpower, config.WillpowerCost))
	if not ok then
		refuse(id, reason)
		return
	end
	local root = localRoot()
	if root == nil then
		refuse(id, "NotReady")
		return
	end
	local aimPoint = CameraController:GetAimPoint(config.Range)
	if (aimPoint - root.Position).Magnitude > config.Range + PowersConfig.Aim.RangeTolerance then
		refuse(id, "OutOfRange")
		return
	end
	Remotes.CastConstruct:Fire(id, aimPoint)
	castCombatMode()
	playAnimation("ConstructCast", false)
end

-- Server answers ---------------------------------------------------------------------------

local function onPowerRejected(powerId: Types.PowerId, reason: Types.PowerRejectReason)
	-- From the server, so trusted; still never let a malformed message throw.
	if type(powerId) ~= "string" or type(reason) ~= "string" then
		return
	end
	if powerId == "Beam" then
		local wasFiring = beam.firing
		endBeam(false)
		-- Raising the shield ends the beam on the server, which says "Busy": the
		-- player did that on purpose, so it needs no message.
		if reason == "Busy" and not wasFiring and isShielding() then
			return
		end
	elseif powerId == "Shield" then
		shieldRequest = nil
	end
	refuse(powerId, reason)
end

local function onCharacterChanged()
	-- The server stops every power when a character dies or is replaced.
	endBeam(false)
	shieldRequest = nil
	castToken += 1
	CameraController:SetCombatMode(CAST_COMBAT, false)
	releaseTracks()
end

-- API ------------------------------------------------------------------------------------

function PowerController.GetSelectedConstruct(_self: PowerController): Types.ConstructId
	return selected
end

function PowerController.SelectConstruct(_self: PowerController, constructId: Types.ConstructId)
	if table.find(constructOrder, constructId) ~= nil then
		setSelected(constructId)
	end
end

function PowerController.IsFiringBeam(_self: PowerController): boolean
	return beam.firing
end

function PowerController.IsShielding(_self: PowerController): boolean
	return isShielding()
end

-- The Feedback text for a refused power (Config.Text.Ring.Rejected).
function PowerController.DescribeRejection(
	_self: PowerController,
	powerId: Types.PowerId,
	reason: Types.PowerRejectReason
): string
	return describe(powerId, reason)
end

function PowerController.GetDisplayName(_self: PowerController, powerId: Types.PowerId): string
	return displayName(powerId)
end

function PowerController.Init(_self: PowerController)
	InputController:BindAction("FireBeam", function(phase: Types.ActionPhase)
		if phase == "Begin" then
			startBeam()
		else
			endBeam(true)
		end
	end)
	InputController:BindAction("ToggleShield", function(phase: Types.ActionPhase)
		if phase == "Begin" then
			toggleShield()
		end
	end)
	InputController:BindAction("CastConstruct", function(phase: Types.ActionPhase)
		if phase == "Begin" then
			cast(selected)
		end
	end)
	InputController:BindAction("NextConstruct", function(phase: Types.ActionPhase)
		if phase == "Begin" then
			cycleSelection(1)
		end
	end)
	InputController:BindAction("PreviousConstruct", function(phase: Types.ActionPhase)
		if phase == "Begin" then
			cycleSelection(-1)
		end
	end)
	-- Direct casts select what they cast, so "Cast" repeats it.
	local function bindDirect(actionName: string, id: Types.ConstructId)
		InputController:BindAction(actionName, function(phase: Types.ActionPhase)
			if phase == "Begin" then
				setSelected(id)
				cast(id)
			end
		end)
	end
	bindDirect("CastWall", "Wall")
	bindDirect("CastHammer", "Hammer")
	bindDirect("CastCage", "Cage")
	InputController:SetTouchLabel("CastConstruct", displayName(selected))

	Remotes.PowerRejected:Connect(onPowerRejected)
	-- Flight's own instant checks get the same message and sound as every power.
	FlightController.Refused:Connect(function(reason: Types.PowerRejectReason)
		refuse("Flight", reason)
	end)
	LocalPlayer:GetAttributeChangedSignal(Attributes.BeamActive):Connect(onBeamActiveChanged)
	LocalPlayer.CharacterAdded:Connect(onCharacterChanged)
	LocalPlayer.CharacterRemoving:Connect(onCharacterChanged)
end

function PowerController.Start(_self: PowerController)
	-- A death ends powers on the server; end them here too, at once.
	local function watchDeath(character: Model)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
			or character:WaitForChild("Humanoid", WorldConfig.Spawning.CharacterLoadTimeout)
		if humanoid ~= nil and humanoid:IsA("Humanoid") and LocalPlayer.Character == character then
			humanoid.Died:Once(function()
				if LocalPlayer.Character == character then
					onCharacterChanged()
				end
			end)
		end
	end
	LocalPlayer.CharacterAdded:Connect(watchDeath)
	local character = LocalPlayer.Character
	if character ~= nil then
		watchDeath(character)
	end
end

export type PowerController = typeof(PowerController)

return PowerController
