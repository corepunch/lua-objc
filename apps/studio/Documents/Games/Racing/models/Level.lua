-- Builds a race from its data (catalog/tracks/*.lua) and checks it can be
-- driven before anyone tries: the track begins with the start, every piece
-- is one the game knows, the road comes back round to the start facing the
-- way it began, it never runs over itself, every model is one the kit has,
-- and no scenery stands on the road. A race that fails says why, by name,
-- and the preview shows the error.
--
-- A race is data, in kit units (one road width):
--   id, title, laps (1 to 9)
--   track = {"start", "long", "right", ...}   (see models/Track.lua)
--   rivals = {{"raceCarGreen", pace = 0.9}, ...}   (up to 3; pace 0.5 to 1)
--   scenery = {{"treeLarge", x, z, yaw = 0, scale = 1}, ...}
-- Scenery stands on the ground at its centre (x, z) and turns round it.
-- Gantries (models tagged "overhead") arch over the road, so they may
-- stand on it.
local Kit = require("demo.playground.catalog.Kit")
local Track = require("demo.playground.models.Track")

local Level = {}

local LIMITS = {laps = 9, rivals = 3, shortest = 12, roadHalf = 0.5}

-- How far (x, z) is from the road's middle line, in kit units.
local function fromRoad(line, x, z)
	local best = math.huge
	for _, p in ipairs(line) do
		local dx, dz = p.x - x, p.z - z
		best = math.min(best, dx * dx + dz * dz)
	end
	return math.sqrt(best)
end

-- Where to put a model's origin so the middle of its footprint stands at
-- (x, z) and it turns round that middle.
local function centred(model, x, z, yaw, scale)
	local b = Kit.manifest[model].bounds
	local cx, cz = (b[1] + b[4]) / 2 * scale, (b[3] + b[6]) / 2 * scale
	local rx, rz = Track.rotate(cx, cz, yaw)
	return x - rx, z - rz
end

-- The middle and corners of a model's footprint standing at (x, z).
local function footprint(model, x, z, yaw, scale)
	local size = Kit.manifest[model].size
	local w, d = size[1] * scale / 2, size[3] * scale / 2
	local points = {{x = x, z = z}}
	for _, corner in ipairs({{-w, -d}, {w, -d}, {w, d}, {-w, d}}) do
		local rx, rz = Track.rotate(corner[1], corner[2], yaw)
		table.insert(points, {x = x + rx, z = z + rz})
	end
	return points
end

-- Whether a model arches over the road.
local function spans(model)
	for _, tag in ipairs(Kit.manifest[model].tags or {}) do
		if tag == "overhead" then return true end
	end
	return false
end

-- Directions from the start, for saying where a track ends.
local function where(finish)
	local parts = {}
	if math.abs(finish.z) > 0.01 then table.insert(parts, string.format("%g %s", math.abs(finish.z), finish.z > 0 and "ahead of" or "behind")) end
	if math.abs(finish.x) > 0.01 then table.insert(parts, string.format("%g to the %s of", math.abs(finish.x), finish.x > 0 and "left" or "right")) end
	local facing = ({[0] = "forward", [90] = "left", [180] = "back", [270] = "right"})[finish.heading] or (finish.heading .. " degrees")
	local place = #parts > 0 and table.concat(parts, " and ") .. " the start" or "at the start"
	return place .. ", facing " .. facing
end

function Level.parse(def)
	local name = "track " .. tostring(def.id or def.title or "?")
	local scale = Kit.scale
	assert(type(def.track) == "table" and #def.track > 0, name .. " has no track")
	if def.track[1] ~= "start" then error(name .. ": the track must begin with \"start\"", 0) end
	for index, step in ipairs(def.track) do
		if index > 1 and step == "start" then error(string.format("%s: piece %d is a second \"start\"; a track has one", name, index), 0) end
	end
	local pieces, line, finish = Track.layout(def.track)
	if not pieces then
		error(string.format("%s: piece %d '%s' is not a track piece (use one of: %s)", name, line, tostring(def.track[line]), Track.names()), 0)
	end
	if finish.x ~= 0 or finish.z ~= 0 or finish.heading ~= 0 then
		error(string.format("%s: the track does not join up. It ends %s; it must end at the start, facing forward", name, where(finish)), 0)
	end
	for i = 1, #pieces do
		for j = i + 1, #pieces do
			if Track.overlap(pieces[i].box, pieces[j].box) then
				error(string.format("%s: piece %d '%s' runs over piece %d '%s'", name, j, pieces[j].kind, i, pieces[i].kind), 0)
			end
		end
	end

	local level = {id = def.id, title = def.title or def.id, laps = def.laps or 3, pieces = {}, rivals = {}}
	if math.type(level.laps) ~= "integer" or level.laps < 1 or level.laps > LIMITS.laps then
		error(string.format("%s: laps must be a whole number from 1 to %d", name, LIMITS.laps), 0)
	end
	for _, piece in ipairs(pieces) do
		table.insert(level.pieces, {model = piece.model, x = piece.x * scale, y = 0, z = piece.z * scale, yaw = piece.yaw, scale = scale})
	end

	for index, item in ipairs(def.scenery or {}) do
		local model, x, z = item[1], item[2], item[3]
		local yaw, size = item.yaw or 0, item.scale or 1
		if not Kit.manifest[model] then
			error(string.format("%s: scenery %d '%s' is not a model in %s (see its manifest)", name, index, tostring(model), Kit.name), 0)
		end
		assert(type(x) == "number" and type(z) == "number", string.format("%s: scenery %d needs x and z", name, index))
		for _, p in ipairs(spans(model) and {} or footprint(model, x, z, yaw, size)) do
			if fromRoad(line, p.x, p.z) < LIMITS.roadHalf then
				error(string.format("%s: scenery %d '%s' at %g, %g stands on the road; move it off the track", name, index, model, x, z), 0)
			end
		end
		local ox, oz = centred(model, x, z, yaw, size)
		table.insert(level.pieces, {model = model, x = ox * scale, y = 0, z = oz * scale, yaw = yaw, scale = size * scale})
	end

	if #(def.rivals or {}) > LIMITS.rivals then
		error(string.format("%s: the start has room for %d rivals", name, LIMITS.rivals), 0)
	end
	for index, rival in ipairs(def.rivals or {}) do
		local model, pace = rival[1], rival.pace or 0.9
		local entry = Kit.manifest[model]
		local vehicle = false
		for _, tag in ipairs(entry and entry.tags or {}) do vehicle = vehicle or tag == "vehicle" end
		if not vehicle then error(string.format("%s: rival %d '%s' is not a car in %s", name, index, tostring(model), Kit.name), 0) end
		if type(pace) ~= "number" or pace < 0.5 or pace > 1 then
			error(string.format("%s: rival %d's pace must be from 0.5 to 1 (1 is as fast as you)", name, index), 0)
		end
		table.insert(level.rivals, {model = model, pace = pace})
	end
	level.car = def.car or "raceCarRed"
	if not Kit.manifest[level.car] then error(string.format("%s: car '%s' is not a model in %s", name, level.car, Kit.name), 0) end

	local points = {}
	for _, p in ipairs(line) do table.insert(points, {x = p.x * scale, z = p.z * scale, radius = p.radius * scale}) end
	level.path = Track.path(points)
	if level.path.length < LIMITS.shortest * scale then
		error(string.format("%s: the track is too short; make it at least %d road pieces long", name, LIMITS.shortest), 0)
	end
	return level
end

return Level
