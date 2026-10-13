--!strict
--[[
	BeamRenderer: draws one energy beam, given its two ends every frame.

	The look (Config.VFX.Beam, Config.Powers.Beam.Width):
	  * a hot neon core cylinder, Beam.Width thick, that flickers;
	  * two soft glow layers and a band of crawling sparkle energy around it
	    (flat Beams that always face the camera);
	  * a glowing ball, light and sparks at the ring (the muzzle);
	  * where the beam hits something: a glow, a light and sparks spraying back
	    toward the caster.

	Used for the local player's beam and for every other player's.

	API:
	  BeamRenderer.new(name): BeamRenderer
	  renderer:Update(from, to, hit)   (hit: the beam stopped at something)
	  renderer:SetVisible(visible)
	  renderer:GetMuzzle(): BasePart   (sounds can hang on it)
	  renderer:Destroy()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local PowersConfig = require(Shared.Config.Powers)
local VFXConfig = require(Shared.Config.VFX)

local Parts = require(script.Parent.Parts)

export type BeamRenderer = {
	Update: (self: BeamRenderer, from: Vector3, to: Vector3, hit: boolean) -> (),
	SetVisible: (self: BeamRenderer, visible: boolean) -> (),
	GetMuzzle: (self: BeamRenderer) -> BasePart,
	Destroy: (self: BeamRenderer) -> (),
}

local config = VFXConfig.Beam
local WIDTH = PowersConfig.Beam.Width

-- Shorter than this (studs), the beam has no direction to draw.
local MIN_LENGTH = 0.05
-- Turns a cylinder (whose axis is X) to run along a CFrame's look direction.
local ALONG_LOOK = CFrame.Angles(0, math.rad(90), 0)
-- Turns a part so its top (+Y, the particle emission direction) points along
-- a CFrame's look direction.
local TOP_ALONG_LOOK = CFrame.Angles(-math.rad(90), 0, 0)

local function newBeam(name: string, a0: Attachment, a1: Attachment, width: number, transparency: number): Beam
	local beam = Instance.new("Beam")
	beam.Name = name
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.FaceCamera = true
	beam.Segments = 1
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Color = ColorSequence.new(VFXConfig.Color)
	beam.Transparency = NumberSequence.new(transparency)
	beam.Width0 = width
	beam.Width1 = width
	beam.Parent = a0.Parent
	return beam
end

local BeamRenderer = {}

function BeamRenderer.new(name: string): BeamRenderer
	local container = Instance.new("Folder")
	container.Name = name

	local core = Parts.neon(
		"Core",
		Vector3.new(1, WIDTH, WIDTH),
		CFrame.identity,
		VFXConfig.CoreColor,
		config.CoreTransparency,
		Enum.PartType.Cylinder
	)
	local startAttachment = Instance.new("Attachment")
	startAttachment.Name = "Start"
	startAttachment.Parent = core
	local endAttachment = Instance.new("Attachment")
	endAttachment.Name = "End"
	endAttachment.Parent = core
	core.Parent = container

	local innerGlow = newBeam(
		"InnerGlow",
		startAttachment,
		endAttachment,
		WIDTH * config.InnerGlowScale,
		config.InnerGlowTransparency
	)
	local outerGlow = newBeam(
		"OuterGlow",
		startAttachment,
		endAttachment,
		WIDTH * config.OuterGlowScale,
		config.OuterGlowTransparency
	)
	local energy =
		newBeam("Energy", startAttachment, endAttachment, WIDTH * config.EnergyScale, config.EnergyTransparency)
	energy.Texture = VFXConfig.Textures.Sparkle
	energy.TextureMode = Enum.TextureMode.Wrap
	energy.TextureLength = config.EnergyTextureLength
	energy.TextureSpeed = config.EnergyTextureSpeed

	local muzzleConfig = config.Muzzle
	local muzzle = Parts.neon(
		"Muzzle",
		Vector3.one * muzzleConfig.Size,
		CFrame.identity,
		VFXConfig.CoreColor,
		muzzleConfig.Transparency,
		Enum.PartType.Ball
	)
	Parts.light(muzzle, muzzleConfig.LightRange, muzzleConfig.LightBrightness)
	local muzzleSparks = Parts.emitter(muzzle, {
		Count = 0,
		Speed = muzzleConfig.SparkSpeed,
		Lifetime = muzzleConfig.SparkLifetime,
		Size = muzzleConfig.SparkSize,
	})
	muzzleSparks.Rate = muzzleConfig.SparkRate
	muzzle.Parent = container

	local impactConfig = config.Impact
	local impactGlow = Parts.neon(
		"ImpactGlow",
		Vector3.one * impactConfig.GlowSize,
		CFrame.identity,
		VFXConfig.CoreColor,
		impactConfig.GlowTransparency,
		Enum.PartType.Ball
	)
	local impactLight = Parts.light(impactGlow, impactConfig.LightRange, impactConfig.LightBrightness)
	local impactSparks = Parts.emitter(impactGlow, {
		Count = 0,
		Speed = impactConfig.SparkSpeed,
		Lifetime = impactConfig.SparkLifetime,
		Size = impactConfig.SparkSize,
		Spread = impactConfig.SparkSpread,
		Acceleration = Vector3.new(0, -impactConfig.SparkGravity, 0),
	})
	impactSparks.Rate = impactConfig.SparkRate
	impactGlow.Parent = container

	local visible = false
	local impactShown = true
	-- Each beam flickers out of step with the others.
	local phase = math.random() * 100

	local renderer = {} :: BeamRenderer

	local function showImpact(shown: boolean)
		if shown == impactShown then
			return
		end
		impactShown = shown
		impactGlow.Transparency = if shown then impactConfig.GlowTransparency else 1
		impactLight.Enabled = shown
		impactSparks.Enabled = shown
	end

	function renderer.Update(_self: BeamRenderer, from: Vector3, to: Vector3, hit: boolean)
		local offset = to - from
		local length = offset.Magnitude
		if length < MIN_LENGTH then
			return
		end
		local t = os.clock() + phase
		local speed = config.FlickerSpeed
		-- Two out-of-step waves read as a living flicker rather than a pulse.
		local wave = 0.6 * math.sin(t * speed) + 0.4 * math.sin(t * speed * 2.3 + 1.7)
		local flicker = 1 + config.FlickerAmount * wave
		local width = WIDTH * flicker

		local look = CFrame.lookAt(from + offset / 2, to)
		core.Size = Vector3.new(length, width, width)
		core.CFrame = look * ALONG_LOOK
		startAttachment.Position = Vector3.new(-length / 2, 0, 0)
		endAttachment.Position = Vector3.new(length / 2, 0, 0)

		local glowWidth = WIDTH * config.InnerGlowScale * flicker
		innerGlow.Width0 = glowWidth
		innerGlow.Width1 = glowWidth
		local outerWidth = WIDTH * config.OuterGlowScale * (1 + config.FlickerAmount * 0.5 * wave)
		outerGlow.Width0 = outerWidth
		outerGlow.Width1 = outerWidth

		muzzle.Size = Vector3.one * (muzzleConfig.Size * flicker)
		muzzle.CFrame = CFrame.new(from)

		showImpact(hit)
		if hit then
			impactGlow.Size = Vector3.one * (impactConfig.GlowSize * flicker)
			-- Sparks spray back out of the surface, toward the caster.
			impactGlow.CFrame = CFrame.lookAt(to, from) * TOP_ALONG_LOOK
		end
	end

	function renderer.SetVisible(_self: BeamRenderer, shown: boolean)
		if shown == visible then
			return
		end
		visible = shown
		container.Parent = if shown then Parts.folder() else nil
	end

	function renderer.GetMuzzle(_self: BeamRenderer): BasePart
		return muzzle
	end

	function renderer.Destroy(_self: BeamRenderer)
		visible = false
		container:Destroy()
	end

	showImpact(false)
	return renderer
end

return BeamRenderer
