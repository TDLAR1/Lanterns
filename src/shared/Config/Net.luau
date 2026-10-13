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
		-- Ring powers. Toggles allow a few quick presses; BeamAim carries the aim
		-- point Config.Powers.Beam.AimSendRate times a second while firing.
		SetFlying = { Rate = 3, Burst = 6 },
		SetBoosting = { Rate = 6, Burst = 10 },
		BeamStart = { Rate = 4, Burst = 6 },
		BeamAim = { Rate = 25, Burst = 40 },
		BeamStop = { Rate = 4, Burst = 6 },
		SetShield = { Rate = 3, Burst = 6 },
		CastConstruct = { Rate = 3, Burst = 5 },
	},
}

return Net
