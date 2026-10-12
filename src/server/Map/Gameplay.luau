--!strict
--[[
	Gameplay: the tagged objects gameplay code finds the map through (by tag
	and attribute, never by path):
	  * DistrictZone volumes under Map/Zones,
	  * the single main SpawnLocation and one DistrictSpawn per district under
	    Map/Spawns,
	  * MissionMarker discs under Map/MissionMarkers.
	The ring-battery spot is part of the Sheriff's Office (Interiors.luau).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig = require(ReplicatedStorage.Shared.Config.Map)
local TagsModule = require(ReplicatedStorage.Shared.Util.Tags)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local World = require(ReplicatedStorage.Shared.Config.World)

local MapLayout = require(script.Parent.MapLayout)
local Shapes = require(script.Parent.Shapes)

type Style = Shapes.Style

local Tags = TagsModule.Tags
local Attributes = TagsModule.Attributes

-- Invisible, non-interactive helper volume (zones, respawn points).
local HIDDEN: Style = {
	Material = Enum.Material.SmoothPlastic,
	Color = Color3.fromRGB(255, 255, 255),
	Transparency = 1,
	CanCollide = false,
	CastShadow = false,
}

local Gameplay = {
	-- Name of the BillboardGui under each marker that shows its MarkerId
	-- (WorldService hides it on live servers).
	DevLabelName = "DevLabel",
}

local function zonePart(
	folder: Instance,
	name: string,
	districtId: string,
	priority: number,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	y0: number,
	y1: number
)
	local part = Shapes.Part(
		folder,
		name,
		CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
		Vector3.new(x1 - x0, y1 - y0, z1 - z0),
		HIDDEN
	)
	part:AddTag(Tags.DistrictZone)
	part:SetAttribute(Attributes.DistrictId, districtId)
	part:SetAttribute(Attributes.Priority, priority)
end

function Gameplay.BuildZones(folder: Instance)
	local settings = MapLayout.ZoneSettings
	local boundary = World.Boundary
	-- Zones reach as far as anyone can legally be: the hard edge plus the
	-- server's lag tolerance, and above the flight ceiling by the same margin.
	local y0 = settings.Bottom
	local y1 = boundary.Ceiling + boundary.ServerTolerance

	local totals: { [string]: number } = {}
	for _, zone in MapLayout.Zones do
		totals[zone.DistrictId] = (totals[zone.DistrictId] or 0) + 1
	end
	local seen: { [string]: number } = {}
	for _, zone in MapLayout.Zones do
		local id = zone.DistrictId
		seen[id] = (seen[id] or 0) + 1
		local name = if totals[id] > 1 then `{id} {seen[id]}` else id
		zonePart(folder, name, id, settings.TownPriority, zone.X0, zone.X1, zone.Z0, zone.Z1, y0, y1)
	end

	-- OuterRing covers the whole world at low priority, as a grid of tiles
	-- (a part may be at most 2048 studs on any axis).
	local halfX = boundary.HalfSizeX + boundary.ServerTolerance
	local halfZ = boundary.HalfSizeZ + boundary.ServerTolerance
	local tiles = settings.OuterTiles
	local stepX, stepZ = halfX * 2 / tiles, halfZ * 2 / tiles
	local index = 0
	for i = 0, tiles - 1 do
		for j = 0, tiles - 1 do
			index += 1
			local x0, z0 = -halfX + stepX * i, -halfZ + stepZ * j
			zonePart(
				folder,
				`OuterRing {index}`,
				"OuterRing",
				settings.OuterPriority,
				x0,
				x0 + stepX,
				z0,
				z0 + stepZ,
				y0,
				y1
			)
		end
	end
end

function Gameplay.BuildSpawns(folder: Instance)
	local main = MapLayout.MainSpawn
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "MainSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(main.Size, 1, main.Size)
	-- Unrotated: new players face north, up Main St toward town.
	spawn.CFrame = CFrame.new(main.X, 0.5, main.Z)
	spawn.Material = Enum.Material.Concrete
	spawn.Color = Color3.fromRGB(150, 160, 150)
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
	spawn.Neutral = true
	spawn.Enabled = true
	spawn.AllowTeamChangeOnTouch = false
	spawn.Duration = MapConfig.MainSpawn.Duration
	spawn:AddTag(Tags.MainSpawn)
	spawn.Parent = folder

	local height = MapConfig.DistrictSpawnHeight
	for _, point in MapLayout.DistrictSpawns do
		-- Respawned characters take this part's orientation, so it looks at something worth seeing.
		local cframe =
			CFrame.lookAt(Vector3.new(point.X, height, point.Z), Vector3.new(point.LookX, height, point.LookZ))
		local part = Shapes.Part(folder, `{point.DistrictId}Spawn`, cframe, Vector3.new(2, 1, 2), HIDDEN)
		part:AddTag(Tags.DistrictSpawn)
		part:SetAttribute(Attributes.DistrictId, point.DistrictId)
	end
end

function Gameplay.BuildMissionMarkers(container: Instance)
	local config = MapConfig.MissionMarker
	local disc: Style = {
		Material = Enum.Material.Neon,
		Color = config.Color,
		Transparency = config.Transparency,
		CanCollide = false,
		CastShadow = false,
	}
	local beam: Style = {
		Material = Enum.Material.Neon,
		Color = config.Color,
		Transparency = config.BeamTransparency,
		CanCollide = false,
		CastShadow = false,
	}
	for _, marker in MapLayout.MissionMarkers do
		-- Lifted a hair off the surface so the disc never shares its plane.
		local y = marker.Surface + 0.08 + config.Thickness / 2
		local part = Shapes.Cylinder(
			container,
			marker.Id,
			CFrame.new(marker.X, y, marker.Z),
			config.Thickness,
			config.Diameter,
			disc
		)
		-- Mission code may detect players stepping on a marker.
		part.CanTouch = true
		part:AddTag(Tags.MissionMarker)
		part:SetAttribute(Attributes.MarkerId, marker.Id)
		part:SetAttribute(Attributes.DistrictId, marker.DistrictId)

		Shapes.Cylinder(
			part,
			"Beam",
			CFrame.new(marker.X, marker.Surface + config.BeamHeight / 2, marker.Z),
			config.BeamHeight,
			config.BeamDiameter,
			beam
		)

		if config.ShowDevLabels then
			local billboard = Instance.new("BillboardGui")
			billboard.Name = Gameplay.DevLabelName
			billboard.Size = UDim2.fromOffset(220, 32)
			billboard.StudsOffsetWorldSpace = Vector3.new(0, config.DevLabelHeight, 0)
			billboard.MaxDistance = config.DevLabelMaxDistance
			billboard.AlwaysOnTop = true
			billboard.LightInfluence = 0
			billboard.Parent = part
			local label = Instance.new("TextLabel")
			label.Name = "MarkerId"
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.TextScaled = true
			label.FontFace = Theme.FontBold
			label.TextColor3 = config.Color
			label.TextStrokeTransparency = 0.3
			label.Text = marker.Id
			label.Parent = billboard
		end
	end
end

return Gameplay
