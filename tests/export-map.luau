--[[
	Builds the blockout map offline and saves it as a model file you can drop
	into Studio (an alternative to building it from the command bar):

		lune run tests/export-map

	Output: build/RushvilleMap.rbxm  (and build/map-parts.json, a flat list of
	every part used by tooling that draws the map from above).
]]

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Harness = require("./Harness")

local place = Harness.buildPlace()
local requireModule = Harness.newRequire(place)
local MapBuilder = requireModule(place:GetService("ServerScriptService").Server.Map.MapBuilder)

local workspace = place:GetService("Workspace")
local existing = workspace:FindFirstChild("Map")
if existing then
	existing:Destroy()
end
local map = MapBuilder.Build(workspace)

fs.writeDir("build")
fs.writeFile("build/RushvilleMap.rbxm", roblox.serializeModel({ map }))

local rows = {}
for _, part in map:GetDescendants() do
	if part:IsA("BasePart") then
		local cf = part.CFrame
		local rx, ry, rz = cf:ToOrientation()
		local shape = if part:IsA("Part") then part.Shape.Name else part.ClassName
		table.insert(rows, {
			path = part:GetFullName(),
			class = part.ClassName,
			shape = shape,
			position = { cf.Position.X, cf.Position.Y, cf.Position.Z },
			orientation = { math.deg(rx), math.deg(ry), math.deg(rz) },
			size = { part.Size.X, part.Size.Y, part.Size.Z },
			color = { part.Color.R, part.Color.G, part.Color.B },
			transparency = part.Transparency,
			canCollide = part.CanCollide,
			tags = part:GetTags(),
		})
	end
end
fs.writeFile("build/map-parts.json", serde.encode("json", rows))
print(`Saved build/RushvilleMap.rbxm ({#rows} parts)`)
