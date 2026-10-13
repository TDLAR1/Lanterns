--!strict
--[[
	RingController: the local player's power ring as the server reports it.

	RingService (server) is the one authority over willpower, ring charge and
	cooldowns. It mirrors them to the LocalPlayer as attributes (Util/Tags
	Attributes: Willpower, WillpowerMax, RingCharge, RingChargeMax, Recharging,
	CooldownEnd_<PowerId>, ...), and this controller only reads them, for the
	HUD and for instant feedback. CanAttempt mirrors RingService:CanUse so a
	power the server would refuse is refused on the spot; the server still
	decides every request.

	API:
	  RingController:IsReady(): boolean            (the ring exists: its attributes arrived)
	  RingController:GetWillpower(): number
	  RingController:GetWillpowerMax(): number
	  RingController:GetCharge(): number
	  RingController:GetChargeMax(): number
	  RingController:GetCooldownRemaining(powerId): number   (seconds, 0 when ready)
	  RingController:GetStrength(): number         (construct multiplier, Config.Ring.Strength)
	  RingController:CanAttempt(powerId, minWillpower): (boolean, PowerRejectReason?)
	  RingController:HasLivingCharacter(): boolean
	  RingController.Changed  Signal()             (any ring attribute changed, or the character
	                                                spawned / died)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local RingConfig = require(Shared.Config.Ring)
local Signal = require(Shared.Util.Signal)
local TagsModule = require(Shared.Util.Tags)
local Types = require(Shared.Types)

local Attributes = TagsModule.Attributes
local LocalPlayer = Players.LocalPlayer

-- Every standard Humanoid rig (R6, R15, custom StarterCharacter) names its root this.
local ROOT_PART_NAME = "HumanoidRootPart"

-- Attributes whose changes matter to anything that shows or checks the ring.
local WATCHED: { [string]: boolean } = {
	[Attributes.Willpower] = true,
	[Attributes.WillpowerMax] = true,
	[Attributes.RingCharge] = true,
	[Attributes.RingChargeMax] = true,
	[Attributes.Recharging] = true,
	[Attributes.Shielding] = true,
	[Attributes.BeamActive] = true,
	[Attributes.Flying] = true,
	[Attributes.Boosting] = true,
}

local characterConnections: { RBXScriptConnection } = {}

local RingController = {
	-- Something the ring state depends on changed.
	Changed = Signal.new() :: Signal.Signal<()>,
}

local function readNumber(name: string): number?
	local value = LocalPlayer:GetAttribute(name)
	-- NaN is the only value not equal to itself.
	if type(value) == "number" and value == value then
		return value
	end
	return nil
end

local function fireChanged()
	RingController.Changed:Fire()
end

local function disconnectCharacter()
	for _, connection in characterConnections do
		connection:Disconnect()
	end
	table.clear(characterConnections)
end

local function watchCharacter(character: Model)
	disconnectCharacter()
	table.insert(
		characterConnections,
		character.ChildAdded:Connect(function(child: Instance)
			-- The Humanoid and root can arrive after the character itself.
			if child:IsA("Humanoid") or child.Name == ROOT_PART_NAME then
				fireChanged()
				if child:IsA("Humanoid") then
					table.insert(characterConnections, child.Died:Connect(fireChanged))
				end
			end
		end)
	)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		table.insert(characterConnections, humanoid.Died:Connect(fireChanged))
	end
	fireChanged()
end

function RingController.IsReady(_self: RingController): boolean
	return readNumber(Attributes.Willpower) ~= nil and readNumber(Attributes.RingCharge) ~= nil
end

function RingController.GetWillpower(_self: RingController): number
	return readNumber(Attributes.Willpower) or 0
end

function RingController.GetWillpowerMax(_self: RingController): number
	local value = readNumber(Attributes.WillpowerMax)
	return if value ~= nil and value > 0 then value else RingConfig.Willpower.Max
end

function RingController.GetCharge(_self: RingController): number
	return readNumber(Attributes.RingCharge) or 0
end

function RingController.GetChargeMax(_self: RingController): number
	local value = readNumber(Attributes.RingChargeMax)
	return if value ~= nil and value > 0 then value else RingConfig.Charge.Max
end

function RingController.GetCooldownRemaining(_self: RingController, powerId: Types.PowerId): number
	local readyAt = readNumber(Attributes.CooldownPrefix .. powerId)
	if readyAt == nil then
		return 0
	end
	return math.max(0, readyAt - Workspace:GetServerTimeNow())
end

-- Mirror of RingService:GetStrength from the replicated willpower.
function RingController.GetStrength(self: RingController): number
	local strength = RingConfig.Strength
	local fraction = self:GetWillpower() / self:GetWillpowerMax()
	local t = math.clamp(fraction / strength.FullAtWillpowerFraction, 0, 1)
	return strength.MinMultiplier + (1 - strength.MinMultiplier) * t
end

function RingController.HasLivingCharacter(_self: RingController): boolean
	local character = LocalPlayer.Character
	if character == nil or not character:IsDescendantOf(Workspace) then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and character:FindFirstChild(ROOT_PART_NAME) ~= nil
end

-- Client mirror of RingService:CanUse, in the same order, from the attributes.
-- Only for instant feedback: the server checks every request again.
function RingController.CanAttempt(
	self: RingController,
	powerId: Types.PowerId,
	minWillpower: number
): (boolean, Types.PowerRejectReason?)
	if not self:IsReady() or not self:HasLivingCharacter() then
		return false, "NotReady"
	end
	-- The battery's oath is the one block the client can see; others (being
	-- caged) are only known to the server, which answers with Busy itself.
	if LocalPlayer:GetAttribute(Attributes.Recharging) == true then
		return false, "Busy"
	end
	if self:GetCharge() <= 0 then
		return false, "NoCharge"
	end
	if self:GetCooldownRemaining(powerId) > 0 then
		return false, "Cooldown"
	end
	if self:GetWillpower() < minWillpower then
		return false, "NoWillpower"
	end
	return true, nil
end

function RingController.Init(_self: RingController)
	LocalPlayer.AttributeChanged:Connect(function(name: string)
		if WATCHED[name] or string.sub(name, 1, #Attributes.CooldownPrefix) == Attributes.CooldownPrefix then
			fireChanged()
		end
	end)
	LocalPlayer.CharacterAdded:Connect(watchCharacter)
	LocalPlayer.CharacterRemoving:Connect(function()
		disconnectCharacter()
		fireChanged()
	end)
end

function RingController.Start(_self: RingController)
	local character = LocalPlayer.Character
	if character ~= nil then
		watchCharacter(character)
	end
end

export type RingController = typeof(RingController)

return RingController
