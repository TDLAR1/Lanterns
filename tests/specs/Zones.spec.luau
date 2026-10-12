return function(t, ctx)
	local Zones = ctx.require(ctx.shared.Util.Zones)
	local roblox = ctx.roblox
	local Vector3, CFrame = roblox.Vector3, roblox.CFrame

	local function zonePart(districtId: string, center, size, priority: number?, yaw: number?)
		local part = roblox.Instance.new("Part")
		part.Size = size
		part.CFrame = CFrame.new(center) * CFrame.Angles(0, math.rad(yaw or 0), 0)
		part:SetAttribute("DistrictId", districtId)
		if priority then
			part:SetAttribute("Priority", priority)
		end
		-- Zones skip parts that are no longer in the world (Parent == nil).
		part.Parent = roblox.Instance.new("Folder")
		return part
	end

	t.test("FromPart reads attributes and rejects untagged parts", function()
		local zone = Zones.FromPart(zonePart("Downtown", Vector3.zero, Vector3.new(10, 10, 10), 5))
		t.expect(zone and zone.DistrictId == "Downtown" and zone.Priority == 5, "parsed")
		local bare = roblox.Instance.new("Part")
		t.expect(Zones.FromPart(bare) == nil, "missing DistrictId -> nil")
	end)

	t.test("higher priority wins, then the smaller zone", function()
		local outer = Zones.FromPart(zonePart("OuterRing", Vector3.zero, Vector3.new(1000, 100, 1000), 0))
		local town = Zones.FromPart(zonePart("Downtown", Vector3.zero, Vector3.new(100, 100, 100), 10))
		local small = Zones.FromPart(zonePart("RailYard", Vector3.new(10, 0, 0), Vector3.new(20, 100, 20), 10))
		local zones = { outer, town, small }
		t.expect(Zones.Resolve(zones, Vector3.new(400, 0, 0)).DistrictId == "OuterRing", "only outer")
		t.expect(Zones.Resolve(zones, Vector3.new(-40, 0, 0)).DistrictId == "Downtown", "priority")
		t.expect(Zones.Resolve(zones, Vector3.new(12, 0, 0)).DistrictId == "RailYard", "same priority, smaller")
		t.expect(Zones.Resolve(zones, Vector3.new(0, 0, 900)) == nil, "outside everything")
	end)

	t.test("rotated zones use their own axes", function()
		local zone = Zones.FromPart(zonePart("Farmstead", Vector3.zero, Vector3.new(100, 10, 10), 0, 90))
		-- Rotated 90 degrees, the long side now runs along Z.
		t.expect(Zones.Contains(zone, Vector3.new(0, 0, 45)), "inside along Z")
		t.expect(not Zones.Contains(zone, Vector3.new(45, 0, 0)), "outside along X")
	end)
end
