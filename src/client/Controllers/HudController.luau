--!strict
--[[
	HudController: owns the client's ScreenGuis and the UI scale.

	UI is laid out for a viewport Theme.ReferenceHeight pixels tall. Every
	ScreenGui made here gets a UIScale of (viewport height / ReferenceHeight),
	clamped to [Theme.MinScale, Theme.MaxScale] and updated whenever the window
	is resized or the device rotates. On short screens (phones) the scale stops
	at MinScale, so the logical screen is shorter than ReferenceHeight (about 460
	units on a 390 pt tall phone): layouts must size to the screen or scroll, as
	the Districts panel does.

	The main "HUD" ScreenGui keeps its contents inside the core UI safe area:
	below the Roblox top bar, clear of its menu and chat buttons and of screen
	notches. Other controllers parent their UI to it (GetRoot) or ask for their
	own ScreenGui (CreateScreenGui) when they need different stacking or the
	whole screen.

	API:
	  HudController:GetRoot(): ScreenGui
	  HudController:CreateScreenGui(name, options): ScreenGui
	  HudController:GetScale(): number
	  HudController.ScaleChanged  Signal(scale)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Signal = require(Shared.Util.Signal)
local Theme = require(Shared.Config.Theme)
local UIConfig = require(Shared.Config.UI)

export type ScreenGuiOptions = {
	DisplayOrder: number,
	-- Cover the entire screen, including the top bar and notch areas (e.g. a
	-- full-screen tint). Otherwise content stays inside the safe area.
	FullScreen: boolean?,
}

-- The engine creates PlayerGui alongside the player; this only yields in the
-- rare case it has not replicated before the client scripts run.
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local root: ScreenGui? = nil
local scales: { UIScale } = {}
local currentScale = 1
local viewportConnection: RBXScriptConnection? = nil

local HudController = {
	-- The UI scale changed (window resized, device rotated). (scale)
	ScaleChanged = Signal.new() :: Signal.Signal<number>,
}

local function computeScale(): number
	local camera = Workspace.CurrentCamera
	-- No camera yet: lay out at the reference size until one appears.
	local height = if camera ~= nil then camera.ViewportSize.Y else Theme.ReferenceHeight
	return math.clamp(height / Theme.ReferenceHeight, Theme.MinScale, Theme.MaxScale)
end

local function refreshScale()
	local scale = computeScale()
	if scale == currentScale then
		return
	end
	currentScale = scale
	for _, uiScale in scales do
		uiScale.Scale = scale
	end
	HudController.ScaleChanged:Fire(scale)
end

-- The camera can be replaced (e.g. by a camera script), so follow whichever is current.
local function watchCamera()
	if viewportConnection ~= nil then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end
	local camera = Workspace.CurrentCamera
	if camera ~= nil then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshScale)
	end
	refreshScale()
end

function HudController.CreateScreenGui(_self: HudController, name: string, options: ScreenGuiOptions): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	-- Built once per session; the character respawning must not rebuild it.
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = options.DisplayOrder
	if options.FullScreen then
		gui.IgnoreGuiInset = true
		gui.ScreenInsets = Enum.ScreenInsets.None
		gui.ClipToDeviceSafeArea = false
	else
		gui.IgnoreGuiInset = false
		gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
		gui.ClipToDeviceSafeArea = true
	end

	local uiScale = Instance.new("UIScale")
	uiScale.Scale = currentScale
	uiScale.Parent = gui
	table.insert(scales, uiScale)
	uiScale.Destroying:Connect(function()
		local index = table.find(scales, uiScale)
		if index ~= nil then
			table.remove(scales, index)
		end
	end)

	gui.Parent = playerGui
	return gui
end

-- The main HUD ScreenGui. Only valid after Init.
function HudController.GetRoot(_self: HudController): ScreenGui
	assert(root ~= nil, "HudController:GetRoot() called before HudController:Init()")
	return root
end

function HudController.GetScale(_self: HudController): number
	return currentScale
end

function HudController.Init(self: HudController)
	currentScale = computeScale()
	root = self:CreateScreenGui("HUD", { DisplayOrder = UIConfig.DisplayOrder.Hud })
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	watchCamera()
end

function HudController.Start(_self: HudController) end

export type HudController = typeof(HudController)

return HudController
