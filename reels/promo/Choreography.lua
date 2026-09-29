-- Where everything is at time t: the camera and every device, as pure
-- functions of t, so a still, a motion-blur sub-frame and the movie agree.
--
-- The film is one world seen by one camera. Shots are spans of the
-- timeline (SHOT); within a shot, objects follow keyed paths (reel/space.lua
-- `path`, smooth through every key) and a few poses are derived from
-- others where two objects must meet exactly: the montage window lands in
-- the display's window slot, the phone lifts off Lua Studio's preview, and
-- the camera squares up to the game phone's screen until the screen fills
-- the frame, where the film cuts into the game's own world.
--
-- Units are 10 cm; y is up and devices face +z. Rotations are
-- {pitch, yaw, roll} in degrees, SceneKit's euler order.
local Space = require("reel.space")
local path, track, transform, orbit = Space.path, Space.track, Space.transform, Space.orbit

local C = {}

-- The timeline, in seconds (120 BPM: a beat is 0.5 s, a bar 2 s).
local SHOT = {
	montage = 0, landing = 2.95, landed = 3.55, frame = 3.5,
	studio = 6.0, send1 = 7.7, send2 = 10.2, zero = 11.0,
	lift = 13.0, free = 14.2, voiceChange = 15.35,
	wall = 17.0, portal = 20.3, cut = 21.8,
	speed = 25.0, hero = 27.8,
}
C.SHOT = SHOT

-- Device geometry the choreography needs (devices/*.etlua).
local DEVICE = {
	padScreen = { w = 2.672, h = 2.004, points = { 1376, 1032 }, z = 0.0263 },
	phoneScreen = { w = 0.662, h = 1.44, z = 0.0421 },
	phoneBody = 1.496,
	displayScreen = { w = 5.97, y = 0.03, z = 0.071, points = 1600 },
	window = { w = 3.0 },
}
C.DEVICE = DEVICE

-- Lua Studio's phone preview in the iPad capture, in screen points.
local PREVIEW = { x = 26, y = 120, w = 388, h = 888 }
C.PREVIEW = PREVIEW

-- ── Composition slots ────────────────────────────────────────────────────

local SLOT = {
	display = { position = { -3.1, 0.45, -8.2 }, rotation = { 0, 22, 0 } },
	pad = { position = { 0.6, -0.1, -3.2 }, rotation = { -4, -12, 0 } },
	phone = { position = { 2.9, -0.55, 0.9 }, rotation = { -6, -28, 0 } },
}

-- A point on the iPad's screen, (u, v) in screen points from its top-left,
-- `lift` in front of the glass, in the world at t.
function C.padPoint(t, u, v, lift)
	local s = DEVICE.padScreen
	local p = C.pose("pad", t)
	local local_ = { (u / s.points[1] - 0.5) * s.w, (0.5 - v / s.points[2]) * s.h, s.z + (lift or 0) }
	return transform(local_, p.position, p.rotation, p.scale)
end

-- Where each device's label goes in the composition, in clear space: above
-- the display's top-left corner, below the iPad, above the phone.
function C.label(name)
	local slot = SLOT[name]
	local offsets = { display = { -2.9, 2.15, 0 }, pad = { -1.3, -1.35, 0 }, phone = { -0.3, 1.0, 0 } }
	return transform(offsets[name], slot.position, slot.rotation, 1)
end

-- ── Keyed tracks ─────────────────────────────────────────────────────────

local KEYS = {}

-- The montage window: turns over on the beat into the next app, then flies
-- into the display's window slot (derived below).
KEYS.window = {
	position = { { 0, { 0, 0, 0 } }, { SHOT.landing, { 0.05, 0.02, 0.1 } } },
}

KEYS.phone = {
	-- Crosses the montage in the foreground and settles in its slot.
	position = { { 1.8, { -3.4, -1.5, 2.4 } }, { 2.8, SLOT.phone.position }, { SHOT.studio, SLOT.phone.position, hold = true } },
	rotation = { { 1.8, { 10, 40, -6 } }, { 2.8, SLOT.phone.rotation }, { SHOT.studio, SLOT.phone.rotation, hold = true } },
}

KEYS.pad = {
	position = { { 3.45, { 3.2, 1.6, -15 } }, { 4.7, SLOT.pad.position }, { SHOT.studio, SLOT.pad.position },
		{ 7.0, { 0.3, 0.1, -3.2 } }, { SHOT.lift, { 0.3, 0.1, -3.2 }, hold = true },
		{ 13.5, { 0.1, -0.2, -4.4 } }, { 14.8, { -1.4, -1.6, -11 } } },
	rotation = { { 3.45, { 10, 55, 8 } }, { 4.7, SLOT.pad.rotation }, { SHOT.studio, SLOT.pad.rotation },
		{ 7.0, { 0, 0, 0 } }, { SHOT.zero, { 0, 0, 0 }, hold = true }, { 12.0, { -2, 6, 0 } },
		{ SHOT.lift, { 0, 0, 0 }, hold = true }, { 14.8, { -18, 30, 6 } } },
}

-- The phone off Lua Studio, filmed in close-up: turns on each beat of
-- "talk, change, see it".
local STAGE = { 0.9, 0.35, -2.4 }
KEYS.lifted = {
	position = { { 14.2, STAGE }, { 15.4, { 0.95, 0.4, -2.45 } }, { SHOT.wall, { 1.0, 0.35, -2.5 } },
		{ 17.45, { 3.2, 0.6, 1.6 } } },
	rotation = { { 14.2, { -6, 32, 2 } }, { 14.7, { -4, 26, 0 } }, { 15.3, { -2, -8, 0 } }, { 15.9, { -16, 2, 0 } },
		{ 16.6, { -6, 24, -3 } }, { SHOT.wall, { -4, 40, -4 } }, { 17.45, { 20, 70, -10 } } },
}

-- ── Poses ────────────────────────────────────────────────────────────────

local function smooth(u) return u * u * (3 - 2 * u) end
local function clamp(u) return u < 0 and 0 or (u > 1 and 1 or u) end
local function ease(t, a, b) return smooth(clamp((t - a) / (b - a))) end

local function lerpPose(a, b, p)
	return { position = Space.lerp3(a.position, b.position, p), rotation = Space.lerp3(a.rotation, b.rotation, p),
		scale = (a.scale or 1) + ((b.scale or 1) - (a.scale or 1)) * p }
end

-- The montage window turns 180° about y at each flip.
local FLIPS = { 0.75, 1.5, 2.25 }
local FLIP = 0.34

local function windowPose(t)
	local yaw, pitch = 0, 0
	for _, at in ipairs(FLIPS) do
		local u = clamp((t - at) / FLIP)
		local e = u < 0.5 and 4 * u * u * u or 1 - (-2 * u + 2) ^ 3 / 2
		yaw = yaw + 180 * e
		pitch = pitch + 9 * math.sin(math.pi * u)
	end
	local drift = { position = path(t, KEYS.window.position), rotation = { pitch - 3, yaw - 8 + 5 * t, 0 }, scale = 1 }
	if t <= SHOT.landing then return drift end
	-- The window slot: the display's screen centre, just in front of the glass.
	local d = SLOT.display
	local slot = {
		position = transform({ 0, DEVICE.displayScreen.y, DEVICE.displayScreen.z + 0.012 }, d.position, d.rotation, 1),
		rotation = { d.rotation[1], d.rotation[2] + 720, d.rotation[3] },
		scale = DEVICE.displayScreen.w * 1200 / DEVICE.displayScreen.points / DEVICE.window.w,
	}
	local start = windowPose(SHOT.landing)
	return lerpPose(start, slot, ease(t, SHOT.landing, SHOT.landed))
end

-- The phone lifting off the preview: it starts as the preview, lying on the
-- iPad's screen at the preview's size, and rises into the close-up.
local function liftPose(t)
	local start = {
		position = C.padPoint(SHOT.lift, PREVIEW.x + PREVIEW.w / 2, PREVIEW.y + PREVIEW.h / 2, 0.03),
		rotation = C.pose("pad", SHOT.lift).rotation,
		scale = PREVIEW.h / DEVICE.padScreen.points[2] * DEVICE.padScreen.h / DEVICE.phoneBody,
	}
	local target = { position = path(t, KEYS.lifted.position), rotation = path(t, KEYS.lifted.rotation), scale = 1 }
	return lerpPose(start, target, ease(t, SHOT.lift, SHOT.free))
end

-- The game phone: landscape, standing at the end of the wall.
local GAME = { position = { 8.2, 0.35, -6.4 }, rotation = { 0, -18, 0 } }
C.GAME = GAME

local POSES = {
	window = windowPose,
	pad = function(t)
		return { position = path(t, KEYS.pad.position), rotation = path(t, KEYS.pad.rotation), scale = 1 }
	end,
	phone = function(t)
		if t < SHOT.lift then
			return { position = path(t, KEYS.phone.position), rotation = path(t, KEYS.phone.rotation), scale = 1 }
		end
		return liftPose(t)
	end,
	display = function() return { position = SLOT.display.position, rotation = SLOT.display.rotation, scale = 1 } end,
	game = function() return { position = GAME.position, rotation = GAME.rotation, scale = 1 } end,
}

-- pose(name, t) -> {position, rotation, scale}
function C.pose(name, t)
	local fn = POSES[name] or error("choreography: no pose for " .. tostring(name))
	return fn(t)
end

-- Attribute helpers: `position="C.at('phone', t)"`.
function C.at(name, t) return C.pose(name, t).position end
function C.turn(name, t) return C.pose(name, t).rotation end
function C.size(name, t) return C.pose(name, t).scale end

-- ── The game phone's screen, and the cut into the game ──────────────────

-- The screen's centre and normal in the world. The phone lies on its side
-- (rolled 90° inside the GAME node), so the screen's up is world up.
function C.gameScreen()
	local g = GAME
	local centre = transform({ 0, 0, DEVICE.phoneScreen.z }, g.position, g.rotation, 1)
	local normal = Space.rotate({ 0, 0, 1 }, g.rotation)
	return centre, normal
end

-- The lens at the cut: the screen's height (the phone's width, lying down)
-- fills the frame's height, so the game inside continues full frame.
C.CUT = { fieldOfView = 36 }
function C.cutDistance()
	return DEVICE.phoneScreen.w / 2 / math.tan(math.rad(C.CUT.fieldOfView / 2))
end

-- ── Camera ───────────────────────────────────────────────────────────────

local CAMERA = {}

CAMERA.montage = {
	-- The window sits right of centre so the words have the left.
	eye = { { 0, { -0.85, 0.2, 5.3 } }, { 2.2, { -0.3, 0.3, 4.75 } }, { SHOT.landing, { -0.2, 0.32, 4.7 } },
		{ 4.8, { 1.35, 0.85, 7.2 } }, { SHOT.studio, { 1.2, 0.8, 7.0 } } },
	target = { { 0, { -1.0, 0.02, 0 } }, { 2.2, { -0.8, 0.02, 0 } }, { SHOT.landing, { -0.7, 0.02, 0 } },
		{ 4.8, { 0.05, -0.1, -3.4 } }, { SHOT.studio, { 0.1, -0.1, -3.4 } } },
	lens = { { 0, 34 }, { SHOT.landing, 34 }, { 4.8, 38 }, { SHOT.studio, 38 } },
}

-- Lua Studio: framed in screen points on the iPad, so a push to the diff or
-- the preview lands on the capture's own layout. {time, u, v, distance}.
CAMERA.studio = {
	{ 7.0, 688, 516, 4.3 }, { 7.9, 688, 516, 4.3, hold = true }, { 8.8, 930, 380, 2.35 },
	{ 9.25, 930, 380, 2.35, hold = true }, { 9.95, 688, 560, 3.7 }, { SHOT.send2 + 0.1, 688, 560, 3.7, hold = true },
	{ 11.0, 222, 300, 2.4 }, { 12.5, 688, 516, 4.4 }, { SHOT.lift, 220, 564, 1.35 },
}

local function studioCamera(t)
	local keys = CAMERA.studio
	local u = track(t, (function() local k = {} for i, key in ipairs(keys) do k[i] = { key[1], key[2], hold = key.hold } end return k end)())
	local v = track(t, (function() local k = {} for i, key in ipairs(keys) do k[i] = { key[1], key[3], hold = key.hold } end return k end)())
	local d = track(t, (function() local k = {} for i, key in ipairs(keys) do k[i] = { key[1], key[4], hold = key.hold } end return k end)())
	local target = C.padPoint(t, u, v)
	local p = C.pose("pad", t)
	local normal = Space.rotate({ 0, 0, 1 }, p.rotation)
	return Space.add3(target, Space.scale3(normal, d)), target, 34
end

-- The phone close-up: an orbit around the phone, from straight on (where
-- the preview was) out to a three-quarter view, across the front, over the
-- top as it tilts back and close past its edge. {time, yaw, pitch, distance}.
CAMERA.orbit = {
	{ SHOT.lift, 0, 0, 1.35 }, { SHOT.free, 22, 6, 2.9 }, { 14.8, -18, 3, 3.1 }, { 15.6, 4, 14, 2.9 },
	{ 16.5, 48, -4, 2.3 }, { SHOT.wall, 60, 0, 2.6 },
}
-- In the close-up the phone stands right of centre, the words on the left:
-- the camera and its target slide this far to the camera's left.
local ASIDE = 0.55

local function orbitCamera(t)
	local keys = CAMERA.orbit
	local function col(i) local k = {} for n, key in ipairs(keys) do k[n] = { key[1], key[i] } end return k end
	local yaw, pitch, distance = track(t, col(2)), track(t, col(3)), track(t, col(4))
	local p = C.pose("phone", t)
	-- At the lift the camera stands where the studio shot ended, on the
	-- iPad's axis; the orbit's frame turns with the iPad until the phone
	-- is free of it.
	local base = Space.lerp3(C.turn("pad", SHOT.lift), { 0, 0, 0 }, ease(t, SHOT.lift, SHOT.free))
	local offset = Space.rotate(Space.sub3(orbit({ 0, 0, 0 }, distance, yaw, pitch), { 0, 0, 0 }), base)
	local side = Space.normalize3({ offset[3], 0, -offset[1] })
	local aside = Space.scale3(side, -ASIDE * ease(t, SHOT.lift, SHOT.free))
	local target = Space.add3(p.position, aside)
	local eye = Space.add3(target, offset)
	if t < SHOT.free then
		local studioEye, studioTarget = studioCamera(SHOT.lift)
		local e = ease(t, SHOT.lift, SHOT.free)
		eye = Space.lerp3(Space.add3(studioEye, Space.sub3(target, studioTarget)), eye, e)
	end
	return eye, target, track(t, { { SHOT.lift, 34 }, { 14.0, 30 }, { 16.5, 28 }, { SHOT.wall, 32 } })
end

-- The wall: a truck along the floating apps, then a turn to the game
-- phone and the push into its screen.
CAMERA.wall = {
	eye = { { SHOT.wall, nil }, { 17.7, { -2.6, 0.7, -1.2 } }, { 19.6, { 3.4, 0.45, -1.6 } }, { SHOT.portal, { 5.2, 0.4, -2.2 } } },
	target = { { SHOT.wall, nil }, { 17.7, { -3.4, 0.7, -7.2 } }, { 19.6, { 3.4, 0.45, -7.4 } }, { SHOT.portal, { 7.4, 0.35, -6.6 } } },
}

local function wallCamera(t)
	local from, fromTarget = orbitCamera(SHOT.wall)
	local eyeKeys = { { SHOT.wall, from } }
	local targetKeys = { { SHOT.wall, fromTarget } }
	for i = 2, #CAMERA.wall.eye do
		table.insert(eyeKeys, CAMERA.wall.eye[i])
		table.insert(targetKeys, CAMERA.wall.target[i])
	end
	if t <= SHOT.portal then
		return path(t, eyeKeys), path(t, targetKeys), track(t, { { SHOT.wall, 32 }, { 17.7, 34 }, { SHOT.portal, 34 } })
	end
	-- Square up to the screen: the eye closes on the screen's axis until the
	-- screen's height fills the frame at the cut.
	local centre, normal = C.gameScreen()
	local final = Space.add3(centre, Space.scale3(normal, C.cutDistance()))
	local e = ease(t, SHOT.portal, SHOT.cut)
	local eased = e * e * (3 - 2 * e) -- slow in, fast arrival: a push, not a drift
	local startEye, startTarget = path(SHOT.portal, eyeKeys), path(SHOT.portal, targetKeys)
	local eye = Space.lerp3(startEye, final, eased)
	local target = Space.lerp3(startTarget, centre, math.min(1, e * 1.6))
	return eye, target, 34 + (C.CUT.fieldOfView - 34) * eased
end

-- The speed run: a corridor of devices the camera flies down, far from the
-- rest of the world, ending on the hero composition.
local CORRIDOR = 40
C.CORRIDOR = CORRIDOR
CAMERA.speed = {
	eye = { { SHOT.speed, { CORRIDOR + 0.3, 0.35, 3.0 } }, { 27.0, { CORRIDOR - 0.2, 0.3, -17.5 } },
		{ SHOT.hero, { CORRIDOR + 0.9, 0.55, -21.2 } }, { 30, { CORRIDOR + 1.3, 0.62, -20.4 } } },
	target = { { SHOT.speed, { CORRIDOR, 0.3, -8 } }, { 27.0, { CORRIDOR - 0.2, 0.2, -28 } },
		{ SHOT.hero, { CORRIDOR + 0.3, 0.1, -30 } }, { 30, { CORRIDOR + 0.35, 0.1, -30 } } },
	lens = { { SHOT.speed, 40 }, { 26.8, 44 }, { SHOT.hero, 32 }, { 30, 31 } },
}

-- camera(t) -> eye, target, fieldOfView, roll
function C.camera(t)
	if t < SHOT.studio then
		return path(t, CAMERA.montage.eye), path(t, CAMERA.montage.target), track(t, CAMERA.montage.lens), 0
	elseif t < 7.0 then
		-- From the composition to the iPad as it turns to face us.
		local eye, target = studioCamera(7.0)
		local e = ease(t, SHOT.studio, 7.0)
		return Space.lerp3(path(SHOT.studio, CAMERA.montage.eye), eye, e),
			Space.lerp3(path(SHOT.studio, CAMERA.montage.target), target, e), 34, -2 * math.sin(math.pi * e)
	elseif t < SHOT.lift then
		local eye, target, lens = studioCamera(t)
		return eye, target, lens, 0
	elseif t < SHOT.wall then
		local eye, target, lens = orbitCamera(t)
		return eye, target, lens, 3 * math.sin((t - SHOT.lift) * 1.3) * ease(t, SHOT.lift, 14.2)
	elseif t < SHOT.speed then
		local eye, target, lens = wallCamera(math.min(t, SHOT.cut))
		return eye, target, lens, 0
	end
	return path(t, CAMERA.speed.eye), path(t, CAMERA.speed.target), track(t, CAMERA.speed.lens),
		-4 * math.sin(math.pi * clamp((t - SHOT.speed) / (SHOT.hero - SHOT.speed)))
end

-- Focus: shallow on the phone close-up and the hero composition, where a
-- product shot wants the background soft; everywhere else the lens is
-- sharp throughout (0 turns depth of field off). Returns distance, f-stop.
local FOCUS = { { SHOT.free, 16.9, 1.4 }, { SHOT.hero + 0.2, 30, 2.4 } }
function C.focus(t)
	for _, span in ipairs(FOCUS) do
		if t >= span[1] and t < span[2] then
			local eye, target = C.camera(t)
			return Space.length3(Space.sub3(target, eye)), span[3]
		end
	end
	return 0, 5.6
end
function C.fStop(t) return (select(2, C.focus(t))) end

function C.eye(t) return (C.camera(t)) end
function C.target(t) return (select(2, C.camera(t))) end
function C.lens(t) return (select(3, C.camera(t))) end
function C.roll(t) return (select(4, C.camera(t))) end

-- ── The game's own camera, after the cut ────────────────────────────────

-- In level cells (Sawmill: 13 × 7). It starts as the view the phone
-- showed, the game's own framing, then drops behind the player, skims the
-- grass, watches a coin go and rises over the level.
C.QUEST = {
	start = 21.0, -- reel time of game time 0
	-- The player walks left along row 2 (a coin at its end, 23.5 s), then
	-- down to the next (23.9 s); crates stand at (2, 3) and (9, 3) and a saw
	-- runs along row 1, so the camera trails north of the row, high enough.
	eye = { { SHOT.cut, { 6, 14.7, 14.5 } }, { 22.7, { 6.2, 1.2, 0.5 } }, { 23.35, { 2.8, 0.95, 0.7 } },
		{ 24.0, { 1.6, 1.5, 5.9 } }, { SHOT.speed, { 4.5, 8.5, 11.5 } } },
	target = { { SHOT.cut, { 6, 0, 3 } }, { 22.7, { 3.4, 0.35, 2.0 } }, { 23.35, { 0.3, 0.3, 2.1 } },
		{ 24.0, { 0.1, 0.3, 3.7 } }, { SHOT.speed, { 5.5, 0, 3 } } },
	lens = { { SHOT.cut, C.CUT.fieldOfView }, { 22.7, 44 }, { 23.9, 42 }, { SHOT.speed, 40 } },
}

-- The game camera before the cut: the game's own framing, fitted to the
-- landscape screen with the lens the cut uses.
function C.questCamera(t)
	local Q = C.QUEST
	return { id = "camera", x = path(t, Q.eye)[1], y = path(t, Q.eye)[2], z = path(t, Q.eye)[3],
		lookAt = path(t, Q.target), fieldOfView = track(t, Q.lens), fieldOfViewAxis = "vertical" }
end

return C
