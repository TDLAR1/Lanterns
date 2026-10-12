--!strict
-- Networking limits. Rate limits are per player, per remote (token bucket:
-- Rate = sustained requests/second, Burst = largest allowed spike).

local Net = {
	-- Messages that fail argument validation never happen with an unmodified
	-- client, so after this many in one session the player is kicked.
	MaxInvalidMessages = 25,
	InvalidMessageKickMessage = "Unexpected network data from your client.",

	RateLimits = {
		GetProfileSummary = { Rate = 0.5, Burst = 3 },
	},
}

return Net
