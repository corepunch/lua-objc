-- apps/slicer: cuts, slices, the 140 BPM grid snap, the waveform view's
-- press/drag/release, in-place marker updates and WAV export.
_G.__headless = true

local t = require("TestKit")
local bridge = require("AppKitNative")
local Model = require("apps.slicer.Model")
local Controller = require("apps.slicer.Controller")

local dir = os.tmpname()
os.remove(dir)
os.execute("mkdir -p '" .. dir .. "'")

-- A 16-bit stereo WAV of `seconds` at 44.1 kHz.
local function writeWav(path, seconds)
	local rate, frames = 44100, math.floor(44100 * seconds)
	local samples = {}
	for i = 0, frames - 1 do
		local v = math.floor(math.sin(i / rate * 2 * math.pi * 220) * 12000)
		table.insert(samples, string.pack("<i2i2", v, v))
	end
	local data = table.concat(samples)
	local file = assert(io.open(path, "wb"))
	file:write("RIFF", string.pack("<I4", 36 + #data), "WAVEfmt ",
		string.pack("<I4I2I2I4I4I2I2", 16, 1, 2, rate, rate * 4, 4, 16), "data", string.pack("<I4", #data), data)
	file:close()
end

local bar = 60 / 140 * 4
local source = dir .. "/Break.wav"
writeWav(source, 2 * bar)

-- Model: slices between the start, the cuts and the end.
local model = Model.new()
model:open(source, {duration = 2 * bar})
t.assertEqual(#model:slices(), 1, "a file without cuts is one slice")
local first = model:addCut(bar)
t.assertEqual(model.selected, first, "a new cut is selected")
t.assertEqual(model:addCut(bar), first, "a cut on an existing cut selects it instead")
model:addCut(0)
model:addCut(2 * bar)
t.assertEqual(#model:slices(), 2, "cuts at either end make no empty slices")
t.assertEqual(model:slices()[2].start, bar, "the second slice starts at the cut")
model:select(first)
t.assertEqual(model:currentSlice().index, 2, "the selected cut's slice plays")
t.assertEqual(model:fileName(3, 12), "Break 03.wav", "slice files are numbered in order")
t.assertEqual(model:fileName(3, 120), "Break 003.wav", "the number pads to the slice count")
t.expect(model:removeSelected() and #model.cuts == 2, "Delete removes the selected cut")
t.assertEqual(model:width(), nil, "a file opens fitted to the window")
model:zoomBy(2, 400)
t.assertEqual(model:width(), 800, "zooming in doubles what the window shows")
model:zoomBy(0.5, 400)
t.expect(model:width() == nil and not model:canZoomOut(), "zooming back out fits the window again")
for _ = 1, 20 do model:zoomBy(2, 400) end
t.expect(model.zoom == Model.maxZoom and not model:canZoomIn(), "zoom stops at the closest level")

-- The app: open, cut on the grid, drag, export.
local alerts = {}
local controller = Controller.new({
	pickFolder = function() return dir end,
	alert = function(title) table.insert(alerts, title) end,
})
controller:createWindow()
t.expect(controller.content.refs.waveform == nil, "no waveform before a file is open")
t.expect(controller:open(source), "a WAV opens")
local waveform = controller.content.refs.waveform
t.expect(waveform ~= nil, "the editor shows the waveform")
t.expect(math.abs(bridge._waveformSend(waveform, "duration") - 2 * bar) < 1e-3, "the view decoded the whole file")
t.expect(not controller:open(dir .. "/missing.wav") and alerts[1], "a file that cannot open alerts")
t.assertEqual(controller.content.refs.waveform, waveform, "a failed open keeps the file")

local width = waveform.size.width
local sixteenth = 60 / 140 / 4
local function x(sixteenths) return sixteenths * sixteenth / (2 * bar) * width end
bridge._waveformSend(waveform, "press", x(16.4))
t.assertEqual(#controller.model.cuts, 1, "pressing the waveform adds a cut")
local cut = controller.model.cuts[1]
t.expect(math.abs(cut.time - 16 * sixteenth) < 1e-9, "the cut snaps to the nearest sixteenth")
t.assertEqual(controller.content.refs.waveform, waveform, "a new cut updates the waveform in place")
t.assertEqual(waveform.selectedId, cut.id, "the new cut is drawn selected")

-- Press the cut, drag it about two sixteenths later, release.
bridge._waveformSend(waveform, "press", x(16) + 1)
t.assertEqual(#controller.model.cuts, 1, "pressing a cut grabs it rather than adding one")
bridge._waveformSend(waveform, "drag", x(17.8))
t.expect(math.abs(controller.model.cuts[1].time - 16 * sixteenth) < 1e-9, "the model hears about a drag only on release")
bridge._waveformSend(waveform, "release", x(17.8))
t.expect(math.abs(controller.model.cuts[1].time - 18 * sixteenth) < 1e-9, "the dropped cut lands on the grid")

controller:actions().setGrid(4)
t.assertEqual(waveform.division, 0, "the Off grid places cuts freely")
bridge._waveformSend(waveform, "press", 100)
t.expect(math.abs(controller.model.cuts[2].time - 100 / width * 2 * bar) < 1e-6, "an unsnapped cut lands where pressed")
t.expect(controller:key("delete") and #controller.model.cuts == 1, "Delete in the waveform removes the cut")
t.expect(not controller:key("q"), "other keys pass through")

controller:actions().zoomIn()
t.assertEqual(controller.content.refs.waveform, waveform, "zooming resizes the waveform in place")
t.expect(waveform.size.width > width, "zooming in widens the waveform past the window")
controller:actions().zoomOut()
t.assertEqual(waveform.size.width, width, "zooming out fits the window again")

local written = controller:export()
t.assertEqual(#written, 2, "every slice is exported")
t.assertEqual(written[1], dir .. "/Break 01.wav", "exports are named after the file")
local Audio = require("apps.slicer.services.Audio")
local audio = Audio.new()
local info1, info2 = audio:info(written[1]), audio:info(written[2])
t.expect(math.abs(info1.duration - 18 * sixteenth) < 1e-4, "the first slice ends at the cut")
t.expect(math.abs(info1.duration + info2.duration - 2 * bar) < 1e-4, "the slices add up to the file")
t.assertEqual(info1.channels, 2, "slices keep the source's channels")

os.execute("rm -rf '" .. dir .. "'")
os.exit(t.summary() and 0 or 1)
