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
local Types = require(script.Parent.Types)

local Remotes = {
	-- Server -> client --------------------------------------------------------

	-- A district was discovered for the first time.
	-- (districtId, discoveredCount, totalCount)
	DistrictDiscovered = Net.ServerEvent("DistrictDiscovered") :: Net.ServerEvent<Types.DistrictId, number, number>,

	-- Short on-screen notification. (message, kind)
	Notify = Net.ServerEvent("Notify") :: Net.ServerEvent<string, Types.NotifyKind>,

	-- Client -> server -------------------------------------------------------

	-- Asked once after the client starts; answers with the player's save summary
	-- (nil if the profile could not be loaded in time).
	GetProfileSummary = Net.ClientFunction("GetProfileSummary", {
		Args = {},
		RateLimit = NetConfig.RateLimits.GetProfileSummary,
	}) :: Net.ClientFunction<(), (Types.ProfileSummary?)>,
}

return Remotes
