--!strict
--[[
	HitNumbers: floating damage numbers for the attacker (Remotes.HitConfirmed).

	Each number pops in a little large, rises Config.VFX.HitNumbers.Rise studs
	and fades out, drawn on top of the world (a BillboardGui on an attachment in
	Terrain, so it needs no part and removes itself). Bigger hits get bigger
	numbers; a small random sideways offset keeps quick hits from stacking
	exactly on top of each other.

	API:
	  HitNumbers.show(position, amount)
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Theme = require(Shared.Config.Theme)
local VFXConfig = require(Shared.Config.VFX)

local Create = require(script.Parent.Parent.UI.Create)

local config = VFXConfig.HitNumbers
local random = Random.new()

local HitNumbers = {}

function HitNumbers.show(position: Vector3, amount: number)
	-- Damage arrives as a sum of fractional ticks; whole numbers read better.
	local shown = math.max(1, math.round(amount))
	local strength = math.clamp(amount / config.AmountForMax, 0, 1)
	local textSize = math.floor(config.TextSizeMin + (config.TextSizeMax - config.TextSizeMin) * strength + 0.5)

	local anchor = Instance.new("Attachment")
	anchor.Name = "HitNumber"
	anchor.WorldPosition = position + Vector3.new(random:NextNumber(-1, 1), 0, random:NextNumber(-1, 1)) * config.Jitter

	local gui = Instance.new("BillboardGui")
	gui.Name = "HitNumber"
	gui.Adornee = anchor
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = config.MaxDistance
	gui.Size = UDim2.fromOffset(config.TextSizeMax * 4, config.TextSizeMax * 2)
	gui.ResetOnSpawn = false

	local label = Create.label("Amount", tostring(shown), Theme.FontBold, textSize, config.Color)
	label.Size = UDim2.fromScale(1, 1)
	local stroke = Create.textStroke(label, config.StrokeColor, config.StrokeThickness, 0)
	local pop = Instance.new("UIScale")
	pop.Scale = config.PopScale
	pop.Parent = label
	label.Parent = gui
	gui.Parent = anchor
	anchor.Parent = Workspace.Terrain

	TweenService:Create(pop, TweenInfo.new(config.PopTime, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	TweenService:Create(
		gui,
		TweenInfo.new(config.Lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ StudsOffsetWorldSpace = Vector3.new(0, config.Rise, 0) }
	):Play()
	local fade = TweenInfo.new(config.FadeTime)
	task.delay(math.max(config.Lifetime - config.FadeTime, 0), function()
		if anchor.Parent == nil then
			return
		end
		TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
	end)
	Debris:AddItem(anchor, config.Lifetime + 0.1)
end

return HitNumbers
