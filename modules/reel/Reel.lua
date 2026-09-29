-- Reel: motion pieces written as etlua templates and rendered offline.
--
--   package.path = "modules/reel/?.lua;" .. package.path
--   local Reel = require("Reel")
--   local reel = Reel.load("reels/diskmap/views/Reel.etlua", {
--   	captures = Reel.captures("reels/diskmap/captures"),
--   })
--   reel:still(8.9, "/tmp/still.png")
--   reel:movie("build/Showreel.mov")
--
-- A template describes a timeline of nodes (reel/elements.lua) whose
-- attributes and motion are functions of time; frames are pure functions
-- of `t`, averaged over several sub-frames for motion blur. See README.md.
local xml = require("ui.xml")
local Audio = require("reel.audio")
local Captures = require("reel.captures")
local Curves = require("reel.curves")
local Elements = require("reel.elements")
local Instruments = require("reel.instruments")
local Motion = require("reel.motion")
local Pen = require("reel.pen")
local Scene = require("reel.scene")
local Space = require("reel.space")

-- The toolkit, for bespoke shots and scores: curves and easing, motion
-- presets, the pen and its shapes, the mix and its instruments.
local Reel = {
	curves = Curves,
	space = Space,
	motion = Motion,
	elements = Elements,
	Pen = Pen,
	Shape = Pen.Shape,
	rgb = Pen.rgb,
	audio = Audio,
	instruments = Instruments,
}
Reel.__index = Reel

local native
function Reel.native()
	native = native or require("ReelNative")
	return native
end

-- captures(dir, hint): window captures written by `lua-objc --capture` or a
-- `--capture-plan`; `hint` tells the reader how to make missing ones.
function Reel.captures(dir, hint)
	return Captures.open(dir, Reel.native(), hint)
end

-- Values templates can use while rendering: the curves and the motion
-- vocabulary next to the caller's data. The same table is also `reel`, so
-- a template hands everything to its scenes with partial("Scene.etlua", reel).
local function templateData(data)
	local context = {}
	for name, fn in pairs(Curves) do context[name] = fn end
	for name, fn in pairs(Motion) do context[name] = fn end
	for name, fn in pairs(Space) do context[name] = fn end
	for key, value in pairs(data or {}) do context[key] = value end
	context.reel = context
	return context
end

-- load(path, data) -> reel. `data` is visible to the template and to
-- attribute expressions.
function Reel.load(path, data)
	local description = xml.describeFile(path, templateData(data))
	return Reel.fromSource(description.source, data)
end

function Reel.fromSource(source, data)
	local scene = Scene.build(xml.parse(source), { elements = Elements, data = data or {}, native = Reel.native() })
	return setmetatable({ scene = scene, events = scene.events }, Reel)
end

-- Draws time t, without motion blur, onto a canvas the reel's size.
function Reel:draw(canvas, t)
	Scene.draw(self.scene, canvas, t)
end

function Reel:canvas()
	return Reel.native().canvas(self.scene.width, self.scene.height)
end

-- Renders the motion-blurred frame at t: `subframes` renders spread across
-- a `shutter` fraction of the frame interval (0.5 is a 180° shutter).
function Reel:frame(canvas, t, accumulator)
	local scene = self.scene
	local n = scene.subframes
	if n <= 1 then return self:draw(canvas, t) end
	accumulator = accumulator or self:accumulator()
	local open = scene.shutter / scene.fps
	for i = 0, n - 1 do
		self:draw(canvas, math.max(0, t + (i / (n - 1) - 0.5) * open))
		accumulator:add(canvas)
	end
	accumulator:resolve(canvas)
end

function Reel:accumulator()
	self.sharedAccumulator = self.sharedAccumulator or Reel.native().accumulator(self.scene.width, self.scene.height)
	return self.sharedAccumulator
end

-- still(t, path): one motion-blurred frame as PNG.
function Reel:still(t, path)
	local canvas = self:canvas()
	self:frame(canvas, t)
	canvas:snapshot():write(path)
end

-- writeWav(path, sampleRate, left, right)
function Reel.writeWav(path, sampleRate, left, right)
	Reel.native().writeWav(path, sampleRate, left, right)
end

-- movie(path, {from, to, audio, progress}): H.264 frames from `from` to
-- `to`, with `audio` (a sound file) muxed in as AAC.
function Reel:movie(path, options)
	options = options or {}
	local scene = self.scene
	local from, to = options.from or 0, options.to or scene.duration
	if to <= from then error("reel: nothing to render between " .. from .. " and " .. to, 2) end
	local movie = Reel.native().movie({ path = path, width = scene.width, height = scene.height, fps = scene.fps,
		audio = options.audio })
	local canvas, accumulator = self:canvas(), self:accumulator()
	local first, last = math.floor(from * scene.fps + 0.5), math.floor(to * scene.fps + 0.5) - 1
	for frame = first, last do
		self:frame(canvas, frame / scene.fps, accumulator)
		movie:append(canvas)
		if options.progress then options.progress(frame - first + 1, last - first + 1) end
	end
	return movie:finish()
end

return Reel
