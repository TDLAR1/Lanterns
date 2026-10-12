--!strict
--[[
	ZoneController: the district the player is in, and which districts they have
	discovered, as told by the server.

	The server decides both (ZoneService): it sets the LocalPlayer attribute
	Attributes.PlayerDistrict and fires Remotes.DistrictDiscovered. This
	controller only follows along and presents them:
	  * Entering a different district shows its name as a banner. Dying and
	    respawning in the same district does not (the attribute goes nil and back).
	  * A first discovery shows a success toast with the server's count.

	The discovered set starts from the save summary (ProfileController) and grows
	with each discovery event; either may arrive first.

	API:
	  ZoneController:GetCurrentDistrict(): string?
	  ZoneController:GetDiscovered(): { [districtId]: true }   (a copy)
	  ZoneController:IsDiscovered(districtId): boolean
	  ZoneController:GetDiscoveredCount(): number   (districts in Config.World.Districts only)
	  ZoneController.DistrictChanged    Signal(districtId?)
	  ZoneController.DiscoveredChanged  Signal()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Util.Signal)
local TagsModule = require(Shared.Util.Tags)
local Text = require(Shared.Config.Text)
local Types = require(Shared.Types)
local WorldConfig = require(Shared.Config.World)

local NotificationController = require(script.Parent.NotificationController)
local ProfileController = require(script.Parent.ProfileController)

local Attributes = TagsModule.Attributes
local LocalPlayer = Players.LocalPlayer

local districtsById: { [string]: Types.DistrictInfo } = {}
for _, district in WorldConfig.Districts do
	districtsById[district.Id] = district
end

local discovered: { [string]: boolean } = {}
local currentDistrict: string? = nil
-- The district whose banner was shown last. Kept while the attribute is nil
-- (dead / respawning) so coming back to the same district stays quiet.
local lastBannerDistrict: string? = nil

local ZoneController = {
	-- The player entered another district, or left every district (nil). (districtId?)
	DistrictChanged = Signal.new() :: Signal.Signal<string?>,
	-- The set of discovered districts grew.
	DiscoveredChanged = Signal.new() :: Signal.Signal<()>,
}

local function readDistrictAttribute(): string?
	local value = LocalPlayer:GetAttribute(Attributes.PlayerDistrict)
	return if type(value) == "string" and value ~= "" then value else nil
end

local function onDistrictAttributeChanged()
	local districtId = readDistrictAttribute()
	if districtId == currentDistrict then
		return
	end
	currentDistrict = districtId
	ZoneController.DistrictChanged:Fire(districtId)

	if districtId == nil or districtId == lastBannerDistrict then
		return
	end
	local info = districtsById[districtId]
	if info ~= nil then
		lastBannerDistrict = districtId
		NotificationController:ShowBanner(info.DisplayName, info.Subtitle)
	end
end

local function addDiscovered(ids: { string })
	local changed = false
	for _, id in ids do
		if not discovered[id] then
			discovered[id] = true
			changed = true
		end
	end
	if changed then
		ZoneController.DiscoveredChanged:Fire()
	end
end

local function onDistrictDiscovered(districtId: Types.DistrictId, discoveredCount: number, totalCount: number)
	if type(districtId) ~= "string" then
		return
	end
	addDiscovered({ districtId })
	local info = districtsById[districtId]
	local name = if info ~= nil then info.DisplayName else districtId
	-- The counts are the server's: it alone knows the saved total.
	if type(discoveredCount) == "number" and type(totalCount) == "number" then
		NotificationController:Notify(
			string.format(Text.DistrictDiscovered, name, discoveredCount, totalCount),
			"Success"
		)
	end
end

function ZoneController.GetCurrentDistrict(_self: ZoneController): string?
	return currentDistrict
end

-- A copy of the discovered set (district id -> true).
function ZoneController.GetDiscovered(_self: ZoneController): { [string]: boolean }
	return table.clone(discovered)
end

function ZoneController.IsDiscovered(_self: ZoneController, districtId: string): boolean
	return discovered[districtId] == true
end

function ZoneController.GetDiscoveredCount(_self: ZoneController): number
	local count = 0
	for _, district in WorldConfig.Districts do
		if discovered[district.Id] then
			count += 1
		end
	end
	return count
end

function ZoneController.Init(_self: ZoneController)
	-- Connected in Init so nothing sent while other controllers start is missed.
	Remotes.DistrictDiscovered:Connect(onDistrictDiscovered)
	ProfileController.SummaryLoaded:Connect(function(summary: Types.ProfileSummary)
		addDiscovered(summary.DiscoveredDistricts)
	end)
	LocalPlayer:GetAttributeChangedSignal(Attributes.PlayerDistrict):Connect(onDistrictAttributeChanged)
end

function ZoneController.Start(_self: ZoneController)
	local summary = ProfileController:GetSummary()
	if summary ~= nil then
		addDiscovered(summary.DiscoveredDistricts)
	end
	-- The server may have set the district before this script ran.
	onDistrictAttributeChanged()
end

export type ZoneController = typeof(ZoneController)

return ZoneController
