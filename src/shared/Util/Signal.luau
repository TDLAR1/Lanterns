--!strict
--[[
	Signal: a small typed event object for communication *within* one side
	(server service -> server service, or controller -> controller).
	For server <-> client communication use Shared/Remotes instead.

	Handlers run in their own thread (task.spawn), so one erroring or yielding
	handler never blocks the others or the code that fired the signal.
]]

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Wait: (self: Signal<T...>) -> T...,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
}

type Entry = {
	connection: Connection,
	handler: (...any) -> (),
}

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	-- Ordered list so handlers fire in the order they were connected.
	local entries: { Entry } = {}

	local function connect(handler: (...any) -> ()): Connection
		local connection = {} :: Connection
		connection.Connected = true
		function connection.Disconnect(self: Connection)
			if not self.Connected then
				return
			end
			self.Connected = false
			for index, entry in entries do
				if entry.connection == self then
					table.remove(entries, index)
					break
				end
			end
		end
		table.insert(entries, { connection = connection, handler = handler })
		return connection
	end

	local signal = {}

	function signal.Connect(_self: any, handler: (...any) -> ()): Connection
		return connect(handler)
	end

	function signal.Once(_self: any, handler: (...any) -> ()): Connection
		local connection: Connection
		connection = connect(function(...)
			connection:Disconnect()
			handler(...)
		end)
		return connection
	end

	function signal.Wait(_self: any): ...any
		local thread = coroutine.running()
		local connection: Connection
		connection = connect(function(...)
			connection:Disconnect()
			task.spawn(thread, ...)
		end)
		return coroutine.yield()
	end

	function signal.Fire(_self: any, ...: any)
		-- Snapshot first: handlers may connect/disconnect while we iterate.
		local snapshot = table.clone(entries)
		for _, entry in snapshot do
			if entry.connection.Connected then
				task.spawn(entry.handler, ...)
			end
		end
	end

	function signal.DisconnectAll(_self: any)
		for _, entry in entries do
			entry.connection.Connected = false
		end
		table.clear(entries)
	end

	return (signal :: any) :: Signal<T...>
end

return Signal
