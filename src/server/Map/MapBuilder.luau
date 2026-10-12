--!strict
--[[
	MapBuilder: builds the Rushville blockout map (Milestone 0) from MapLayout.

	Workspace/<Config.World.MapFolderName>
	  Rushville/        Ground, Roads/, one folder per town district
	  OuterRing/        farmland out to the play-area boundary
	  Zones/            invisible DistrictZone volumes
	  Spawns/           the main SpawnLocation + one DistrictSpawn per district
	  MissionMarkers    (Model, streams persistently) MissionMarker discs

	Every spec element is a Model tagged Blockout whose PrimaryPart is an
	invisible "Footprint" box matching the build table, so it can later be
	swapped for a real model aligned to that footprint.

	The build is deterministic and needs no running game, so it also works from
	Studio's command bar in edit mode:
		require(game.ServerScriptService.Server.Map.MapBuilder).Build(workspace)
		require(game.ServerScriptService.Server.Map.MapBuilder).Build(workspace, { Replace = true })
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local World = require(ReplicatedStorage.Shared.Config.World)

local Downtown = require(script.Parent.Downtown)
local Fields = require(script.Parent.Fields)
local Gameplay = require(script.Parent.Gameplay)
local Interiors = require(script.Parent.Interiors)
local MapLayout = require(script.Parent.MapLayout)
local OuterRing = require(script.Parent.OuterRing)
local Props = require(script.Parent.Props)
local Roads = require(script.Parent.Roads)
local Rural = require(script.Parent.Rural)
local Shapes = require(script.Parent.Shapes)

export type BuildOptions = {
	-- Destroy an existing Map folder and build a fresh one.
	Replace: boolean?,
}

type Builder = (model: Model, element: MapLayout.Element) -> ()

-- Which function builds each kind of element's visible geometry.
local BUILDERS: { [MapLayout.Kind]: Builder } = {
	Ground = Roads.Ground,
	MainStreet = Roads.MainStreet,
	CenterStreet = Roads.CenterStreet,
	CountyRoad = Roads.CountyRoad,
	ElmAve = Roads.ElmAve,
	OakSt = Roads.OakSt,
	Railroad = Roads.Railroad,
	Storefront = Downtown.Storefront,
	Diner = Interiors.Diner,
	SheriffOffice = Interiors.SheriffOffice,
	Motel = Downtown.Motel,
	PostOffice = Downtown.PostOffice,
	Church = Downtown.Church,
	GasStation = Downtown.GasStation,
	WaterTower = Rural.WaterTower,
	Farmhouse = Rural.Farmhouse,
	Barn = Rural.Barn,
	Silo = Rural.Silo,
	GrainElevator = Interiors.GrainElevator,
	House = Rural.House,
	CallowayHome = Rural.CallowayHome,
	Cornfield = Fields.Cornfield,
	WheatField = Fields.WheatField,
	CrimeScene = Fields.CrimeScene,
}

local MapBuilder = {}

local function buildTown(map: Folder)
	local rushville = Shapes.Folder(map, "Rushville")
	local folders: { [string]: Instance } = { Rushville = rushville }
	local isDistrict: { [string]: boolean } = {}
	folders.Roads = Shapes.Folder(rushville, "Roads")
	for _, district in World.Districts do
		if district.Id ~= "OuterRing" then
			folders[district.Id] = Shapes.Folder(rushville, district.Id)
			isDistrict[district.Id] = true
		end
	end

	for _, element in MapLayout.Elements do
		local folder: Instance? = folders[element.Folder]
		assert(folder ~= nil, `MapLayout element "{element.Name}" has unknown folder "{element.Folder}"`)
		local center = Vector3.new(element.X, element.CenterY or element.Height / 2, element.Z)
		local size = Vector3.new(element.SizeX, element.Height, element.SizeZ)
		local districtId = if isDistrict[element.Folder] then element.Folder else nil
		local model = Shapes.Element(folder, element.Name, center, size, districtId)
		BUILDERS[element.Kind](model, element)
	end

	-- Extras that are not rows of the build table.
	Roads.BuildExtras(folders.Roads, folders.Downtown)
	Downtown.BuildChurchyard(folders.Downtown)
	Downtown.BuildCars(folders)
	Rural.BuildFarmyard(folders.Farmstead)
	Rural.BuildTrees(folders)
	Interiors.BuildElevatorFence(folders.RailYard)

	local welcome = MapLayout.WelcomeSign
	Props.WelcomeSign(folders.RailYard, welcome.X, welcome.Z, welcome.Width, welcome.Height)
	local siding = MapLayout.Siding
	Props.Siding(folders.RailYard, siding.X0, siding.X1, siding.Z, siding.Boxcars)

	local poles = MapLayout.UtilityPoles
	local northPoles = Props.Extra(folders.Farmstead, "Utility Poles", "Farmstead")
	Props.PoleLine(northPoles, poles.North.X, poles.North.Z0, poles.North.Z1, poles.North.Spacing)
	local southPoles = Props.Extra(folders.RailYard, "Utility Poles", "RailYard")
	Props.PoleLine(southPoles, poles.South.X, poles.South.Z0, poles.South.Z1, poles.South.Spacing)
end

--[[
	Builds the map into `parent` and returns its folder. If `parent` already
	has a map folder it is returned untouched (with a warning) unless
	options.Replace is set, in which case it is destroyed and rebuilt.
]]
function MapBuilder.Build(parent: Instance, options: BuildOptions?): Folder
	local existing = parent:FindFirstChild(World.MapFolderName)
	if existing ~= nil then
		if options == nil or not options.Replace then
			assert(
				existing:IsA("Folder"),
				`{existing:GetFullName()} exists but is a {existing.ClassName}, not a Folder`
			)
			warn(`[MapBuilder] {existing:GetFullName()} already exists; pass \{ Replace = true } to rebuild it`)
			return existing
		end
		existing:Destroy()
	end

	-- Everything is assembled unparented and parented to `parent` last, so the
	-- whole map replicates in one burst instead of part by part.
	local map = Instance.new("Folder")
	map.Name = World.MapFolderName

	buildTown(map)
	OuterRing.Build(Shapes.Folder(map, "OuterRing"))
	Gameplay.BuildZones(Shapes.Folder(map, "Zones"))
	Gameplay.BuildSpawns(Shapes.Folder(map, "Spawns"))

	local markers = Instance.new("Model")
	markers.Name = "MissionMarkers"
	-- Markers must exist on every client regardless of distance (mission UI points at them).
	markers.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	markers.Parent = map
	Gameplay.BuildMissionMarkers(markers)

	map.Parent = parent
	return map
end

return MapBuilder
