--!strict
--[[
	Remotes: EVERY message between client and server is declared here, once.

	To add one:
	  1. Pick the kind (see Net.luau): ClientEvent, ServerEvent or ClientFunction.
	  2. For anything the client sends, give one validator per argument and a
	     rate limit in Config/Net.luau (RateLimits.<Name>).
	  3. Cast to the matching Net type so callers get argument type checking.

	Requiring this module on the server creates the Instances; on the client it
	waits for them, so require it before anything uses a remote.
]]

local Net = require(script.Parent.Net)
local NetConfig = require(script.Parent.Config.Net)
local PowersConfig = require(script.Parent.Config.Powers)
local Types = require(script.Parent.Types)
local Validate = require(script.Parent.Util.Validate)

local Remotes = {
	-- Server -> client --------------------------------------------------------

	-- A district was discovered for the first time.
	-- (districtId, discoveredCount, totalCount)
	DistrictDiscovered = Net.ServerEvent("DistrictDiscovered") :: Net.ServerEvent<Types.DistrictId, number, number>,

	-- Short on-screen notification. (message, kind)
	Notify = Net.ServerEvent("Notify") :: Net.ServerEvent<string, Types.NotifyKind>,

	-- The server refused a power request from this client. (powerId, reason)
	PowerRejected = Net.ServerEvent("PowerRejected") :: Net.ServerEvent<Types.PowerId, Types.PowerRejectReason>,

	-- Another player's beam, for drawing it. Sent to everyone except the caster
	-- (who draws their own beam immediately) every server beam tick.
	-- (caster, from, to)
	BeamVisual = Net.ServerEvent("BeamVisual", { Unreliable = true }) :: Net.ServerEvent<Player, Vector3, Vector3>,

	-- A one-shot effect for every client to play. (effectId, position, scale)
	-- scale is effect-specific (e.g. the hammer's radius); 1 when unused.
	PowerEffect = Net.ServerEvent("PowerEffect") :: Net.ServerEvent<Types.EffectId, Vector3, number>,

	-- Damage this client's powers just dealt, for hit numbers. (position, amount)
	HitConfirmed = Net.ServerEvent("HitConfirmed") :: Net.ServerEvent<Vector3, number>,

	-- The oath moment at the ring battery began. (duration in seconds, battery position)
	OathStarted = Net.ServerEvent("OathStarted") :: Net.ServerEvent<number, Vector3>,
	-- The oath moment ended. (completed: false if it was interrupted)
	OathEnded = Net.ServerEvent("OathEnded") :: Net.ServerEvent<boolean>,

	-- Client -> server -------------------------------------------------------

	-- Asked after the client starts, and again while it answers nil; answers with
	-- the player's save summary once it has loaded (nil if it could not be loaded).
	GetProfileSummary = Net.ClientFunction("GetProfileSummary", {
		Args = {},
		RateLimit = NetConfig.RateLimits.GetProfileSummary,
	}) :: Net.ClientFunction<(), (Types.ProfileSummary?)>,

	-- Ring powers. The server validates every request against willpower, charge,
	-- cooldowns and range (RingService) and answers refusals with PowerRejected.
	-- Aim is always a world-space POINT (where the crosshair ray hit): the server
	-- checks it against the caster's own position and range.

	-- Take off (true) / land (false).
	SetFlying = Net.ClientEvent("SetFlying", {
		Args = { Validate.Boolean },
		RateLimit = NetConfig.RateLimits.SetFlying,
	}) :: Net.ClientEvent<boolean>,

	-- Boost held (true) / released (false) while flying.
	SetBoosting = Net.ClientEvent("SetBoosting", {
		Args = { Validate.Boolean },
		RateLimit = NetConfig.RateLimits.SetBoosting,
	}) :: Net.ClientEvent<boolean>,

	-- Start firing the beam at an aim point.
	BeamStart = Net.ClientEvent("BeamStart", {
		Args = { Validate.Vector3 },
		RateLimit = NetConfig.RateLimits.BeamStart,
	}) :: Net.ClientEvent<Vector3>,

	-- New aim point while firing (unreliable: only the latest matters).
	BeamAim = Net.ClientEvent("BeamAim", {
		Args = { Validate.Vector3 },
		RateLimit = NetConfig.RateLimits.BeamAim,
		Unreliable = true,
	}) :: Net.ClientEvent<Vector3>,

	-- Stop firing the beam.
	BeamStop = Net.ClientEvent("BeamStop", {
		Args = {},
		RateLimit = NetConfig.RateLimits.BeamStop,
	}) :: Net.ClientEvent<()>,

	-- Raise (true) / drop (false) the shield.
	SetShield = Net.ClientEvent("SetShield", {
		Args = { Validate.Boolean },
		RateLimit = NetConfig.RateLimits.SetShield,
	}) :: Net.ClientEvent<boolean>,

	-- Cast a construct at an aim point. (constructId, aimPoint)
	CastConstruct = Net.ClientEvent("CastConstruct", {
		Args = { Validate.OneOf(PowersConfig.ConstructOrder), Validate.Vector3 },
		RateLimit = NetConfig.RateLimits.CastConstruct,
	}) :: Net.ClientEvent<Types.ConstructId, Vector3>,
}

return Remotes
