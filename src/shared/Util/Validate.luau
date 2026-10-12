--!strict
--[[
	Validate: runtime checks for values that arrive from clients.

	Never trust remote arguments. A client can send anything Roblox can serialize:
	wrong types, NaN, +/-inf, enormous strings, Instances it should not reference,
	or nothing at all. Every client -> server remote lists one validator per
	argument (see Shared/Remotes.luau) and Net rejects the message before any game
	code sees it if a single validator returns false.
]]

export type Validator = (value: any) -> boolean

local Validate = {}

local function isFiniteNumber(value: any): boolean
	-- NaN is the only value not equal to itself.
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Any finite number.
Validate.Number = isFiniteNumber :: Validator

-- A finite number within [min, max].
function Validate.NumberRange(min: number, max: number): Validator
	return function(value: any): boolean
		return isFiniteNumber(value) and value >= min and value <= max
	end
end

-- A whole number within [min, max].
function Validate.Integer(min: number, max: number): Validator
	return function(value: any): boolean
		return isFiniteNumber(value) and value % 1 == 0 and value >= min and value <= max
	end
end

function Validate.Boolean(value: any): boolean
	return type(value) == "boolean"
end

-- A valid UTF-8 string of at most maxLength bytes. Invalid UTF-8 is rejected
-- because DataStores refuse it: one such string stored in a profile would make
-- every save of that profile fail. (The length check runs first so the UTF-8
-- scan only ever covers strings within the limit.)
function Validate.String(maxLength: number): Validator
	return function(value: any): boolean
		return type(value) == "string" and #value <= maxLength and utf8.len(value) ~= nil
	end
end

-- One of a fixed set of strings (e.g. an action or construct id).
function Validate.OneOf(options: { string }): Validator
	local allowed: { [string]: boolean } = {}
	for _, option in options do
		allowed[option] = true
	end
	return function(value: any): boolean
		return type(value) == "string" and allowed[value] == true
	end
end

-- A Vector3 with finite components.
function Validate.Vector3(value: any): boolean
	return typeof(value) == "Vector3"
		and isFiniteNumber(value.X)
		and isFiniteNumber(value.Y)
		and isFiniteNumber(value.Z)
end

-- A direction vector: finite and (approximately) length 1.
function Validate.UnitVector3(value: any): boolean
	return Validate.Vector3(value) and math.abs(value.Magnitude - 1) <= 0.01
end

-- A Vector3 no longer than maxMagnitude.
function Validate.Vector3Max(maxMagnitude: number): Validator
	return function(value: any): boolean
		return Validate.Vector3(value) and value.Magnitude <= maxMagnitude
	end
end

-- An Instance of the given class that is still in the game (has a parent chain to game).
function Validate.InstanceOf(className: string): Validator
	return function(value: any): boolean
		return typeof(value) == "Instance" and value:IsA(className) and value:IsDescendantOf(game)
	end
end

-- Allows nil, otherwise defers to the wrapped validator.
function Validate.Optional(validator: Validator): Validator
	return function(value: any): boolean
		return value == nil or validator(value)
	end
end

return Validate
