-- Three-dimensional helpers for <SceneView> attributes and bespoke shots:
-- vectors, camera placement and smooth paths through keyed positions. All
-- pure functions of their arguments, like reel/curves.lua, so a camera move
-- written as `position="path(t, cameraKeys)"` renders any instant exactly.
--
-- Vectors are plain {x, y, z} tables; angles are degrees, as in SceneView
-- attributes. SceneKit's axes: y up, the camera looks down -z.
local Space = {}

local sin, cos, rad, sqrt = math.sin, math.cos, math.rad, math.sqrt

function Space.vec(x, y, z) return { x, y, z } end

function Space.add3(a, b) return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
function Space.sub3(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
function Space.scale3(a, s) return { a[1] * s, a[2] * s, a[3] * s } end
function Space.length3(a) return sqrt(a[1] * a[1] + a[2] * a[2] + a[3] * a[3]) end
function Space.lerp3(a, b, p) return { a[1] + (b[1] - a[1]) * p, a[2] + (b[2] - a[2]) * p, a[3] + (b[3] - a[3]) * p } end

function Space.normalize3(a)
	local length = Space.length3(a)
	if length == 0 then return { 0, 0, 0 } end
	return { a[1] / length, a[2] / length, a[3] / length }
end

-- orbit(target, distance, yaw, pitch): a point `distance` from `target`,
-- turned `yaw` degrees about the vertical (0 in front, on +z; positive to
-- the right) and raised `pitch` degrees above the horizon.
function Space.orbit(target, distance, yaw, pitch)
	local y, p = rad(yaw), rad(pitch)
	return {
		target[1] + distance * cos(p) * sin(y),
		target[2] + distance * sin(p),
		target[3] + distance * cos(p) * cos(y),
	}
end

-- dolly(from, target, distance): the point on the line from `target`
-- toward `from` that is `distance` from the target: a camera pushed in or
-- pulled back along its own axis.
function Space.dolly(from, target, distance)
	return Space.add3(target, Space.scale3(Space.normalize3(Space.sub3(from, target)), distance))
end

-- fill(height, fieldOfView): how far a camera with that vertical field of
-- view stands from something `height` tall to fill the frame with it.
function Space.fill(height, fieldOfView)
	return height / 2 / math.tan(rad(fieldOfView) / 2)
end

-- rotate(v, {pitch, yaw, roll}) -> v turned by a node's rotation attribute
-- (degrees) the way SceneKit turns it: about x by the pitch, then about y
-- by the yaw, then about z by the roll, all in the parent's axes.
function Space.rotate(v, euler)
	local x, y, z = v[1], v[2], v[3]
	local p, w, r = rad(euler[1] or 0), rad(euler[2] or 0), rad(euler[3] or 0)
	y, z = y * cos(p) - z * sin(p), y * sin(p) + z * cos(p)
	x, z = x * cos(w) + z * sin(w), -x * sin(w) + z * cos(w)
	x, y = x * cos(r) - y * sin(r), x * sin(r) + y * cos(r)
	return { x, y, z }
end

-- transform(point, position, rotation, scale) -> where a point in a node's
-- own space lands in its parent's: scaled, turned, then moved. A point on a
-- device's screen, for a camera that must frame it or another object that
-- must start from it.
function Space.transform(point, position, rotation, scale)
	local s = scale or 1
	local turned = Space.rotate({ point[1] * s, point[2] * s, point[3] * s }, rotation or { 0, 0, 0 })
	return Space.add3(turned, position)
end

-- Cubic Hermite interpolation between keyed values with Catmull-Rom
-- tangents scaled to uneven key spacing, so the motion is smooth through
-- every key (continuous velocity) and eases in and out of the first and the
-- last. A key {time, value, hold = true} stops dead on its value.
local function hermite(t, keys, get, set)
	local n = #keys
	if n == 0 then error("path needs keys", 3) end
	if t <= keys[1][1] or n == 1 then return keys[1][2] end
	if t >= keys[n][1] then return keys[n][2] end
	local i = 1
	while keys[i + 1][1] < t do i = i + 1 end
	local k0, k1 = keys[i], keys[i + 1]
	local t0, t1 = k0[1], k1[1]
	local span = t1 - t0
	local u = (t - t0) / span
	local function tangent(index)
		local key = keys[index]
		if key.hold or index == 1 or index == n then return nil end
		local before, after = keys[index - 1], keys[index + 1]
		return before, after, (after[1] - before[1])
	end
	local h00 = 2 * u ^ 3 - 3 * u ^ 2 + 1
	local h10 = u ^ 3 - 2 * u ^ 2 + u
	local h01 = -2 * u ^ 3 + 3 * u ^ 2
	local h11 = u ^ 3 - u ^ 2
	local b0, a0, d0 = tangent(i)
	local b1, a1, d1 = tangent(i + 1)
	return set(function(c)
		local p0, p1 = get(k0[2], c), get(k1[2], c)
		local m0 = b0 and (get(a0[2], c) - get(b0[2], c)) / d0 * span or 0
		local m1 = b1 and (get(a1[2], c) - get(b1[2], c)) / d1 * span or 0
		return h00 * p0 + h10 * m0 + h01 * p1 + h11 * m1
	end)
end

local function component(v, c) return v[c] end
local function vector(f) return { f(1), f(2), f(3) } end
local function scalar(v) return v end
local function number(f) return f() end

-- path(t, {{t0, {x, y, z}}, {t1, {x, y, z}, hold = true}, …}) -> {x, y, z}:
-- a smooth path through keyed points, for camera positions and targets.
function Space.path(t, keys)
	return hermite(t, keys, component, vector)
end

-- track(t, {{t0, value}, …}) -> number: the same for one value (a field of
-- view, a roll, a yaw).
function Space.track(t, keys)
	return hermite(t, keys, scalar, number)
end

return Space
