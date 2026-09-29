-- Reel's SceneKit layer (modules/reel/reel/world.lua, native/scene.m) and
-- its 3-D helpers (reel/space.lua): the offscreen renderer, <SceneView>
-- records posed from `t`, surfaces, states, transitions and projection.
-- Everything renders into small offscreen canvases.
_G.__headless = true
package.path = "modules/reel/?.lua;" .. package.path

local t = require("TestKit")
local Reel = require("Reel")
local Space = require("reel.space")
local N = Reel.native()

local function near(a, b, tolerance) return math.abs(a - b) <= (tolerance or 0.02) end
local function nearVector(a, b, tolerance)
	return near(a[1], b[1], tolerance) and near(a[2], b[2], tolerance) and near(a[3], b[3], tolerance)
end

-- ── Space ────────────────────────────────────────────────────────────────

t.expect(nearVector(Space.orbit({ 0, 0, 0 }, 2, 0, 0), { 0, 0, 2 }, 1e-9), "orbit yaw 0 stands in front, on +z")
t.expect(nearVector(Space.orbit({ 1, 0, 0 }, 2, 90, 0), { 3, 0, 0 }, 1e-9), "positive yaw orbits to the right")
t.expect(nearVector(Space.orbit({ 0, 0, 0 }, 2, 0, 90), { 0, 2, 0 }, 1e-9), "pitch 90 looks straight down")
t.expect(nearVector(Space.dolly({ 0, 0, 10 }, { 0, 0, 0 }, 3), { 0, 0, 3 }, 1e-9), "dolly moves along the camera axis")
t.expect(near(Space.fill(2, 90), 1, 1e-9), "fill() is the distance that frames a height")
local keys = { { 0, { 0, 0, 0 } }, { 1, { 1, 2, 3 } }, { 3, { 5, 0, 0 } } }
t.expect(nearVector(Space.path(-1, keys), { 0, 0, 0 }), "a path holds its first key before it")
t.expect(nearVector(Space.path(1, keys), { 1, 2, 3 }, 1e-9), "a path passes through every key")
t.expect(nearVector(Space.path(9, keys), { 5, 0, 0 }), "a path holds its last key after it")
-- Continuous velocity through the middle key: the slopes either side agree.
local e = 1e-4
local before = Space.sub3(Space.path(1, keys), Space.path(1 - e, keys))
local after = Space.sub3(Space.path(1 + e, keys), Space.path(1, keys))
t.expect(nearVector(before, after, 1e-5), "a path is smooth through its keys")
local start = Space.sub3(Space.path(e, keys), Space.path(0, keys))
t.expect(Space.length3(start) < 1e-5, "a path eases out of its first key")
local held = { { 0, { 0, 0, 0 } }, { 1, { 1, 0, 0 }, hold = true }, { 2, { 2, 0, 0 } } }
t.expect(Space.length3(Space.sub3(Space.path(1 + e, held), Space.path(1, held))) < 1e-5, "a held key stops dead")
t.expect(near(Space.track(0.5, { { 0, 10 }, { 1, 20 } }), 15, 1e-9), "track() eases between two values")
local holding = { { 0, { 0, 0, 0 } }, { 1, { 5, 0, 0 } }, { 3, { 5, 0, 0 } }, { 4, { 9, 0, 0 } } }
t.expect(nearVector(Space.path(2, holding), { 5, 0, 0 }, 1e-9), "a path between two equal keys holds still")
t.expect(near(Space.track(2, { { 0, 0 }, { 1, 5 }, { 3, 5 }, { 4, 9 } }), 5, 1e-9), "and so does a track")
t.assertThrows(function() Space.path(0, {}) end, "a path needs keys")

-- ── Native scene ─────────────────────────────────────────────────────────

-- rotate() and transform() agree with SceneKit: a child's origin under a
-- turned, scaled, moved parent lands where world() finds it.
do
	local s = N.scene()
	local node = s:node(0)
	local euler = { 25, -40, 70 }
	s:pose(node, 1, 2, -1, math.rad(euler[1]), math.rad(euler[2]), math.rad(euler[3]), 2, 2, 2)
	local wx, wy, wz = s:world(node, 0.5, -0.3, 0.8)
	t.expect(nearVector({ wx, wy, wz }, Space.transform({ 0.5, -0.3, 0.8 }, { 1, 2, -1 }, euler, 2), 1e-4),
		"rotate() and transform() match SceneKit's euler order")
end

local scene = N.scene()
local camera = scene:node(0)
scene:camera(camera, { fieldOfView = 40 })
scene:pose(camera, 0, 0, 4, 0, 0, 0, 1, 1, 1)
local box = scene:node(0)
t.expect(scene:geometry(box, "box", { width = 1, height = 1, length = 1 }), "a box geometry builds")
scene:material(box, { color = { 1, 0, 0, 1 }, lighting = "constant" })
scene:pose(box, 0, 0, 0, 0, 0, 0, 1, 1, 1)
local image = scene:render(camera, 64, 48)
local pw, ph = image:pixelSize()
t.expect(pw == 64 and ph == 48, "a render has the requested pixel size")
local r, g, b, a = image:pixel(32, 24)
t.expect(r > 0.95 and g < 0.05 and a > 0.99, "the box fills the centre of the frame")
t.expect(select(4, image:pixel(1, 1)) < 0.01, "nothing drawn is transparent")
scene:pose(box, 5, 0, 0, 0, 0, 0, 1, 1, 1)
t.expect(select(4, scene:render(camera, 64, 48):pixel(32, 24)) < 0.01, "a pose applies to the next render")
scene:pose(box, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, true)
t.expect(select(4, scene:render(camera, 64, 48):pixel(32, 24)) < 0.01, "a hidden node draws nothing")
local nil1, message = scene:geometry(box, "blob", {})
t.expect(nil1 == nil and message:find("blob"), "an unknown geometry names itself")
local nil2, missing = scene:model(scene:node(0), "no/such/model.obj")
t.expect(nil2 == nil and missing:find("cannot read"), "a missing model is reported")
t.expect(scene:model(scene:node(0), "apps/coin-quest/assets/models/coin-gold.obj"), "Coin Quest's models load")
local px, py, depth = scene:project(camera, 64, 48, 0, 0, 0)
t.expect(near(px, 32, 1e-3) and near(py, 24, 1e-3) and near(depth, 4, 1e-6), "project() maps the look point to the centre")
px, py = scene:project(camera, 64, 48, 0, 1, 0)
t.expect(py < 24, "up in the world is up in the frame")
t.expect(scene:geometry(scene:node(0), "slab", { width = 1, height = 2, length = 0.1, cornerRadius = 0.2, chamfer = 0.02 }),
	"a slab (rounded device body) builds")
t.assertThrows(function() scene:render(box, 8, 8) end, "only a camera renders")
t.assertThrows(function() scene:pose(999, 0, 0, 0, 0, 0, 0, 1, 1, 1) end, "an unknown handle is an error")

-- ── <SceneView> ──────────────────────────────────────────────────────────

local function reel(body, data)
	return Reel.fromSource('<Reel width="64" height="48" fps="30" duration="4" background="#000000" subframes="1">'
		.. body .. '</Reel>', data)
end
local function frame(r, time)
	local canvas = r:canvas()
	r:draw(canvas, time)
	return canvas
end

local lens = '<Camera position="0 0 4" lookAt="0 0 0" fieldOfView="40" />'
local moving = reel('<SceneView>' .. lens
	.. '<Node geometry="box" color="#FF0000" lighting="constant" position="step(t - 1) * 5, 0, 0" /></SceneView>')
t.expect(frame(moving, 0.5):pixel(32, 24) > 0.95, "a record renders where its attributes put it")
t.expect(frame(moving, 1.5):pixel(32, 24) < 0.05, "attributes are expressions of t")
t.expect(frame(moving, 0.5):pixel(32, 24) > 0.95, "frames are pure functions of t (scrubbing back)")
local listed = reel('<SceneView>' .. lens
	.. '<Node geometry="box" color="#FF0000" lighting="constant" position="{0, step(t - 1) * 5, 0}" scale="1, 1, 1" /></SceneView>')
t.expect(frame(listed, 0.5):pixel(32, 24) > 0.95 and frame(listed, 1.5):pixel(32, 24) < 0.05,
	"a vector is a {x, y, z} table or three values")

local a1, a2 = frame(moving, 0.5), frame(moving, 0.5)
local same = true
for x = 0, 63, 7 do for y = 0, 47, 5 do
	local r1, g1, b1 = a1:pixel(x, y)
	local r2, g2, b2 = a2:pixel(x, y)
	if r1 ~= r2 or g1 ~= g2 or b1 ~= b2 then same = false end
end end
t.expect(same, "rendering the same instant twice is identical")

local timed = reel('<SceneView>' .. lens
	.. '<Node geometry="box" color="#FF0000" lighting="constant" from="1" to="2" transition="pop" /></SceneView>')
t.expect(frame(timed, 0.5):pixel(32, 24) < 0.05, "a record is off stage before `from`")
t.expect(frame(timed, 1.5):pixel(32, 24) > 0.95, "and on stage after its insertion transition")
t.expect(frame(timed, 2.5):pixel(32, 24) < 0.05, "and gone after `to` and its removal transition")
local popping = frame(timed, 1.05)
local lit = 0
for x = 0, 63 do if popping:pixel(x, 24) > 0.5 then lit = lit + 1 end end
local full = 0
local settled = frame(timed, 1.5)
for x = 0, 63 do if settled:pixel(x, 24) > 0.5 then full = full + 1 end end
t.expect(lit > 0 and lit < full, "a pop grows the node in")

local backed = reel('<SceneView background="#0000FF">' .. lens .. '</SceneView>')
t.expect(select(3, frame(backed, 0):pixel(1, 1)) > 0.95, "a background fills the view behind the scene")

local driven = reel('<SceneView states="poses(t)">' .. lens
	.. '<Node id="hero" geometry="box" color="#00FF00" lighting="constant" /></SceneView>',
	{ poses = function(time) return { { id = "hero", x = time < 1 and 0 or 5 }, { id = "gone", x = 1 } } end })
t.expect(select(2, frame(driven, 0.5):pixel(32, 24)) > 0.95, "states pose identified nodes")
t.expect(select(2, frame(driven, 1.5):pixel(32, 24)) < 0.05, "states override the template, like nodeStates")

-- States pose a template's camera too: aim and lens.
local aimed = reel('<SceneView states="poses(t)"><Camera id="camera" position="0 0 4" lookAt="0 0 0" fieldOfView="40" />'
	.. '<Node geometry="box" position="3 0 0" color="#00FF00" lighting="constant" /></SceneView>',
	{ poses = function(time) return { { id = "camera", lookAt = time < 1 and { 0, 0, 0 } or { 3, 0, 0 },
		fieldOfView = time < 2 and 40 or 150 } } end })
t.expect(select(2, frame(aimed, 0.5):pixel(32, 24)) < 0.05, "the template's lookAt holds without a state")
t.expect(select(2, frame(aimed, 1.5):pixel(32, 24)) > 0.95, "a state's lookAt aims the camera")
local wide, narrow = 0, 0
for x = 0, 63 do
	if select(2, frame(aimed, 2.5):pixel(x, 24)) > 0.5 then wide = wide + 1 end
	if select(2, frame(aimed, 1.5):pixel(x, 24)) > 0.5 then narrow = narrow + 1 end
end
t.expect(wide < narrow, "a state's fieldOfView changes the lens")

local screen = reel('<SceneView>' .. lens
	.. '<Node geometry="plane" width="2" height="1.5"><Surface width="20" height="15" background="#0000FF">'
	.. '<Rect x="0" y="0" width="10" height="15" color="#FFFF00" /></Surface></Node></SceneView>')
local shot = frame(screen, 0)
local lr, lg, lb = shot:pixel(28, 24)
local rr, rg, rb = shot:pixel(36, 24)
t.expect(lr > 0.9 and lg > 0.9 and lb < 0.1, "a surface draws reel elements onto its node")
t.expect(rb > 0.9 and rr < 0.1, "and keeps its background elsewhere, the right way round")
local upright = reel('<SceneView>' .. lens
	.. '<Node geometry="plane" width="2" height="1.5"><Surface width="20" height="15" background="#0000FF">'
	.. '<Rect x="0" y="0" width="20" height="7" color="#FFFF00" /></Surface></Node></SceneView>')
local up = frame(upright, 0)
t.expect(up:pixel(32, 20) > 0.9 and up:pixel(32, 28) < 0.1, "a surface is the right way up")

-- A surface off screen is not drawn; a far one is drawn coarser.
local draws = 0
local counted = reel('<SceneView>' .. lens
	.. '<Node id="near" geometry="plane" width="2" height="1.5" position="{step(t - 1) * 40, 0, 0}"><Surface width="400" height="300" density="2">'
	.. '<Draw with="count" /></Surface></Node></SceneView>', { shots = { count = function() draws = draws + 1 end } })
frame(counted, 0.5)
t.assertEqual(draws, 1, "a surface on screen draws")
frame(counted, 1.5)
t.assertEqual(draws, 1, "a surface off screen does not draw")
local sized = Reel.fromSource('<Reel width="1280" height="960" subframes="1"><SceneView>' .. lens
	.. '<Node id="far" geometry="plane" width="2" height="1.5" position="{0, 0, -60 * step(t - 1)}"><Surface width="400" height="300" density="2">'
	.. '<Rect width="400" height="300" color="#FF0000" /></Surface></Node></SceneView></Reel>')
local function densities(r)
	local found = {}
	local function walk(node)
		if node.view then for _, record in ipairs(node.view.records) do
			for level in pairs(record.surface and record.surface.canvases or {}) do table.insert(found, level) end
		end end
		for _, child in ipairs(node.children) do walk(child) end
	end
	walk(r.scene.root)
	table.sort(found)
	return found
end
frame(sized, 0.5)
frame(sized, 1.5)
local levels = densities(sized)
t.expect(#levels == 2 and levels[1] < levels[2] and levels[2] <= 2, "a far surface draws at a lower density, never above its own")

local spinning = reel('<SceneView>' .. lens
	.. '<Node geometry="box" width="2" height="0.3" length="0.3" color="#FFFFFF" lighting="constant" spin="0 0 90" /></SceneView>')
t.expect(frame(spinning, 0):pixel(18, 24) > 0.9, "spin starts from the template pose")
t.expect(frame(spinning, 1):pixel(18, 24) < 0.1 and frame(spinning, 1):pixel(32, 12) > 0.9,
	"spin turns the content by its rate times t")

-- A game's own prefab renders unchanged: Coin Quest's coin, with its spin
-- and bob, as the live SceneView draws it.
local here = os.getenv("PWD") .. "/"
local coin = Reel.load(here .. "tests/fixtures/reel_scene/Coin.etlua", { root = here })
t.expect(frame(coin, 0.3):pixel(32, 24) > 0.3, "Coin Quest's coin prefab renders in a reel")

local projected = reel('<SceneView id="stage">' .. lens .. '</SceneView>'
	.. '<Let name="spot" value="project(\'stage\', {0, 0, 0})" />'
	.. '<Rect x="spot[1] - 2" y="spot[2] - 2" width="4" height="4" color="#FFFFFF" />')
t.expect(frame(projected, 0):pixel(32, 24) > 0.9, "project() pins 2-D elements to 3-D points")

t.assertThrows(function() reel('<SceneView><Node geometry="box" /></SceneView>') end, "a SceneView needs a camera")
t.assertThrows(function() reel('<SceneView>' .. lens .. '<Node geometry="box" colour="#FFFFFF" /></SceneView>') end,
	"an unknown record attribute is an error")
t.assertThrows(function() reel('<SceneView>' .. lens .. '<Rect /></SceneView>') end, "only records live in a SceneView")
t.assertThrows(function() reel('<Surface width="10" height="10" />') end, "a Surface belongs inside a scene node")
t.assertThrows(function() reel('<SceneView>' .. lens .. '<Node model="no/such.obj" /></SceneView>') end,
	"a missing model fails the load")
t.assertThrows(function() reel('<SceneView>' .. lens .. '<Node id="a" /><Node id="a" /></SceneView>') end,
	"ids are unique")
t.assertThrows(function() reel('<SceneView camera="\'nope\'">' .. lens .. '</SceneView>'):draw(N.canvas(64, 48), 0) end,
	"an unknown camera is an error")
-- The live view's app hooks have no meaning offline and are accepted.
t.expect(reel('<SceneView onKey="key" onFrame="frame">' .. lens .. '</SceneView>'), "app-only hooks are ignored")

-- <Image>: a plain image file (a simulator screenshot) at its size in points.
local imageDir = os.tmpname()
os.remove(imageDir)
os.execute("mkdir -p " .. imageDir)
local pixels = N.canvas(8, 8)
pixels:clear(1, 0, 0, 1)
pixels:snapshot():write(imageDir .. "/red.png")
local pictured = reel('<Image src="' .. imageDir .. '/red.png" density="2" x="10" y="10" />'
	.. '<Image src="' .. imageDir .. '/red.png" x="30" y="10" width="20" height="4" />')
local pc = frame(pictured, 0)
t.expect(pc:pixel(12, 12) > 0.9 and pc:pixel(15, 12) < 0.1, "an image at density 2 is half its pixel size in points")
t.expect(pc:pixel(48, 12) > 0.9 and pc:pixel(40, 15) < 0.1, "width and height stretch an image")
t.assertThrows(function() reel('<Image src="' .. imageDir .. '/none.png" />') end, "a missing image fails the load")

-- Sub-frames can follow the picture.
local calls = 0
local adaptive = Reel.fromSource('<Reel width="8" height="8" fps="30" subframes="2 + 4 * step(t - 1)"><Draw with="count" /></Reel>',
	{ shots = { count = function() calls = calls + 1 end } })
adaptive:frame(adaptive:canvas(), 0.5)
t.assertEqual(calls, 2, "subframes as an expression of t (slow passage)")
adaptive:frame(adaptive:canvas(), 1.5)
t.assertEqual(calls, 8, "subframes as an expression of t (fast passage)")

-- A monospaced style sets code in the monospaced system font: "iii" is as
-- wide as "MMM".
t.expect(math.abs(N.text("iii", 20, "regular", 0, "mono"):metrics() - N.text("MMM", 20, "regular", 0, "mono"):metrics()) < 0.01,
	"design mono is monospaced")
t.expect(N.text("iii", 20, "regular", 0):metrics() < N.text("MMM", 20, "regular", 0):metrics(), "the system font is proportional")

-- Identifiers containing "/" (an app's "task/2") cut as whole views.
Reel.native()
local captures = Reel.captures(imageDir)
local page = N.canvas(40, 20)
page:clear(0.5, 0.5, 0.5, 1)
page:snapshot():write(imageDir .. "/app.png")
local layout = assert(io.open(imageDir .. "/app.layout.xml", "w"))
layout:write('<?xml version="1.0"?><Layout scale="2"><View class="NSView" window="0 0 20 10">'
	.. '<View class="NSView" identifier="task/2" window="2 3 4 5" /></View></Layout>')
layout:close()
local x, y, w, h = captures:get("app"):rect("#task/2")
t.expect(x == 2 and y == 3 and w == 4 and h == 5, "a view whose identifier contains a slash cuts by its whole name")
os.execute("rm -rf " .. imageDir)

os.exit(t.summary() and 0 or 1)
