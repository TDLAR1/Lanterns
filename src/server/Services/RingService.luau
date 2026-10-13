--!strict
--[[
	RingService: every player's power ring. The one authority over willpower,
	ring charge and cooldowns; every power service asks it before acting.

	  * Willpower (Config.Ring.Willpower) is spent by powers and regenerates on
	    its own RegenDelay seconds after the last spend.
	  * Ring charge (Config.Ring.Charge) is worn down by powers and NEVER
	    regenerates here; only the ring battery refills it (Refill). It is saved
	    (PlayerData.Ring.Charge), so rejoining never refills it either.
	  * Cooldowns are per power. The ready time is mirrored to the client as the
	    attribute CooldownEnd_<PowerId> in server time (Workspace:GetServerTimeNow()).
	  * Other services can block all powers for a reason (e.g. "Recharging"
	    while the oath plays) with SetBlocked.

	State is mirrored to each Player as attributes (Willpower, WillpowerMax,
	RingCharge, RingChargeMax) for the HUD. Clients only ever read them.

	A ring exists once the player's save has loaded; until then every request is
	refused with "NotReady". The ring Part (tagged PowerRing) is welded to the
	right hand of every character; beams start there.

	API:
	  RingService:CanUse(player, powerId, minWillpower): (boolean, PowerRejectReason?)
	  RingService:TrySpend(player, powerId, minWillpower, willpowerCost, chargeCost): (boolean, PowerRejectReason?)
	  RingService:Drain(player, willpower, charge): boolean       (continuous costs; false = ran out)
	  RingService:StartCooldown(player, powerId, seconds)
	  RingService:IsOnCooldown(player, powerId): boolean
	  RingService:SetBlocked(player, reason, blocked)
	  RingService:IsBlocked(player): boolean
	  RingService:GetWillpower(player): number
	  RingService:GetCharge(player): number
	  RingService:GetStrength(player): number                     (construct multiplier, see Config.Ring.Strength)
	  RingService:Refill(player, refillWillpower)                 (battery: full charge)
	  RingService:GetRingPart(player): BasePart?
	  RingService.Depleted   Signal(player, "Willpower" | "Charge")   (just hit zero: stop continuous powers)
	  RingService.RingReady  Signal(player)                          (ring state created after the save loaded)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local RingConfig = require(Shared.Config.Ring)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Util.Signal)
local TagsModule = require(Shared.Util.Tags)
local Text = require(Shared.Config.Text)
local Types = require(Shared.Types)

local Characters = require(script.Parent.Characters)
local DataService = require(script.Parent.DataService)

local Tags = TagsModule.Tags
local Attributes = TagsModule.Attributes

export type Resource = "Willpower" | "Charge"

type RingState = {
	-- The loaded save; Ring.Charge is kept in sync with `charge`.
	data: Types.PlayerData,
	willpower: number,
	charge: number,
	-- os.clock() of the last willpower spend (regeneration waits RegenDelay after it).
	lastSpend: number,
	-- os.clock() when each power is ready again.
	cooldowns: { [Types.PowerId]: number },
	-- Reasons currently blocking every power (set by other services).
	blocks: { [string]: boolean },
	-- Low-charge warning already shown since the last recharge.
	lowWarned: boolean,
	-- Last values written to the attributes (to only send changes).
	sentWillpower: number,
	sentCharge: number,
}

local states: { [Player]: RingState } = {}
local ringParts: { [Player]: BasePart } = {}

local RingService = {
	Depleted = Signal.new() :: Signal.Signal<Player, Resource>,
	RingReady = Signal.new() :: Signal.Signal<Player>,
}

-- Attribute values are rounded so tiny regen steps do not each replicate.
local function round(value: number): number
	return math.floor(value * 10 + 0.5) / 10
end

local function publish(player: Player, state: RingState, force: boolean?)
	local willpower = round(state.willpower)
	local charge = round(state.charge)
	if force or willpower ~= state.sentWillpower then
		state.sentWillpower = willpower
		player:SetAttribute(Attributes.Willpower, willpower)
	end
	if force or charge ~= state.sentCharge then
		state.sentCharge = charge
		player:SetAttribute(Attributes.RingCharge, charge)
	end
end

local function setCharge(player: Player, state: RingState, value: number)
	local before = state.charge
	state.charge = math.clamp(value, 0, RingConfig.Charge.Max)
	state.data.Ring.Charge = state.charge

	if state.charge <= RingConfig.Charge.LowThreshold and state.charge > 0 and not state.lowWarned then
		state.lowWarned = true
		Remotes.Notify:FireClient(player, Text.Ring.Low, "Warning")
	end
	if before > 0 and state.charge <= 0 then
		Remotes.Notify:FireClient(player, Text.Ring.Depleted, "Warning")
		local ring: BasePart? = ringParts[player]
		if ring ~= nil then
			Remotes.PowerEffect:FireAll("RingDepleted", ring.Position, 1)
		end
		RingService.Depleted:Fire(player, "Charge")
	end
end

local function spendWillpower(player: Player, state: RingState, amount: number)
	if amount <= 0 then
		return
	end
	local before = state.willpower
	state.willpower = math.max(0, state.willpower - amount)
	state.lastSpend = os.clock()
	if before > 0 and state.willpower <= 0 then
		RingService.Depleted:Fire(player, "Willpower")
	end
end

local function hasLivingCharacter(player: Player): boolean
	return Characters.GetRootPart(player, true) ~= nil
end

-- Ring part ------------------------------------------------------------------

local function buildRing(hand: BasePart): BasePart
	local visual = RingConfig.Visual

	-- The band is a short cylinder whose axis runs along the finger (the hand's
	-- down direction), sitting at the bottom of the hand where the fingers are.
	local band = Instance.new("Part")
	band.Name = "PowerRing"
	band.Shape = Enum.PartType.Cylinder
	band.Size = Vector3.new(visual.BandWidth, visual.BandDiameter, visual.BandDiameter)
	band.Material = Enum.Material.Neon
	band.Color = visual.Color
	band.CanCollide = false
	band.CanQuery = false
	band.CanTouch = false
	band.Massless = true
	band.CastShadow = false
	-- Cylinder axis is the part's X axis: turn it to point along the hand's Y axis.
	band.CFrame = hand.CFrame
		* CFrame.new(0, -hand.Size.Y / 2 + visual.BandWidth / 2, -hand.Size.Z * 0.15)
		* CFrame.Angles(0, 0, math.rad(90))

	local stone = Instance.new("Part")
	stone.Name = "Stone"
	stone.Size = Vector3.new(visual.StoneSize, visual.StoneSize, visual.StoneSize)
	stone.Material = Enum.Material.Neon
	stone.Color = visual.Color
	stone.CanCollide = false
	stone.CanQuery = false
	stone.CanTouch = false
	stone.Massless = true
	stone.CastShadow = false
	-- On the back of the finger (the hand's -Z side faces forward on R15/R6 rigs).
	stone.CFrame = band.CFrame * CFrame.new(0, 0, -visual.BandDiameter / 2)
	stone.Parent = band

	local stoneWeld = Instance.new("WeldConstraint")
	stoneWeld.Part0 = band
	stoneWeld.Part1 = stone
	stoneWeld.Parent = band

	local light = Instance.new("PointLight")
	light.Color = visual.Color
	light.Range = visual.LightRange
	light.Brightness = visual.LightBrightness
	light.Shadows = false
	light.Parent = band

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = band
	weld.Parent = band

	band:AddTag(Tags.PowerRing)
	return band
end

local function attachRing(player: Player, character: Model)
	if Characters.WaitForRootPart(character, 10) == nil then
		return
	end
	-- R15 has a RightHand; R6 only a "Right Arm" whose bottom is the hand.
	local hand = character:WaitForChild("RightHand", 5) or character:FindFirstChild("Right Arm")
	if hand == nil or not hand:IsA("BasePart") or player.Character ~= character then
		return
	end
	local existing: BasePart? = ringParts[player]
	if existing ~= nil then
		existing:Destroy()
	end
	local ring = buildRing(hand)
	ring.Parent = character
	ringParts[player] = ring
end

-- Lifecycle ------------------------------------------------------------------

local function createState(player: Player, data: Types.PlayerData)
	local charge = math.clamp(data.Ring.Charge, 0, RingConfig.Charge.Max)
	local state: RingState = {
		data = data,
		willpower = RingConfig.Willpower.Max,
		charge = charge,
		lastSpend = 0,
		cooldowns = {},
		blocks = {},
		-- Do not warn again on join for a ring that was already low when saved.
		lowWarned = charge <= RingConfig.Charge.LowThreshold,
		sentWillpower = -1,
		sentCharge = -1,
	}
	states[player] = state
	player:SetAttribute(Attributes.WillpowerMax, RingConfig.Willpower.Max)
	player:SetAttribute(Attributes.RingChargeMax, RingConfig.Charge.Max)
	publish(player, state, true)
	RingService.RingReady:Fire(player)
end

local function removePlayer(player: Player)
	states[player] = nil
	ringParts[player] = nil
end

-- Regenerates willpower and publishes attributes on a fixed interval.
local function startRegenLoop()
	local sinceAttributes = 0
	RunService.Heartbeat:Connect(function(deltaTime: number)
		local now = os.clock()
		local regen = RingConfig.Willpower.RegenPerSecond * deltaTime
		for _, state in states do
			if
				state.willpower < RingConfig.Willpower.Max
				and now - state.lastSpend >= RingConfig.Willpower.RegenDelay
			then
				state.willpower = math.min(RingConfig.Willpower.Max, state.willpower + regen)
			end
		end
		sinceAttributes += deltaTime
		if sinceAttributes >= RingConfig.AttributeUpdateInterval then
			sinceAttributes = 0
			for player, state in states do
				publish(player, state)
			end
		end
	end)
end

-- API ------------------------------------------------------------------------

-- Whether `player` may start `powerId` right now, and why not.
function RingService.CanUse(
	_self: RingService,
	player: Player,
	powerId: Types.PowerId,
	minWillpower: number
): (boolean, Types.PowerRejectReason?)
	local state = states[player]
	if state == nil or not hasLivingCharacter(player) then
		return false, "NotReady"
	end
	if next(state.blocks) ~= nil then
		return false, "Busy"
	end
	if state.charge <= 0 then
		return false, "NoCharge"
	end
	local readyAt = state.cooldowns[powerId]
	if readyAt ~= nil and os.clock() < readyAt then
		return false, "Cooldown"
	end
	if state.willpower < minWillpower then
		return false, "NoWillpower"
	end
	return true, nil
end

-- Checks CanUse and that the costs are affordable, then pays them. Returns
-- false (and the reason) without spending anything if the power can't be used.
function RingService.TrySpend(
	self: RingService,
	player: Player,
	powerId: Types.PowerId,
	minWillpower: number,
	willpowerCost: number,
	chargeCost: number
): (boolean, Types.PowerRejectReason?)
	local ok: boolean, reason: Types.PowerRejectReason? =
		self:CanUse(player, powerId, math.max(minWillpower, willpowerCost))
	if not ok then
		return false, reason
	end
	local state = states[player]
	spendWillpower(player, state, willpowerCost)
	setCharge(player, state, state.charge - chargeCost)
	publish(player, state)
	return true, nil
end

-- Continuous costs (per tick) for held powers. Pays what it can; returns false
-- once willpower or charge ran out (the caller should stop the power), or if
-- the player has no ring.
function RingService.Drain(_self: RingService, player: Player, willpower: number, charge: number): boolean
	local state = states[player]
	if state == nil then
		return false
	end
	spendWillpower(player, state, willpower)
	setCharge(player, state, state.charge - charge)
	return state.willpower > 0 and state.charge > 0
end

function RingService.StartCooldown(_self: RingService, player: Player, powerId: Types.PowerId, seconds: number)
	local state = states[player]
	if state == nil or seconds <= 0 then
		return
	end
	state.cooldowns[powerId] = os.clock() + seconds
	player:SetAttribute(Attributes.CooldownPrefix .. powerId, Workspace:GetServerTimeNow() + seconds)
end

function RingService.IsOnCooldown(_self: RingService, player: Player, powerId: Types.PowerId): boolean
	local state = states[player]
	local readyAt = if state ~= nil then state.cooldowns[powerId] else nil
	return readyAt ~= nil and os.clock() < readyAt
end

-- Blocks (or unblocks) every power for `reason`. Powers stay blocked while any
-- reason is set. The caller is responsible for stopping powers already active.
function RingService.SetBlocked(_self: RingService, player: Player, reason: string, blocked: boolean)
	local state = states[player]
	if state == nil then
		return
	end
	if blocked then
		state.blocks[reason] = true
	else
		state.blocks[reason] = nil
	end
end

function RingService.IsBlocked(_self: RingService, player: Player): boolean
	local state = states[player]
	return state ~= nil and next(state.blocks) ~= nil
end

function RingService.GetWillpower(_self: RingService, player: Player): number
	local state = states[player]
	return if state ~= nil then state.willpower else 0
end

function RingService.GetCharge(_self: RingService, player: Player): number
	local state = states[player]
	return if state ~= nil then state.charge else 0
end

-- Construct strength multiplier from current willpower (Config.Ring.Strength).
function RingService.GetStrength(_self: RingService, player: Player): number
	local state = states[player]
	if state == nil then
		return RingConfig.Strength.MinMultiplier
	end
	local strength = RingConfig.Strength
	local fraction = state.willpower / RingConfig.Willpower.Max
	local t = math.clamp(fraction / strength.FullAtWillpowerFraction, 0, 1)
	return strength.MinMultiplier + (1 - strength.MinMultiplier) * t
end

-- Fills the ring (the battery). Optionally refills willpower too.
function RingService.Refill(_self: RingService, player: Player, refillWillpower: boolean)
	local state = states[player]
	if state == nil then
		return
	end
	setCharge(player, state, RingConfig.Charge.Max)
	state.lowWarned = false
	if refillWillpower then
		state.willpower = RingConfig.Willpower.Max
	end
	publish(player, state)
end

-- Sets charge directly (used while the battery fills it gradually).
function RingService.SetCharge(_self: RingService, player: Player, value: number)
	local state = states[player]
	if state == nil then
		return
	end
	setCharge(player, state, value)
	if value >= RingConfig.Charge.Max then
		state.lowWarned = false
	end
	publish(player, state)
end

function RingService.GetRingPart(_self: RingService, player: Player): BasePart?
	local ring: BasePart? = ringParts[player]
	if ring ~= nil and ring.Parent ~= nil then
		return ring
	end
	return nil
end

function RingService.Init(_self: RingService)
	DataService.ProfileLoaded:Connect(createState)
	DataService.ProfileReleased:Connect(removePlayer)
end

function RingService.Start(_self: RingService)
	startRegenLoop()

	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character: Model)
			attachRing(player, character)
		end)
		local character = player.Character
		if character ~= nil then
			task.spawn(attachRing, player, character)
		end
		-- The save may have loaded before this service started listening.
		local data = DataService:GetData(player)
		if data ~= nil and states[player] == nil then
			createState(player, data)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(removePlayer)
end

export type RingService = typeof(RingService)

return RingService
