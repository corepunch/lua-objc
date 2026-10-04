-- Whether an authored level can be cleared: a graph of the surfaces the
-- hero can stand on, joined where a jump carries from one to the next.
--
-- The jump it allows is shorter and lower than the one the hero actually
-- has (World.RULES and tests/coin_quest.test.lua measure the real one), so
-- a level it passes is never tighter than it says. Every coin, star, heart,
-- key and checkpoint must be within a jump of a surface the hero reaches,
-- the flag must be reachable, and no surface the hero reaches may be a dead
-- end with no way back to the start. Saws, spikes and gates are timing and
-- order, not geometry.

local Terrain = require("apps.coin-quest.models.Terrain")

local Reach = {}

Reach.JUMP = {
	rise = 1.25, -- the highest ledge a jump reaches
	gap = 2.6, -- the widest gap between two surfaces at one height
	risePenalty = 0.6, -- less gap per unit climbed
	dropBonus = 0.6, -- more per unit dropped
	dropLimit = 4, -- up to this far down
	springRise = 3.8, -- a spring's throw
	springGap = 2.5,
	grab = 1.3, -- how far above a surface a jump takes an item
	near = 1.6, -- and how far beside it
}

-- Distance from a point to a segment.
local function toSegment(px, pz, a, b)
	local dx, dz = b[1] - a[1], b[2] - a[2]
	local t = ((px - a[1]) * dx + (pz - a[2]) * dz) / math.max(dx * dx + dz * dz, 1e-12)
	t = math.max(0, math.min(1, t))
	local x, z = a[1] + dx * t - px, a[2] + dz * t - pz
	return math.sqrt(x * x + z * z)
end

-- Whether a point is inside a convex footprint (corners in order).
local function inside(px, pz, corners)
	local sign = 0
	for i = 1, #corners do
		local a, b = corners[i], corners[i % #corners + 1]
		local cross = (b[1] - a[1]) * (pz - a[2]) - (b[2] - a[2]) * (px - a[1])
		if math.abs(cross) > 1e-9 then
			local this = cross > 0 and 1 or -1
			if sign ~= 0 and this ~= sign then return false end
			sign = this
		end
	end
	return true
end

-- The distance from a point to a footprint, 0 inside it.
local function toFootprint(px, pz, corners)
	if inside(px, pz, corners) then return 0 end
	local best = math.huge
	for i = 1, #corners do best = math.min(best, toSegment(px, pz, corners[i], corners[i % #corners + 1])) end
	return best
end

-- The distance between two footprints, 0 when they touch or overlap. For
-- convex shapes it is a corner of one to the other, unless an edge of one
-- crosses the other, when a corner lies inside or the distance is 0 anyway.
local function gap(a, b)
	local best = math.huge
	for _, p in ipairs(a.corners) do best = math.min(best, toFootprint(p[1], p[2], b.corners)) end
	for _, p in ipairs(b.corners) do best = math.min(best, toFootprint(p[1], p[2], a.corners)) end
	-- Two crossing footprints with no corner inside the other.
	if best > 0 and toFootprint((a.x0 + a.x1) / 2, (a.z0 + a.z1) / 2, b.corners) == 0 then best = 0 end
	return best
end

local function box(x0, x1, z0, z1)
	return {{x0, z0}, {x1, z0}, {x1, z1}, {x0, z1}}
end

local function covered(solid, solids)
	for _, other in ipairs(solids) do
		if other ~= solid and math.abs(other.y0 - solid.y1) < 1e-6 and other.x0 <= solid.x0 and other.x1 >= solid.x1
			and other.z0 <= solid.z0 and other.z1 >= solid.z1 then
			return true
		end
	end
end

-- Every surface: `{x0, x1, z0, z1, lo, hi, spring}`.
function Reach.surfaces(level)
	local surfaces = {}
	local springs = {}
	for _, spring in ipairs(level.spawns.springs) do springs[spring.solid] = true end
	for _, solid in ipairs(level.solids) do
		-- A tree is a wall, not a ledge.
		if not solid.trunk and not covered(solid, level.solids) then
			table.insert(surfaces, {x0 = solid.x0, x1 = solid.x1, z0 = solid.z0, z1 = solid.z1,
				corners = Terrain.corners(solid), lo = math.min(solid.low, solid.y1), hi = solid.y1, spring = springs[solid]})
		end
	end
	local sizes = require("apps.coin-quest.models.Level").SIZES
	for _, mover in ipairs(level.spawns.movers) do
		local w, d = sizes.mover.w / 2, sizes.mover.d / 2
		local x0, x1 = math.min(mover.x, mover.x2) - w, math.max(mover.x, mover.x2) + w
		local z0, z1 = math.min(mover.z, mover.z2) - d, math.max(mover.z, mover.z2) + d
		table.insert(surfaces, {x0 = x0, x1 = x1, z0 = z0, z1 = z1, corners = box(x0, x1, z0, z1),
			lo = math.min(mover.y, mover.y2), hi = math.max(mover.y, mover.y2)})
	end
	for _, plank in ipairs(level.spawns.planks) do
		local w = sizes.plank.w / 2
		table.insert(surfaces, {x0 = plank.x - w, x1 = plank.x + w, z0 = plank.z - w, z1 = plank.z + w,
			corners = box(plank.x - w, plank.x + w, plank.z - w, plank.z + w), lo = plank.y, hi = plank.y})
	end
	for _, gate in ipairs(level.spawns.gates) do
		local w = sizes.gate.w / 2
		table.insert(surfaces, {x0 = gate.x - w, x1 = gate.x + w, z0 = gate.z - w, z1 = gate.z + w,
			corners = box(gate.x - w, gate.x + w, gate.z - w, gate.z + w), lo = gate.y + sizes.gate.h, hi = gate.y + sizes.gate.h})
	end
	return surfaces
end

-- Whether a jump from surface `a` lands on surface `b`.
function Reach.jumps(a, b)
	local J = Reach.JUMP
	local rise = b.lo - a.hi
	local between = gap(a, b)
	if a.spring then return rise <= J.springRise and between <= J.springGap end
	if rise > J.rise then return false end
	if rise > 0 then return between <= J.gap - J.risePenalty * rise end
	return between <= J.gap + J.dropBonus * math.min(-rise, J.dropLimit)
end

local function within(surface, item)
	local J = Reach.JUMP
	return toFootprint(item.x, item.z, surface.corners) <= J.near and item.y - surface.hi <= J.grab
		and item.y >= surface.lo - J.dropLimit
end

-- The problems that make a level unclearable, as messages; empty when the
-- level is sound.
function Reach.problems(level)
	local problems = {}
	local surfaces = Reach.surfaces(level)
	local start = level.spawns.player
	local first
	for index, surface in ipairs(surfaces) do
		if start.y >= surface.lo - 1e-6 and start.y <= surface.hi + 1e-6 and inside(start.x, start.z, surface.corners) then
			first = first or index
		end
	end
	if not first then return {"the start is not on a surface"} end
	local function search(from, forward)
		local seen, queue, head = {[from] = true}, {from}, 1
		while queue[head] do
			local current = queue[head]
			head = head + 1
			for index, surface in ipairs(surfaces) do
				local ok = forward and Reach.jumps(surfaces[current], surface) or (not forward and Reach.jumps(surface, surfaces[current]))
				if not seen[index] and ok then
					seen[index] = true
					table.insert(queue, index)
				end
			end
		end
		return seen
	end
	local reached, home = search(first, true), search(first, false)
	local function need(list, what)
		for _, item in ipairs(list) do
			local ok = false
			for index in pairs(reached) do
				if within(surfaces[index], item) then ok = true end
			end
			if not ok then
				table.insert(problems, string.format("%s at %.1f, %.1f, %.1f cannot be reached", what, item.x, item.y, item.z))
			end
		end
	end
	local spawns = level.spawns
	need(spawns.coins, "coin")
	need(spawns.stars, "star")
	need(spawns.hearts, "heart")
	need(spawns.keys, "key")
	need(spawns.checkpoints, "checkpoint")
	need({spawns.flag}, "flag")
	for index in pairs(reached) do
		if not home[index] then
			local s = surfaces[index]
			table.insert(problems, string.format("dead end on the surface at %.1f, %.1f, %.1f",
				(s.x0 + s.x1) / 2, s.hi, (s.z0 + s.z1) / 2))
			break
		end
	end
	return problems
end

function Reach.clearable(level)
	return #Reach.problems(level) == 0
end

return Reach
