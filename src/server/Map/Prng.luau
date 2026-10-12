--!strict
--[[
	Prng: a tiny deterministic random number generator for map variety.

	Roblox's Random is not available in the offline Lune tests, and the map must
	come out identical in Lune, Studio and live servers, so this is a
	Park-Miller "minimal standard" generator (state * 48271 mod 2^31 - 1). Every
	intermediate value stays below 2^53, so plain Luau numbers are exact.

	Give each area its own generator and seed (see MapLayout) so editing one
	area never reshuffles another.
]]

local MODULUS = 2147483647
local MULTIPLIER = 48271

export type Prng = {
	-- Uniform number in [0, 1).
	Next: (self: Prng) -> number,
	-- Uniform number in [min, max).
	Range: (self: Prng, min: number, max: number) -> number,
	-- Uniform whole number in [min, max].
	Int: (self: Prng, min: number, max: number) -> number,
	-- True with the given probability.
	Chance: (self: Prng, probability: number) -> boolean,
}

local Prng = {}

function Prng.new(seed: number): Prng
	-- Fold any seed into 1..MODULUS-1 (0 would stay 0 forever).
	local state = math.floor(math.abs(seed)) % (MODULUS - 1) + 1

	local generator = {}

	function generator.Next(_self: Prng): number
		state = (state * MULTIPLIER) % MODULUS
		return (state - 1) / (MODULUS - 1)
	end

	function generator.Range(self: Prng, min: number, max: number): number
		return min + (max - min) * self:Next()
	end

	function generator.Int(self: Prng, min: number, max: number): number
		return math.min(max, min + math.floor(self:Next() * (max - min + 1)))
	end

	function generator.Chance(self: Prng, probability: number): boolean
		return self:Next() < probability
	end

	return (generator :: any) :: Prng
end

return Prng
