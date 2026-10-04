-- Collision geometry: everything solid in a level as a box turned to any
-- angle about the vertical, whose top is flat, a ramp or an arch. Pure
-- functions over plain tables, so the world, the level checker and the
-- tests share them.
--
-- A solid is its centre (`cx`, `cz`), turn (`c`, `s`: cosine and sine of
-- its yaw), half width and depth in its own frame (`hw`, `hd`), bottom and
-- highest top (`y0`, `y1`), and shape. A ramp rises from `low` at its local
-- +z edge to the full height at -z (the kit's slopes and wooden ramps); an
-- arch bows up along its local x from `low` at its ends (the kit's curves).
-- `x0..x1`, `z0..z1` bound it, for a quick rejection.
local Terrain = {}

-- Turns a local vector by `yaw` degrees about the vertical, as SceneKit
-- turns a node.
local function turn(x, z, c, s)
	return x * c + z * s, -x * s + z * c
end

-- A solid standing at (x, y, z), turned by `yaw` degrees. `size` gives
-- `w`, `d`, `h`, and optionally `shape`, `low` (height of the low end) and
-- `ox`, `oz` (where the box sits in the piece's own frame, for a fence along
-- one edge).
function Terrain.solid(x, y, z, size, yaw)
	local r = math.rad(yaw or 0)
	local c, s = math.cos(r), math.sin(r)
	local ox, oz = turn(size.ox or 0, size.oz or 0, c, s)
	local solid = {cx = x + ox, cz = z + oz, c = c, s = s, hw = size.w / 2, hd = size.d / 2, y0 = y, y1 = y + size.h,
		shape = size.shape or "box", low = y + (size.low or size.h)}
	local ex = math.abs(c) * solid.hw + math.abs(s) * solid.hd
	local ez = math.abs(s) * solid.hw + math.abs(c) * solid.hd
	solid.x0, solid.x1, solid.z0, solid.z1 = solid.cx - ex, solid.cx + ex, solid.cz - ez, solid.cz + ez
	return solid
end

-- A world point in the solid's own frame.
function Terrain.localPoint(solid, x, z)
	local dx, dz = x - solid.cx, z - solid.cz
	return dx * solid.c - dz * solid.s, dx * solid.s + dz * solid.c
end

function Terrain.contains(solid, x, z, margin)
	margin = margin or 0
	if x < solid.x0 - margin or x > solid.x1 + margin or z < solid.z0 - margin or z > solid.z1 + margin then
		return false
	end
	local lx, lz = Terrain.localPoint(solid, x, z)
	return math.abs(lx) <= solid.hw + margin and math.abs(lz) <= solid.hd + margin
end

-- The height of the solid's top above (x, z), clamped into its footprint.
function Terrain.top(solid, x, z)
	if solid.shape == "box" then return solid.y1 end
	local lx, lz = Terrain.localPoint(solid, x, z)
	lx = math.max(-solid.hw, math.min(solid.hw, lx))
	lz = math.max(-solid.hd, math.min(solid.hd, lz))
	if solid.shape == "ramp" then
		return solid.low + (solid.y1 - solid.low) * (1 - lz / solid.hd) / 2
	end
	local u = lx / solid.hw
	return solid.y1 - (solid.y1 - solid.low) * u * u
end

-- The four corners of the footprint, in order round it.
function Terrain.corners(solid)
	local points = {}
	for _, corner in ipairs({{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}) do
		local x, z = turn(corner[1] * solid.hw, corner[2] * solid.hd, solid.c, solid.s)
		table.insert(points, {solid.cx + x, solid.cz + z})
	end
	return points
end

-- The highest top under (x, z) no higher than `below`, within `margin` of a
-- footprint, and the solid it belongs to. Nil over water.
function Terrain.ground(solids, x, z, below, margin)
	local best, owner
	for _, solid in ipairs(solids) do
		if Terrain.contains(solid, x, z, margin) then
			local top = Terrain.top(solid, x, z)
			if top <= below and (not best or top > best) then best, owner = top, solid end
		end
	end
	return best, owner
end

-- The solid a body of `radius` and `height` standing at (x, y, z) runs
-- into: one overlapping it that rises more than `step` above its feet.
function Terrain.blocked(solids, x, y, z, radius, height, step)
	for _, solid in ipairs(solids) do
		if solid.y0 < y + height and Terrain.contains(solid, x, z, radius) and Terrain.top(solid, x, z) > y + step then
			return solid
		end
	end
end

-- The underside a body rising from `from` to `to` (its head) bumps.
function Terrain.ceiling(solids, x, z, from, to, radius)
	for _, solid in ipairs(solids) do
		if solid.y0 >= from and solid.y0 < to and Terrain.contains(solid, x, z, radius) then return solid end
	end
end

return Terrain
