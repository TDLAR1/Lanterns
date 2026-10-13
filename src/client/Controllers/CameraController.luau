--!strict
--[[
	CameraController: the combat camera, aiming, field of view and camera shake.

	Roblox's own camera scripts keep driving the camera; this controller only
	adjusts their result, from two render steps around the default camera update
	(Enum.RenderPriority.Camera):
	  * Just before it, the camera is put back exactly where the camera scripts
	    left it last frame (unless something else moved it since). They build each
	    frame on the camera's current rotation, so without this the shake would
	    drift the view. Touch aiming turns that rotation here too (see below), so
	    the camera scripts carry it on as if the player had dragged the screen.
	  * Just after it, the shoulder offset, shake and field of view are applied
	    and a character on foot is turned to face the camera.
	Workspace.CurrentCamera is read every frame, so a replaced camera simply takes
	over, and the character is looked up again every frame, so respawns need
	nothing special. A Scriptable camera (cutscenes) and VR are left alone.

	COMBAT MODE (SetCombatMode) is on while any reason is active and lingers
	Config.Camera.CombatLinger seconds after the last one ends, so beam taps
	never swing the camera in and out. While it is on:
	  * The camera slides over the right shoulder (Config.Camera.Combat): less as
	    it zooms in (none in first person), and never into a wall beside it.
	  * A character on foot faces where the camera looks: Humanoid.AutoRotate is
	    off and the root part turns to the camera's yaw. Flying (PlatformStand;
	    FlightController poses the body), sitting, climbing, swimming and
	    ragdolled characters are left alone. While the ring battery's oath plays
	    (Attributes.Recharging) the server owns the facing and AutoRotate.
	  * A small ring-green crosshair shows at the exact centre of the screen
	    (not over a Scriptable camera).
	  * On keyboard and mouse the mouse is locked to the centre and the cursor
	    hidden (the crosshair replaces it), except while a panel or the Roblox
	    menu is open, so their buttons stay clickable.
	  * On touch, the finger holding a Config.Camera.TouchAim action's button
	    (the Beam button) turns the camera as it drags: aim while you fire.
	When it ends, AutoRotate and the mouse are restored to what they were.

	AIMING. GetAimRay is the ray through the crosshair, without camera shake.
	GetAimPoint follows it into the world. It skips the local character, anything
	between the camera and the character (the camera is behind it), and parts you
	can see through or walk through (Config.Camera.Aim) unless they belong to a
	character (a dummy's limbs never collide but must be hit). The result is
	clamped to maxDistance from the character.

	API:
	  CameraController:GetAimRay(): Ray                        (unit direction)
	  CameraController:GetAimPoint(maxDistance): Vector3
	  CameraController:SetCombatMode(reason, active)           (any reason active = on)
	  CameraController:SetFovOffset(source, degrees)           (summed onto
	    Config.Flight.Camera.NormalFov and smoothed; 0 removes the source)
	  CameraController:Shake(intensity, duration)              (decaying; shakes add up)
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VRService = game:GetService("VRService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local CameraConfig = require(Shared.Config.Camera)
local FlightConfig = require(Shared.Config.Flight)
local TagsModule = require(Shared.Util.Tags)

local Create = require(script.Parent.Parent.UI.Create)
local HudController = require(script.Parent.HudController)
local InputController = require(script.Parent.InputController)

type ShakeEntry = {
	intensity: number,
	duration: number,
	startedAt: number,
}

-- One drawn piece of the crosshair, faded together with the others.
type CrosshairPiece = {
	frame: Frame,
	stroke: UIStroke,
}

-- The finger currently aiming the camera from one action's touch button.
type TouchDrag = {
	input: InputObject,
	position: Vector3,
}

local LocalPlayer = Players.LocalPlayer
local Tags = TagsModule.Tags
local Attributes = TagsModule.Attributes

local combatConfig = CameraConfig.Combat
local crosshairConfig = CameraConfig.Crosshair
local aimConfig = CameraConfig.Aim
local shakeConfig = CameraConfig.Shake
local touchAimConfig = CameraConfig.TouchAim
local fovConfig = FlightConfig.Camera

local RESTORE_STEP_NAME = "CameraControllerRestore"
local APPLY_STEP_NAME = "CameraControllerApply"
-- Every standard Humanoid rig (R15, R6, custom StarterCharacter) names its root this.
local ROOT_PART_NAME = "HumanoidRootPart"
-- Most shakes kept at once; beyond this the oldest is dropped (a burst of hits
-- must not grow the list without bound).
local MAX_SHAKES = 16
-- Below this a blend, offset or shake counts as nothing (avoids endless tiny
-- property writes while it settles).
local EPSILON = 1e-3
-- The default camera scripts drive these camera types in third person.
local DRIVEN_CAMERA_TYPES: { [Enum.CameraType]: boolean } = {
	[Enum.CameraType.Custom] = true,
	[Enum.CameraType.Follow] = true,
}
-- Humanoid states in which a character on foot may be turned to face the camera.
local FACING_STATES: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.Running] = true,
	[Enum.HumanoidStateType.RunningNoPhysics] = true,
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.Landed] = true,
}

-- Combat mode.
local reasons: { [string]: boolean } = {}
local lingerUntil = 0
local blend = 0

-- Field of view.
local fovOffsets: { [string]: number } = {}
local currentFov = fovConfig.NormalFov
-- What was last written to the camera (nil: write once to a new camera).
local writtenFov: number? = nil

local shakes: { ShakeEntry } = {}

-- Camera bookkeeping. cleanCFrame is where the camera scripts put the camera
-- this frame, appliedCFrame what this controller wrote over it (nil: nothing),
-- aimCFrame the clean camera with the shoulder offset but without shake.
local trackedCamera: Camera? = nil
local cleanCFrame: CFrame? = nil
local appliedCFrame: CFrame? = nil
local aimCFrame: CFrame? = nil

-- Mouse lock: whether it is ours, and what to give back.
local mouseLocked = false
local mouseBehaviorBefore = Enum.MouseBehavior.Default
local mouseIconBefore = true

-- The Humanoid whose AutoRotate combat mode switched off, and its value before.
local rotatingHumanoid: Humanoid? = nil
local autoRotateBefore = true

local touchDrags: { [string]: TouchDrag } = {}

local crosshairPieces: { CrosshairPiece } = {}
local crosshairGui: ScreenGui? = nil
local shownCrosshair = -1

-- Shoulder-offset wall check: ignores the character and parts you walk through.
local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Exclude
wallParams.RespectCanCollide = true
wallParams.IgnoreWater = true
local wallFilterCharacter: Model? = nil

local CameraController = {}

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

local function isActive(now: number): boolean
	return next(reasons) ~= nil or now < lingerUntil
end

local function isRecharging(): boolean
	return LocalPlayer:GetAttribute(Attributes.Recharging) == true
end

local function findRoot(character: Model?): BasePart?
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild(ROOT_PART_NAME)
	return if root ~= nil and root:IsA("BasePart") then root else nil
end

-- The local character's Humanoid while it is alive and in the world.
local function livingHumanoid(): Humanoid?
	local character = LocalPlayer.Character
	if character == nil or not character:IsDescendantOf(Workspace) then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return nil
	end
	return humanoid
end

-- AutoRotate ------------------------------------------------------------------

local function releaseAutoRotate()
	local humanoid = rotatingHumanoid
	if humanoid == nil then
		return
	end
	rotatingHumanoid = nil
	-- During the oath the battery has switched AutoRotate off on the server and
	-- switches it back itself when the oath ends; restoring it here would let
	-- the character turn away from the battery.
	if humanoid.Parent ~= nil and not isRecharging() and humanoid.AutoRotate ~= autoRotateBefore then
		humanoid.AutoRotate = autoRotateBefore
	end
end

-- Keeps AutoRotate off while combat mode is on. Called every frame (a server
-- write, e.g. the end of an oath, may switch it back on) and straight from
-- SetCombatMode, so the walking value is saved before FlightController (which
-- turns combat mode on first) switches AutoRotate off for flight.
local function holdAutoRotate(active: boolean)
	local humanoid = if active and not isRecharging() then livingHumanoid() else nil
	if humanoid == nil then
		releaseAutoRotate()
		return
	end
	if rotatingHumanoid ~= humanoid then
		releaseAutoRotate()
		rotatingHumanoid = humanoid
		autoRotateBefore = humanoid.AutoRotate
	end
	if humanoid.AutoRotate then
		humanoid.AutoRotate = false
	end
end

-- Turns a character on foot toward the camera's yaw.
local function faceCamera(look: Vector3, deltaTime: number)
	local humanoid = rotatingHumanoid
	if humanoid == nil or humanoid.PlatformStand or humanoid.Sit or not FACING_STATES[humanoid:GetState()] then
		return
	end
	local root = humanoid.RootPart
	if root == nil or root.Anchored then
		return
	end
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < EPSILON then
		return
	end
	local yaw = yawOf(root.CFrame.LookVector)
	local turn = wrapAngle(yawOf(flat) - yaw) * smoothing(combatConfig.TurnResponsiveness, deltaTime)
	if math.abs(turn) < EPSILON then
		return
	end
	root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw + turn, 0)
end

-- Mouse lock ------------------------------------------------------------------

local function updateMouseLock(active: boolean)
	local wanted = active
		and InputController:GetDevice() == "KeyboardMouse"
		and not InputController:IsMenuOpen()
		and not GuiService.MenuIsOpen
	if wanted then
		if not mouseLocked then
			mouseLocked = true
			local before = UserInputService.MouseBehavior
			-- The camera scripts' own locks (first person, holding the right mouse
			-- button) are momentary and re-applied by them every frame, so the
			-- value to give back is the free mouse.
			mouseBehaviorBefore = if before == Enum.MouseBehavior.LockCurrentPosition
					or before == Enum.MouseBehavior.LockCenter
				then Enum.MouseBehavior.Default
				else before
			mouseIconBefore = UserInputService.MouseIconEnabled
		end
		-- Re-asserted every frame: the camera scripts lock to the current position
		-- while the right mouse button is held and restore our value afterwards.
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
		if UserInputService.MouseIconEnabled then
			UserInputService.MouseIconEnabled = false
		end
	elseif mouseLocked then
		mouseLocked = false
		if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = mouseBehaviorBefore
		end
		UserInputService.MouseIconEnabled = mouseIconBefore
	end
end

-- Crosshair -------------------------------------------------------------------

local function addCrosshairPiece(parent: ScreenGui, name: string, size: Vector2, offset: Vector2, round: boolean)
	local frame = Create.frame(name)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, offset.X, 0.5, offset.Y)
	frame.Size = UDim2.fromOffset(size.X, size.Y)
	frame.BackgroundColor3 = crosshairConfig.Color
	frame.BackgroundTransparency = 1
	if round then
		Create.corner(frame, UDim.new(0.5, 0))
	end
	local stroke = Create.stroke(frame, crosshairConfig.OutlineColor, crosshairConfig.OutlineThickness, 1)
	frame.Parent = parent
	table.insert(crosshairPieces, { frame = frame, stroke = stroke })
end

-- A centre dot and four short ticks around it. Full screen (no top-bar inset),
-- so scale (0.5, 0.5) is exactly the viewport centre the aim ray goes through.
local function buildCrosshair()
	local gui = HudController:CreateScreenGui("Crosshair", {
		DisplayOrder = crosshairConfig.DisplayOrder,
		FullScreen = true,
	})
	gui.Enabled = false
	local dot = crosshairConfig.DotSize
	local length = crosshairConfig.TickLength
	local thickness = crosshairConfig.TickThickness
	local reach = crosshairConfig.TickGap + length / 2
	addCrosshairPiece(gui, "Dot", Vector2.new(dot, dot), Vector2.zero, true)
	addCrosshairPiece(gui, "Top", Vector2.new(thickness, length), Vector2.new(0, -reach), false)
	addCrosshairPiece(gui, "Bottom", Vector2.new(thickness, length), Vector2.new(0, reach), false)
	addCrosshairPiece(gui, "Left", Vector2.new(length, thickness), Vector2.new(-reach, 0), false)
	addCrosshairPiece(gui, "Right", Vector2.new(length, thickness), Vector2.new(reach, 0), false)
	crosshairGui = gui
end

local function showCrosshair(opacity: number)
	local gui = crosshairGui
	-- Rounded so a settled blend costs no property writes.
	local rounded = math.floor(opacity * 100 + 0.5) / 100
	if gui == nil or rounded == shownCrosshair then
		return
	end
	shownCrosshair = rounded
	gui.Enabled = rounded > 0
	local outlineOpacity = 1 - crosshairConfig.OutlineTransparency
	for _, piece in crosshairPieces do
		piece.frame.BackgroundTransparency = 1 - rounded
		piece.stroke.Transparency = 1 - outlineOpacity * rounded
	end
end

-- Camera adjustments ----------------------------------------------------------

-- Camera-space shoulder offset for this frame (right, up, back).
local function shoulderOffset(camera: Camera, clean: CFrame): Vector3
	if blend < EPSILON then
		return Vector3.zero
	end
	-- Fades out as the camera zooms in: first person has no shoulder.
	local zoom = (clean.Position - camera.Focus.Position).Magnitude
	local zoomWeight = math.clamp(
		(zoom - combatConfig.OffsetMinZoom) / (combatConfig.OffsetFullZoom - combatConfig.OffsetMinZoom),
		0,
		1
	)
	local offset = combatConfig.ShoulderOffset * (blend * zoomWeight)
	local distance = offset.Magnitude
	if distance < EPSILON then
		return Vector3.zero
	end

	-- Never slide into a wall beside the camera: stop WallPadding short of it.
	local character = LocalPlayer.Character
	if character ~= wallFilterCharacter then
		wallFilterCharacter = character
		wallParams.FilterDescendantsInstances = if character ~= nil then { character } else {}
	end
	local direction = clean:VectorToWorldSpace(offset).Unit
	local hit = Workspace:Raycast(clean.Position, direction * (distance + combatConfig.WallPadding), wallParams)
	if hit ~= nil then
		offset *= math.max(0, hit.Distance - combatConfig.WallPadding) / distance
	end
	return offset
end

-- The sum of every running shake, as a camera-space jitter.
local function shakeOffset(now: number): CFrame
	local intensity = 0
	for index = #shakes, 1, -1 do
		local entry = shakes[index]
		local progress = (now - entry.startedAt) / entry.duration
		if progress >= 1 then
			table.remove(shakes, index)
		else
			-- Quadratic decay: a sharp kick that settles smoothly.
			intensity += entry.intensity * (1 - progress) ^ 2
		end
	end
	intensity = math.min(intensity, shakeConfig.MaxIntensity) * shakeConfig.Scale
	if intensity < EPSILON then
		return CFrame.identity
	end
	-- Smooth noise (not random jumps) at Frequency cycles per second. math.noise
	-- mostly stays within +-0.5, so it is doubled to use the configured range.
	local t = now * shakeConfig.Frequency
	local function wobble(seed: number): number
		return math.clamp(math.noise(t, seed) * 2, -1, 1) * intensity
	end
	local angle = math.rad(shakeConfig.MaxAngle)
	return CFrame.new(wobble(11.3) * shakeConfig.MaxOffset, wobble(23.7) * shakeConfig.MaxOffset, 0)
		* CFrame.Angles(wobble(37.1) * angle, wobble(41.9) * angle, wobble(53.3) * angle * 0.5)
end

local function updateFov(camera: Camera, deltaTime: number)
	local target = fovConfig.NormalFov
	for _, degrees in fovOffsets do
		target += degrees
	end
	if math.abs(target - currentFov) < 0.01 then
		currentFov = target
	else
		currentFov += (target - currentFov) * smoothing(fovConfig.FovResponsiveness, deltaTime)
	end
	-- At rest at the normal field of view (already written once), leave the
	-- camera alone so other code can still change it.
	if writtenFov == currentFov and currentFov == fovConfig.NormalFov then
		return
	end
	if camera.FieldOfView ~= currentFov then
		camera.FieldOfView = currentFov
	end
	writtenFov = currentFov
end

-- Touch aiming: how far the fingers holding the TouchAim buttons dragged since
-- last frame, as (yaw, pitch) radians.
local function collectTouchAim(): (number, number)
	local yaw, pitch = 0, 0
	for _, actionName in touchAimConfig.Actions do
		local input = InputController:GetTouchInput(actionName)
		local drag = touchDrags[actionName]
		if input == nil then
			touchDrags[actionName] = nil
		elseif drag ~= nil and drag.input == input then
			local delta = input.Position - drag.position
			drag.position = input.Position
			-- Same direction as dragging the screen: right turns right, down looks down.
			yaw -= delta.X * touchAimConfig.Sensitivity.X
			pitch -= delta.Y * touchAimConfig.Sensitivity.Y
		else
			-- A new finger: it starts aiming from where it is now.
			touchDrags[actionName] = { input = input, position = input.Position }
		end
	end
	return yaw, pitch
end

-- Turns the camera before the camera scripts run; they continue from its new
-- rotation and keep their own pitch limits and zoom.
local function turnCamera(camera: Camera, yaw: number, pitch: number)
	local current = camera.CFrame
	local look = current.LookVector
	local maxPitch = math.rad(touchAimConfig.MaxPitch)
	local newPitch = math.clamp(math.asin(math.clamp(look.Y, -1, 1)) + pitch, -maxPitch, maxPitch)
	local newYaw = yawOf(look) + yaw
	local direction =
		Vector3.new(-math.sin(newYaw) * math.cos(newPitch), math.sin(newPitch), -math.cos(newYaw) * math.cos(newPitch))
	camera.CFrame = CFrame.lookAlong(current.Position, direction)
end

local function drivesCamera(camera: Camera): boolean
	return DRIVEN_CAMERA_TYPES[camera.CameraType] == true and not VRService.VREnabled
end

-- Render step before the default camera.
local function restoreCamera()
	local camera = Workspace.CurrentCamera
	local applied, clean = appliedCFrame, cleanCFrame
	appliedCFrame = nil
	if camera == nil then
		return
	end
	if camera == trackedCamera and applied ~= nil and clean ~= nil and camera.CFrame == applied then
		camera.CFrame = clean
	end
	local yaw, pitch = collectTouchAim()
	if (yaw ~= 0 or pitch ~= 0) and drivesCamera(camera) then
		turnCamera(camera, yaw, pitch)
	end
end

-- Render step after the default camera.
local function applyCamera(deltaTime: number)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	if camera ~= trackedCamera then
		-- A new camera: nothing of ours is on it yet.
		trackedCamera = camera
		writtenFov = nil
	end
	local now = os.clock()
	local active = isActive(now)

	local target = if active then 1 else 0
	blend += (target - blend) * smoothing(combatConfig.BlendResponsiveness, deltaTime)
	if math.abs(target - blend) < EPSILON then
		blend = target
	end

	holdAutoRotate(active)
	updateMouseLock(active)
	-- Only over a camera the player steers: a cutscene (the oath moment) may
	-- start while combat mode still lingers, and must not show the crosshair.
	local driven = drivesCamera(camera)
	showCrosshair(if driven then blend else 0)

	local clean = camera.CFrame
	cleanCFrame = clean
	if active then
		faceCamera(clean.LookVector, deltaTime)
	end

	if not driven then
		aimCFrame = clean
		return
	end
	local offset = shoulderOffset(camera, clean)
	local aim = if offset == Vector3.zero then clean else clean * CFrame.new(offset)
	aimCFrame = aim
	local final = aim * shakeOffset(now)
	if final ~= clean then
		camera.CFrame = final
		appliedCFrame = final
	end
	updateFov(camera, deltaTime)
end

-- Aiming ----------------------------------------------------------------------

-- Parts of a character (or a Damageable model) are always hit, see-through or not.
local function belongsToCharacter(part: BasePart): boolean
	local model = part:FindFirstAncestorWhichIsA("Model")
	while model ~= nil do
		if model:FindFirstChildOfClass("Humanoid") ~= nil or model:HasTag(Tags.Damageable) then
			return true
		end
		model = model:FindFirstAncestorWhichIsA("Model")
	end
	return false
end

local function passesThrough(instance: Instance): boolean
	if not instance:IsA("BasePart") or instance:IsA("Terrain") then
		return false
	end
	if instance.Transparency < aimConfig.IgnoreTransparency and instance.CanCollide then
		return false
	end
	return not belongsToCharacter(instance)
end

-- Follows the ray from `start` for `length` studs; returns the first solid hit or the end.
local function traceAim(start: Vector3, direction: Vector3, length: number, character: Model?): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if character ~= nil then { character } else {}
	local position = start
	local remaining = length
	for passed = 0, aimConfig.MaxPassThrough do
		if remaining <= 0 then
			return position
		end
		local result = Workspace:Raycast(position, direction * remaining, params)
		if result == nil then
			return position + direction * remaining
		end
		if passed == aimConfig.MaxPassThrough or not passesThrough(result.Instance) then
			return result.Position
		end
		params:AddToFilter(result.Instance)
		remaining -= result.Distance
		position = result.Position
	end
	return position + direction * remaining
end

-- API -------------------------------------------------------------------------

-- The ray from the camera through the crosshair (the centre of the screen),
-- with the shoulder offset but not the shake. Direction is a unit vector.
function CameraController.GetAimRay(_self: CameraController): Ray
	local camera = Workspace.CurrentCamera
	local aim = aimCFrame
	if camera ~= nil and camera == trackedCamera and aim ~= nil then
		return Ray.new(aim.Position, aim.LookVector)
	end
	-- Before the first frame (or right after the camera was replaced).
	if camera ~= nil then
		local viewport = camera.ViewportSize
		local ray = camera:ViewportPointToRay(viewport.X / 2, viewport.Y / 2)
		return Ray.new(ray.Origin, ray.Direction.Unit)
	end
	return Ray.new(Vector3.zero, -Vector3.zAxis)
end

-- Where the crosshair points in the world, at most maxDistance studs from the
-- local character (from the camera when there is no character).
function CameraController.GetAimPoint(self: CameraController, maxDistance: number): Vector3
	local ray = self:GetAimRay()
	local origin, direction = ray.Origin, ray.Direction
	local character = LocalPlayer.Character
	local root = findRoot(character)
	local centre = if root ~= nil then root.Position else origin
	local range = math.max(maxDistance, 0)

	-- Start level with the character: whatever is between it and the camera
	-- behind it is not what the player aims at.
	local toCentre = centre - origin
	local along = math.max(0, toCentre:Dot(direction))
	local reachSquared = range * range - (toCentre:Dot(toCentre) - along * along)
	local point: Vector3
	if reachSquared <= 0 then
		-- The ray never comes within range (e.g. range 0): aim at its nearest point.
		point = origin + direction * along
	else
		local length = math.sqrt(reachSquared)
		point = traceAim(origin + direction * along, direction, length, character)
	end

	local offset = point - centre
	if offset.Magnitude > range then
		point = if offset.Magnitude > EPSILON then centre + offset.Unit * range else centre
	end
	return point
end

-- Turns combat mode on while any reason is active (e.g. "Beam", "Flight").
-- Setting the same reason twice is harmless; it ends with one `false`.
function CameraController.SetCombatMode(_self: CameraController, reason: string, active: boolean)
	if active then
		reasons[reason] = true
		holdAutoRotate(true)
	elseif reasons[reason] then
		reasons[reason] = nil
		if next(reasons) == nil then
			lingerUntil = os.clock() + CameraConfig.CombatLinger
		end
	end
end

-- Adds `degrees` of field of view for `source` (replacing its previous value).
function CameraController.SetFovOffset(_self: CameraController, source: string, degrees: number)
	if degrees == 0 or degrees ~= degrees then
		fovOffsets[source] = nil
	else
		fovOffsets[source] = degrees
	end
end

-- Shakes the camera, strongest at once and fading out over `duration` seconds.
-- Intensity 1 is Config.Camera.Shake's MaxAngle / MaxOffset.
function CameraController.Shake(_self: CameraController, intensity: number, duration: number)
	if not (intensity > 0 and duration > 0) then
		return
	end
	if #shakes >= MAX_SHAKES then
		table.remove(shakes, 1)
	end
	table.insert(shakes, { intensity = intensity, duration = duration, startedAt = os.clock() })
end

function CameraController.Init(_self: CameraController)
	buildCrosshair()
end

function CameraController.Start(_self: CameraController)
	RunService:BindToRenderStep(RESTORE_STEP_NAME, Enum.RenderPriority.Camera.Value - 1, restoreCamera)
	RunService:BindToRenderStep(APPLY_STEP_NAME, Enum.RenderPriority.Camera.Value + 1, applyCamera)
end

export type CameraController = typeof(CameraController)

return CameraController
