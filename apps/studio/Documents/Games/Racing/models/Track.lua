-- A track is a list of road pieces driven in order: "start", "straight",
-- "left", "wideRight"... Each piece begins where the one before it ends
-- and faces the way it left, so the road always joins up; the list only
-- has to come back round to the start.
--
-- Kenney's road tiles are one unit wide. Each kind's `ports` are its two
-- open edges in the model's own coordinates: the middle of the edge and
-- the direction out of the piece there, in degrees (0 is +z, -90 is -x).
-- A corner is entered at one port and left at the other: a right turn
-- goes in at A and out at B, a left turn the other way round, so one model
-- turns both ways. Its middle line is a quarter circle round the corner
-- of the tile.
--
-- Headings are in degrees: a heading h drives along (sin h, cos h), so
-- the start drives toward +z and a right turn ends facing -x.
local Track = {}

local function straight(model, length)
	return {model = model, length = length, width = 1, depth = length,
		ports = {A = {x = -0.5, z = 0, out = 180}, B = {x = -0.5, z = length, out = 0}},
		line = function(t) return -0.5, t * length end, radius = math.huge}
end

local function corner(model, size, turn)
	local r = size - 0.5
	return {model = model, turn = turn, width = size, depth = size, radius = r,
		ports = {A = {x = -0.5, z = 0, out = 180}, B = {x = -size, z = r, out = -90}},
		-- From A to B round the tile's corner at (-size, 0).
		line = function(t)
			local a = t * math.pi / 2
			return -size + r * math.cos(a), r * math.sin(a)
		end, length = r * math.pi / 2}
end

Track.PIECES = {
	start = straight("roadStartPositions", 2),
	straight = straight("roadStraight", 1),
	long = straight("roadStraightLong", 2),
	right = corner("roadCornerSmall", 1, "right"),
	left = corner("roadCornerSmall", 1, "left"),
	wideRight = corner("roadCornerLarge", 2, "right"),
	wideLeft = corner("roadCornerLarge", 2, "left"),
	sweepRight = corner("roadCornerLarger", 3, "right"),
	sweepLeft = corner("roadCornerLarger", 3, "left"),
}

-- The names a track may use, for error messages.
function Track.names()
	local names = {}
	for name in pairs(Track.PIECES) do table.insert(names, name) end
	table.sort(names)
	return table.concat(names, ", ")
end

-- A point of the model's own coordinates turned by `yaw` degrees about
-- the vertical axis, as SceneKit turns a node.
function Track.rotate(x, z, yaw)
	local a = math.rad(yaw)
	local c, s = math.cos(a), math.sin(a)
	return x * c + z * s, -x * s + z * c
end

-- Snaps tiny floating-point drift, so a closed track ends exactly at 0.
local function tidy(v)
	local r = math.floor(v * 1000 + 0.5) / 1000
	if r == 0 then r = 0 end
	return r
end

-- Lays the steps out from (0, 0) heading 0. Returns the placed pieces
-- ({step, kind, model, x, z, yaw, box}), the middle line as points
-- ({x, z, radius}) and where the road ends ({x, z, heading}).
function Track.layout(steps)
	local x, z, heading = 0, 0, 0
	local pieces, line = {}, {}
	for index, step in ipairs(steps) do
		local kind = Track.PIECES[step]
		if not kind then return nil, index end
		local enter, leave = kind.ports.A, kind.ports.B
		if kind.turn == "left" then enter, leave = leave, enter end
		-- Turn the piece so its entry faces along the heading, then move
		-- it so its entry sits where the road ends.
		local yaw = heading - (enter.out + 180)
		local ex, ez = Track.rotate(enter.x, enter.z, yaw)
		local ox, oz = x - ex, z - ez
		-- The tile covers x in [-width, 0] and z in [0, depth] of its own
		-- coordinates; turned by a multiple of 90 degrees it stays a box.
		local x1, z1 = Track.rotate(-kind.width, 0, yaw)
		local x2, z2 = Track.rotate(0, kind.depth, yaw)
		local box = {minX = tidy(ox + math.min(x1, x2)), maxX = tidy(ox + math.max(x1, x2)),
			minZ = tidy(oz + math.min(z1, z2)), maxZ = tidy(oz + math.max(z1, z2))}
		table.insert(pieces, {step = index, kind = step, model = kind.model, x = tidy(ox), z = tidy(oz), yaw = tidy(yaw % 360), box = box})
		-- The middle line, every eighth of a unit, without the end point
		-- (the next piece starts there).
		local count = math.max(1, math.ceil(kind.length / 0.125))
		for k = 0, count - 1 do
			local t = k / count
			if kind.turn == "left" then t = 1 - t end
			local lx, lz = kind.line(t)
			local rx, rz = Track.rotate(lx, lz, yaw)
			table.insert(line, {x = ox + rx, z = oz + rz, radius = kind.radius})
		end
		local lx, lz = Track.rotate(leave.x, leave.z, yaw)
		x, z, heading = tidy(ox + lx), tidy(oz + lz), tidy((yaw + leave.out) % 360)
	end
	return pieces, line, {x = x, z = z, heading = heading}
end

-- Whether two placed pieces share more than an edge.
function Track.overlap(a, b)
	return math.min(a.maxX, b.maxX) - math.max(a.minX, b.minX) > 0.01
		and math.min(a.maxZ, b.maxZ) - math.max(a.minZ, b.minZ) > 0.01
end

-- A closed path through `points` ({x, z, radius}, already in scene
-- units): each point gains its distance along the loop `s`, its heading
-- and its right-hand direction; `length` is once round.
function Track.path(points)
	local path = {points = points}
	local s = 0
	for index, p in ipairs(points) do
		local q = points[index % #points + 1]
		local dx, dz = q.x - p.x, q.z - p.z
		local d = math.sqrt(dx * dx + dz * dz)
		p.s, p.heading = s, math.deg(math.atan(dx, dz))
		p.rightX, p.rightZ = -dz / d, dx / d
		s = s + d
	end
	path.length = s
	return path
end

-- The point of the path nearest (x, z): its index and how far away it is.
function Track.nearest(path, x, z)
	local best, bestDistance = 1, math.huge
	for index, p in ipairs(path.points) do
		local dx, dz = p.x - x, p.z - z
		local d = dx * dx + dz * dz
		if d < bestDistance then best, bestDistance = index, d end
	end
	return best, math.sqrt(bestDistance)
end

-- Where on the path distance `s` falls (wrapped once round), `lane` units
-- to the right of the middle: x, z, heading and the point it lies past.
-- `hint` is the index to search from, as a car moving forward passes it.
function Track.at(path, s, lane, hint)
	local points, length = path.points, path.length
	s = s % length
	local index = hint or 1
	if points[index].s > s then index = 1 end
	while index < #points and points[index + 1].s <= s do index = index + 1 end
	local p = points[index]
	local q = points[index % #points + 1]
	local span = (index == #points and length or q.s) - p.s
	local t = span > 0 and (s - p.s) / span or 0
	local x = p.x + (q.x - p.x) * t + p.rightX * (lane or 0)
	local z = p.z + (q.z - p.z) * t + p.rightZ * (lane or 0)
	return x, z, p.heading, index
end

return Track
