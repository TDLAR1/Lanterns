--!strict
--[[
	Boundary: where a position sits relative to the edge of the play area
	(Config.World.Boundary). Shared so the client (soft push-back, warning UI,
	flight steering) and the server (hard enforcement) use the same numbers.
]]

local World = require(script.Parent.Parent.Config.World)

export type BoundaryState = {
	-- 0 = comfortably inside. 0..1 = inside the soft band (1 = at the hard edge).
	-- Above 1 = past the hard edge.
	Depth: number,
	-- Unit direction back toward the play area; Vector3.zero when Depth is 0.
	Inward: Vector3,
	-- The nearest position that is inside the hard edge and below the ceiling.
	Clamped: Vector3,
}

local Boundary = {}

-- How far into the soft band one axis is (0 = not in it), and which way is "back in".
local function axisDepth(value: number, halfSize: number, margin: number): (number, number)
	local over = math.abs(value) - (halfSize - margin)
	if over <= 0 then
		return 0, 0
	end
	return over / margin, -math.sign(value)
end

function Boundary.Evaluate(position: Vector3): BoundaryState
	local config = World.Boundary
	local depthX, signX = axisDepth(position.X, config.HalfSizeX, config.SoftMargin)
	local depthZ, signZ = axisDepth(position.Z, config.HalfSizeZ, config.SoftMargin)
	local overCeiling = position.Y - (config.Ceiling - config.CeilingSoftMargin)
	local depthY = if overCeiling > 0 then overCeiling / config.CeilingSoftMargin else 0

	local inward = Vector3.new(signX * depthX, -depthY, signZ * depthZ)
	if inward.Magnitude > 0 then
		inward = inward.Unit
	end

	return {
		Depth = math.max(depthX, depthY, depthZ),
		Inward = inward,
		Clamped = Vector3.new(
			math.clamp(position.X, -config.HalfSizeX, config.HalfSizeX),
			math.min(position.Y, config.Ceiling),
			math.clamp(position.Z, -config.HalfSizeZ, config.HalfSizeZ)
		),
	}
end

-- True if `position` is more than `tolerance` studs past the hard edge or ceiling.
function Boundary.IsBeyond(position: Vector3, tolerance: number): boolean
	local config = World.Boundary
	return math.abs(position.X) > config.HalfSizeX + tolerance
		or math.abs(position.Z) > config.HalfSizeZ + tolerance
		or position.Y > config.Ceiling + tolerance
end

return Boundary
