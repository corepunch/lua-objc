-- Where everything is at time t: the camera and every device, as pure
-- functions of t, so a still, a motion-blur sub-frame and the movie agree.
--
-- The film is about building apps on the iPad and the iPhone. It is one
-- world seen by one camera, in five acts on a 120 BPM grid (a beat is
-- 0.5 s): the app assembles on the iPhone; the agent edits it from Lua
-- Studio on the iPad while the iPhone beside it shows each change live and
-- is tapped; one request lands in the app's Model, Controller and View,
-- shown as three code panels beside the iPhone, which then shows it and is
-- used; the iPhone turns into a game and the camera goes through its
-- screen; the Mac joins only for the closing composition. Moves are few and slow, with holds, so every change
-- on a screen can be read.
--
-- Units are 10 cm; y is up and devices face +z. Rotations are
-- {pitch, yaw, roll} in degrees, SceneKit's euler order.
local Space = require("reel.space")
local path, track, transform = Space.path, Space.track, Space.transform

local C = {}

-- The timeline, in seconds.
local SHOT = {
	open = 0, pair = 2.6, together = 3.6,
	send1 = 5.0, change1 = 7.0, send2 = 8.0, change2 = 9.5, tap = 10.5, checked = 10.6,
	noBuild = 11.75, alone = 13.0,
	send3 = 14.0, layers = { 14.5, 15.0, 15.5 }, change3 = 16.0, tapOpen = 16.9, opened = 17.0,
	turn = 17.6, swap = 18.45, cut = 19.5, hero = 23.6, logo = 26.0,
}
C.SHOT = SHOT

local DEVICE = {
	phoneScreen = { w = 0.662, h = 1.44, z = 0.0421 },
}
C.DEVICE = DEVICE

-- ── Device paths ────────────────────────────────────────────────────────

-- The pair: the iPad at left, the iPhone beside it in front, both turned a
-- little toward the middle.
local PAIR = {
	pad = { position = { -0.55, 0.32, -2.3 }, rotation = { -3, 11, 0 } },
	phone = { position = { 1.72, -0.22, -1.25 }, rotation = { -4, -17, 0 } },
}
C.PAIR = PAIR
-- The phone alone, right of centre, the code panels at its left.
local ALONE = { position = { 0.35, 0.05, -1.0 } }

local KEYS = {}

KEYS.phone = {
	position = {
		{ SHOT.open, { 0.05, -0.02, 0 } }, { SHOT.pair, { 0.05, -0.02, -0.05 } },
		{ SHOT.together, PAIR.phone.position }, { SHOT.noBuild, PAIR.phone.position, hold = true },
		{ SHOT.alone + 0.4, ALONE.position }, { SHOT.turn, { 0.35, 0.05, -1.05 }, hold = true },
		{ SHOT.swap, { 0.45, 0.1, -1.4 } },
	},
	rotation = {
		{ SHOT.open, { -10, 42, 5 } }, { SHOT.pair, { -4, -14, 0 } },
		{ SHOT.together, PAIR.phone.rotation }, { SHOT.noBuild, PAIR.phone.rotation, hold = true },
		{ SHOT.alone + 0.4, { -4, -8, 0 } }, { 14.8, { -3, -13, 0 } }, { 16.2, { -5, -6, 0 } },
		{ SHOT.turn, { -4, -6, 0 }, hold = true }, { SHOT.swap, { 0, 0, 90 } },
	},
}

KEYS.pad = {
	position = {
		{ SHOT.pair, { -5.2, 1.4, -9.0 } }, { SHOT.together, PAIR.pad.position }, { SHOT.noBuild, PAIR.pad.position, hold = true },
		-- It recedes into depth behind the phone and fades, never leaving
		-- the frame.
		{ SHOT.alone + 0.9, { -0.9, 0.35, -6.0 } },
	},
	rotation = {
		{ SHOT.pair, { 10, 50, -5 } }, { SHOT.together, PAIR.pad.rotation }, { SHOT.noBuild, PAIR.pad.rotation, hold = true },
		{ SHOT.alone + 0.9, { -4, 20, 0 } },
	},
}

-- The game phone lies on its side where the phone turned, so the swap is
-- invisible: the same body in the same place, now running the game.
local GAME = { position = { 0.45, 0.1, -1.4 }, rotation = { 0, 0, 0 } }
C.GAME = GAME

-- The closing composition: the Mac behind at left, the iPad in the middle
-- turned toward us, the iPhone in front at right, all turned differently.
local HERO = {
	display = { position = { 3.0, 1.5, -10.8 }, rotation = { 0, 12, 0 } },
	pad = { position = { 4.0, 0.1, -6.3 }, rotation = { -4, -11, 0 } },
	phone = { position = { 4.7, -0.45, -3.9 }, rotation = { -8, -30, -2 } },
}
C.HERO = HERO

local function smooth(u) u = u < 0 and 0 or (u > 1 and 1 or u); return u * u * (3 - 2 * u) end

-- The hero devices glide into the composition from further off.
local function arrive(name, t, from, delay)
	local u = smooth((t - SHOT.hero - delay) / 1.6)
	local slot = HERO[name]
	return { position = Space.lerp3(from.position, slot.position, u),
		rotation = Space.lerp3(from.rotation, slot.rotation, u), scale = 1 }
end

-- The three layers of the filter edit: code panels stacked at the phone's
-- left, turned a little toward it. Each rises into place on its beat and,
-- before the phone turns, they recede into depth and fade.
local LAYERS = { x = -1.0, ys = { 0.16, -0.18, -0.52 }, z = -1.05, yaw = 10, width = 1.4, rise = { 0, -0.14, -0.45 } }
C.LAYERS = LAYERS

-- An ease out that overshoots a little and settles, like a spring.
local function back(u)
	u = u < 0 and 0 or (u > 1 and 1 or u)
	local s = 1.4
	return 1 + (s + 1) * (u - 1) ^ 3 + s * (u - 1) ^ 2
end

local function layerPose(i, t)
	local k = back((t - SHOT.layers[i]) / 0.55)
	local away = smooth((t - (SHOT.turn - 0.55 + (i - 1) * 0.06)) / 0.55)
	local rise = LAYERS.rise
	return {
		position = { LAYERS.x + rise[1] * (1 - k), LAYERS.ys[i] + rise[2] * (1 - k), LAYERS.z + rise[3] * (1 - k) - 1.6 * away },
		rotation = { 0, LAYERS.yaw + 14 * (1 - k), 0 }, scale = 1,
		opacity = math.min(1, math.max(0, (t - SHOT.layers[i]) / 0.15)) * (1 - away),
	}
end

local POSES = {
	phone = function(t)
		return { position = path(t, KEYS.phone.position), rotation = path(t, KEYS.phone.rotation), scale = 1 }
	end,
	pad = function(t)
		return { position = path(t, KEYS.pad.position), rotation = path(t, KEYS.pad.rotation), scale = 1 }
	end,
	game = function() return { position = GAME.position, rotation = GAME.rotation, scale = 1 } end,
	layer1 = function(t) return layerPose(1, t) end,
	layer2 = function(t) return layerPose(2, t) end,
	layer3 = function(t) return layerPose(3, t) end,
	heroDisplay = function(t)
		return arrive("display", t, { position = { 7.0, 2.6, -15 }, rotation = { 0, -30, 0 } }, 0.2)
	end,
	heroPad = function(t)
		return arrive("pad", t, { position = { 3.9, -2.2, -8 }, rotation = { 18, -20, 0 } }, 0)
	end,
	heroPhone = function(t)
		return arrive("phone", t, { position = { 7.6, -1.2, -1.2 }, rotation = { -20, -60, -8 } }, 0.35)
	end,
}

function C.pose(name, t)
	local fn = POSES[name] or error("choreography: no pose for " .. tostring(name))
	return fn(t)
end
function C.at(name, t) return C.pose(name, t).position end
function C.turn(name, t) return C.pose(name, t).rotation end
function C.size(name, t) return C.pose(name, t).scale end
function C.opacity(name, t) return C.pose(name, t).opacity or 1 end

-- Where each device's label goes, in clear space beside it.
function C.label(name, t)
	local p = C.pose(name, t)
	local offsets = { pad = { -1.35, 1.3, 0 }, phone = { -0.36, 0.95, 0 } }
	return transform(offsets[name], p.position, p.rotation, 1)
end

-- ── The game phone's screen, and the cut into the game ──────────────────

function C.gameScreen()
	local centre = transform({ 0, 0, DEVICE.phoneScreen.z }, GAME.position, GAME.rotation, 1)
	return centre, Space.rotate({ 0, 0, 1 }, GAME.rotation)
end

-- At the cut the screen's height (the phone's width, lying down) fills the
-- frame, so the game on the glass continues full frame.
C.CUT = { fieldOfView = 36 }
function C.cutDistance()
	return DEVICE.phoneScreen.w / 2 / math.tan(math.rad(C.CUT.fieldOfView / 2))
end

-- ── Camera ───────────────────────────────────────────────────────────────

-- Framings computed from the devices' own geometry. The iPad's chat column
-- (right of Lua Studio's stage, 1376 × 1032 pt screen) and the phone's
-- screen, each seen square-on from `distance`.
local PAD_SCREEN = { w = 2.672, h = 2.004, points = { 1376, 1032 }, z = 0.0263 }
local function onPad(u, v, distance)
	local p = PAIR.pad
	local point = transform({ (u / PAD_SCREEN.points[1] - 0.5) * PAD_SCREEN.w, (0.5 - v / PAD_SCREEN.points[2]) * PAD_SCREEN.h,
		PAD_SCREEN.z }, p.position, p.rotation, 1)
	return Space.add3(point, Space.scale3(Space.rotate({ 0, 0, 1 }, p.rotation), distance)), point
end
local function onPhone(dy, distance)
	local p = PAIR.phone
	local point = transform({ 0, dy, DEVICE.phoneScreen.z }, p.position, p.rotation, 1)
	-- A little from the left and above, so the phone keeps its depth.
	local eye = Space.add3(point, Space.scale3(Space.rotate(Space.normalize3({ -0.25, 0.12, 1 }), p.rotation), distance))
	return eye, point
end
-- Tight on the composer while the first prompt is typed, then up with its
-- bubble into the conversation.
local LOW_EYE, LOW = onPad(900, 965, 0.95)
local _, CHAT = onPad(935, 400, 2.3)
-- The whole conversation column, composer included: on a send the camera
-- pulls back to it so the bubble's flight stays in frame end to end.
local COLUMN_EYE, COLUMN = onPad(935, 530, 3.05)
local TAP_EYE, TAP = onPhone(0.2, 1.45)
-- The two-shot: the conversation beside the phone, held while a prompt is
-- sent and the phone changes, so cause and effect share one frame.
local TWO = Space.lerp3(CHAT, TAP, 0.52)
TWO[2] = TWO[2] + 0.08
local TWO_EYE = Space.add3(TWO, Space.scale3(Space.normalize3({ 0.05, 0.1, 1 }), 3.05))

-- With the phone and the code panels: a slow orbit that turns with the
-- beats, the phone right of centre so the panels and the words have the
-- left. {time, yaw, pitch, distance}.
local ORBIT = {
	{ SHOT.alone + 0.6, 0, 3, 3.3 }, { 14.8, 6, 4, 3.25 }, { 16.2, -4, 2, 3.2 }, { SHOT.turn, 3, 3, 3.25 },
}
local ASIDE = 0.85

local function orbitCamera(t)
	local function col(i) local k = {} for n, key in ipairs(ORBIT) do k[n] = { key[1], key[i] } end return k end
	local p = C.at("phone", math.min(t, SHOT.turn))
	local offset = Space.orbit({ 0, 0, 0 }, track(t, col(4)), track(t, col(2)), track(t, col(3)))
	local side = Space.normalize3({ offset[3], 0, -offset[1] })
	local target = Space.add3(p, Space.scale3(side, -ASIDE))
	return Space.add3(target, offset), target
end

local ORBIT_EYE, ORBIT_TARGET = orbitCamera(SHOT.alone + 0.6)

-- Keyed eye and target. Holds keep the camera still while a screen changes;
-- moves between them take about a second.
local CAMERA = {
	eye = {
		{ 0, { -0.95, 0.28, 3.9 } }, { SHOT.pair, { -0.7, 0.22, 3.35 } },
		{ SHOT.together, { 0.55, 0.42, 3.9 } },
		-- Low on the composer as the prompt is typed, up with the bubble,
		-- held on the answer and its diff.
		{ 4.2, LOW_EYE }, { SHOT.send1, LOW_EYE, hold = true }, { 5.35, COLUMN_EYE }, { 6.2, COLUMN_EYE, hold = true },
		-- The two-shot: the change lands on the phone, the second prompt is
		-- sent and lands too, without a cut.
		{ 6.8, TWO_EYE }, { 9.95, TWO_EYE, hold = true },
		-- In on the phone for the tap.
		{ 10.35, TAP_EYE }, { 11.5, TAP_EYE, hold = true },
		{ 12.5, { 0.6, 0.35, 4.3 } }, { SHOT.alone + 0.6, ORBIT_EYE },
	},
	target = {
		{ 0, { -0.95, 0.02, 0 } }, { SHOT.pair, { -0.75, 0.0, 0 } },
		{ SHOT.together, { 0.45, 0.05, -1.7 } },
		{ 4.2, LOW }, { SHOT.send1, LOW, hold = true }, { 5.35, COLUMN }, { 6.2, COLUMN, hold = true },
		{ 6.8, TWO }, { 9.95, TWO, hold = true },
		{ 10.35, TAP }, { 11.5, TAP, hold = true },
		{ 12.5, { 0.6, 0.05, -1.6 } }, { SHOT.alone + 0.6, ORBIT_TARGET },
	},
	lens = { { 0, 34 }, { SHOT.together, 36 }, { 6.2, 36 }, { 6.8, 33 }, { 9.95, 33 }, { 10.35, 36 }, { 12.5, 36 },
		{ SHOT.alone + 0.6, 32 } },
}

-- The turn to the game and the push into its screen: the eye closes on the
-- screen's axis until its height fills the frame at the cut.
local function portalCamera(t)
	local startEye, startTarget = orbitCamera(SHOT.turn)
	local centre, normal = C.gameScreen()
	local final = Space.add3(centre, Space.scale3(normal, C.cutDistance()))
	local u = smooth((t - SHOT.turn) / (SHOT.cut - SHOT.turn))
	local e = u * u * (3 - 2 * u)
	return Space.lerp3(startEye, final, e), Space.lerp3(startTarget, centre, math.min(1, u * 1.5)),
		32 + (C.CUT.fieldOfView - 32) * e
end

-- The close: from the world after the game to the composition, slowly.
local HERO_CAMERA = {
	eye = { { SHOT.hero, { 5.2, 0.2, 2.8 } }, { SHOT.logo, { 1.9, 0.8, 3.6 } }, { 30, { 2.15, 0.9, 3.8 } } },
	target = { { SHOT.hero, { 5.0, -0.2, -3.5 } }, { SHOT.logo, { 0.7, 0.25, -6.0 } }, { 30, { 0.75, 0.25, -6.0 } } },
	lens = { { SHOT.hero, 40 }, { SHOT.logo, 37 }, { 30, 36 } },
}

-- camera(t) -> eye, target, fieldOfView, roll
function C.camera(t)
	if t < SHOT.alone + 0.6 then
		return path(t, CAMERA.eye), path(t, CAMERA.target), track(t, CAMERA.lens), 0
	elseif t < SHOT.turn then
		local eye, target = orbitCamera(t)
		return eye, target, 32, math.sin((t - SHOT.alone) * 1.1)
	elseif t < SHOT.hero then
		local eye, target, lens = portalCamera(math.min(t, SHOT.cut))
		return eye, target, lens, 0
	end
	return path(t, HERO_CAMERA.eye), path(t, HERO_CAMERA.target), track(t, HERO_CAMERA.lens), 0
end

function C.eye(t) return (C.camera(t)) end
function C.target(t) return (select(2, C.camera(t))) end
function C.lens(t) return (select(3, C.camera(t))) end
function C.roll(t) return (select(4, C.camera(t))) end

-- Shallow focus on the phone close-ups and the closing composition.
local FOCUS = { { 10.35, 11.7, 1.6 }, { SHOT.alone + 0.6, SHOT.turn, 2.8 }, { SHOT.logo - 0.6, 30, 2.8 } }
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

-- ── The game's own camera after the cut ─────────────────────────────────

-- In level cells (Sawmill: 13 × 7). The view the phone showed, then behind
-- the player skimming the grass north of row 2, the coin at its end, and up
-- over the level. `start` is the reel time of game time 0, chosen so the
-- coins go on beats.
C.QUEST = {
	start = 19.04,
	eye = { { SHOT.cut, { 6, 14.7, 14.5 } }, { 20.6, { 6.2, 1.2, 0.5 } }, { 21.3, { 2.8, 0.95, 0.7 } },
		{ 22.1, { 1.6, 1.5, 5.9 } }, { SHOT.hero, { 4.5, 8.5, 11.5 } } },
	target = { { SHOT.cut, { 6, 0, 3 } }, { 20.6, { 3.4, 0.35, 2.0 } }, { 21.3, { 0.3, 0.3, 2.1 } },
		{ 22.1, { 0.1, 0.3, 3.7 } }, { SHOT.hero, { 5.5, 0, 3 } } },
	lens = { { SHOT.cut, C.CUT.fieldOfView }, { 20.6, 44 }, { 22.1, 42 }, { SHOT.hero, 40 } },
}

function C.questCamera(t)
	local Q = C.QUEST
	local eye = path(t, Q.eye)
	return { id = "camera", x = eye[1], y = eye[2], z = eye[3], lookAt = path(t, Q.target),
		fieldOfView = track(t, Q.lens), fieldOfViewAxis = "vertical" }
end

return C
