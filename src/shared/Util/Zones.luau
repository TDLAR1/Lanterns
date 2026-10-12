--!strict
--[[
	Zones: point-in-district math for the invisible zone volumes.

	A zone volume is an anchored, invisible Part tagged DistrictZone with a
	DistrictId attribute (and optional Priority). Zones may be rotated and may
	overlap; where they overlap the higher Priority wins, then the smaller one.
	Part CFrame/Size are read live, so resizing a zone in Studio just works.
]]

local TagsModule = require(script.Parent.Tags)

local Attributes = TagsModule.Attributes

export type ZoneVolume = {
	Part: BasePart,
	DistrictId: string,
	Priority: number,
}

local Zones = {}

-- Reads a zone Part's attributes. Returns nil (with a warning) if it is misconfigured.
function Zones.FromPart(part: BasePart): ZoneVolume?
	local districtId = part:GetAttribute(Attributes.DistrictId)
	if type(districtId) ~= "string" or districtId == "" then
		warn(`[Zones] {part:GetFullName()} is tagged as a zone but has no {Attributes.DistrictId} attribute`)
		return nil
	end
	local priority = part:GetAttribute(Attributes.Priority)
	return {
		Part = part,
		DistrictId = districtId,
		Priority = if type(priority) == "number" then priority else 0,
	}
end

function Zones.Contains(zone: ZoneVolume, position: Vector3): boolean
	local localPoint = zone.Part.CFrame:PointToObjectSpace(position)
	local half = zone.Part.Size / 2
	return math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y and math.abs(localPoint.Z) <= half.Z
end

-- The zone that owns `position`, or nil if it is in none.
function Zones.Resolve(zones: { ZoneVolume }, position: Vector3): ZoneVolume?
	local best: ZoneVolume? = nil
	local bestVolume = math.huge
	for _, zone in zones do
		if zone.Part.Parent ~= nil and Zones.Contains(zone, position) then
			local size = zone.Part.Size
			local volume = size.X * size.Y * size.Z
			if best == nil or zone.Priority > best.Priority or (zone.Priority == best.Priority and volume < bestVolume) then
				best = zone
				bestVolume = volume
			end
		end
	end
	return best
end

return Zones
