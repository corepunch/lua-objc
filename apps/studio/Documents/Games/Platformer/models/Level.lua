-- Builds a level from its data (catalog/levels/*.lua) and checks it can be
-- played before anyone tries: every piece is a model the kit has, the hero
-- starts on solid ground, and every coin and the flag can be reached by
-- running and jumping from the start (springs throw higher). A level that
-- fails says why, by name, and the preview shows the error.
--
-- A level is data:
--   id, title, biome ("grass" or "snow"), facing (degrees the first view looks)
--   start = {x, y, z}
--   pieces = {{"block-grass-large", x, y, z, yaw = 0, scale = 1}, ...}
--   coins, springs, spikes = {{x, y, z}, ...}
--   flag = {x, y, z}
-- Positions are where a thing stands: a piece's `y` is its bottom, a
-- coin's `y` the bottom of the coin.
local Kit = require("demo.playground.catalog.Kit")
local Ground = require("demo.playground.models.Ground")
local World = require("demo.playground.models.World")

local Level = {}

local function point(list)
	local out = {}
	for _, p in ipairs(list or {}) do table.insert(out, {x = p[1], y = p[2], z = p[3]}) end
	return out
end

-- How far a run and jump carries the hero across a gap, rising `rise`
-- (negative when landing lower) with a take-off speed `speed`.
local function reach(rules, speed, rise)
	local g = rules.gravity
	local disc = speed * speed - 2 * g * rise
	if disc < 0 then return -1 end
	local airtime = (speed + math.sqrt(disc)) / g
	return rules.runSpeed * airtime * 0.85 -- a margin for steering
end

local function height(rules, speed) return speed * speed / (2 * rules.gravity) end

-- Whether another piece sits on `box`'s top, so nobody can stand there.
local function covered(boxes, box)
	for _, other in ipairs(boxes) do
		if other ~= box and math.abs(other.bottom - box.top) < 0.05 and Ground.inside(other, box.x, box.z, 0) then return true end
	end
	return false
end

-- The surfaces the hero can reach from the start, by breadth-first search.
local function reachable(level, rules)
	local boxes = {}
	for _, box in ipairs(level.solids) do
		if not covered(level.solids, box) then table.insert(boxes, box) end
	end
	level.surfaces = boxes
	local start
	for index, box in ipairs(boxes) do
		if Ground.inside(box, level.start.x, level.start.z, 0) and math.abs(Ground.topAt(box, level.start.x, level.start.z) - level.start.y) < 0.35 then
			start = index
		end
	end
	if not start then return nil end
	-- A spring on a surface lets the hero leave it at spring speed.
	local speed = {}
	for index, box in ipairs(boxes) do
		speed[index] = rules.jumpSpeed
		for _, spring in ipairs(level.spawns.springs) do
			if Ground.inside(box, spring.x, spring.z, 0) and math.abs(box.top - spring.y) < 0.35 then
				speed[index] = rules.springSpeed
			end
		end
	end
	local seen, queue = {[start] = true}, {start}
	while #queue > 0 do
		local from = table.remove(queue, 1)
		local a = boxes[from]
		for to, b in ipairs(boxes) do
			if not seen[to] then
				-- A ramp is entered at its low end and stood on at its high end.
				local enter = b.ramp and (b.top - (b.top - b.bottom) * 2 / 3) or b.top
				local rise = enter - a.top
				local gap = Ground.gap(a, b)
				local ok = (rise <= rules.step and gap <= 0.05)
					or (rise <= height(rules, speed[from]) and gap <= reach(rules, speed[from], rise))
				if ok then seen[to] = true; table.insert(queue, to) end
			end
		end
	end
	return seen, speed
end

-- Whether something standing at `p` can be touched from a reachable surface.
local function touchable(level, rules, seen, speed, p)
	for index in pairs(seen) do
		local box = level.surfaces[index]
		if Ground.inside(box, p.x, p.z, rules.reach + 0.6) then
			local above = p.y - Ground.topAt(box, p.x, p.z)
			if above >= -0.5 and above <= height(rules, speed[index]) + rules.reach then return true end
		end
	end
	return false
end

function Level.parse(def, rules)
	rules = rules or World.RULES
	local name = "level " .. tostring(def.id or def.title or "?")
	assert(type(def.pieces) == "table" and #def.pieces > 0, name .. " has no pieces")
	assert(def.start and def.flag, name .. " needs a start and a flag")
	local level = {id = def.id, title = def.title or def.id, biome = def.biome or "grass", facing = def.facing or 0,
		fall = def.fall or -4, pieces = {}, solids = {}}
	for index, piece in ipairs(def.pieces) do
		local model = piece[1]
		if not Kit.manifest[model] then
			error(string.format("%s: piece %d '%s' is not a model in %s (see its manifest)", name, index, tostring(model), Kit.name), 0)
		end
		table.insert(level.pieces, {model = model, x = piece[2], y = piece[3], z = piece[4], yaw = piece.yaw or 0, scale = piece.scale or 1})
		if Ground.isSolid(model) then table.insert(level.solids, Ground.box(piece)) end
	end
	level.start = {x = def.start[1], y = def.start[2], z = def.start[3]}
	level.spawns = {
		coins = point(def.coins), springs = point(def.springs), spikes = point(def.spikes),
		flag = {x = def.flag[1], y = def.flag[2], z = def.flag[3]},
	}
	local seen, speed = reachable(level, rules)
	if not seen then error(name .. ": the start is not standing on a solid piece", 0) end
	for index, coin in ipairs(level.spawns.coins) do
		if not touchable(level, rules, seen, speed, coin) then
			error(string.format("%s: coin %d at %.1f %.1f %.1f cannot be reached from the start", name, index, coin.x, coin.y, coin.z), 0)
		end
	end
	if not touchable(level, rules, seen, speed, level.spawns.flag) then
		error(name .. ": the flag cannot be reached from the start", 0)
	end
	return level
end

return Level
