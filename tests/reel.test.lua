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
-- A 2x capture of a 20x10 pt window: grey page, a red box at (4, 2, 6, 4) pt.
local page = N.canvas(40, 20)
page:clear(0.5, 0.5, 0.5, 1)
page:fillRect(8, 4, 12, 8, 1, 0, 0, 1)
page:snapshot():write(dir .. "/page-dark.jpg", 1)
write(dir .. "/page-dark.layout.xml", [[<?xml version="1.0" encoding="UTF-8"?>
<Layout>
  <View class="NSView" x="0.0" y="0.0" width="20.0" height="10.0" windowX="0.0" windowY="0.0">
    <View class="LuaStackView" identifier="box" x="4.0" y="4.0" width="6.0" height="4.0" windowX="4.0" windowY="2.0">
    </View>
    <View class="LuaTreemapView" identifier="map" x="12.0" y="0.0" width="8.0" height="10.0" windowX="12.0" windowY="0.0">
      <TreemapCell id="big" depth="0" windowX="12.0" windowY="0.0" width="8.0" height="6.0" label="Big" />
      <TreemapCell id="small" depth="1" windowX="12.0" windowY="6.0" width="8.0" height="4.0" label="Small" />
    </View>
  </View>
</Layout>
]])
local captures = Reel.captures(dir)
local capture = captures:get("page-dark")
local cw, ch = capture:size()
t.expect(cw == 20 and ch == 10, "a 2x capture measures in points")
local bx, by, bw, bh = capture:rect("#box")
t.expect(bx == 4 and by == 2 and bw == 6 and bh == 4, "rect(#id) reads the view's window frame")
local cx, cy, cw2, chh = capture:rect("#map/small")
t.expect(cx == 12 and cy == 6 and cw2 == 8 and chh == 4, "rect(#view/cell) reads a treemap cell")
t.assertEqual(#capture:cells("map"), 2, "cells() lists a view's treemap cells")
t.assertEqual(capture:cells("map", 0)[1].id, "big", "cells(view, depth) filters by depth")
t.assertThrows(function() capture:rect("#missing") end, "an unknown identifier is an error")
local sr, sg = capture:sample(6, 3)
t.expect(sr > 0.9 and sg < 0.1, "sample() reads a window point")
local sprite = capture:piece("#box")
t.expect(sprite.x == 4 and sprite.w == 6 and sprite.h == 4, "piece() cuts at the view's frame")
t.assertEqual(capture:piece("#box"), sprite, "pieces are cached")
local keyed = capture:piece("#box", { outset = 1, key = { 1, 1 } })
t.expect(keyed.w == 8, "outset grows a piece on every side")
local _, _, _, keyedAlpha = keyed.image:pixel(0.25, 0.25)
t.expect(keyedAlpha < 0.1, "keying clears the sampled page colour")

-- import(): the opaque window inside a screenshot with a transparent margin.
local shot = N.canvas(30, 20)
shot:clear(0, 0, 0, 0)
shot:fillRect(5, 4, 16, 10, 0.2, 0.4, 0.6, 1)
shot:snapshot():write(dir .. "/shot.png")
Reel.importCapture(dir .. "/shot.png", dir .. "/imported.jpg", "dark", { 16, 10 })
local imported = N.image(dir .. "/imported.jpg")
local iw, ih = imported:pixelSize()
t.expect(iw == 16 and ih == 10, "import keeps only the opaque window")
t.assertThrows(function() Reel.importCapture(dir .. "/shot.png", dir .. "/bad.jpg", "dark", { 32, 20 }) end,
	"import rejects a window of the wrong size")

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

-- Movie encoding writes an H.264 file with every frame.
local movieReel = reel([[<Reel width="64" height="32" fps="10" duration="0.5" subframes="1"><Backdrop color="#336699" /></Reel>]])
local moviePath = dir .. "/tiny.mov"
t.assertEqual(movieReel:movie(moviePath), 5, "movie() returns the frames written")
local movieFile = io.open(moviePath, "rb")
t.expect(movieFile and movieFile:seek("end") > 0, "the movie file exists")
if movieFile then movieFile:close() end

os.execute("rm -rf " .. dir)
os.exit(t.summary() and 0 or 1)
