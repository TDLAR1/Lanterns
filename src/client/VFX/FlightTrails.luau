--!strict
--[[
	FlightTrails: the glow of a flying character: tapering light trails from its
	hands and feet, a soft light around it, and sparkles shed behind it while it
	boosts (Config.VFX.Flight). Everything is created on this client only, under
	the character's own parts, so it goes away with the character.

	API:
	  FlightTrails.new(character): FlightTrails?   (nil without a root part)
	  trails:SetBoosting(boosting)
	  trails:Destroy()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VFXConfig = require(ReplicatedStorage.Shared.Config.VFX)

local Parts = require(script.Parent.Parts)

export type FlightTrails = {
	SetBoosting: (self: FlightTrails, boosting: boolean) -> (),
	Destroy: (self: FlightTrails) -> (),
}

type Ribbon = {
	trail: Trail,
	a0: Attachment,
	a1: Attachment,
	-- Where the ribbon is centred on its limb (the limb's far end).
	centre: Vector3,
}

local config = VFXConfig.Flight

-- Every standard Humanoid rig (R6, R15, custom StarterCharacter) names its root this.
local ROOT_PART_NAME = "HumanoidRootPart"
-- Limbs that carry trails: R15 hands and feet, else R6 arms and legs.
local LIMB_SETS = {
	{ "LeftHand", "RightHand", "LeftFoot", "RightFoot" },
	{ "Left Arm", "Right Arm", "Left Leg", "Right Leg" },
}

local function findLimbs(character: Model): { BasePart }
	for _, names in LIMB_SETS do
		local limbs: { BasePart } = {}
		for _, name in names do
			local limb = character:FindFirstChild(name)
			if limb ~= nil and limb:IsA("BasePart") then
				table.insert(limbs, limb)
			end
		end
		if #limbs > 0 then
			return limbs
		end
	end
	return {}
end

local function setRibbonWidth(ribbon: Ribbon, width: number)
	ribbon.a0.Position = ribbon.centre - Vector3.xAxis * (width / 2)
	ribbon.a1.Position = ribbon.centre + Vector3.xAxis * (width / 2)
end

local function newRibbon(limb: BasePart): Ribbon
	-- The bottom of a hanging hand / foot / limb is its far end.
	local centre = Vector3.new(0, -limb.Size.Y / 2, 0)
	local a0 = Instance.new("Attachment")
	a0.Name = "FlightTrail0"
	a0.Parent = limb
	local a1 = Instance.new("Attachment")
	a1.Name = "FlightTrail1"
	a1.Parent = limb

	local trail = Instance.new("Trail")
	trail.Name = "FlightTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.MinLength = 0.05
	trail.Color = ColorSequence.new(VFXConfig.CoreColor, VFXConfig.Color)
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.15),
	})
	trail.Parent = limb

	local ribbon: Ribbon = { trail = trail, a0 = a0, a1 = a1, centre = centre }
	setRibbonWidth(ribbon, config.TrailWidth)
	return ribbon
end

local FlightTrails = {}

function FlightTrails.new(character: Model): FlightTrails?
	local root = character:FindFirstChild(ROOT_PART_NAME)
	if root == nil or not root:IsA("BasePart") then
		return nil
	end

	local ribbons: { Ribbon } = {}
	for _, limb in findLimbs(character) do
		table.insert(ribbons, newRibbon(limb))
	end
	local glow = Parts.light(root, config.LightRange, config.LightBrightness)
	glow.Name = "FlightGlow"
	local sparks = Parts.emitter(root, {
		Count = 0,
		Speed = config.BoostSparkSpeed,
		Lifetime = config.BoostSparkLifetime,
		Size = config.BoostSparkSize,
	})
	sparks.Name = "BoostSparks"

	local boosting: boolean? = nil
	local trails = {} :: FlightTrails

	function trails.SetBoosting(_self: FlightTrails, on: boolean)
		if on == boosting then
			return
		end
		boosting = on
		local lifetime = if on then config.BoostTrailLifetime else config.TrailLifetime
		local width = if on then config.BoostTrailWidth else config.TrailWidth
		local transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, if on then config.BoostTrailTransparency else config.TrailTransparency),
			NumberSequenceKeypoint.new(1, 1),
		})
		for _, ribbon in ribbons do
			ribbon.trail.Lifetime = lifetime
			ribbon.trail.Transparency = transparency
			setRibbonWidth(ribbon, width)
		end
		glow.Range = if on then config.BoostLightRange else config.LightRange
		glow.Brightness = if on then config.BoostLightBrightness else config.LightBrightness
		sparks.Rate = if on then config.BoostSparkRate else 0
	end

	function trails.Destroy(_self: FlightTrails)
		for _, ribbon in ribbons do
			ribbon.trail:Destroy()
			ribbon.a0:Destroy()
			ribbon.a1:Destroy()
		end
		table.clear(ribbons)
		glow:Destroy()
		sparks:Destroy()
	end

	trails:SetBoosting(false)
	return trails
end

return FlightTrails
