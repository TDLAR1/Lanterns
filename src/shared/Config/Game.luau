--!strict
-- Game-wide identity.

local Game = {
	-- The game's title, shown in the server start-up log. When the final name is
	-- chosen, update the README title too.
	Name = "[YOUR GAME NAME]",
	-- The town's name, used by in-world signs and the welcome toasts.
	TownName = "Rushville",
	-- Shown in the server start-up log next to Name.
	Version = "0.2.0 · Milestone 1",
}

return Game
