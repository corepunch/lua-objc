-- The Reel motion package (modules/reel): curves, the native canvas, image
-- and accumulator services, captures looked up by layout identifier, and the
-- template scene graph. Everything renders into small offscreen canvases.
_G.__headless = true
package.path = "modules/reel/?.lua;" .. package.path

local t = require("TestKit")
local Reel = require("Reel")
local Curves = require("reel.curves")
local N = Reel.native()

local function near(a, b, tolerance) return math.abs(a - b) <= (tolerance or 0.02) end
local function tmpdir()
	local dir = os.tmpname()
	os.remove(dir)
	os.execute("mkdir -p " .. dir)
	return dir
end
local function write(path, body)
	local file = assert(io.open(path, "w"))
	file:write(body)
	file:close()
end

-- ── Curves ───────────────────────────────────────────────────────────────

t.assertEqual(Curves.spring(0, 0.5, 0.5), 0, "a spring rests at 0 before release")
t.expect(near(Curves.spring(10, 0.5, 0.5), 1, 1e-6), "a spring settles at 1")
local peak = 0
for i = 1, 200 do peak = math.max(peak, Curves.spring(i / 200, 0.5, 0.4)) end
t.expect(peak > 1.05, "an underdamped spring overshoots")
peak = 0
for i = 1, 200 do peak = math.max(peak, Curves.spring(i / 200, 0.5, 1)) end
t.expect(peak <= 1 + 1e-9, "a critically damped spring never overshoots")
-- The Swift reel wrote springs as frequency (Hz) and damping; response is
-- the period, so f = 2.2 is response 1 / 2.2.
t.expect(near(Curves.spring(0.1, 1 / 2.2, 0.45), 1 - math.exp(-0.45 * 2 * math.pi * 2.2 * 0.1)
	* (math.cos(2 * math.pi * 2.2 * math.sqrt(1 - 0.45 ^ 2) * 0.1)
	+ 0.45 / math.sqrt(1 - 0.45 ^ 2) * math.sin(2 * math.pi * 2.2 * math.sqrt(1 - 0.45 ^ 2) * 0.1)), 1e-9),
	"spring(response, damping) matches the frequency form")
t.assertEqual(Curves.progress(1, 2, 3), 0, "progress is 0 before its span")
t.assertEqual(Curves.progress(4, 2, 3), 1, "progress is 1 after its span")
t.assertEqual(Curves.ease(2.5, 2, 3, "linear"), 0.5, "linear ease is proportional")
t.assertEqual(Curves.ease(3, 2, 3, "outExpo"), 1, "outExpo reaches exactly 1")
t.assertThrows(function() Curves.ease(0, 0, 1, "wobbly") end, "an unknown easing is an error")
t.assertEqual(Curves.pulse(1, { 2 }), 0, "a pulse is silent before its hit")
t.assertEqual(Curves.pulse(2, { 1, 2 }), 1, "a pulse peaks on the latest hit")
t.expect(near(Curves.mixScale(1, 4, 0.5), 2, 1e-9), "scales interpolate geometrically")
local grid = Curves.grid(120)
t.assertEqual(grid.beat, 0.5, "120 BPM has half-second beats")
t.assertEqual(grid.bar, 2, "a bar is four beats")
t.assertEqual(grid(3), 1.5, "the grid converts beats to seconds")
t.assertEqual(#Curves.every(0.5, 4, 6), 4, "every() excludes its end")

-- ── Canvas ───────────────────────────────────────────────────────────────

local canvas = N.canvas(40, 20)
local w, h = canvas:size()
t.expect(w == 40 and h == 20, "a canvas reports its pixel size")
canvas:clear(0, 0, 1, 1)
canvas:fillRect(0, 0, 10, 10, 1, 0, 0, 1)
local r, g, b, a = canvas:pixel(2, 2)
t.expect(r == 1 and g == 0 and b == 0 and a == 1, "canvas origin is top-left")
r, g, b = canvas:pixel(2, 15)
t.expect(r == 0 and b == 1, "fills stay inside their rect")
canvas:save()
canvas:alpha(0.5)
canvas:fillRect(20, 0, 10, 10, 1, 1, 1, 1)
canvas:restore()
r, g, b = canvas:pixel(25, 5)
t.expect(near(r, 0.5) and near(b, 1), "alpha blends over what is below")
canvas:save()
canvas:translate(30, 10)
canvas:scale(2)
canvas:fillRect(0, 0, 2, 2, 0, 1, 0, 1)
canvas:restore()
r, g = canvas:pixel(33, 13)
t.expect(g == 1 and r == 0, "transforms apply to drawing")
canvas:clear(0, 0, 0, 1)
canvas:save()
canvas:clip(N.path():ellipse(0, 0, 20, 20))
canvas:fillRect(0, 0, 40, 20, 1, 1, 1, 1)
canvas:restore()
t.assertEqual((canvas:pixel(10, 10)), 1, "a clip path admits its inside")
t.assertEqual((canvas:pixel(1, 1)), 0, "a clip path excludes its outside")
t.assertEqual((canvas:pixel(30, 10)), 0, "a clip ends with restore")
canvas:clear(0, 0, 0, 1)
canvas:linearGradient({ 0, 0, 0, 1, 0, 1, 1, 1, 1, 1 }, 0, 0, 40, 0)
t.expect(canvas:pixel(35, 5) > canvas:pixel(5, 5), "a linear gradient runs from its start to its end")

local text = N.text("Reel", 20, "bold")
local textWidth, ascent = text:metrics()
t.expect(textWidth > 20 and ascent > 10, "text reports typographic metrics")
t.expect(N.text("Reel Reel", 20, "bold"):metrics() > textWidth, "longer text is wider")
canvas:clear(0, 0, 0, 1)
canvas:fillText(text, 0, 18, 1, 1, 1, 1)
local lit = 0
for x = 0, 39 do for y = 0, 19 do if canvas:pixel(x, y) > 0.5 then lit = lit + 1 end end end
t.expect(lit > 20, "fillText draws glyphs above the baseline")
canvas:clear(0, 0, 0, 1)
t.expect(canvas:symbol("circle.fill", 10, 10, 16, 1, 1, 1, 1) > 0, "an SF Symbol draws")
t.expect(canvas:pixel(10, 10) > 0.9, "the symbol fills its centre")
t.assertThrows(function() canvas:symbol("no.such.symbol.reel", 10, 10, 16, 1, 1, 1, 1) end,
	"an unknown SF Symbol is an error")

canvas:clear(0.6, 0.6, 0.6, 1)
canvas:blend("difference")
canvas:fillRect(0, 0, 40, 20, 0.6, 0.6, 0.6, 1)
canvas:blend("normal")
t.expect((canvas:pixel(5, 5)) < 0.01, "difference blending cancels identical pixels")
t.assertThrows(function() canvas:blend("sparkle") end, "an unknown blend mode is an error")

-- ── Accumulator ──────────────────────────────────────────────────────────

local accumulator = N.accumulator(40, 20)
canvas:clear(0, 0, 0, 1); accumulator:add(canvas)
canvas:clear(1, 1, 1, 1); accumulator:add(canvas)
accumulator:resolve(canvas)
t.expect(near((canvas:pixel(5, 5)), 0.5), "the accumulator averages sub-frames")
t.assertThrows(function() accumulator:resolve(canvas) end, "resolving starts a fresh accumulation")
t.assertThrows(function() accumulator:add(N.canvas(10, 10)) end, "sizes must match")

-- ── Images and captures ──────────────────────────────────────────────────

local dir = tmpdir()
-- What `lua-objc --capture` writes for a 20x10 pt window at 2x: a grey page
-- with a red box at (4, 2, 6, 4) pt, and the layout with its scale.
local page = N.canvas(40, 20)
page:clear(0.5, 0.5, 0.5, 1)
page:fillRect(8, 4, 12, 8, 1, 0, 0, 1)
page:snapshot():write(dir .. "/page-dark.png")
write(dir .. "/page-dark.layout.xml", [[<?xml version="1.0" encoding="UTF-8"?>
<Layout scale="2">
  <View class="NSView" frame="0 0 20 10" window="0 0 20 10" intrinsic="-1 -1" fitting="20 10">
    <View class="LuaStackView" identifier="box" frame="4 4 6 4" window="4 2 6 4">
    </View>
    <View class="LuaTreemapView" identifier="map" frame="12 0 8 10" window="12 0 8 10">
      <TreemapCell id="big" depth="0" window="12 0 8 6" label="Big" />
      <TreemapCell id="small" depth="1" window="12 6 8 4" label="Docs &amp; &quot;Data&quot;" />
    </View>
    <View class="LuaStackView" identifier="empty" frame="0 0 1 1" window="0 0 1 1" />
  </View>
</Layout>
]])
local captures = Reel.captures(dir)
local capture = captures:get("page-dark")
local cw, ch = capture:size()
t.expect(cw == 20 and ch == 10, "a capture measures in the layout's points")
local bx, by, bw, bh = capture:rect("#box")
t.expect(bx == 4 and by == 2 and bw == 6 and bh == 4, "rect(#id) reads the view's window frame")
local cx, cy, cw2, chh = capture:rect("#map/small")
t.expect(cx == 12 and cy == 6 and cw2 == 8 and chh == 4, "rect(#view/cell) reads a treemap cell")
t.assertEqual(#capture:cells("map"), 2, "cells() lists a view's treemap cells")
t.assertEqual(capture:cells("map", 0)[1].id, "big", "cells(view, depth) filters by depth")
t.assertEqual(capture:cells("map", 1)[1].label, 'Docs & "Data"', "cell labels are unescaped")
local sr, sg = capture:sample(6, 3)
t.expect(sr > 0.9 and sg < 0.1, "sample() reads a window point at the layout's scale")
local sprite = capture:piece("#box")
t.expect(sprite.x == 4 and sprite.w == 6 and sprite.h == 4, "piece() cuts at the view's frame")
t.assertEqual(capture:piece("#box"), sprite, "pieces are cached")
local keyed = capture:piece("#box", { outset = 1, key = { 1, 1 } })
t.expect(keyed.w == 8, "outset grows a piece on every side")
local _, _, _, keyedAlpha = keyed.image:pixel(0.25, 0.25)
t.expect(keyedAlpha < 0.1, "keying clears the sampled page colour")

-- Anything a reel expects from a capture and does not find is an error that
-- names it, never an empty piece.
local function failure(fn)
	local ok, err = pcall(fn)
	return not ok and tostring(err) or nil
end
local missingCapture = failure(function() captures:get("absent-dark") end)
t.expect(missingCapture and missingCapture:find("absent-dark.png", 1, true)
	and missingCapture:find("absent-dark.layout.xml", 1, true) and missingCapture:find("--capture", 1, true),
	"a missing capture names both files and how to write them")
t.expect(failure(function() Reel.captures(dir, "run make my-captures"):get("absent-dark") end)
	:find("(run make my-captures)", 1, true), "a reel can say how its captures are made")
write(dir .. "/half-dark.layout.xml", "<Layout scale=\"2\"></Layout>")
t.expect(failure(function() captures:get("half-dark") end):find("half-dark.png", 1, true)
	and not failure(function() captures:get("half-dark") end):find("layout.xml", 1, true),
	"a capture missing only its image names only the image")
t.expect(failure(function() capture:rect("#missing") end):find("no view #missing", 1, true),
	"an unknown identifier is an error")
t.expect(failure(function() capture:cells("missing") end):find("no view #missing", 1, true),
	"cells() of an unknown view is an error")
t.expect(failure(function() capture:cells("map", 2) end):find("no treemap cells in #map at depth 2", 1, true),
	"cells() that finds none is an error")
t.expect(failure(function() capture:rows("empty") end):find("no table rows in #empty", 1, true),
	"rows() of a view without rows is an error")
t.assertThrows(function() capture:rect("#map/absent") end, "an unknown treemap cell is an error")
page:snapshot():write(dir .. "/unscaled-dark.png")
write(dir .. "/unscaled-dark.layout.xml", [[<Layout><View class="NSView" window="0 0 20 10" /></Layout>]])
t.expect(failure(function() captures:get("unscaled-dark"):size() end):find("not a lua-objc --capture layout", 1, true),
	"a layout without a scale is not a capture")
write(dir .. "/wrong-dark.layout.xml", [[<Layout scale="1"><View class="NSView" window="0 0 20 10" /></Layout>]])
page:snapshot():write(dir .. "/wrong-dark.png")
t.expect(failure(function() captures:get("wrong-dark"):piece("window") end):find("40x20 px but its layout expects 20x10 px", 1, true),
	"an image that is not the layout's root at its scale is an error")

-- ── Scene graph ──────────────────────────────────────────────────────────

local function reel(source, data)
	return Reel.fromSource(source, data or {})
end

local plain = reel([[<Reel width="40" height="20" subframes="1"><Backdrop color="#FF0000" /></Reel>]])
local frame = plain:canvas()
plain:draw(frame, 0)
t.expect((frame:pixel(20, 10)) == 1, "a backdrop fills the frame")
t.assertEqual(plain.scene.width, 40, "the <Reel> root sets the frame size")

-- Groups compose: a group at (20, 10) scaled 2 puts a child's (1, 1) at (22, 12).
local nested = reel([[<Reel width="40" height="20" subframes="1" background="#000000">
  <Group x="20" y="10" scale="2"><Group x="1" y="1"><Glow color="#FFFFFF" radius="2" /></Group></Group>
</Reel>]])
nested:draw(frame, 0)
t.expect((frame:pixel(21, 11)) > 0.5, "nested transforms compose")
t.expect((frame:pixel(15, 12)) < 0.05, "a child draws at its own position")

-- Expressions of t, motion modifiers and visibility windows.
local timed = reel([[<Reel width="40" height="20" subframes="1" background="#000000">
  <Group x="10 + t * 10" y="10" from="1" to="3"><Glow color="#FFFFFF" radius="3" /></Group>
  <Group x="30" y="10" motion="pop(2)"><Glow color="#00FF00" radius="3" /></Group>
</Reel>]])
timed:draw(frame, 0.5)
t.expect((frame:pixel(20, 10)) < 0.1, "a node is hidden before `from`")
timed:draw(frame, 1)
t.expect((frame:pixel(19, 9)) > 0.5, "attribute expressions read t")
timed:draw(frame, 3)
t.expect((frame:pixel(40 - 1, 10)) < 0.1, "a node is hidden from `to` on")
local _, green = frame:pixel(29, 9)
t.expect(green > 0.5, "a pop has landed after its spring settles")
timed:draw(frame, 0.5)
_, green = frame:pixel(29, 9)
t.expect(green < 0.1, "a pop is hidden before its time")
t.assertEqual(#timed.events, 1, "motion modifiers declare sound events")
t.expect(timed.events[1].kind == "pop" and timed.events[1].time == 2, "events carry their kind and time")

local sounds = reel([[<Reel width="40" height="20">
  <Group motion="slam(3), punch(1)" /><Group motion="pop(1.5, {sound = 'tick'})" />
</Reel>]])
t.expect(#sounds.events == 2 and sounds.events[1].kind == "tick" and sounds.events[2].kind == "slam",
	"events are sorted by time and a modifier can name its sound")

-- Text rises into place and styles come from <Style>/<Palette>.
local titled = reel([[<Reel width="80" height="40" subframes="1" background="#000000">
  <Palette name="brand" colors="#FF0000 #0000FF" />
  <Style name="title" size="20" weight="bold" gradient="brand" />
  <Text style="title" text="Hi there" x="40" y="28" at="0" exit="5" />
</Reel>]])
local textCanvas = titled:canvas()
local function litPixels(c, width, height)
	local count = 0
	for x = 0, width - 1 do for y = 0, height - 1 do
		local rr, _, bb = c:pixel(x, y)
		if rr + bb > 0.5 then count = count + 1 end
	end end
	return count
end
titled:draw(textCanvas, 3)
t.expect(litPixels(textCanvas, 80, 40) > 30, "settled text is drawn")
titled:draw(textCanvas, 6)
t.assertEqual(litPixels(textCanvas, 80, 40), 0, "text has left through its mask after exit")

-- Captures in the scene: a Window gives its children window points.
local windowed = reel([[<Reel width="40" height="20" subframes="1" background="#000000">
  <Frame capture="page-dark" x="20" y="10">
    <Piece rect="#box" motion="fadeIn(0, 0.01)" />
    <Fill rect="#map/big" color="sample(1, 1)" />
  </Frame>
</Reel>]], { captures = captures })
windowed:draw(frame, 1)
local pr, pg = frame:pixel(10 + 7, 4 + 4)
t.expect(pr > 0.9 and pg < 0.1, "a piece lands where it was in the window")
local fr, fg, fb = frame:pixel(10 + 16, 5 + 2)
t.expect(near(fr, 0.5, 0.05) and near(fg, 0.5, 0.05) and near(fb, 0.5, 0.05), "Fill paints a sampled colour over a cell")

-- Reduced-resolution layers keep soft content where it was.
local reduced = reel([[<Reel width="40" height="20" subframes="1" background="#000000">
  <Backdrop color="#000000" resolution="0.5"><Glow color="#FFFFFF" x="30" y="10" radius="6" /></Backdrop>
</Reel>]])
reduced:draw(frame, 0)
t.expect((frame:pixel(30, 10)) > 0.6 and (frame:pixel(5, 10)) < 0.1, "a reduced layer draws at full-frame position")

-- Motion blur averages sub-frames across the shutter.
local blurred = reel([[<Reel width="40" height="20" fps="10" subframes="3" shutter="1" background="#000000">
  <Group x="t * 100" y="10"><Glow color="#FFFFFF" radius="2" /></Group>
</Reel>]])
blurred:frame(frame, 0.2)
t.expect((frame:pixel(20, 10)) > 0.15 and (frame:pixel(20, 10)) < 0.6, "a moving node is blurred along its path")

-- Errors name the element.
local ok, err = pcall(reel, [[<Reel><Sparkle /></Reel>]])
t.expect(not ok and tostring(err):find("<Sparkle>") ~= nil, "unknown elements are reported by name")
ok, err = pcall(reel, [[<Reel><Text style="missing" text="x" /></Reel>]])
t.expect(not ok and tostring(err):find("unknown style") ~= nil, "unknown styles are reported")
ok, err = pcall(reel, [[<Reel><Group motion="wobble(1)" /></Reel>]])
t.expect(not ok and tostring(err):find("<Group> motion") ~= nil, "bad motion is reported with its element")
ok, err = pcall(reel, [[<Group />]])
t.expect(not ok and tostring(err):find("<Reel> root") ~= nil, "a reel needs a <Reel> root")

-- ── The toolkit: pen, shapes, colours ────────────────────────────────────

local Pen, Shape = Reel.Pen, Reel.Shape
local c1 = Reel.rgb(0xFF8000)
t.expect(c1[1] == 1 and near(c1[2], 128 / 255, 1e-9) and c1[3] == 0 and c1[4] == 1, "rgb() reads hex numbers")
t.assertEqual(Reel.rgb("#00FF0080")[4], 128 / 255, "rgb() reads #RRGGBBAA strings")
t.assertEqual(Reel.rgb(0xFFFFFF, 0.5)[4], 0.5, "rgb() takes an alpha")

local penCanvas = N.canvas(100, 100)
local pen = Pen.new(penCanvas, N)
penCanvas:clear(0, 0, 0, 1)
pen:fill(Shape.sector(50, 50, 20, 40, -math.pi / 2, math.pi / 2), 0xFFFFFF)
t.expect((penCanvas:pixel(65, 35)) > 0.9, "a sector covers its quarter")
t.expect((penCanvas:pixel(35, 35)) < 0.1, "a sector leaves the rest")
t.expect((penCanvas:pixel(52, 45)) < 0.1, "a sector keeps its hole")
penCanvas:clear(0, 0, 0, 1)
pen:fill(Shape.without(Shape.rect(40, 40, 20, 20)), 0xFFFFFF)
t.expect((penCanvas:pixel(50, 50)) < 0.1 and (penCanvas:pixel(10, 10)) > 0.9, "without() cuts a hole in everything")
penCanvas:clear(0, 0, 0, 1)
pen:place({ x = 50, y = 50, scale = 2, alpha = 0.5, anchor = { 5, 5 } }, function(p)
	p:rect(0, 0, 10, 10, 0xFFFFFF)
	t.assertEqual(p.zoom, 2, "place() tracks the on-screen scale")
end)
t.expect(near((penCanvas:pixel(45, 45)), 0.5) and (penCanvas:pixel(35, 35)) < 0.1, "place() anchors, scales and fades")
t.assertEqual(pen.zoom, 1, "place() restores the scale")
pen:place({ alpha = 0 }, function() error("an invisible placement must not draw") end)
penCanvas:clear(0, 0, 0, 1)
pen:ring({ cx = 50, cy = 50, r = 30, width = 10, sweep = 1, segments = { { 50, 0xFF0000 }, { 50, 0x0000FF } }, gap = 0 })
local rr, _, rb = penCanvas:pixel(80, 50)
t.expect(rr > 0.9 and rb < 0.1, "a ring's first segment runs clockwise from 12 o'clock")
rr, _, rb = penCanvas:pixel(20, 50)
t.expect(rb > 0.9, "a ring's second segment follows")
local function snapshotBurst()
	penCanvas:clear(0, 0, 0, 1)
	pen:burst({ at = 0, x = 50, y = 50, colors = { 0xFFFFFF }, count = 40, speed = 200, seed = 9 }, 0.2)
	local lit = 0
	for x = 0, 99, 3 do for y = 0, 99, 3 do if penCanvas:pixel(x, y) > 0.3 then lit = lit + 1 end end end
	return lit
end
local burstLit = snapshotBurst()
t.expect(burstLit > 0, "a burst throws particles")
t.assertEqual(snapshotBurst(), burstLit, "a burst is the same every render")
penCanvas:clear(0, 0, 0, 1)
pen:chip("hammer.fill", 0x1C7CF4, 50, 50, 40)
local _, _, chipBlue = penCanvas:pixel(35, 50)
t.expect(chipBlue > 0.8, "a chip fills its rounded square")

-- ── Curves for cues ──────────────────────────────────────────────────────

local keys = { { 1, 2, 100 }, { 3, 4, 50 } }
t.assertEqual(Curves.keys(0, 10, keys), 10, "keys() holds the start before the first move")
t.assertEqual(Curves.keys(2.5, 10, keys), 100, "keys() holds each value between moves")
t.assertEqual(Curves.keys(9, 10, keys), 50, "keys() ends on the last value")
t.expect(near(Curves.keys(1.5, 10, keys, "linear"), 55, 1e-9), "keys() eases between values")
local flipX, flips = Curves.flip(1.165, { 1 }, 0.32)
t.expect(flipX < 0.1 and flips == 1, "a flip is edge-on halfway and counts from there")
t.assertEqual((Curves.flip(2, { 1 }, 0.32)), 1, "a finished flip is flat again")

-- ── Elements: variables, stagger, clips, text, shots, cues ───────────────

local shotCalls = {}
local vocab = reel([[<Reel width="80" height="40" subframes="1" background="#000000">
  <Let name="half" value="t / 2" />
  <Group x="half * 10" y="20" clip="rect(-5, -20, 10, 40)"><Rect x="-20" y="-20" width="40" height="40" color="#FFFFFF" /></Group>
  <Group stagger="1"><Cue sound="tick" at="2" /><Cue sound="tick" at="2" until="3" /></Group>
  <Draw with="probe" x="70" y="10" />
</Reel>]], { shots = { probe = function(p, time, node) table.insert(shotCalls, { p, time, node.tag }) end } })
local vocabCanvas = vocab:canvas()
vocab:draw(vocabCanvas, 4)
t.expect((vocabCanvas:pixel(20, 20)) > 0.9, "Let variables feed later attributes")
t.expect((vocabCanvas:pixel(28, 20)) < 0.1, "clip limits a node and its children")
t.expect(#shotCalls == 1 and shotCalls[1][2] == 4 and shotCalls[1][3] == "Draw", "a <Draw> shot receives the pen, t and its node")
t.expect(vocab.events[1].time == 2 and vocab.events[2].time == 3 and vocab.events[2]["until"] == 4,
	"stagger delays each child's events, including cue ends")
t.assertThrows(function() reel([[<Reel><Draw with="missing" /></Reel>]], { shots = {} }) end, "an unknown shot is an error")
local setupCalls, drawCalls = 0, 0
local staged = reel([[<Reel width="20" height="10" subframes="1"><Draw with="staged" /></Reel>]], { shots = { staged = {
	setup = function(node, context) setupCalls = setupCalls + 1; node.box = { context.captures:get("page-dark"):rect("#box") } end,
	draw = function(_, _, node) drawCalls = drawCalls + node.box[1] end,
} }, captures = captures })
t.expect(setupCalls == 1 and drawCalls == 0, "a shot's setup runs once while the reel loads")
staged:draw(staged:canvas(), 1)
t.assertEqual(drawCalls, 4, "a shot's draw sees what its setup resolved")
t.expect(failure(function()
	reel([[<Reel><Draw with="late" /></Reel>]], { captures = captures, shots = { late = {
		setup = function(_, context) context.captures:get("page-dark"):rect("#gone") end, draw = function() end } } })
end):find("no view #gone", 1, true), "a shot's missing piece fails the load, not a frame")
t.assertThrows(function() reel([[<Reel><Draw with="nodraw" /></Reel>]], { shots = { nodraw = {} } }) end,
	"a shot table needs a draw function")
t.expect(failure(function()
	reel([[<Reel><Frame capture="page-dark"><Piece rect="#gone" /></Frame></Reel>]], { captures = captures })
end):find("no view #gone", 1, true), "a <Piece> of a missing view fails the load")
t.expect(failure(function()
	reel([[<Reel><Frame capture="page-dark"><Fill rect="#map/gone" color="#000000" /></Frame></Reel>]], { captures = captures })
end):find("no cell #map/gone", 1, true), "a <Fill> of a missing cell fails the load")
t.expect(failure(function()
	reel([[<Reel><Window capture="absent-dark" /></Reel>]], { captures = captures })
end):find("absent-dark.png", 1, true), "an element's missing capture fails the load")
t.assertThrows(function() reel([[<Reel><Let name="step" value="1" /></Reel>]]) end, "a Let cannot hide a helper")

local staggered = reel([[<Reel width="40" height="20" subframes="1" background="#000000">
  <Group stagger="1"><Group x="10" y="10" motion="pop(0)"><Glow radius="3" /></Group><Group x="30" y="10" motion="pop(0)"><Glow radius="3" /></Group></Group>
</Reel>]])
staggered:draw(frame, 0.5)
t.expect((frame:pixel(9, 9)) > 0.3 and (frame:pixel(29, 9)) < 0.05, "stagger runs each child later than the one before")

local stretched = reel([[<Reel width="40" height="20" subframes="1" background="#000000">
  <Group x="20" y="10" sx="3" sy="2" anchorX="1 + t" anchorY="1"><Rect width="2" height="2" color="#FFFFFF" /></Group>
</Reel>]])
stretched:draw(frame, 0)
t.expect((frame:pixel(22, 10)) > 0.9 and (frame:pixel(24, 10)) < 0.1 and (frame:pixel(20, 13)) < 0.1,
	"sx and sy stretch around the anchor")
stretched:draw(frame, 1)
t.expect((frame:pixel(15, 10)) > 0.9 and (frame:pixel(21, 10)) < 0.1, "anchorX can move with t")

local slammed = reel([[<Reel width="200" height="60" subframes="1" background="#000000">
  <Style name="s" size="30" weight="bold" color="#FFFFFF" />
  <Style name="red" size="30" weight="bold" color="#FF0000" />
  <Slam style="s" style2="red" text="Go now" x="100" y="45" at="1, 2" />
</Reel>]])
t.expect(#slammed.events == 2 and slammed.events[2].kind == "slam", "every slammed word sounds")
local slamCanvas = slammed:canvas()
local function redAndWhite(time)
	slammed:draw(slamCanvas, time)
	local white, red = 0, 0
	for x = 0, 199, 2 do for y = 0, 59, 2 do
		local pr, pg = slamCanvas:pixel(x, y)
		if pr > 0.6 and pg > 0.6 then white = white + 1 elseif pr > 0.6 then red = red + 1 end
	end end
	return white, red
end
local w1, r1 = redAndWhite(1.5)
t.expect(w1 > 0 and r1 == 0, "a word waits for its own hit")
local w2, r2 = redAndWhite(4)
t.expect(w2 > 0 and r2 > 0, "per-word styles apply")
t.assertThrows(function() reel([[<Reel><Style name="s" size="10" /><Slam style="s" text="a b" at="1" /></Reel>]]) end,
	"a slam needs one hit per word")

local counted = reel([[<Reel width="200" height="60" subframes="1" background="#000000">
  <Style name="n" size="30" weight="bold" color="#FFFFFF" digits="true" />
  <Counter style="n" x="100" y="45" value="t" format="%.1f" final="9.9" unit=" GB" />
</Reel>]])
local countCanvas = counted:canvas()
counted:draw(countCanvas, 9.9)
local counterLit = 0
for x = 0, 199, 2 do for y = 0, 59, 2 do if countCanvas:pixel(x, y) > 0.5 then counterLit = counterLit + 1 end end end
t.expect(counterLit > 20, "a counter draws its reading and unit")

-- ── Capture rows and parts ───────────────────────────────────────────────

write(dir .. "/rows-dark.layout.xml", [[<Layout scale="2">
  <View class="LuaScrollView" identifier="list" window="0 0 20 10">
    <View class="NSTableView" window="0 0 20 10">
      <View class="LuaTableRowView" window="0 5 20 5" />
      <View class="NSTableRowView" window="0 0 20 5" />
    </View>
  </View>
</Layout>]])
page:snapshot():write(dir .. "/rows-dark.png")
local rows = captures:get("rows-dark")
t.assertEqual(#rows:rows("list"), 2, "table rows, and rows of an NSTableRowView subclass, belong to the nearest identified view")
t.assertEqual(rows:row("list", 1).y, 0, "rows are in display order, not the table's reuse order")
local rx, ry, rw, rh = rows:rect("#list/row/2")
t.expect(rx == 0 and ry == 5 and rw == 20 and rh == 5, "rect(#view/row/N) reads the Nth row")
t.assertEqual(rows:row("list", 2).y, 5, "row(view, n) reads the Nth row")
t.expect(failure(function() rows:rect("#list/row/3") end):find("no row 3 in #list (2 rows)", 1, true),
	"a missing row is an error that says how many there are")
t.assertThrows(function() rows:row("list", 0) end, "row() counts from 1")
local part = rows:piece("#list/row/1", { part = { 4, 2, 6, 3 } })
t.expect(part.x == 4 and part.y == 2 and part.w == 6 and part.h == 3, "part narrows a piece to a sub-rectangle")
local small = rows:piece("window", { downsample = 0.5 })
local smallW = small.image:pixelSize()
t.expect(small.w == 20 and smallW == 20, "downsample keeps the size in points with fewer pixels")

-- ── Audio ────────────────────────────────────────────────────────────────

local Audio, I = Reel.audio, Reel.instruments
local mixA, mixB = Audio.new(1, 1000), Audio.new(1, 1000)
local sameNoise = true
for _ = 1, 50 do if mixA:noise() ~= mixB:noise() then sameNoise = false end end
t.expect(sameNoise, "noise is deterministic")
local first, last = mixA:range(0.25, 0.5)
t.expect(first == 250 and last == 749, "range() covers the samples in an interval")
mixA:add(10, 1, 0, 0.5)
t.expect(mixA.dryL[11] == 2 and mixA.dryR[11] == 0 and mixA.sendL[11] == 1, "add() pans and sends")
t.assertEqual(Audio.midiHz(69), 440, "A4 is 440 Hz")
local drums = Audio.new(1, 8000)
I.kick(drums, 0.5)
local before, after = 0, 0
for i = 1, 3900 do before = before + math.abs(drums.dryL[i]) end
for i = 4001, 5000 do after = after + math.abs(drums.dryL[i]) end
t.expect(before == 0 and after > 10, "a kick sounds from its time on")
I.bell(drums, 0.1, 880, 0.5)
I.whoosh(drums, 0.2, 0.4)
local left, right = drums:master({ kicks = { 0.5 } })
local peakLevel = 0
for i = 1, #left do peakLevel = math.max(peakLevel, math.abs(left[i]), math.abs(right[i])) end
t.expect(near(peakLevel, 0.89, 1e-6), "master normalises to its peak")

-- Motion sounds only where a sound is implied or asked for.
local quiet = reel([[<Reel><Group motion="enter{at = 1}, leave{at = 2}, pop(3, {sound = false})" /><Group motion="enter{at = 4, sound = 'pop'}" /></Reel>]])
t.expect(#quiet.events == 1 and quiet.events[1].time == 4, "enter, leave and silenced pops make no sound unless asked")

-- ── Movies ───────────────────────────────────────────────────────────────

-- Movie encoding writes an H.264 file with every frame, with sound muxed in,
-- and the frame reader decodes it back.
local movieReel = reel([[<Reel width="64" height="32" fps="10" duration="0.5" subframes="1"><Backdrop color="#336699" /></Reel>]])
local moviePath = dir .. "/tiny.mov"
local wavPath = dir .. "/tiny.wav"
local tone = Audio.new(0.5, 44100)
I.tone(tone, 0, 440, { length = 0.5 })
local toneL, toneR = tone:master()
Reel.writeWav(wavPath, 44100, toneL, toneR)
t.assertEqual(movieReel:movie(moviePath, { audio = wavPath }), 5, "movie() returns the frames written")
local reader = N.frames(moviePath)
local decoded, firstFrame = 0, nil
while true do
	local image = reader:next()
	if not image then break end
	decoded = decoded + 1
	firstFrame = firstFrame or image
end
t.assertEqual(decoded, 5, "the frame reader decodes every frame")
local fr2, fg2, fb2 = firstFrame:pixel(30, 15)
t.expect(near(fr2, 0x33 / 255, 0.05) and near(fg2, 0x66 / 255, 0.05) and near(fb2, 0x99 / 255, 0.05),
	"decoded frames keep their colour")

os.execute("rm -rf " .. dir)
os.exit(t.summary() and 0 or 1)
