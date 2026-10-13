--!strict
-- Damage rules and the training dummies.

local Combat = {
	-- Whether ring powers can hurt other players. Off: the town is a shared hub;
	-- powers only affect Damageable targets (dummies, and mission enemies later).
	PvPEnabled = false,

	TrainingDummy = {
		Health = 250,
		-- Seconds after being destroyed before a dummy stands up again.
		RespawnTime = 4,
		-- Studs; the dummy's overall height.
		Height = 6,
	},

	-- Damage numbers shown to the attacker.
	HitFeedback = {
		Enabled = true,
		-- Hits within this many seconds on the same target merge into one number.
		MergeWindow = 0.35,
	},
}

return Combat
