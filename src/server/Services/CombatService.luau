--!strict
--[[
	CombatService: who ring powers can hurt, and how damage is dealt.

	  * A target is a Model with a living Humanoid: anything tagged Damageable
	    (training dummies; mission enemies later) and, only while
	    Config.Combat.PvPEnabled is on, another player's character. Never the
	    attacker's own character.
	  * Damage sets Humanoid.Health directly (clamped at 0) instead of calling
	    Humanoid:TakeDamage, so the rules here are the only rules:
	      - a player target whose Player has Attributes.Shielding takes
	        Config.Powers.Shield.DamageReduction less;
	      - a target with a ForceField (spawn protection) takes none.
	  * Defeated fires exactly once per target, when its health reaches 0.
	  * The attacker is told what they dealt (Remotes.HitConfirmed) for hit
	    numbers. The first hit on a target is reported at once; further hits on
	    it within Config.Combat.HitFeedback.MergeWindow are summed into one
	    follow-up message, so a beam's ticks read as a few numbers, not a stream.

	API:
	  CombatService:ResolveTarget(part, attacker): Model?
	  CombatService:ApplyDamage(attacker, target, amount, source): number   (damage dealt)
	  CombatService:Knockback(target, velocity)
	  CombatService:GetTargetsInRadius(position, radius, attacker): { Model }
	  CombatService:GetTargetRoot(target): BasePart?
	  CombatService.Damaged   Signal(attacker, target, amount, source)
	  CombatService.Defeated  Signal(attacker, target)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local CombatConfig = require(Shared.Config.Combat)
local PowersConfig = require(Shared.Config.Powers)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Util.Signal)
local TagsModule = require(Shared.Util.Tags)
local Types = require(Shared.Types)

local Tags = TagsModule.Tags
local Attributes = TagsModule.Attributes

-- Hits on one target by one attacker, waiting to be reported together.
type HitWindow = {
	amount: number,
	position: Vector3,
}

local hitWindows: { [Player]: { [Model]: HitWindow } } = {}

-- Targets already reported as defeated. Weak keys: a destroyed target drops out by itself.
local defeated = setmetatable({} :: { [Model]: boolean }, { __mode = "k" })

local CombatService = {
	-- Damage was dealt. (attacker, target, amount actually dealt, source power)
	Damaged = Signal.new() :: Signal.Signal<Player, Model, number, Types.PowerId>,
	-- A target's health reached 0. Fires once per target. (attacker, target)
	Defeated = Signal.new() :: Signal.Signal<Player, Model>,
}

local function isFiniteVector(value: Vector3): boolean
	return value.X == value.X
		and value.Y == value.Y
		and value.Z == value.Z
		and math.abs(value.X) ~= math.huge
		and math.abs(value.Y) ~= math.huge
		and math.abs(value.Z) ~= math.huge
end

local function livingHumanoid(model: Model): Humanoid?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

local function targetRoot(target: Model): BasePart?
	local root = target:FindFirstChild("HumanoidRootPart")
	if root ~= nil and root:IsA("BasePart") then
		return root
	end
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil and humanoid.RootPart ~= nil then
		return humanoid.RootPart
	end
	return target.PrimaryPart
end

-- Where a hit number should appear: over the head, else at the root.
local function hitPosition(target: Model): Vector3
	local head = target:FindFirstChild("Head")
	if head ~= nil and head:IsA("BasePart") then
		return head.Position
	end
	local root = targetRoot(target)
	if root ~= nil then
		return root.Position
	end
	return target:GetPivot().Position
end

local function sendHit(attacker: Player, position: Vector3, amount: number)
	if attacker.Parent == Players then
		Remotes.HitConfirmed:FireClient(attacker, position, amount)
	end
end

-- Reports a hit to the attacker. The first hit opens a merge window and is
-- sent straight away (instant feedback); hits during the window are summed
-- and sent when it closes, which opens the next window if anything was sent.
local function reportHit(attacker: Player, target: Model, amount: number)
	local feedback = CombatConfig.HitFeedback
	if not feedback.Enabled then
		return
	end
	local windows = hitWindows[attacker]
	if windows == nil then
		if attacker.Parent ~= Players then
			return
		end
		windows = {}
		hitWindows[attacker] = windows
	end

	local position = hitPosition(target)
	local open = windows[target]
	if open ~= nil then
		open.amount += amount
		open.position = position
		return
	end

	sendHit(attacker, position, amount)
	local window: HitWindow = { amount = 0, position = position }
	windows[target] = window

	local function close()
		local current = hitWindows[attacker]
		if current == nil or current[target] ~= window then
			-- The attacker left meanwhile.
			return
		end
		if window.amount > 0 then
			sendHit(attacker, window.position, window.amount)
			window.amount = 0
			task.delay(feedback.MergeWindow, close)
		else
			current[target] = nil
		end
	end
	task.delay(feedback.MergeWindow, close)
end

-- The part that moves a target: its HumanoidRootPart (or the Humanoid's root,
-- or the Model's PrimaryPart). Nil if it has none.
function CombatService.GetTargetRoot(_self: CombatService, target: Model): BasePart?
	return targetRoot(target)
end

local function resolveTarget(part: BasePart, attacker: Player): Model?
	if not part:IsDescendantOf(Workspace) then
		return nil
	end
	local current: Instance? = part.Parent
	while current ~= nil and current ~= Workspace do
		if current:IsA("Model") then
			if current:HasTag(Tags.Damageable) then
				return if livingHumanoid(current) ~= nil then current else nil
			end
			local owner = Players:GetPlayerFromCharacter(current)
			if owner ~= nil then
				if owner == attacker or not CombatConfig.PvPEnabled then
					return nil
				end
				return if livingHumanoid(current) ~= nil then current else nil
			end
		end
		current = current.Parent
	end
	return nil
end

-- The target `part` belongs to (see the header), or nil if it is not part of
-- one, the target is already dead, or it is the attacker's own character.
function CombatService.ResolveTarget(_self: CombatService, part: BasePart, attacker: Player): Model?
	return resolveTarget(part, attacker)
end

-- Deals `amount` damage to `target` and returns how much was actually dealt
-- (less when shielded, capped at the target's remaining health).
function CombatService.ApplyDamage(
	_self: CombatService,
	attacker: Player,
	target: Model,
	amount: number,
	source: Types.PowerId
): number
	-- Also rejects NaN (every comparison with NaN is false).
	if not (amount > 0) then
		return 0
	end
	if target == attacker.Character or not target:IsDescendantOf(Workspace) then
		return 0
	end
	local humanoid = livingHumanoid(target)
	if humanoid == nil or target:FindFirstChildOfClass("ForceField") ~= nil then
		return 0
	end

	local victim = Players:GetPlayerFromCharacter(target)
	if victim ~= nil and victim:GetAttribute(Attributes.Shielding) == true then
		amount *= 1 - math.clamp(PowersConfig.Shield.DamageReduction, 0, 1)
	end

	local before = humanoid.Health
	local after = math.max(0, before - amount)
	humanoid.Health = after
	local dealt = before - after
	if dealt <= 0 then
		return 0
	end

	CombatService.Damaged:Fire(attacker, target, dealt, source)
	reportHit(attacker, target, dealt)
	if after <= 0 and not defeated[target] then
		defeated[target] = true
		CombatService.Defeated:Fire(attacker, target)
	end
	return dealt
end

-- Pushes a target. Only moves targets that physics can move (an anchored
-- root, e.g. a training dummy or a caged target, stays put).
function CombatService.Knockback(_self: CombatService, target: Model, velocity: Vector3)
	if not isFiniteVector(velocity) then
		return
	end
	local root = targetRoot(target)
	if root ~= nil and not root.Anchored then
		root.AssemblyLinearVelocity = velocity
	end
end

-- Every living target with a part within `radius` studs of `position`
-- (each target once), never the attacker.
function CombatService.GetTargetsInRadius(
	_self: CombatService,
	position: Vector3,
	radius: number,
	attacker: Player
): { Model }
	local targets: { Model } = {}
	if not isFiniteVector(position) or not (radius > 0) then
		return targets
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local character = attacker.Character
	params.FilterDescendantsInstances = if character ~= nil then { character } else {}

	local seen: { [Model]: boolean } = {}
	for _, part in Workspace:GetPartBoundsInRadius(position, radius, params) do
		local target = resolveTarget(part, attacker)
		if target ~= nil and not seen[target] then
			seen[target] = true
			table.insert(targets, target)
		end
	end
	return targets
end

function CombatService.Init(_self: CombatService) end

function CombatService.Start(_self: CombatService)
	Players.PlayerRemoving:Connect(function(player: Player)
		-- Pending merge windows find their attacker gone and stop by themselves.
		hitWindows[player] = nil
	end)
end

export type CombatService = typeof(CombatService)

return CombatService
