--!strict
--[[
	Fader: fades a piece of UI (a root and all of its descendants) in and out as
	one, with TweenService.

	A CanvasGroup could do this with one property, but it renders its contents to
	a texture: extra memory on phones and slightly soft text. Tweening each
	element's own transparency costs nothing while nothing is fading.

	Fader.new(root) records the transparencies the UI was BUILT with as its shown
	look, then hides it at once. So build the UI fully visible, then wrap it.
	Elements added under the root afterwards are not faded.

	Faded UI is display-only: frame backgrounds, TextLabels, ImageLabels and
	UIStrokes fade; buttons and text boxes do not (a half-transparent button
	would still take clicks).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UIConfig = require(ReplicatedStorage.Shared.Config.UI)

export type Fader = {
	-- Fades everything to its built look over `duration` seconds.
	Show: (self: Fader, duration: number) -> (),
	-- Fades everything out over `duration` seconds.
	Hide: (self: Fader, duration: number) -> (),
	-- Hides everything immediately (stops any fade in progress).
	HideNow: (self: Fader) -> (),
}

type Tracked = {
	instance: Instance,
	-- Property -> transparency when fully shown. Only properties that are visible
	-- at all (below 1) are tracked.
	shown: { [string]: number },
	-- Same properties, all at 1.
	hidden: { [string]: number },
}

-- Reads the transparencies that make `instance` visible, as tween goals.
local function readShown(instance: Instance): { [string]: number }
	local values: { [string]: number } = {}
	local function track(property: string, value: number)
		if value < 1 then
			values[property] = value
		end
	end
	if instance:IsA("GuiObject") then
		track("BackgroundTransparency", instance.BackgroundTransparency)
	end
	if instance:IsA("TextLabel") then
		track("TextTransparency", instance.TextTransparency)
		track("TextStrokeTransparency", instance.TextStrokeTransparency)
	elseif instance:IsA("ImageLabel") then
		track("ImageTransparency", instance.ImageTransparency)
	elseif instance:IsA("UIStroke") then
		track("Transparency", instance.Transparency)
	end
	return values
end

-- Typed counterpart of readShown: sets every one of those properties to 1.
local function hideImmediately(instance: Instance)
	if instance:IsA("GuiObject") then
		instance.BackgroundTransparency = 1
	end
	if instance:IsA("TextLabel") then
		instance.TextTransparency = 1
		instance.TextStrokeTransparency = 1
	elseif instance:IsA("ImageLabel") then
		instance.ImageTransparency = 1
	elseif instance:IsA("UIStroke") then
		instance.Transparency = 1
	end
end

local Fader = {}

function Fader.new(root: Instance): Fader
	local tracked: { Tracked } = {}
	local candidates = root:GetDescendants()
	table.insert(candidates, root)
	for _, instance in candidates do
		local shown = readShown(instance)
		if next(shown) ~= nil then
			local hidden: { [string]: number } = {}
			for property in shown do
				hidden[property] = 1
			end
			table.insert(tracked, { instance = instance, shown = shown, hidden = hidden })
		end
	end

	local playing: { Tween } = {}

	local function stop()
		for _, tween in playing do
			tween:Cancel()
		end
		table.clear(playing)
	end

	local function fadeTo(visible: boolean, duration: number)
		stop()
		local info = TweenInfo.new(duration, UIConfig.FadeEasingStyle, Enum.EasingDirection.Out)
		for _, entry in tracked do
			local tween = TweenService:Create(entry.instance, info, if visible then entry.shown else entry.hidden)
			table.insert(playing, tween)
			tween:Play()
		end
	end

	local fader: Fader = {
		Show = function(_self: Fader, duration: number)
			fadeTo(true, duration)
		end,
		Hide = function(_self: Fader, duration: number)
			fadeTo(false, duration)
		end,
		HideNow = function(_self: Fader)
			stop()
			for _, entry in tracked do
				hideImmediately(entry.instance)
			end
		end,
	}
	fader:HideNow()
	return fader
end

return Fader
