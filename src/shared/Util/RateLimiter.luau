--!strict
--[[
	RateLimiter: per-player token bucket.

	Each player gets a bucket holding up to `Burst` tokens that refills at `Rate`
	tokens per second. Every request spends one token; with no tokens left the
	request is refused. Burst absorbs legitimate spikes (network jitter bunching
	packets together) while Rate caps the sustained request rate.
]]

export type RateLimit = {
	-- Tokens regained per second (sustained requests per second).
	Rate: number,
	-- Bucket size (largest allowed burst).
	Burst: number,
}

export type RateLimiter = {
	Allow: (self: RateLimiter, player: Player) -> boolean,
	Remove: (self: RateLimiter, player: Player) -> (),
}

type Bucket = {
	tokens: number,
	updatedAt: number,
}

local RateLimiter = {}

function RateLimiter.new(limit: RateLimit): RateLimiter
	assert(limit.Rate > 0 and limit.Burst >= 1, "RateLimiter needs Rate > 0 and Burst >= 1")
	local buckets: { [Player]: Bucket } = {}

	local limiter = {}

	function limiter.Allow(_self: RateLimiter, player: Player): boolean
		local now = os.clock()
		local bucket = buckets[player]
		if not bucket then
			bucket = { tokens = limit.Burst, updatedAt = now }
			buckets[player] = bucket
		end
		bucket.tokens = math.min(limit.Burst, bucket.tokens + (now - bucket.updatedAt) * limit.Rate)
		bucket.updatedAt = now
		if bucket.tokens >= 1 then
			bucket.tokens -= 1
			return true
		end
		return false
	end

	function limiter.Remove(_self: RateLimiter, player: Player)
		buckets[player] = nil
	end

	return (limiter :: any) :: RateLimiter
end

return RateLimiter
