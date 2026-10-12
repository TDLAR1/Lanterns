--!strict
--[[
	Characters: safe lookups of a player's character parts, shared by the
	services, plus a "being placed" mark SpawnService sets on a respawned
	character until it has moved it. A helper module, not a service (no
	Init/Start).

	Characters come and go at any moment (respawns, players leaving, parts
	destroyed by the void), so every function here returns nil / false instead
	of erroring when something is missing, and every wait has a timeout.
]]

local Workspace = game:GetService("Workspace")

-- Every standard Humanoid rig (R6, R15, custom StarterCharacter) names its root this.
local ROOT_PART_NAME = "HumanoidRootPart"

-- Characters the server is about to move (SpawnService's district respawn),
-- mapped to the os.clock() time after which they count as placed anyway, so a
-- move that never happens cannot freeze district tracking. Weak keys: a
-- destroyed character drops out by itself.
local placingUntil = setmetatable({} :: { [Model]: number }, { __mode = "k" })

local Characters = {}

-- Marks a new character as about to be moved by the server, for at most
-- `timeout` seconds. Until then it is not where it will end up, so district
-- tracking should ignore it (see IsBeingPlaced).
function Characters.BeginPlacement(character: Model, timeout: number)
	placingUntil[character] = os.clock() + timeout
end

-- The character has been moved (or the move was given up).
function Characters.EndPlacement(character: Model)
	placingUntil[character] = nil
end

function Characters.IsBeingPlaced(character: Model): boolean
	local deadline = placingUntil[character]
	return deadline ~= nil and os.clock() < deadline
end

-- The character's root part, or nil if it has none (yet / any more).
function Characters.FindRootPart(character: Model): BasePart?
	local root = character:FindFirstChild(ROOT_PART_NAME)
	if root ~= nil and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- The root part of the player's current character, or nil if there is no
-- character in the world or it has no root part. With requireAlive, also nil
-- once the character's Humanoid has died.
function Characters.GetRootPart(player: Player, requireAlive: boolean?): BasePart?
	local character = player.Character
	if character == nil or not character:IsDescendantOf(Workspace) then
		return nil
	end
	local root = Characters.FindRootPart(character)
	if root == nil then
		return nil
	end
	if requireAlive then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid == nil or humanoid.Health <= 0 then
			return nil
		end
	end
	return root
end

-- Yields until the character is in Workspace (true), or `timeout` seconds pass
-- (false). CharacterAdded fires BEFORE the character is parented, so code that
-- moves a new character must wait for this first.
function Characters.WaitUntilInWorld(character: Model, timeout: number): boolean
	if character:IsDescendantOf(Workspace) then
		return true
	end
	local thread = coroutine.running()
	local finished = false
	local connection: RBXScriptConnection? = nil
	local function finish(inWorld: boolean)
		if finished then
			return
		end
		finished = true
		if connection ~= nil then
			connection:Disconnect()
		end
		-- Deferred: resume only after the engine has finished the step that
		-- parented the character (spawn placement happens around it).
		task.defer(thread, inWorld)
	end
	connection = character.AncestryChanged:Connect(function()
		if character:IsDescendantOf(Workspace) then
			finish(true)
		end
	end)
	local timeoutThread = task.delay(timeout, finish, false)
	local inWorld: boolean = coroutine.yield()
	if coroutine.status(timeoutThread) == "suspended" then
		task.cancel(timeoutThread)
	end
	return inWorld
end

-- Yields until `character` has a root part and is in the world, then returns
-- the root part. Nil if that takes longer than `timeout` seconds in total.
function Characters.WaitForRootPart(character: Model, timeout: number): BasePart?
	local deadline = os.clock() + timeout
	local root = character:WaitForChild(ROOT_PART_NAME, timeout)
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	if not Characters.WaitUntilInWorld(character, math.max(deadline - os.clock(), 0)) then
		return nil
	end
	return root
end

-- The character's Humanoid, waiting up to `timeout` seconds for it to appear.
function Characters.WaitForHumanoid(character: Model, timeout: number): Humanoid?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		return humanoid
	end
	local child = character:WaitForChild("Humanoid", timeout)
	if child ~= nil and child:IsA("Humanoid") then
		return child
	end
	return nil
end

return Characters
