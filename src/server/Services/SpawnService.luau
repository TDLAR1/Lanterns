--!strict
--[[
	SpawnService: where characters (re)spawn.

	  * New players appear at the map's main SpawnLocation (Roblox handles this;
	    WorldService makes sure it is the only enabled one).
	  * When a character dies, the death position is remembered. If
	    Config.World.Spawning.RespawnAtNearestDistrict is on, the next character
	    is moved to the district respawn point nearest to that position, among
	    districts the player has DISCOVERED. With none discovered (or data not
	    loaded), the player stays at the main spawn.
	  * Before that move the area around the respawn point is streamed in for
	    the client (Workspace.StreamingEnabled), and the character is marked as
	    being placed so ZoneService does not count the main spawn's district.

	No public API: it only reacts to characters.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local WorldConfig = require(Shared.Config.World)

local Characters = require(script.Parent.Characters)
local WorldService = require(script.Parent.WorldService)
local ZoneService = require(script.Parent.ZoneService)

local spawning = WorldConfig.Spawning

local deathPositions: { [Player]: Vector3 } = {}
local characterAddedConnections: { [Player]: RBXScriptConnection } = {}

local SpawnService = {}

local function nearestDiscoveredSpawn(player: Player, position: Vector3): BasePart?
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, district in WorldConfig.Districts do
		if ZoneService:IsDiscovered(player, district.Id) then
			local spawnPart = WorldService:GetDistrictSpawn(district.Id)
			if spawnPart ~= nil then
				local distance = (spawnPart.Position - position).Magnitude
				if distance < bestDistance then
					best = spawnPart
					bestDistance = distance
				end
			end
		end
	end
	return best
end

local function moveToSpawn(player: Player, character: Model, spawnPart: BasePart)
	local root = Characters.WaitForRootPart(character, spawning.CharacterLoadTimeout)
	-- Anything may have changed while waiting: the player left or respawned again,
	-- or the spawn part was removed.
	if root ~= nil and player.Character == character and spawnPart:IsDescendantOf(Workspace) then
		local lift = spawnPart.Size.Y / 2 + spawning.RespawnHeightOffset
		local target = spawnPart.CFrame + Vector3.yAxis * lift
		-- With streaming on, the client may not have the ground there yet; moving
		-- first would drop the character through the world.
		local ok, err = pcall(function()
			player:RequestStreamAroundAsync(target.Position, spawning.StreamAroundTimeout)
		end)
		if not ok then
			warn(`[SpawnService] Could not stream the respawn area for {player.Name}: {err}`)
		end
		-- Checked again: streaming yields, and the player may have left or respawned.
		if player.Character == character and spawnPart:IsDescendantOf(Workspace) then
			character:PivotTo(target)
		end
	end
	-- Moved or given up: either way district tracking may look at it again.
	Characters.EndPlacement(character)
end

local function rememberDeaths(player: Player, character: Model)
	local humanoid = Characters.WaitForHumanoid(character, spawning.CharacterLoadTimeout)
	if humanoid == nil then
		return
	end
	humanoid.Died:Once(function()
		if player.Parent ~= Players or player.Character ~= character then
			return
		end
		local root = Characters.FindRootPart(character)
		-- No root (e.g. destroyed by falling out of the world): nothing sensible to
		-- measure from, so this respawn uses the main spawn.
		if root ~= nil then
			deathPositions[player] = root.Position
		end
	end)
end

local function onCharacterAdded(player: Player, character: Model)
	local deathPosition: Vector3? = deathPositions[player]
	deathPositions[player] = nil
	if deathPosition ~= nil and spawning.RespawnAtNearestDistrict then
		local spawnPart = nearestDiscoveredSpawn(player, deathPosition)
		if spawnPart ~= nil then
			-- Until the move, the character stands at the main spawn; ZoneService
			-- ignores it meanwhile so that spawn's district never flashes up.
			Characters.BeginPlacement(character, spawning.CharacterLoadTimeout + spawning.StreamAroundTimeout)
			-- Deferred: Roblox places the new character at its SpawnLocation after
			-- CharacterAdded fires, which would undo a move made right now.
			task.defer(moveToSpawn, player, character, spawnPart)
		end
	end
	-- Last: it may yield waiting for the Humanoid.
	rememberDeaths(player, character)
end

local function onPlayerAdded(player: Player)
	-- PlayerAdded and the "already in game" pass in Start can both reach a player.
	local existing: RBXScriptConnection? = characterAddedConnections[player]
	if existing ~= nil then
		return
	end
	characterAddedConnections[player] = player.CharacterAdded:Connect(function(character: Model)
		onCharacterAdded(player, character)
	end)
	-- Already spawned before we were listening: only track its death; it is
	-- already where it should be.
	local character = player.Character
	if character ~= nil then
		task.spawn(rememberDeaths, player, character)
	end
end

local function onPlayerRemoving(player: Player)
	local connection: RBXScriptConnection? = characterAddedConnections[player]
	if connection ~= nil then
		connection:Disconnect()
	end
	characterAddedConnections[player] = nil
	deathPositions[player] = nil
end

function SpawnService.Init(_self: SpawnService) end

function SpawnService.Start(_self: SpawnService)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

export type SpawnService = typeof(SpawnService)

return SpawnService
