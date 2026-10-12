--!strict
--[[
	BoundaryController: the soft edge of the play area, on the client.

	Every frame (RunService.Heartbeat) the local character's root part is checked
	with Util/Boundary (Config.World.Boundary):
	  * Inside the soft band (Depth > 0) a warning overlay appears, stronger the
	    deeper the player goes: a warm glow around the screen edges plus a short
	    message. The character is pushed back by raising its velocity toward the
	    play area to at least Depth x MaxPushSpeed. Only the missing amount is
	    added, so the push never builds up frame after frame.
	  * At or past the hard edge (Depth >= 1) the root part is also put back on
	    the edge, keeping its rotation.
	The client owns its character's physics, so this is smooth for the player;
	BoundaryService on the server is only the anti-exploit backstop.

	The overlay is its own full-screen ScreenGui under the HUD, so the glow also
	covers the top bar and notch areas. The message sits at
	Config.UI.Boundary.TextPositionY (below the character, between the touch
	thumbstick and jump button).

	API:
	  BoundaryController:GetState(): BoundaryState?
	    The latest evaluation for the local character (nil without a live
	    character). Flight steering can read it instead of evaluating again.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Boundary = require(Shared.Util.Boundary)
local Text = require(Shared.Config.Text)
local Theme = require(Shared.Config.Theme)
local UIConfig = require(Shared.Config.UI)
local WorldConfig = require(Shared.Config.World)

local Create = require(script.Parent.Parent.UI.Create)
local HudController = require(script.Parent.HudController)

type Overlay = {
	gui: ScreenGui,
	edges: { Frame },
	title: TextLabel,
	hint: TextLabel,
	textStrokes: { UIStroke },
}

-- Every standard Humanoid rig (R6, R15, custom StarterCharacter) names its root this.
local ROOT_PART_NAME = "HumanoidRootPart"

local LocalPlayer = Players.LocalPlayer
local config = UIConfig.Boundary

local overlay: Overlay? = nil
local state: Boundary.BoundaryState? = nil
-- Last depth drawn, so standing still costs no property writes.
local shownDepth = 0

-- Looked up again only when the character or its parts change.
local cachedCharacter: Model? = nil
local cachedRoot: BasePart? = nil
local cachedHumanoid: Humanoid? = nil

local BoundaryController = {}

-- A glow along one screen edge: opaque at the edge, clear toward the middle.
-- `rotation` turns the gradient (0 = from the left edge, 90 = from the top).
local function buildEdge(name: string, anchor: Vector2, size: UDim2, rotation: number, parent: ScreenGui): Frame
	local edge = Create.frame(name)
	edge.AnchorPoint = anchor
	edge.Position = UDim2.fromScale(anchor.X, anchor.Y)
	edge.Size = size
	edge.BackgroundColor3 = Theme.Warning
	edge.BackgroundTransparency = 1
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Transparency = NumberSequence.new(0, 1)
	gradient.Parent = edge
	edge.Parent = parent
	return edge
end

local function buildOverlay(): Overlay
	local gui = HudController:CreateScreenGui("BoundaryWarning", {
		DisplayOrder = UIConfig.DisplayOrder.BoundaryWarning,
		FullScreen = true,
	})
	gui.Enabled = false

	local thickness = config.VignetteSize
	local edges = {
		buildEdge("Top", Vector2.new(0.5, 0), UDim2.fromScale(1, thickness), 90, gui),
		buildEdge("Bottom", Vector2.new(0.5, 1), UDim2.fromScale(1, thickness), 270, gui),
		buildEdge("Left", Vector2.new(0, 0.5), UDim2.fromScale(thickness, 1), 0, gui),
		buildEdge("Right", Vector2.new(1, 0.5), UDim2.fromScale(thickness, 1), 180, gui),
	}

	local message = Create.frame("Message")
	message.AnchorPoint = Vector2.new(0.5, 0.5)
	message.Position = UDim2.fromScale(0.5, config.TextPositionY)
	message.Size = UDim2.new(1, -2 * UIConfig.ScreenMargin, 0, config.TitleHeight + config.HintHeight)
	Create.maxSize(message, config.MaxWidth)
	Create.list(message, Enum.FillDirection.Vertical, 0)

	local title = Create.label("Title", Text.Boundary.Title, Theme.FontBold, config.TitleTextSize, Theme.Warning)
	title.Size = UDim2.new(1, 0, 0, config.TitleHeight)
	title.TextTransparency = 1
	title.LayoutOrder = 1
	local titleStroke = Create.textStroke(title, Theme.PanelColor, config.TextStrokeThickness, 1)
	title.Parent = message

	local hint = Create.label("Hint", Text.Boundary.Hint, Theme.Font, config.HintTextSize, Theme.TextPrimary)
	hint.Size = UDim2.new(1, 0, 0, config.HintHeight)
	hint.TextTransparency = 1
	hint.LayoutOrder = 2
	local hintStroke = Create.textStroke(hint, Theme.PanelColor, config.TextStrokeThickness, 1)
	hint.Parent = message

	message.Parent = gui

	return {
		gui = gui,
		edges = edges,
		title = title,
		hint = hint,
		textStrokes = { titleStroke, hintStroke },
	}
end

local function showWarning(depth: number)
	local current = overlay
	if current == nil or depth == shownDepth then
		return
	end
	shownDepth = depth
	current.gui.Enabled = depth > 0
	if depth <= 0 then
		return
	end

	local glowTransparency = 1 - math.min(depth, 1) * config.VignetteMaxOpacity
	for _, edge in current.edges do
		edge.BackgroundTransparency = glowTransparency
	end
	-- The text becomes fully readable early in the band; the glow keeps growing.
	local textOpacity = math.clamp(depth / config.TextFullDepth, 0, 1)
	current.title.TextTransparency = 1 - textOpacity
	current.hint.TextTransparency = 1 - textOpacity
	for _, stroke in current.textStrokes do
		stroke.Transparency = 1 - (1 - config.TextStrokeTransparency) * textOpacity
	end
	current.hint.Text = if depth >= 1 then Text.Boundary.EdgeHint else Text.Boundary.Hint
end

-- The local character's root part while it is alive and in the world, else nil.
local function getLiveRoot(): BasePart?
	local character = LocalPlayer.Character
	if character == nil then
		return nil
	end
	local root, humanoid = cachedRoot, cachedHumanoid
	if
		character ~= cachedCharacter
		or root == nil
		or root.Parent ~= character
		or humanoid == nil
		or humanoid.Parent ~= character
	then
		cachedCharacter = character
		local found = character:FindFirstChild(ROOT_PART_NAME)
		root = if found ~= nil and found:IsA("BasePart") then found else nil
		humanoid = character:FindFirstChildOfClass("Humanoid")
		cachedRoot, cachedHumanoid = root, humanoid
	end
	if root == nil or humanoid == nil or humanoid.Health <= 0 or not character:IsDescendantOf(Workspace) then
		return nil
	end
	return root
end

local function pushBack(root: BasePart, evaluated: Boundary.BoundaryState)
	local depth = evaluated.Depth
	local inward = evaluated.Inward
	if depth >= 1 then
		root.CFrame = CFrame.new(evaluated.Clamped) * root.CFrame.Rotation
	end
	-- MaxPushSpeed is the push at the hard edge; past it the clamp above takes over.
	local minimumInwardSpeed = math.min(depth, 1) * WorldConfig.Boundary.MaxPushSpeed
	local velocity = root.AssemblyLinearVelocity
	local inwardSpeed = velocity:Dot(inward)
	if inwardSpeed < minimumInwardSpeed then
		root.AssemblyLinearVelocity = velocity + inward * (minimumInwardSpeed - inwardSpeed)
	end
end

local function step()
	local root = getLiveRoot()
	if root == nil then
		state = nil
		showWarning(0)
		return
	end
	local evaluated = Boundary.Evaluate(root.Position)
	state = evaluated
	showWarning(evaluated.Depth)
	-- An anchored root is being placed by a script (e.g. a cutscene): leave it alone.
	if evaluated.Depth > 0 and not root.Anchored then
		pushBack(root, evaluated)
	end
end

function BoundaryController.GetState(_self: BoundaryController): Boundary.BoundaryState?
	return state
end

function BoundaryController.Init(_self: BoundaryController)
	overlay = buildOverlay()
end

function BoundaryController.Start(_self: BoundaryController)
	RunService.Heartbeat:Connect(step)
end

export type BoundaryController = typeof(BoundaryController)

return BoundaryController
