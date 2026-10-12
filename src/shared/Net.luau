--!strict
--[[
	Net: typed wrappers around RemoteEvents / RemoteFunctions.

	Remotes are DECLARED in Shared/Remotes.luau, the single place that lists every
	message between client and server. This module provides the constructors used
	there and the runtime behaviour:

	  * Server: constructing a remote creates its Instance in ReplicatedStorage.Remotes.
	  * Client: constructing a remote waits for that Instance to replicate.
	  * Every client -> server message is checked against a per-player rate limit
	    and then against one validator per argument BEFORE any handler runs.
	    Over-limit and invalid messages are dropped. Invalid messages are counted;
	    an unmodified client never sends one, so too many gets the player kicked.
	  * A client firing a server -> client event is counted as an invalid message.

	Three kinds of remote:
	  ClientEvent<T...>        client -> server   (client :Fire, server :Connect)
	  ServerEvent<T...>        server -> client   (server :FireClient/:FireAll, client :Connect)
	  ClientFunction<A..., R...> client asks, server answers (client :Invoke, server :SetHandler)
	There is deliberately no server -> client request/response: a client could
	simply never answer and hang the server thread.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NetConfig = require(script.Parent.Config.Net)
local RateLimiter = require(script.Parent.Util.RateLimiter)
local Validate = require(script.Parent.Util.Validate)

export type Validator = Validate.Validator
export type RateLimit = RateLimiter.RateLimit

export type ClientEvent<T...> = {
	Name: string,
	-- Client only.
	Fire: (self: ClientEvent<T...>, T...) -> (),
	-- Server only. Handlers only ever receive arguments that passed validation.
	Connect: (self: ClientEvent<T...>, handler: (player: Player, T...) -> ()) -> (),
}

export type ServerEvent<T...> = {
	Name: string,
	-- Server only.
	FireClient: (self: ServerEvent<T...>, player: Player, T...) -> (),
	FireAll: (self: ServerEvent<T...>, T...) -> (),
	FireAllExcept: (self: ServerEvent<T...>, except: Player, T...) -> (),
	-- Client only.
	Connect: (self: ServerEvent<T...>, handler: (T...) -> ()) -> RBXScriptConnection,
}

export type ClientFunction<A..., R...> = {
	Name: string,
	-- Client only. Yields until the server answers. The server answers with
	-- nothing if the request was rate limited or invalid, so declare R... as
	-- optional types and handle nil.
	Invoke: (self: ClientFunction<A..., R...>, A...) -> R...,
	-- Server only. Exactly one handler per function.
	SetHandler: (self: ClientFunction<A..., R...>, handler: (player: Player, A...) -> R...) -> (),
}

export type ClientEventOptions = {
	-- One validator per argument, in order. Extra arguments are rejected.
	Args: { Validator },
	RateLimit: RateLimit,
	-- Use an UnreliableRemoteEvent (may drop/reorder; for high-frequency updates
	-- where only the latest value matters, e.g. aim direction).
	Unreliable: boolean?,
}

export type ServerEventOptions = {
	Unreliable: boolean?,
}

export type ClientFunctionOptions = {
	Args: { Validator },
	RateLimit: RateLimit,
}

-- Structural view shared by RemoteEvent and UnreliableRemoteEvent.
type EventInstance = {
	OnClientEvent: RBXScriptSignal<...any>,
	OnServerEvent: RBXScriptSignal<(Player, ...any)>,
	FireAllClients: (self: any, ...any) -> (),
	FireClient: (self: any, player: Player, ...any) -> (),
	FireServer: (self: any, ...any) -> (),
}

local IS_SERVER = RunService:IsServer()
local IS_STUDIO = RunService:IsStudio()
local FOLDER_NAME = "Remotes"

local Net = {}

local folder: Instance
if IS_SERVER then
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

local declaredNames: { [string]: boolean } = {}
local limiters: { RateLimiter.RateLimiter } = {}
local invalidCounts: { [Player]: number } = {}

local function getRemoteInstance(name: string, className: string): Instance
	assert(not declaredNames[name], `Remote "{name}" is declared twice`)
	declaredNames[name] = true
	if IS_SERVER then
		assert(
			folder:FindFirstChild(name) == nil,
			`An Instance named "{name}" already exists in ReplicatedStorage.Remotes`
		)
		local remote = Instance.new(className)
		remote.Name = name
		remote.Parent = folder
		return remote
	end
	return folder:WaitForChild(name)
end

local function argsAreValid(validators: { Validator }, ...: any): boolean
	if select("#", ...) > #validators then
		return false
	end
	for index, validator in validators do
		if not validator((select(index, ...))) then
			return false
		end
	end
	return true
end

-- Counts a message an unmodified client never sends; too many in one session
-- gets the player kicked.
local function rejectInvalid(player: Player, remoteName: string)
	local count = (invalidCounts[player] or 0) + 1
	invalidCounts[player] = count
	warn(`[Net] Invalid message from {player.Name} ({player.UserId}) on {remoteName} ({count})`)
	if count >= NetConfig.MaxInvalidMessages then
		player:Kick(NetConfig.InvalidMessageKickMessage)
	end
end

-- Rate limit first (cheap, stops floods), then validate. Returns true if the
-- message may be handled.
local function admit(
	player: Player,
	remoteName: string,
	limiter: RateLimiter.RateLimiter,
	validators: { Validator },
	...: any
): boolean
	if not limiter:Allow(player) then
		if IS_STUDIO then
			warn(`[Net] Rate limited {player.Name} on {remoteName}`)
		end
		return false
	end
	if not argsAreValid(validators, ...) then
		rejectInvalid(player, remoteName)
		return false
	end
	return true
end

local function serverOnly(name: string, method: string)
	assert(IS_SERVER, `{name}:{method}() can only be called on the server`)
end

local function clientOnly(name: string, method: string)
	assert(not IS_SERVER, `{name}:{method}() can only be called on the client`)
end

function Net.ClientEvent(name: string, options: ClientEventOptions): any
	local remote = (
		getRemoteInstance(name, if options.Unreliable then "UnreliableRemoteEvent" else "RemoteEvent") :: any
	) :: EventInstance
	local handlers: { (Player, ...any) -> () } = {}

	if IS_SERVER then
		local limiter = RateLimiter.new(options.RateLimit)
		table.insert(limiters, limiter)
		remote.OnServerEvent:Connect(function(player: Player, ...: any)
			if not admit(player, name, limiter, options.Args, ...) then
				return
			end
			for _, handler in handlers do
				task.spawn(handler, player, ...)
			end
		end)
	end

	local event = { Name = name }

	function event.Fire(_self: any, ...: any)
		clientOnly(name, "Fire")
		remote:FireServer(...)
	end

	function event.Connect(_self: any, handler: (Player, ...any) -> ())
		serverOnly(name, "Connect")
		table.insert(handlers, handler)
	end

	return event
end

function Net.ServerEvent(name: string, options: ServerEventOptions?): any
	local unreliable = options ~= nil and options.Unreliable == true
	local remote = (
		getRemoteInstance(name, if unreliable then "UnreliableRemoteEvent" else "RemoteEvent") :: any
	) :: EventInstance

	if IS_SERVER then
		-- Server -> client only: a client firing it is always invalid. Connecting
		-- also stops Roblox queueing (and warning about) unhandled invocations.
		remote.OnServerEvent:Connect(function(player: Player)
			rejectInvalid(player, name)
		end)
	end

	local event = { Name = name }

	function event.FireClient(_self: any, player: Player, ...: any)
		serverOnly(name, "FireClient")
		remote:FireClient(player, ...)
	end

	function event.FireAll(_self: any, ...: any)
		serverOnly(name, "FireAll")
		remote:FireAllClients(...)
	end

	function event.FireAllExcept(_self: any, except: Player, ...: any)
		serverOnly(name, "FireAllExcept")
		for _, player in Players:GetPlayers() do
			if player ~= except then
				remote:FireClient(player, ...)
			end
		end
	end

	function event.Connect(_self: any, handler: (...any) -> ()): RBXScriptConnection
		clientOnly(name, "Connect")
		return remote.OnClientEvent:Connect(handler)
	end

	return event
end

function Net.ClientFunction(name: string, options: ClientFunctionOptions): any
	local remote = getRemoteInstance(name, "RemoteFunction") :: RemoteFunction
	local handler: ((Player, ...any) -> ...any)? = nil

	if IS_SERVER then
		local limiter = RateLimiter.new(options.RateLimit)
		table.insert(limiters, limiter)
		remote.OnServerInvoke = function(player: Player, ...: any): ...any
			if not admit(player, name, limiter, options.Args, ...) then
				return
			end
			local current = handler
			if not current then
				warn(`[Net] {name} was invoked before the server set a handler`)
				return
			end
			-- Never let a handler error propagate to (and leak details to) the client.
			local results = table.pack(pcall(current, player, ...))
			if not results[1] then
				warn(`[Net] {name} handler error: {results[2]}`)
				return
			end
			return table.unpack(results, 2, results.n)
		end
	end

	local fn = { Name = name }

	function fn.Invoke(_self: any, ...: any): ...any
		clientOnly(name, "Invoke")
		return remote:InvokeServer(...)
	end

	function fn.SetHandler(_self: any, newHandler: (Player, ...any) -> ...any)
		serverOnly(name, "SetHandler")
		assert(handler == nil, `{name} already has a handler`)
		handler = newHandler
	end

	return fn
end

if IS_SERVER then
	Players.PlayerRemoving:Connect(function(player: Player)
		invalidCounts[player] = nil
		for _, limiter in limiters do
			limiter:Remove(player)
		end
	end)
end

return Net
