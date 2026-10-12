--[[
	Test harness: runs the game's ModuleScripts outside Roblox with Lune.

	It builds the place with Rojo, loads it with Lune's Roblox instance model and
	requires ModuleScripts from it with a Roblox-like environment (script,
	require, game, workspace, Roblox datatypes). Lune does not emulate the engine
	(physics, RunService, CollectionService queries, PivotTo, Random), so only
	data and geometry code can be exercised here; gameplay is tested in Studio.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local PLACE_PATH = ".luau-lsp/test.rbxl"

-- Roblox datatypes that Lune implements, exposed as globals like in the engine.
local DATATYPES = {
	"Axes",
	"BrickColor",
	"CFrame",
	"Color3",
	"ColorSequence",
	"ColorSequenceKeypoint",
	"Enum",
	"Faces",
	"Font",
	"Instance",
	"NumberRange",
	"NumberSequence",
	"NumberSequenceKeypoint",
	"PhysicalProperties",
	"Ray",
	"Rect",
	"Region3",
	"Region3int16",
	"UDim",
	"UDim2",
	"Vector2",
	"Vector2int16",
	"Vector3",
	"Vector3int16",
}

local Harness = {}

-- Builds the Rojo project and returns the resulting DataModel.
function Harness.buildPlace()
	fs.writeDir(".luau-lsp")
	local result = process.exec("rojo", { "build", "default.project.json", "--output", PLACE_PATH })
	if not result.ok then
		error("rojo build failed:\n" .. result.stderr)
	end
	return roblox.deserializePlace(fs.readFile(PLACE_PATH))
end

-- Returns a `require` that loads ModuleScripts from `place` with engine-like globals.
function Harness.newRequire(place)
	local cache = {}
	local loading = {}

	local function requireModule(module)
		if typeof(module) ~= "Instance" or not module:IsA("ModuleScript") then
			error("require() expects a ModuleScript, got " .. tostring(module), 2)
		end
		local cached = cache[module]
		if cached then
			return cached.value
		end
		if loading[module] then
			error("Cyclic require of " .. module:GetFullName(), 2)
		end
		loading[module] = true

		local env = {
			script = module,
			require = requireModule,
			game = place,
			workspace = place:GetService("Workspace"),
			task = task,
			warn = function(...)
				print("[warn]", ...)
			end,
		}
		for _, name in DATATYPES do
			env[name] = roblox[name]
		end

		local chunk = luau.load(module.Source, { debugName = module:GetFullName(), environment = env })
		local value = chunk()
		cache[module] = { value = value }
		loading[module] = nil
		return value
	end

	return requireModule
end

return Harness
