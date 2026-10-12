return function(t, ctx)
	local Boundary = ctx.require(ctx.shared.Util.Boundary)
	local World = ctx.require(ctx.shared.Config.World)
	local Vector3 = ctx.roblox.Vector3
	local config = World.Boundary

	t.test("deep inside the play area has no depth", function()
		local state = Boundary.Evaluate(Vector3.new(0, 50, 0))
		t.near(state.Depth, 0, 1e-6, "depth")
		t.expect(state.Inward.Magnitude == 0, "no inward push")
	end)

	t.test("soft band depth and inward direction", function()
		local x = config.HalfSizeX - config.SoftMargin / 2
		local state = Boundary.Evaluate(Vector3.new(x, 10, 0))
		t.near(state.Depth, 0.5, 1e-6, "halfway into the band")
		t.near(state.Inward.X, -1, 1e-6, "pushes back toward -X")
	end)

	t.test("past the edge is clamped back inside", function()
		local state = Boundary.Evaluate(Vector3.new(-(config.HalfSizeX + 100), 10, config.HalfSizeZ + 50))
		t.expect(state.Depth > 1, "depth beyond 1")
		t.near(state.Clamped.X, -config.HalfSizeX, 1e-6, "clamped X")
		t.near(state.Clamped.Z, config.HalfSizeZ, 1e-6, "clamped Z")
		t.expect(state.Inward.X > 0 and state.Inward.Z < 0, "inward points back to the centre")
	end)

	t.test("ceiling works like an edge", function()
		local state = Boundary.Evaluate(Vector3.new(0, config.Ceiling + 10, 0))
		t.expect(state.Depth > 1, "above the ceiling")
		t.near(state.Clamped.Y, config.Ceiling, 1e-6, "clamped to ceiling")
		t.expect(state.Inward.Y < 0, "pushes down")
	end)

	t.test("IsBeyond uses the tolerance", function()
		local edge = config.HalfSizeX
		t.expect(not Boundary.IsBeyond(Vector3.new(edge + 10, 0, 0), 50), "within tolerance")
		t.expect(Boundary.IsBeyond(Vector3.new(edge + 60, 0, 0), 50), "beyond tolerance")
	end)
end
