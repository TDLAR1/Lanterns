--!strict
--[[
	OathController: the oath moment at the ring battery, on the client.

	BatteryService (server) runs the oath: it freezes the player facing the
	battery, raises the ring and fills the charge. This controller turns it into
	a short cinematic for the player:

	  On Remotes.OathStarted(duration, batteryPosition):
	    * the HUD and all touch controls hide (the ring HUD through
	      RingHudController:SetHidden, the power buttons through
	      InputController:SetTouchHidden, Roblox's thumbstick and jump button
	      through GuiService.TouchControlsEnabled), and so do proximity prompts
	      (the battery's own "Recharge ring" prompt would sit in the shot);
	    * black letterbox bars slide in and the screen edges darken;
	    * the camera turns Scriptable and slowly pushes in on a 3/4 shot of the
	      player facing the battery, worked out from where they and the battery
	      are, on whichever side has room (a raycast keeps it out of walls);
	    * the four Config.Text.Oath.Lines appear one at a time, evenly spread
	      over the duration, large, with a soft green glow;
	    * a charge meter fills with the RingCharge attribute;
	    * the OathChoir sound plays.
	  On Remotes.OathEnded(completed): a green flash (completed) or a quick dark
	    fade (interrupted), and everything is put back: camera (Custom, on the
	    same subject, same field of view), HUD, prompts and touch controls. The
	    OathComplete sound plays when completed.

	Dying, respawning or the end message never arriving
	(Config.UI.Oath.EndGrace) end the moment here too, so the camera and
	controls always come back.

	API:
	  OathController:IsPlaying(): boolean
	  OathController.Started  Signal()
	  OathController.Ended    Signal(completed)
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Util.Signal)
local Text = require(Shared.Config.Text)
local Theme = require(Shared.Config.Theme)
local UIConfig = require(Shared.Config.UI)
local VFXConfig = require(Shared.Config.VFX)

local Create = require(script.Parent.Parent.UI.Create)
local HudController = require(script.Parent.HudController)
local InputController = require(script.Parent.InputController)
local RingController = require(script.Parent.RingController)
local RingHudController = require(script.Parent.RingHudController)
local SoundController = require(script.Parent.SoundController)

local LocalPlayer = Players.LocalPlayer
local config = UIConfig.Oath
local cameraConfig = config.Camera

-- Every standard Humanoid rig (R6, R15, custom StarterCharacter) names its root this.
local ROOT_PART_NAME = "HumanoidRootPart"
local HIDE_REASON = "Oath"
local RENDER_STEP_NAME = "OathCamera"
local CHOIR_LOOP = "OathChoir"

type Overlay = {
	gui: ScreenGui,
	topBar: Frame,
	bottomBar: Frame,
	edges: { Frame },
	lines: { TextLabel },
	lineStrokes: { UIStroke },
	meter: Frame,
	meterFill: Frame,
	meterLabel: TextLabel,
	meterValue: TextLabel,
	flash: Frame,
	dim: Frame,
}

type Shot = {
	from: CFrame,
	to: CFrame,
	focus: Vector3,
}

type Session = {
	duration: number,
	startedAt: number,
	shot: Shot,
	connections: { RBXScriptConnection },
	threads: { thread },
	-- What the moment changed, to put back.
	cameraType: Enum.CameraType,
	cameraSubject: Instance?,
	fieldOfView: number,
	touchControlsEnabled: boolean,
	hudEnabled: boolean,
	promptsEnabled: boolean,
	-- Which of the two line labels shows the current line.
	lineSlot: number,
	shownCharge: number,
}

local overlay: Overlay? = nil
local session: Session? = nil
-- Bumped by every moment, so a fade from an earlier one never hides a newer one.
local generation = 0
local playingTweens: { Tween } = {}

local shotParams = RaycastParams.new()
shotParams.FilterType = Enum.RaycastFilterType.Exclude
shotParams.IgnoreWater = true
-- Glass, light beams and decoration you can walk through never block the shot.
shotParams.RespectCanCollide = true

local OathController = {
	-- The oath moment began.
	Started = Signal.new() :: Signal.Signal<()>,
	-- The oath moment ended. (completed)
	Ended = Signal.new() :: Signal.Signal<boolean>,
}

-- Building ---------------------------------------------------------------------------

local function tween(instance: Instance, time: number, goals: { [string]: any }, style: Enum.EasingStyle?)
	local playing = TweenService:Create(
		instance,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		goals
	)
	table.insert(playingTweens, playing)
	playing.Completed:Once(function()
		local index = table.find(playingTweens, playing)
		if index ~= nil then
			table.remove(playingTweens, index)
		end
	end)
	playing:Play()
end

local function stopTweens()
	for _, playing in table.clone(playingTweens) do
		playing:Cancel()
	end
	table.clear(playingTweens)
end

local function blackFrame(name: string, parent: Instance): Frame
	local frame = Create.frame(name)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 0
	frame.Parent = parent
	return frame
end

-- A dark glow along one screen edge: opaque at the edge, clear toward the middle.
local function edge(name: string, anchor: Vector2, size: UDim2, rotation: number, parent: Instance): Frame
	local frame = blackFrame(name, parent)
	frame.AnchorPoint = anchor
	frame.Position = UDim2.fromScale(anchor.X, anchor.Y)
	frame.Size = size
	frame.BackgroundTransparency = 1
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Transparency = NumberSequence.new(0, 1)
	gradient.Parent = frame
	return frame
end

local function lineLabel(index: number, parent: Instance): (TextLabel, UIStroke)
	local label = Create.label("Line" .. index, "", Theme.FontOath, config.LineTextSize, Theme.TextPrimary)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, config.LinePositionY)
	label.Size = UDim2.new(1, -2 * UIConfig.ScreenMargin, 0, config.LineHeight)
	label.TextWrapped = true
	label.TextTransparency = 1
	Create.maxSize(label, config.LineMaxWidth)
	local glow = Create.textStroke(label, VFXConfig.Color, config.LineGlowThickness, 1)
	label.Parent = parent
	return label, glow
end

local function buildOverlay(): Overlay
	local gui = HudController:CreateScreenGui("Oath", { DisplayOrder = UIConfig.DisplayOrder.Oath, FullScreen = true })
	gui.Enabled = false

	local size = config.VignetteSize
	local edges = {
		edge("Top", Vector2.new(0.5, 0), UDim2.fromScale(1, size), 90, gui),
		edge("Bottom", Vector2.new(0.5, 1), UDim2.fromScale(1, size), 270, gui),
		edge("Left", Vector2.new(0, 0.5), UDim2.fromScale(size, 1), 0, gui),
		edge("Right", Vector2.new(1, 0.5), UDim2.fromScale(size, 1), 180, gui),
	}

	local topBar = blackFrame("TopBar", gui)
	topBar.AnchorPoint = Vector2.new(0.5, 0)
	topBar.Position = UDim2.fromScale(0.5, 0)
	topBar.Size = UDim2.fromScale(1, 0)
	local bottomBar = blackFrame("BottomBar", gui)
	bottomBar.AnchorPoint = Vector2.new(0.5, 1)
	bottomBar.Position = UDim2.fromScale(0.5, 1)
	bottomBar.Size = UDim2.fromScale(1, 0)

	local first, firstGlow = lineLabel(1, gui)
	local second, secondGlow = lineLabel(2, gui)

	-- The charge meter just above the bottom bar.
	local meter = Create.frame("Meter")
	meter.AnchorPoint = Vector2.new(0.5, 1)
	meter.Position = UDim2.new(0.5, 0, 1 - config.LetterboxHeight, -config.MeterGap)
	meter.Size =
		UDim2.fromOffset(config.MeterWidth, config.MeterLabelHeight + config.MeterLabelGap + config.MeterHeight)
	meter.Parent = gui
	local meterLabel =
		Create.label("Label", Text.Ring.ChargeLabel, Theme.FontBold, config.MeterLabelTextSize, Theme.TextSecondary)
	meterLabel.TextXAlignment = Enum.TextXAlignment.Left
	meterLabel.Size = UDim2.new(1, 0, 0, config.MeterLabelHeight)
	meterLabel.TextTransparency = 1
	meterLabel.Parent = meter
	local meterValue = Create.label("Value", "", Theme.FontBold, config.MeterLabelTextSize, Theme.TextPrimary)
	meterValue.TextXAlignment = Enum.TextXAlignment.Right
	meterValue.Size = UDim2.new(1, 0, 0, config.MeterLabelHeight)
	meterValue.TextTransparency = 1
	meterValue.Parent = meter
	local track = Create.frame("Track")
	track.AnchorPoint = Vector2.new(0, 1)
	track.Position = UDim2.fromScale(0, 1)
	track.Size = UDim2.new(1, 0, 0, config.MeterHeight)
	track.BackgroundColor3 = Theme.TextPrimary
	track.BackgroundTransparency = 1
	Create.corner(track, UDim.new(0.5, 0))
	track.Parent = meter
	local meterFill = Create.frame("Fill")
	meterFill.Size = UDim2.fromScale(0, 1)
	meterFill.BackgroundColor3 = VFXConfig.Color
	meterFill.BackgroundTransparency = 1
	Create.corner(meterFill, UDim.new(0.5, 0))
	meterFill.Parent = track

	local flash = Create.frame("Flash")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = VFXConfig.Color
	flash.BackgroundTransparency = 1
	flash.ZIndex = 5
	flash.Parent = gui
	local dim = blackFrame("Dim", gui)
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundTransparency = 1
	dim.ZIndex = 6

	return {
		gui = gui,
		topBar = topBar,
		bottomBar = bottomBar,
		edges = edges,
		lines = { first, second },
		lineStrokes = { firstGlow, secondGlow },
		meter = meter,
		meterFill = meterFill,
		meterLabel = meterLabel,
		meterValue = meterValue,
		flash = flash,
		dim = dim,
	}
end

-- The camera shot ------------------------------------------------------------------------

local function flat(vector: Vector3): Vector3?
	local horizontal = Vector3.new(vector.X, 0, vector.Z)
	if horizontal.Magnitude < 0.05 then
		return nil
	end
	return horizontal.Unit
end

-- How far the camera can go from `focus` along `direction` before a wall.
local function clearance(focus: Vector3, direction: Vector3, distance: number): number
	local reach = distance + cameraConfig.WallPadding
	local result = Workspace:Raycast(focus, direction * reach, shotParams)
	if result == nil then
		return distance
	end
	return math.max((result.Position - focus).Magnitude - cameraConfig.WallPadding, 0)
end

-- A slow push-in on a 3/4 shot of the player facing the battery: from in
-- front of them and to one side, so their face and the battery are both in
-- frame. Whichever side has more room is used; with no room in front at all,
-- the shot looks over their shoulder at the battery instead.
local function computeShot(battery: Vector3): Shot
	local character = LocalPlayer.Character
	local root = if character ~= nil then character:FindFirstChild(ROOT_PART_NAME) else nil
	local rootPart = if root ~= nil and root:IsA("BasePart") then root else nil
	local exclude: { Instance } = {}
	if character ~= nil then
		table.insert(exclude, character)
	end
	local effects = Workspace:FindFirstChild(VFXConfig.FolderName)
	if effects ~= nil then
		table.insert(exclude, effects)
	end
	shotParams.FilterDescendantsInstances = exclude

	local subject = if rootPart ~= nil
		then rootPart.Position + Vector3.yAxis * cameraConfig.ChestHeight
		else battery - Vector3.zAxis * cameraConfig.FallbackDistance
	local facing = flat(battery - subject)
		or (if rootPart ~= nil then flat(rootPart.CFrame.LookVector) else nil)
		or -Vector3.zAxis
	local right = facing:Cross(Vector3.yAxis)
	local focus = subject:Lerp(battery, cameraConfig.FocusBlend)
	local angle = math.rad(cameraConfig.AngleDegrees)
	local lift = Vector3.yAxis * cameraConfig.Height

	local bestDirection = facing
	local bestSide = 1
	local bestRoom = -1
	for _, front in { 1, -1 } do
		for _, side in { 1, -1 } do
			local direction = (facing * front * math.cos(angle) + right * side * math.sin(angle)).Unit
			local withLift = (direction * cameraConfig.StartDistance + lift).Unit
			local room = clearance(focus, withLift, cameraConfig.StartDistance)
			if room > bestRoom then
				bestRoom = room
				bestDirection = direction
				bestSide = side
			end
		end
		if bestRoom >= cameraConfig.MinDistance then
			break
		end
	end

	-- The room was measured along the lifted line the camera actually travels.
	local span = (bestDirection * cameraConfig.StartDistance + lift).Magnitude / cameraConfig.StartDistance
	local startDistance = math.clamp(bestRoom / span, cameraConfig.NearestDistance, cameraConfig.StartDistance)
	local endDistance = startDistance * cameraConfig.EndDistance / cameraConfig.StartDistance
	-- The push-in also drifts a few degrees around the focus.
	local orbit = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(cameraConfig.OrbitDegrees) * bestSide)
	local endDirection = orbit:VectorToWorldSpace(bestDirection)
	local fromPosition = focus + bestDirection * startDistance + lift * (startDistance / cameraConfig.StartDistance)
	local toPosition = focus + endDirection * endDistance + lift * (endDistance / cameraConfig.StartDistance)
	return {
		from = CFrame.lookAt(fromPosition, focus),
		to = CFrame.lookAt(toPosition, focus),
		focus = focus,
	}
end

-- Playing --------------------------------------------------------------------------------

local function easeInOut(alpha: number): number
	return 0.5 - 0.5 * math.cos(math.pi * math.clamp(alpha, 0, 1))
end

local function step(deltaTime: number)
	local current = session
	local camera = Workspace.CurrentCamera
	if current == nil or camera == nil then
		return
	end
	local alpha = easeInOut((os.clock() - current.startedAt) / current.duration)
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	camera.CFrame = current.shot.from:Lerp(current.shot.to, alpha)
	camera.FieldOfView = cameraConfig.StartFov + (cameraConfig.EndFov - cameraConfig.StartFov) * alpha

	local built = overlay
	if built ~= nil then
		local target = math.clamp(RingController:GetCharge() / RingController:GetChargeMax(), 0, 1)
		current.shownCharge += (target - current.shownCharge) * (1 - math.exp(-config.MeterResponsiveness * deltaTime))
		built.meterFill.Size = UDim2.fromScale(current.shownCharge, 1)
		built.meterValue.Text = string.format(Text.Ring.ChargeValue, math.floor(target * 100 + 0.5))
	end
end

local function showLine(current: Session, text: string)
	local built = overlay
	if built == nil or session ~= current then
		return
	end
	local outgoing = current.lineSlot
	local incoming = if outgoing == 1 then 2 else 1
	current.lineSlot = incoming
	local fadeTime = config.LineFadeTime
	tween(built.lines[outgoing], fadeTime, { TextTransparency = 1 })
	tween(built.lineStrokes[outgoing], fadeTime, { Transparency = 1 })

	local label = built.lines[incoming]
	label.Text = text
	label.Position = UDim2.new(0.5, 0, config.LinePositionY, config.LineRise)
	tween(label, fadeTime, { TextTransparency = 0, Position = UDim2.fromScale(0.5, config.LinePositionY) })
	tween(built.lineStrokes[incoming], fadeTime, { Transparency = config.LineGlowTransparency })
end

local function showOverlay(built: Overlay)
	stopTweens()
	built.gui.Enabled = true
	built.flash.BackgroundTransparency = 1
	built.dim.BackgroundTransparency = 1
	built.topBar.Size = UDim2.fromScale(1, 0)
	built.bottomBar.Size = UDim2.fromScale(1, 0)
	for index, label in built.lines do
		label.Text = ""
		label.TextTransparency = 1
		built.lineStrokes[index].Transparency = 1
	end
	built.meterFill.Size = UDim2.fromScale(0, 1)

	local time = config.LetterboxTime
	tween(built.topBar, time, { Size = UDim2.fromScale(1, config.LetterboxHeight) }, Enum.EasingStyle.Sine)
	tween(built.bottomBar, time, { Size = UDim2.fromScale(1, config.LetterboxHeight) }, Enum.EasingStyle.Sine)
	for _, frame in built.edges do
		tween(frame, time, { BackgroundTransparency = 1 - config.VignetteOpacity })
	end
	tween(built.meterLabel, time, { TextTransparency = 0 })
	tween(built.meterValue, time, { TextTransparency = 0 })
	local track = built.meterFill.Parent
	if track ~= nil then
		tween(track, time, { BackgroundTransparency = config.MeterTrackTransparency })
	end
	tween(built.meterFill, time, { BackgroundTransparency = 0 })
end

-- Fades the overlay away: a green flash (completed) or a quick dark fade.
local function hideOverlay(built: Overlay, completed: boolean)
	stopTweens()
	local fadeTime = if completed then config.FadeOutTime else config.InterruptFadeTime
	if completed then
		built.flash.BackgroundTransparency = config.FlashTransparency
		tween(built.flash, config.FlashTime, { BackgroundTransparency = 1 })
	else
		built.dim.BackgroundTransparency = config.InterruptFadeTransparency
		tween(built.dim, config.InterruptFadeTime, { BackgroundTransparency = 1 })
	end
	tween(built.topBar, fadeTime, { Size = UDim2.fromScale(1, 0) }, Enum.EasingStyle.Sine)
	tween(built.bottomBar, fadeTime, { Size = UDim2.fromScale(1, 0) }, Enum.EasingStyle.Sine)
	for _, frame in built.edges do
		tween(frame, fadeTime, { BackgroundTransparency = 1 })
	end
	for index, label in built.lines do
		tween(label, fadeTime, { TextTransparency = 1 })
		tween(built.lineStrokes[index], fadeTime, { Transparency = 1 })
	end
	tween(built.meterLabel, fadeTime, { TextTransparency = 1 })
	tween(built.meterValue, fadeTime, { TextTransparency = 1 })
	local track = built.meterFill.Parent
	if track ~= nil then
		tween(track, fadeTime, { BackgroundTransparency = 1 })
	end
	tween(built.meterFill, fadeTime, { BackgroundTransparency = 1 })

	local mine = generation
	task.delay(math.max(fadeTime, config.FlashTime), function()
		-- A new moment may have started meanwhile; it owns the overlay now.
		if generation == mine and session == nil then
			built.gui.Enabled = false
		end
	end)
end

local function setControlsHidden(current: Session, hidden: boolean)
	RingHudController:SetHidden(HIDE_REASON, hidden)
	InputController:SetTouchHidden(HIDE_REASON, hidden)
	local hud = HudController:GetRoot()
	if hidden then
		hud.Enabled = false
		GuiService.TouchControlsEnabled = false
		-- Local only: other players still see (and can use) the battery's prompt.
		ProximityPromptService.Enabled = false
	else
		hud.Enabled = current.hudEnabled
		GuiService.TouchControlsEnabled = current.touchControlsEnabled
		ProximityPromptService.Enabled = current.promptsEnabled
	end
end

local function restoreCamera(current: Session)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	camera.CameraType = if current.cameraType == Enum.CameraType.Scriptable
		then Enum.CameraType.Custom
		else current.cameraType
	-- The same subject; after a respawn, the new character.
	local character = LocalPlayer.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	local subject = current.cameraSubject
	if humanoid ~= nil and humanoid.Health > 0 then
		camera.CameraSubject = humanoid
	elseif subject ~= nil and subject:IsDescendantOf(game) then
		camera.CameraSubject = subject
	end
	camera.FieldOfView = current.fieldOfView
end

local function finish(completed: boolean)
	local current = session
	if current == nil then
		return
	end
	session = nil
	RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
	for _, connection in current.connections do
		connection:Disconnect()
	end
	for _, thread in current.threads do
		if coroutine.status(thread) == "suspended" then
			task.cancel(thread)
		end
	end

	restoreCamera(current)
	setControlsHidden(current, false)
	SoundController:StopLoop(CHOIR_LOOP)
	if completed then
		SoundController:Play("OathComplete")
	end
	local built = overlay
	if built ~= nil then
		hideOverlay(built, completed)
	end
	OathController.Ended:Fire(completed)
end

local function begin(duration: number, battery: Vector3)
	-- A moment already playing (it never ended cleanly) gives way to the new one.
	finish(false)
	local camera = Workspace.CurrentCamera
	local built = overlay
	if camera == nil or built == nil then
		return
	end
	generation += 1

	local current: Session = {
		duration = math.max(duration, 0.1),
		startedAt = os.clock(),
		shot = computeShot(battery),
		connections = {},
		threads = {},
		cameraType = camera.CameraType,
		cameraSubject = camera.CameraSubject,
		fieldOfView = camera.FieldOfView,
		touchControlsEnabled = GuiService.TouchControlsEnabled,
		hudEnabled = HudController:GetRoot().Enabled,
		promptsEnabled = ProximityPromptService.Enabled,
		lineSlot = 2,
		shownCharge = math.clamp(RingController:GetCharge() / RingController:GetChargeMax(), 0, 1),
	}
	session = current

	setControlsHidden(current, true)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = current.shot.from
	-- Last, so nothing else moves the camera while the moment plays.
	RunService:BindToRenderStep(RENDER_STEP_NAME, Enum.RenderPriority.Last.Value, step)
	showOverlay(built)
	built.meterFill.Size = UDim2.fromScale(current.shownCharge, 1)
	SoundController:StartLoop(CHOIR_LOOP, "OathChoir", SoundService)

	-- One line at a time, evenly spread over the duration.
	local lines = Text.Oath.Lines
	local spacing = current.duration / math.max(#lines, 1)
	for index, line in lines do
		local at = config.LineLead + (index - 1) * spacing
		table.insert(current.threads, task.delay(at, showLine, current, line))
	end
	-- Backstop: the end message never arrived.
	table.insert(
		current.threads,
		task.delay(current.duration + config.EndGrace, function()
			if session == current then
				finish(false)
			end
		end)
	)

	-- Dying or respawning ends the moment at once.
	local character = LocalPlayer.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid ~= nil then
		table.insert(
			current.connections,
			humanoid.Died:Connect(function()
				if session == current then
					finish(false)
				end
			end)
		)
	end
	table.insert(
		current.connections,
		LocalPlayer.CharacterAdded:Connect(function()
			if session == current then
				finish(false)
			end
		end)
	)
	table.insert(
		current.connections,
		LocalPlayer.CharacterRemoving:Connect(function()
			if session == current then
				finish(false)
			end
		end)
	)
	OathController.Started:Fire()
end

-- API --------------------------------------------------------------------------------------

function OathController.IsPlaying(_self: OathController): boolean
	return session ~= nil
end

function OathController.Init(_self: OathController)
	overlay = buildOverlay()
	Remotes.OathStarted:Connect(function(duration: number, batteryPosition: Vector3)
		-- From the server, so trusted; still never let a malformed message throw.
		if type(duration) ~= "number" or duration ~= duration or typeof(batteryPosition) ~= "Vector3" then
			return
		end
		begin(duration, batteryPosition)
	end)
	Remotes.OathEnded:Connect(function(completed: boolean)
		finish(completed == true)
	end)
end

function OathController.Start(_self: OathController) end

export type OathController = typeof(OathController)

return OathController
