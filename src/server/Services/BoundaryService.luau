--!strict
--[[
	BoundaryService: the server's hard edge of the play area.

	The client does the visible part (warning, soft push-back inside the band;
	Config.World.Boundary). This is the anti-exploit backstop: a character that
	gets further than ServerTolerance past the edge or ceiling (only possible
	with a modified client, or extreme lag) is put back inside by the server.

	No public API.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Boundary = require(Shared.Util.Boundary)
local WorldConfig = require(Shared.Config.World)

local Characters = require(script.Parent.Characters)

local config = WorldConfig.Boundary

local BoundaryService = {}

local function checkPlayer(player: Player)
	local root = Characters.GetRootPart(player, true)
	local character = player.Character
	if root == nil or character == nil then
		return
	end
	local position = root.Position
	if not Boundary.IsBeyond(position, config.ServerTolerance) then
		return
	end

	local state = Boundary.Evaluate(position)
	local target = state.Clamped + state.Inward * config.ServerReturnInset
	-- Keep the character's facing; only its position is wrong.
	character:PivotTo(CFrame.new(target) * root.CFrame.Rotation)
	-- Whatever carried it out there must not carry it straight back out.
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	warn(
		string.format(
			"[BoundaryService] %s (%d) was outside the play area at (%.0f, %.0f, %.0f); moved back inside",
			player.Name,
			player.UserId,
			position.X,
			position.Y,
			position.Z
		)
	)
end

function BoundaryService.Init(_self: BoundaryService) end

function BoundaryService.Start(_self: BoundaryService)
	while true do
		task.wait(config.ServerCheckInterval)
		for _, player in Players:GetPlayers() do
			-- Own thread per player: an error is reported (with its traceback) without
			-- switching the boundary off for everyone else.
			task.spawn(checkPlayer, player)
		end
	end
end

export type BoundaryService = typeof(BoundaryService)

return BoundaryService
