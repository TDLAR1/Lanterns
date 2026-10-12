--[[
	Map contract: builds the blockout with MapBuilder and checks it against the
	map spec (Rushville_Map_Layout.pdf build table) plus the gameplay hooks
	(zones, spawns, mission markers, battery spot) the services rely on.

	Every spec element is a Model whose PrimaryPart is an invisible "Footprint"
	part exactly matching the spec box, so positions can be checked here and
	real models can later be aligned to it in Studio.
]]

-- name, folder, centre X, centre Z, size X, size Z, height, [centre Y override]
-- Farmhouse, Barn and silos are shifted 35 studs west of the PDF so the silo
-- row no longer runs into the General Store (agreed fix).
local EXPECTED = {
	{ "Ground", "Rushville", 0, 0, 1000, 700, 1, -0.5 },

	{ "Main St", "Roads", 0, 0, 40, 700, 0.2 },
	{ "Center Street", "Roads", 0, 0, 560, 40, 0.2 },
	{ "County Road", "Roads", -260, -98, 480, 24, 0.2 },
	{ "Elm Ave", "Roads", 380, 0, 200, 24, 0.2 },
	{ "Oak St", "Roads", 382, 45, 24, 330, 0.2 },
	{ "Railroad", "Roads", 0, 256, 1000, 12, 0.5 },

	{ "General Store", "Downtown", -165, -54, 70, 52, 18 },
	{ "Diner", "Downtown", -77.5, -54, 85, 52, 14 },
	{ "Sheriff's Office", "Downtown", 90, -58, 110, 60, 22 },
	{ "Hardware", "Downtown", 190, -54, 70, 52, 16 },
	{ "Bar", "Downtown", -162.5, 53, 75, 50, 14 },
	{ "Motel", "Downtown", -72.5, 63, 85, 70, 18 },
	{ "Post Office", "Downtown", 70, 53, 70, 50, 16 },
	{ "Church", "Downtown", 150, 65.5, 70, 75, 28 },
	{ "Gas Station", "Downtown", 65, 145, 70, 50, 12 },

	{ "Water Tower", "NorthFields", 200, -139, 40, 40, 70 },
	{ "Wheat Field NE", "NorthFields", 270, -250, 420, 160, 3 },

	{ "Farmhouse", "Farmstead", -405, -47.5, 60, 45, 20 },
	{ "Barn", "Farmstead", -320, -50.5, 70, 55, 26 },
	{ "Silo A", "Farmstead", -270, -50, 22, 22, 45 },
	{ "Silo B", "Farmstead", -245, -50, 22, 22, 45 },
	{ "Silo C", "Farmstead", -220, -50, 22, 22, 45 },
	{ "Cornfield NW", "Farmstead", -270, -230, 420, 200, 8 },

	{ "Calloway Home", "Residential", 429, 96, 50, 36, 20 },
	{ "House 1", "Residential", 308, -37, 30, 24, 16 },
	{ "House 2", "Residential", 346, -37, 30, 24, 16 },
	{ "House 3", "Residential", 420, -37, 30, 24, 16 },
	{ "House 4", "Residential", 457, -37, 30, 24, 16 },
	{ "House 5", "Residential", 308, 34, 30, 24, 16 },
	{ "House 6", "Residential", 346, 34, 30, 24, 16 },
	{ "House 7", "Residential", 420, 34, 30, 24, 16 },
	{ "House 8", "Residential", 457, 34, 30, 24, 16 },
	{ "House 9", "Residential", 308, 105, 30, 24, 16 },
	{ "House 10", "Residential", 346, 105, 30, 24, 16 },

	{ "South Wheat Field", "SouthFields", -350, 140, 260, 180, 3 },
	{ "Crime Scene", "SouthFields", -320, 140, 40, 40, 1 },

	{ "Grain Elevator", "RailYard", 125, 217.5, 50, 45, 60 },
	{ "Corn Strip SW", "RailYard", -260, 310, 440, 60, 8 },
	{ "Corn Strip SE", "RailYard", 340, 310, 280, 60, 8 },
}

local FIELDS = {
	["Cornfield NW"] = true,
	["Wheat Field NE"] = true,
	["South Wheat Field"] = true,
	["Corn Strip SW"] = true,
	["Corn Strip SE"] = true,
}

-- Buildings players can walk into in Milestone 0.
local INTERIORS = { "Sheriff's Office", "Diner", "Grain Elevator" }

-- Buildings that must read as solid blocks at ground level.
local SOLID = {
	"General Store",
	"Hardware",
	"Bar",
	"Post Office",
	"Church",
	"Farmhouse",
	"Barn",
	"Silo A",
	"Silo B",
	"Silo C",
	"House 1",
	"House 5",
	"House 9",
}

local MARKER_IDS = {
	"Tutorial_Start",
	"Story_CaseHQ",
	"Story_Diner",
	"Story_CrimeScene",
	"Story_PartnerHome",
	"Story_GrainElevator",
	"Side_Farmstead",
	"Side_WaterTower",
	"Side_Church",
	"Side_GasStation",
	"Side_RailYard",
	"Side_Highway",
}

local MAX_PARTS = 9000
local EPS = 0.01

return function(t, ctx)
	local roblox = ctx.roblox
	local Vector3 = roblox.Vector3

	local MapBuilder = ctx.require(ctx.server.Map.MapBuilder)
	local World = ctx.require(ctx.shared.Config.World)
	local TagsModule = ctx.require(ctx.shared.Util.Tags)
	local Zones = ctx.require(ctx.shared.Util.Zones)
	local Tags, Attributes = TagsModule.Tags, TagsModule.Attributes

	local workspace = ctx.place:GetService("Workspace")
	local existing = workspace:FindFirstChild(World.MapFolderName)
	if existing then
		existing:Destroy()
	end

	local startedAt = os.clock()
	local map = MapBuilder.Build(workspace)
	t.log(string.format("built in %.0f ms", (os.clock() - startedAt) * 1000))

	-- Helpers ---------------------------------------------------------------

	local parts = {}
	local tagged = {}
	for _, descendant in map:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
		for _, tag in descendant:GetTags() do
			tagged[tag] = tagged[tag] or {}
			table.insert(tagged[tag], descendant)
		end
	end

	local function taggedWith(tag: string)
		return tagged[tag] or {}
	end

	local function inside(part, point): boolean
		local localPoint = part.CFrame:PointToObjectSpace(point)
		local half = part.Size / 2
		return math.abs(localPoint.X) <= half.X + EPS
			and math.abs(localPoint.Y) <= half.Y + EPS
			and math.abs(localPoint.Z) <= half.Z + EPS
	end

	local function insideSolid(point): boolean
		for _, part in parts do
			if part.CanCollide and part.Name ~= "Footprint" and inside(part, point) then
				return true
			end
		end
		return false
	end

	local zones = {}
	for _, part in taggedWith(Tags.DistrictZone) do
		table.insert(zones, Zones.FromPart(part))
	end

	local function districtAt(point): string?
		local zone = Zones.Resolve(zones, point)
		return zone and zone.DistrictId
	end

	local rushville = map:FindFirstChild("Rushville")

	local function findModel(name: string, folder: string)
		if not rushville then
			return nil
		end
		local parent = if folder == "Rushville" then rushville else rushville:FindFirstChild(folder)
		return parent and parent:FindFirstChild(name)
	end

	local footprints = {}

	-- Tests ------------------------------------------------------------------

	t.test("map folder layout", function()
		t.expect(map.Name == World.MapFolderName and map.Parent == workspace, "Map folder in Workspace")
		t.expect(rushville ~= nil, "Map/Rushville")
		for _, name in { "OuterRing", "Zones", "Spawns", "MissionMarkers" } do
			t.expect(map:FindFirstChild(name) ~= nil, `Map/{name}`)
		end
		for _, district in World.Districts do
			if district.Id ~= "OuterRing" then
				t.expect(rushville:FindFirstChild(district.Id) ~= nil, `Map/Rushville/{district.Id}`)
			end
		end
		t.expect(rushville:FindFirstChild("Roads") ~= nil, "Map/Rushville/Roads")
	end)

	t.test("Build is idempotent unless Replace is passed", function()
		t.expect(MapBuilder.Build(workspace) == map, "second Build returns the existing map")
	end)

	t.test("every spec element matches the build table", function()
		local problems = {}
		for _, row in EXPECTED do
			local name, folder, x, z, sx, sz, height, centerY = table.unpack(row)
			local model = findModel(name, folder)
			if not model then
				table.insert(problems, `missing {folder}/{name}`)
				continue
			end
			if not model:IsA("Model") then
				table.insert(problems, `{name} is a {model.ClassName}, expected Model`)
				continue
			end
			local footprint = model.PrimaryPart
			if not footprint or footprint.Name ~= "Footprint" then
				table.insert(problems, `{name} PrimaryPart must be its Footprint part`)
				continue
			end
			local expectedPosition = Vector3.new(x, centerY or height / 2, z)
			local expectedSize = Vector3.new(sx, height, sz)
			if (footprint.CFrame.Position - expectedPosition).Magnitude > EPS then
				table.insert(problems, `{name} centre {footprint.CFrame.Position} ~= {expectedPosition}`)
			end
			if (footprint.Size - expectedSize).Magnitude > EPS then
				table.insert(problems, `{name} size {footprint.Size} ~= {expectedSize}`)
			end
			if footprint.CFrame.LookVector:Dot(Vector3.new(0, 0, -1)) < 0.9999 then
				table.insert(problems, `{name} footprint must not be rotated`)
			end
			if footprint.Transparency < 1 or footprint.CanCollide or footprint.CanQuery or footprint.CanTouch then
				table.insert(problems, `{name} footprint must be invisible and non-interactive`)
			end
			if not model:HasTag(Tags.Blockout) or model:GetAttribute(Attributes.BlockoutOf) ~= name then
				table.insert(problems, `{name} needs the Blockout tag and BlockoutOf attribute`)
			end
			footprints[name] = { x = x, z = z, sx = sx, sz = sz, folder = folder }
		end
		t.expect(#problems == 0, table.concat(problems, "\n      "))
	end)

	t.test("nothing overlaps that should not (top-down)", function()
		local function kind(name: string, folder: string): string
			if folder == "Roads" then
				return "road"
			elseif FIELDS[name] then
				return "field"
			elseif name == "Ground" or name == "Crime Scene" then
				return "ignore"
			end
			return "building"
		end
		local entries = {}
		for name, f in footprints do
			local k = kind(name, f.folder)
			if k ~= "ignore" then
				table.insert(entries, { name = name, kind = k, f = f })
			end
		end
		local problems = {}
		for i = 1, #entries do
			for j = i + 1, #entries do
				local a, b = entries[i], entries[j]
				if not (a.kind == "road" and b.kind == "road") then
					local overlapX = math.min(a.f.x + a.f.sx / 2, b.f.x + b.f.sx / 2) - math.max(a.f.x - a.f.sx / 2, b.f.x - b.f.sx / 2)
					local overlapZ = math.min(a.f.z + a.f.sz / 2, b.f.z + b.f.sz / 2) - math.max(a.f.z - a.f.sz / 2, b.f.z - b.f.sz / 2)
					if overlapX > EPS and overlapZ > EPS then
						table.insert(problems, `{a.name} overlaps {b.name}`)
					end
				end
			end
		end
		local scene, wheat = footprints["Crime Scene"], footprints["South Wheat Field"]
		if scene and wheat then
			local fits = math.abs(scene.x - wheat.x) + scene.sx / 2 <= wheat.sx / 2
				and math.abs(scene.z - wheat.z) + scene.sz / 2 <= wheat.sz / 2
			if not fits then
				table.insert(problems, "Crime Scene must sit inside the South Wheat Field")
			end
		end
		t.expect(#problems == 0, table.concat(problems, "\n      "))
	end)

	t.test("every part is anchored and within Roblox size limits", function()
		local problems = {}
		for _, part in parts do
			if not part.Anchored then
				table.insert(problems, `{part:GetFullName()} is not anchored`)
			end
			if part.Size.X > 2048 or part.Size.Y > 2048 or part.Size.Z > 2048 then
				table.insert(problems, `{part:GetFullName()} is larger than 2048 studs`)
			end
			if #problems > 10 then
				break
			end
		end
		t.expect(#problems == 0, table.concat(problems, "\n      "))
		t.log(`{#parts} parts`)
		t.expect(#parts <= MAX_PARTS, `part budget: {#parts} > {MAX_PARTS}`)
	end)

	t.test("ground covers the whole play area", function()
		local half = World.Boundary.HalfSizeX - 10
		local halfZ = World.Boundary.HalfSizeZ - 10
		local gaps = {}
		for x = -half, half, 98 do
			for z = -halfZ, halfZ, 98 do
				if not insideSolid(Vector3.new(x, -0.05, z)) then
					table.insert(gaps, `({x}, {z})`)
				end
			end
		end
		t.expect(#gaps == 0, `no ground at {#gaps} sample points, e.g. {gaps[1]}`)
	end)

	t.test("zone volumes are invisible and cover every district", function()
		t.expect(#zones > 0, "zones exist")
		local seen = {}
		for _, zone in zones do
			local part = zone.Part
			t.expect(part.Transparency >= 1 and not part.CanCollide and not part.CanQuery and not part.CanTouch, `{part:GetFullName()} must be invisible and non-interactive`)
			t.expect(part:IsDescendantOf(map.Zones), `{part:GetFullName()} belongs in Map/Zones`)
			seen[zone.DistrictId] = true
		end
		for _, district in World.Districts do
			t.expect(seen[district.Id], `no zone for {district.Id}`)
		end
	end)

	t.test("every building / field sits in its own district's zone", function()
		local problems = {}
		for name, f in footprints do
			if f.folder ~= "Roads" and f.folder ~= "Rushville" then
				local district = districtAt(Vector3.new(f.x, 5, f.z))
				if district ~= f.folder then
					table.insert(problems, `{name} centre is in {district}, expected {f.folder}`)
				end
			end
		end
		t.expect(#problems == 0, table.concat(problems, "\n      "))
	end)

	t.test("town is fully covered by town districts; outside is OuterRing", function()
		local problems = {}
		for x = -495, 495, 15 do
			for z = -345, 345, 15 do
				local district = districtAt(Vector3.new(x, 5, z))
				if district == nil or district == "OuterRing" then
					table.insert(problems, `({x}, {z}) -> {district}`)
				end
			end
		end
		for _, point in { Vector3.new(1500, 5, 0), Vector3.new(-1500, 5, 1500), Vector3.new(0, 5, -2400), Vector3.new(2400, 400, 2400) } do
			if districtAt(point) ~= "OuterRing" then
				table.insert(problems, `{point} should be OuterRing`)
			end
		end
		local high = Vector3.new(0, World.Boundary.Ceiling - 1, 0)
		if districtAt(high) ~= "Downtown" then
			table.insert(problems, "zones must reach up to the flight ceiling")
		end
		t.expect(#problems == 0, `{#problems} bad samples, e.g. {problems[1]}`)
	end)

	local function insideBuilding(point): string?
		for name, f in footprints do
			if f.folder ~= "Roads" and f.folder ~= "Rushville" and not FIELDS[name] and name ~= "Crime Scene" then
				if math.abs(point.X - f.x) < f.sx / 2 and math.abs(point.Z - f.z) < f.sz / 2 then
					return name
				end
			end
		end
		return nil
	end

	t.test("one main SpawnLocation at the south end of the highway", function()
		local spawnLocations = {}
		for _, part in parts do
			if part:IsA("SpawnLocation") then
				table.insert(spawnLocations, part)
			end
		end
		t.expect(#spawnLocations == 1, `exactly one SpawnLocation (found {#spawnLocations})`)
		local spawn = spawnLocations[1]
		t.expect(spawn:HasTag(Tags.MainSpawn), "tagged MainSpawn")
		t.expect((spawn.CFrame.Position - Vector3.new(0, 0.5, 330)).Magnitude < EPS, `spawn at (0, 0.5, 330), got {spawn.CFrame.Position}`)
		t.expect((spawn.Size - Vector3.new(12, 1, 12)).Magnitude < EPS, "spawn is 12 x 1 x 12")
		t.expect(spawn.Neutral, "neutral spawn")
	end)

	t.test("one respawn point per district, inside its zone and outside buildings", function()
		local byDistrict = {}
		for _, part in taggedWith(Tags.DistrictSpawn) do
			local id = part:GetAttribute(Attributes.DistrictId)
			t.expect(byDistrict[id] == nil, `duplicate DistrictSpawn for {id}`)
			byDistrict[id] = part
			local position = part.CFrame.Position
			t.expect(districtAt(position) == id, `{id} spawn is in {districtAt(position)}`)
			t.expect(insideBuilding(position) == nil, `{id} spawn is inside {insideBuilding(position)}`)
			t.expect(part:IsA("BasePart") and part.Transparency >= 1 and not part.CanCollide, `{id} spawn must be an invisible, non-colliding part`)
		end
		for _, district in World.Districts do
			t.expect(byDistrict[district.Id] ~= nil, `no DistrictSpawn for {district.Id}`)
		end
	end)

	t.test("mission markers", function()
		local container = map:FindFirstChild("MissionMarkers")
		t.expect(container and container:IsA("Model"), "MissionMarkers is a Model")
		t.expect(container.ModelStreamingMode == roblox.Enum.ModelStreamingMode.Persistent, "MissionMarkers streams persistently")
		local found = {}
		for _, marker in taggedWith(Tags.MissionMarker) do
			local id = marker:GetAttribute(Attributes.MarkerId)
			t.expect(type(id) == "string" and found[id] == nil, `marker id {id} missing or duplicated`)
			found[id] = true
			t.expect(marker:IsDescendantOf(container), `{id} belongs in Map/MissionMarkers`)
			local position = marker.CFrame.Position
			local district = marker:GetAttribute(Attributes.DistrictId)
			t.expect(districtAt(position) == district, `{id} is in {districtAt(position)}, attribute says {district}`)
			t.expect(insideBuilding(position) == nil, `{id} is inside {insideBuilding(position)}`)
		end
		for _, id in MARKER_IDS do
			t.expect(found[id], `missing marker {id}`)
		end
	end)

	t.test("ring battery spot in the Sheriff's Office back room", function()
		local spots = taggedWith(Tags.RingBatterySpot)
		t.expect(#spots == 1, `exactly one RingBatterySpot (found {#spots})`)
		local spot = spots[1]
		local position = spot.CFrame.Position
		local office = footprints["Sheriff's Office"]
		t.expect(office ~= nil, "Sheriff's Office exists")
		t.expect(math.abs(position.X - office.x) < office.sx / 2 and math.abs(position.Z - office.z) < office.sz / 2, "inside the office")
		t.expect(position.Z < office.z, "in the back (north) half, away from the street")
		t.expect(spot:GetAttribute(Attributes.DistrictId) == "Downtown", "DistrictId = Downtown")
	end)

	t.test("interiors are walk-in; other buildings are solid", function()
		local problems = {}
		for _, name in INTERIORS do
			local f = footprints[name]
			if f then
				local open, total = 0, 0
				for x = f.x - f.sx / 2 + 4, f.x + f.sx / 2 - 4, 3 do
					for z = f.z - f.sz / 2 + 4, f.z + f.sz / 2 - 4, 3 do
						total += 1
						if not insideSolid(Vector3.new(x, 3, z)) then
							open += 1
						end
					end
				end
				if open / total < 0.6 then
					table.insert(problems, `{name} interior is only {math.floor(open / total * 100)}% open`)
				end
			end
		end
		for _, name in SOLID do
			local f = footprints[name]
			if f and not insideSolid(Vector3.new(f.x, 3, f.z)) then
				table.insert(problems, `{name} is not solid at ground level`)
			end
		end
		t.expect(#problems == 0, table.concat(problems, "\n      "))
	end)

	t.test("crops can be walked through", function()
		for name in FIELDS do
			local f = footprints[name]
			if f and name ~= "South Wheat Field" then
				t.expect(not insideSolid(Vector3.new(f.x, 2, f.z)), `{name} blocks walking at its centre`)
			end
		end
		local wheat = footprints["South Wheat Field"]
		if wheat then
			t.expect(not insideSolid(Vector3.new(wheat.x - 80, 2, wheat.z)), "South Wheat Field blocks walking")
		end
	end)

	t.test("Replace rebuilds deterministically", function()
		local function signature(folder)
			local count, sum = 0, 0
			for _, d in folder:GetDescendants() do
				if d:IsA("BasePart") then
					count += 1
					local p = d.CFrame.Position
					sum += p.X * 0.7 + p.Y * 1.3 + p.Z * 0.9 + d.Size.X + d.Size.Y + d.Size.Z
				end
			end
			return count, sum
		end
		local countA, sumA = signature(map)
		local rebuilt = MapBuilder.Build(workspace, { Replace = true })
		t.expect(rebuilt ~= map and map.Parent == nil, "old map destroyed, new one returned")
		local countB, sumB = signature(rebuilt)
		t.expect(countA == countB and math.abs(sumA - sumB) < 1e-3, "same parts in the same places")
	end)
end
