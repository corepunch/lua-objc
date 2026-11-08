-- What the hero stands on and walks into: one turned box per solid piece,
-- sized from the kit's manifest so collision matches what is drawn.
--
-- A piece stands on its `y` and turns by `yaw` degrees about its origin, as
-- its <Node> does. A ramp (a piece tagged "ramp") rises toward its -z edge:
-- full height there, a third of it at the +z edge.
local Ground = {}

local Kit = require("demo.playground.catalog.Kit").manifest

-- Pieces with these tags are solid; trees, flowers, signs and the like are
-- scenery the hero walks through.
Ground.SOLID = {ground = true, platform = true, ramp = true, overhang = true, container = true, boundary = true}

function Ground.isSolid(name)
	local entry = Kit[name]
	for _, tag in ipairs(entry and entry.tags or {}) do
		if Ground.SOLID[tag] then return true end
	end
	return false
end

-- The box of a placed piece `{name, x, y, z, yaw=, scale=}`.
function Ground.box(piece)
	local entry = assert(Kit[piece[1]], "no model named " .. tostring(piece[1]))
	local b, scale = entry.bounds, piece.scale or 1
	local isRamp = false
	for _, tag in ipairs(entry.tags or {}) do if tag == "ramp" then isRamp = true end end
	local yaw = math.rad(piece.yaw or 0)
	return {
		name = piece[1], x = piece[2], z = piece[4], cos = math.cos(yaw), sin = math.sin(yaw),
		minX = b[1] * scale, maxX = b[4] * scale, minZ = b[3] * scale, maxZ = b[6] * scale,
		bottom = piece[3] + b[2] * scale, top = piece[3] + b[5] * scale, ramp = isRamp,
	}
end

-- A world point in a box's own frame (undoing its yaw).
function Ground.toLocal(box, x, z)
	local dx, dz = x - box.x, z - box.z
	return dx * box.cos - dz * box.sin, dx * box.sin + dz * box.cos
end

function Ground.inside(box, x, z, margin)
	local lx, lz = Ground.toLocal(box, x, z)
	margin = margin or 0
	return lx >= box.minX - margin and lx <= box.maxX + margin and lz >= box.minZ - margin and lz <= box.maxZ + margin
end

-- The box's surface height at a world point inside it.
function Ground.topAt(box, x, z)
	if not box.ramp then return box.top end
	local _, lz = Ground.toLocal(box, x, z)
	local t = math.max(0, math.min(1, (lz - box.minZ) / (box.maxZ - box.minZ)))
	return box.top - (box.top - box.bottom) * t * 2 / 3
end

-- The highest surface under (x, z) no higher than `below`, or nil.
function Ground.height(boxes, x, z, below)
	local best
	for _, box in ipairs(boxes) do
		if Ground.inside(box, x, z, 0.05) then
			local top = Ground.topAt(box, x, z)
			if top <= below and (not best or top > best) then best = top end
		end
	end
	return best
end

-- Whether a body of `radius` at (x, z) from `feet` to `head` runs into a
-- box it cannot step onto.
function Ground.blocked(boxes, x, z, feet, head, radius, step)
	for _, box in ipairs(boxes) do
		if Ground.inside(box, x, z, radius) then
			local top = Ground.inside(box, x, z, 0) and Ground.topAt(box, x, z) or box.top
			if top > feet + step and box.bottom < head then return true end
		end
	end
	return false
end

-- The shortest distance between two boxes' footprints, 0 when they touch.
function Ground.gap(a, b)
	local function corners(box)
		local out = {}
		for _, c in ipairs({{box.minX, box.minZ}, {box.maxX, box.minZ}, {box.maxX, box.maxZ}, {box.minX, box.maxZ}}) do
			table.insert(out, {box.x + c[1] * box.cos + c[2] * box.sin, box.z - c[1] * box.sin + c[2] * box.cos})
		end
		return out
	end
	local function distance(box, x, z)
		local lx, lz = Ground.toLocal(box, x, z)
		local dx = math.max(box.minX - lx, 0, lx - box.maxX)
		local dz = math.max(box.minZ - lz, 0, lz - box.maxZ)
		return math.sqrt(dx * dx + dz * dz)
	end
	local best = math.huge
	for _, c in ipairs(corners(a)) do best = math.min(best, distance(b, c[1], c[2])) end
	for _, c in ipairs(corners(b)) do best = math.min(best, distance(a, c[1], c[2])) end
	return best
end

return Ground
