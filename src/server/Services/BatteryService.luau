--!strict
--[[
	BatteryService: the ring battery in the Sheriff's Office back room, and the
	oath moment that recharges a ring there.

	  * One ProximityPrompt (Config.Ring.Battery) sits on the battery part
	    (WorldService:GetBatterySpot(), tagged RingBatterySpot). It follows the
	    tag, so a battery that appears or is replaced later gets the prompt too.
	  * Triggering it with a ring, a living character, close enough and not
	    already recharging begins the oath:
	      - every power is blocked ("Recharging"), the player is landed and their
	        beam / shield stopped;
	      - the character is frozen, turned to face the battery and raises the
	        ring toward it (the OathPose animation, or the ring arm's shoulder
	        joint when that is empty);
	      - the client plays the moment itself (OathStarted / OathEnded) while the
	        ring charge fills smoothly over Config.Ring.Battery.OathDuration.
	    A refused trigger gets a short Notify (ring not ready / too far away).
	  * Dying, leaving, losing the character or walking further than
	    CancelDistance away interrupts the oath. The charge filled so far is
	    kept: the ring took that much light.
	  * Completing it refills the ring (and willpower: RefillsWillpower) and
	    flares the battery for everyone.
	  * Every way out restores movement, pose and powers. Any number of players
	    can recharge at once; each has their own oath.

	State is mirrored to each Player as the attribute Recharging (only the
	server writes it).

	API:
	  BatteryService:IsRecharging(player): boolean
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local AssetsConfig = require(Shared.Config.Assets)
local RingConfig = require(Shared.Config.Ring)
local Remotes = require(Shared.Remotes)
local TagsModule = require(Shared.Util.Tags)
local Text = require(Shared.Config.Text)

local Characters = require(script.Parent.Characters)
local FlightService = require(script.Parent.FlightService)
local PowerService = require(script.Parent.PowerService)
local RingService = require(script.Parent.RingService)
local WorldService = require(script.Parent.WorldService)

local Tags = TagsModule.Tags
local Attributes = TagsModule.Attributes
local config = RingConfig.Battery
local poseConfig = config.Pose

-- RingService:SetBlocked reason while an oath plays.
local BLOCK_REASON = "Recharging"
local PROMPT_NAME = "RechargePrompt"

-- Where the ring arm's shoulder joint lives: { holder part, joint name }.
-- R15 keeps it in the upper arm, R6 in the torso.
local SHOULDER_JOINTS = {
	{ "RightUpperArm", "RightShoulder" },
	{ "Torso", "Right Shoulder" },
}

-- Movement as it was before the freeze. Only the jump property the Humanoid
-- actually uses (UseJumpPower) is changed and restored.
type Movement = {
	walkSpeed: number,
	autoRotate: boolean,
	useJumpPower: boolean,
	jump: number,
}

type OathSession = {
	player: Player,
	character: Model,
	humanoid: Humanoid,
	batteryPosition: Vector3,
	-- Ring charge when the oath began; the fill runs from here to full.
	startCharge: number,
	-- os.clock() when the charge started filling.
	startedAt: number,
	-- The client was sent OathStarted (so it is owed an OathEnded).
	announced: boolean,
	ended: boolean,
	-- Died / removed hooks, disconnected when the oath ends.
	connections: { RBXScriptConnection },
	-- What has to be undone (nil = not applied, or already undone).
	movement: Movement?,
	track: AnimationTrack?,
	animation: Animation?,
	shoulder: Motor6D?,
}

local sessions: { [Player]: OathSession } = {}

-- The battery part that has the prompt, the prompt, and their connections.
local battery: BasePart? = nil
local prompt: ProximityPrompt? = nil
local batteryConnections: { RBXScriptConnection } = {}

-- Each raised shoulder joint's C0 before an oath turned it. Kept per joint (not
-- per oath) so an oath that starts while the arm is still lowering from the last
-- one aims from, and returns to, the true rest pose. Weak keys: a destroyed
-- joint drops out by itself.
local restC0 = setmetatable({} :: { [Motor6D]: CFrame }, { __mode = "k" })
local jointTweens = setmetatable({} :: { [Motor6D]: Tween }, { __mode = "k" })

local BatteryService = {}

-- Movement -------------------------------------------------------------------

local function freeze(session: OathSession)
	local humanoid = session.humanoid
	local useJumpPower = humanoid.UseJumpPower
	session.movement = {
		walkSpeed = humanoid.WalkSpeed,
		autoRotate = humanoid.AutoRotate,
		useJumpPower = useJumpPower,
		jump = if useJumpPower then humanoid.JumpPower else humanoid.JumpHeight,
	}
	humanoid.WalkSpeed = 0
	-- With WalkSpeed 0 a Humanoid still turns toward the move input; this keeps
	-- the character facing the battery.
	humanoid.AutoRotate = false
	if useJumpPower then
		humanoid.JumpPower = 0
	else
		humanoid.JumpHeight = 0
	end
end

local function unfreeze(session: OathSession)
	local movement = session.movement
	session.movement = nil
	local humanoid = session.humanoid
	if movement == nil or humanoid.Parent == nil then
		return
	end
	humanoid.WalkSpeed = movement.walkSpeed
	humanoid.AutoRotate = movement.autoRotate
	if movement.useJumpPower then
		humanoid.JumpPower = movement.jump
	else
		humanoid.JumpHeight = movement.jump
	end
end

-- Turns the character in place (keeping its height) to look at the battery.
local function faceBattery(character: Model, root: BasePart, target: Vector3)
	local position = root.Position
	local flat = Vector3.new(target.X - position.X, 0, target.Z - position.Z)
	if flat.Magnitude < 0.05 then
		return
	end
	local facing = CFrame.lookAt(position, position + flat)
	-- Pivot the whole model so a rig whose pivot is not its root moves as one.
	local rootToPivot = root.CFrame:ToObjectSpace(character:GetPivot())
	character:PivotTo(facing * rootToPivot)
end

-- Pose -----------------------------------------------------------------------

local function findShoulder(character: Model): Motor6D?
	for _, path in SHOULDER_JOINTS do
		local holder = character:FindFirstChild(path[1])
		local joint = if holder ~= nil then holder:FindFirstChild(path[2]) else nil
		if joint ~= nil and joint:IsA("Motor6D") then
			return joint
		end
	end
	return nil
end

local function tweenJoint(joint: Motor6D, goal: CFrame, duration: number, onCompleted: (() -> ())?)
	local running: Tween? = jointTweens[joint]
	if running ~= nil then
		running:Cancel()
	end
	local tween = TweenService:Create(
		joint,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ C0 = goal }
	)
	jointTweens[joint] = tween
	tween.Completed:Once(function(playbackState: Enum.PlaybackState)
		if jointTweens[joint] == tween then
			jointTweens[joint] = nil
		end
		tween:Destroy()
		if onCompleted ~= nil and playbackState == Enum.PlaybackState.Completed then
			onCompleted()
		end
	end)
	tween:Play()
end

-- The shoulder C0 that points the arm at `target`. The arm hangs along the
-- torso's -Y at rest on R15 and R6 alike, so the turn is worked out in torso
-- space and applied about the joint: C0 = joint position * turn * rest rotation.
local function aimedC0(torso: BasePart, rest: CFrame, target: Vector3): CFrame
	local offset = torso.CFrame:PointToObjectSpace(target) - rest.Position
	if offset.Magnitude < 1e-3 then
		return rest
	end
	local direction = offset.Unit
	-- Pitch swings the hanging arm forward/up about the torso's X axis (0 = down,
	-- 180 = straight up); yaw then swings it about the torso's Y axis.
	local pitch = math.acos(math.clamp(-direction.Y, -1, 1))
	local yaw = math.atan2(-direction.X, -direction.Z)
	pitch = math.clamp(pitch, math.rad(poseConfig.MinPitch), math.rad(poseConfig.MaxPitch))
	yaw = math.clamp(yaw, -math.rad(poseConfig.MaxYaw), math.rad(poseConfig.MaxYaw))
	return CFrame.new(rest.Position) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0) * rest.Rotation
end

local function raiseArm(session: OathSession)
	local joint = findShoulder(session.character)
	local torso = if joint ~= nil then joint.Part0 else nil
	if joint == nil or torso == nil then
		return
	end
	local saved: CFrame? = restC0[joint]
	local rest = if saved ~= nil then saved else joint.C0
	restC0[joint] = rest
	session.shoulder = joint
	tweenJoint(joint, aimedC0(torso, rest, session.batteryPosition), poseConfig.RaiseTime)
end

local function lowerArm(session: OathSession)
	local joint = session.shoulder
	session.shoulder = nil
	if joint == nil then
		return
	end
	local rest: CFrame? = restC0[joint]
	if rest == nil then
		return
	end
	if joint.Parent == nil or session.humanoid.Health <= 0 then
		-- Nobody watches a dead or removed character's arm come down: snap it back.
		local running: Tween? = jointTweens[joint]
		if running ~= nil then
			running:Cancel()
		end
		joint.C0 = rest
		restC0[joint] = nil
		return
	end
	tweenJoint(joint, rest, poseConfig.LowerTime, function()
		restC0[joint] = nil
	end)
end

-- Plays Config.Assets.Animations.OathPose. False when there is none (or it
-- could not be loaded), so the caller falls back to raising the arm.
local function playPoseAnimation(session: OathSession): boolean
	local animationId = AssetsConfig.Animations.OathPose
	if animationId == "" then
		return false
	end
	local animator = session.humanoid:FindFirstChildOfClass("Animator")
	if animator == nil then
		return false
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	-- Loading fails for an id this game may not use; that must not stop the oath.
	local ok, result = pcall(function(): AnimationTrack
		return animator:LoadAnimation(animation)
	end)
	if not ok then
		warn(`[BatteryService] Could not load the OathPose animation ({animationId}): {result}`)
		animation:Destroy()
		return false
	end
	local track = result
	track.Priority = Enum.AnimationPriority.Action
	-- Held for the whole oath even if the animation itself is a one-shot pose.
	track.Looped = true
	track:Play(poseConfig.AnimationFadeTime)
	session.track = track
	session.animation = animation
	return true
end

local function startPose(session: OathSession)
	if not playPoseAnimation(session) then
		raiseArm(session)
	end
end

local function releasePose(session: OathSession)
	local track = session.track
	local animation = session.animation
	session.track = nil
	session.animation = nil
	if track ~= nil then
		local fadeTime = poseConfig.AnimationFadeTime
		track:Stop(fadeTime)
		task.delay(fadeTime, function()
			track:Destroy()
			if animation ~= nil then
				animation:Destroy()
			end
		end)
	end
	lowerArm(session)
end

-- The oath -------------------------------------------------------------------

-- Ends an oath, completed or interrupted, and undoes everything it changed.
-- Safe to call more than once; only the first call counts.
local function endOath(session: OathSession, completed: boolean)
	if session.ended then
		return
	end
	session.ended = true
	local player = session.player
	if sessions[player] == session then
		sessions[player] = nil
	end
	for _, connection in session.connections do
		connection:Disconnect()
	end
	table.clear(session.connections)

	if completed then
		RingService:Refill(player, config.RefillsWillpower)
	end
	if session.announced and player.Parent == Players then
		Remotes.OathEnded:FireClient(player, completed)
		if completed then
			Remotes.Notify:FireClient(player, Text.Ring.Recharged, "Success")
		else
			Remotes.Notify:FireClient(player, Text.Oath.Interrupted, "Warning")
		end
	end
	if completed then
		Remotes.PowerEffect:FireAll("BatteryFlare", session.batteryPosition, 1)
	end

	unfreeze(session)
	releasePose(session)
	player:SetAttribute(Attributes.Recharging, false)
	RingService:SetBlocked(player, BLOCK_REASON, false)
end

local function isStillValid(session: OathSession): boolean
	local player = session.player
	if player.Parent ~= Players or player.Character ~= session.character or session.humanoid.Health <= 0 then
		return false
	end
	local root = Characters.FindRootPart(session.character)
	return root ~= nil and (root.Position - session.batteryPosition).Magnitude <= config.CancelDistance
end

-- Fills the charge step by step until the oath completes or is interrupted.
local function runOath(session: OathSession)
	local maxCharge = RingConfig.Charge.Max
	while true do
		task.wait(config.FillInterval)
		if session.ended then
			return
		end
		if not isStillValid(session) then
			endOath(session, false)
			return
		end
		local progress = (os.clock() - session.startedAt) / config.OathDuration
		if progress >= 1 then
			endOath(session, true)
			return
		end
		RingService:SetCharge(session.player, session.startCharge + (maxCharge - session.startCharge) * progress)
	end
end

local function beginOath(player: Player, character: Model, humanoid: Humanoid, root: BasePart, part: BasePart)
	local batteryPosition = part.Position
	local session: OathSession = {
		player = player,
		character = character,
		humanoid = humanoid,
		batteryPosition = batteryPosition,
		startCharge = RingService:GetCharge(player),
		startedAt = os.clock(),
		announced = false,
		ended = false,
		connections = {},
		movement = nil,
		track = nil,
		animation = nil,
		shoulder = nil,
	}
	sessions[player] = session

	-- Registered first, so every later step is undone however the oath ends.
	RingService:SetBlocked(player, BLOCK_REASON, true)
	player:SetAttribute(Attributes.Recharging, true)
	table.insert(
		session.connections,
		humanoid.Died:Connect(function()
			endOath(session, false)
		end)
	)
	table.insert(
		session.connections,
		character.AncestryChanged:Connect(function()
			if not character:IsDescendantOf(Workspace) then
				endOath(session, false)
			end
		end)
	)

	FlightService:ForceLand(player)
	-- Protected: a failure in another service must not leave this player blocked.
	local stopped, err = pcall(function()
		PowerService:StopAll(player)
	end)
	if not stopped then
		warn(`[BatteryService] Stopping {player.Name}'s powers failed: {err}`)
	end
	if session.ended then
		-- Interrupted while the powers were stopping (it may yield), before the
		-- client heard of the oath: endOath has already undone the rest.
		return
	end

	freeze(session)
	faceBattery(character, root, batteryPosition)
	startPose(session)

	Remotes.OathStarted:FireClient(player, config.OathDuration, batteryPosition)
	session.announced = true
	-- The fill is timed from here: stopping the powers above may have yielded.
	session.startedAt = os.clock()
	task.spawn(runOath, session)
end

-- RingService has no "has a ring" query: CanUse answers NotReady exactly when
-- the player has no ring yet (save not loaded) or no living character. Its
-- other refusals (no charge, cooldown, blocked) do not matter at the battery.
local function hasRing(player: Player): boolean
	local _, reason = RingService:CanUse(player, "Flight", 0)
	return reason ~= "NotReady"
end

local function onTriggered(player: Player, part: BasePart)
	if sessions[player] ~= nil or player.Parent ~= Players then
		return
	end
	local character = player.Character
	local root = Characters.GetRootPart(player, true)
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	if character == nil or root == nil or humanoid == nil or not hasRing(player) then
		Remotes.Notify:FireClient(player, Text.Ring.Rejected.NotReady, "Warning")
		return
	end
	if (root.Position - part.Position).Magnitude > config.PromptMaxDistance + config.TriggerDistanceSlack then
		Remotes.Notify:FireClient(player, Text.Ring.Rejected.OutOfRange, "Warning")
		return
	end
	beginOath(player, character, humanoid, root, part)
end

-- Battery prompt ---------------------------------------------------------------

local function detachPrompt()
	for _, connection in batteryConnections do
		connection:Disconnect()
	end
	table.clear(batteryConnections)
	local current = prompt
	if current ~= nil then
		current:Destroy()
	end
	prompt = nil
	battery = nil
end

local refreshBattery: () -> ()

local function attachPrompt(part: BasePart)
	local newPrompt = Instance.new("ProximityPrompt")
	newPrompt.Name = PROMPT_NAME
	newPrompt.ActionText = config.PromptActionText
	newPrompt.ObjectText = config.PromptObjectText
	newPrompt.HoldDuration = config.PromptHoldDuration
	newPrompt.MaxActivationDistance = config.PromptMaxDistance
	newPrompt.KeyboardKeyCode = config.PromptKeyboardKeyCode
	newPrompt.GamepadKeyCode = config.PromptGamepadKeyCode
	-- The battery core floats inside its fins, which would block the line of sight.
	newPrompt.RequiresLineOfSight = false
	newPrompt.Style = Enum.ProximityPromptStyle.Default
	newPrompt.Parent = part

	battery = part
	prompt = newPrompt
	table.insert(
		batteryConnections,
		newPrompt.Triggered:Connect(function(player: Player)
			onTriggered(player, part)
		end)
	)
	-- Moved out of the world or destroyed: find the battery again.
	table.insert(
		batteryConnections,
		part.AncestryChanged:Connect(function()
			task.defer(refreshBattery)
		end)
	)
end

-- Makes sure the battery in the world (if any) has the prompt, and only it.
function refreshBattery()
	local current = battery
	if
		current ~= nil
		and prompt ~= nil
		and prompt.Parent == current
		and current:HasTag(Tags.RingBatterySpot)
		and current:IsDescendantOf(Workspace)
	then
		return
	end
	detachPrompt()
	local spot = WorldService:GetBatterySpot()
	if spot ~= nil then
		attachPrompt(spot)
	end
end

-- API ------------------------------------------------------------------------

function BatteryService.IsRecharging(_self: BatteryService, player: Player): boolean
	return sessions[player] ~= nil
end

function BatteryService.Init(_self: BatteryService)
	Players.PlayerRemoving:Connect(function(player: Player)
		local session = sessions[player]
		if session ~= nil then
			endOath(session, false)
		end
	end)
end

function BatteryService.Start(_self: BatteryService)
	local function onPlayerAdded(player: Player)
		if sessions[player] == nil then
			player:SetAttribute(Attributes.Recharging, false)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	-- Deferred so WorldService (which tracks the same tag) has seen the change first.
	CollectionService:GetInstanceAddedSignal(Tags.RingBatterySpot):Connect(function()
		task.defer(refreshBattery)
	end)
	CollectionService:GetInstanceRemovedSignal(Tags.RingBatterySpot):Connect(function()
		task.defer(refreshBattery)
	end)
	refreshBattery()
	if battery == nil then
		warn(`[BatteryService] No part tagged {Tags.RingBatterySpot} in Workspace yet; rings cannot be recharged`)
	end
end

export type BatteryService = typeof(BatteryService)

return BatteryService
