--[[
	Offline test runner (Lune). From the project root:

		lune run tests/run            -- all specs
		lune run tests/run Map        -- only specs whose name contains "Map"

	Builds the place with Rojo, then runs every spec in tests/specs against the
	real ModuleScripts. Exits with code 1 if anything fails.
]]

local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Harness = require("./Harness")

local SPECS = {
	{ name = "Validate", run = require("./specs/Validate.spec") },
	{ name = "RateLimiter", run = require("./specs/RateLimiter.spec") },
	{ name = "Boundary", run = require("./specs/Boundary.spec") },
	{ name = "Zones", run = require("./specs/Zones.spec") },
	{ name = "Map", run = require("./specs/Map.spec") },
}

local filter = process.args[1]

local place = Harness.buildPlace()
local ctx = {
	place = place,
	roblox = roblox,
	require = Harness.newRequire(place),
	shared = place:GetService("ReplicatedStorage"):FindFirstChild("Shared"),
	server = place:GetService("ServerScriptService"):FindFirstChild("Server"),
}

local passed, failed = 0, 0

local function makeT(specName: string)
	local t = {}

	function t.test(name: string, fn: () -> ())
		local ok, err = pcall(fn)
		if ok then
			passed += 1
			print(`  ✓ {name}`)
		else
			failed += 1
			print(`  ✗ {name}\n      {err}`)
		end
	end

	function t.expect(condition: any, message: string?)
		if not condition then
			error(message or "expectation failed", 2)
		end
	end

	function t.near(actual: number, expected: number, epsilon: number, message: string?)
		if math.abs(actual - expected) > epsilon then
			error(`{message or "value"}: expected {expected}, got {actual}`, 2)
		end
	end

	function t.log(message: string)
		print(`    · {message}`)
	end

	return t
end

for _, spec in SPECS do
	if filter == nil or string.find(spec.name, filter, 1, true) then
		print(`\n{spec.name}`)
		local ok, err = pcall(spec.run, makeT(spec.name), ctx)
		if not ok then
			failed += 1
			print(`  ✗ spec crashed\n      {err}`)
		end
	end
end

print(`\n{passed} passed, {failed} failed`)
process.exit(if failed > 0 then 1 else 0)
