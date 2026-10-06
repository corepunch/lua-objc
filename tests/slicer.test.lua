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


-- Undo and redo: edits of the cuts, not selection.
local edits = Model.new()
edits:open(source, {duration = 2 * bar})
t.expect(not edits:canUndo() and not edits:canRedo(), "a new file has no history")
local a = edits:addCut(bar)
edits:addCut(bar)
t.assertEqual(#edits.undos, 1, "a click on an existing cut is not an edit")
edits:moveCut(a, bar / 2)
edits:moveCut(a, bar / 2)
t.assertEqual(#edits.undos, 2, "a drag that lands where it started is not an edit")
edits:select(nil)
t.assertEqual(#edits.undos, 2, "selecting is not an edit")
t.expect(edits:undo() and edits.cuts[1].time == bar, "undo puts a moved cut back")
t.expect(edits:undo() and #edits.cuts == 0, "undo removes an added cut")
t.expect(not edits:undo(), "undo stops at the start of the history")
t.expect(edits:redo() and edits:redo() and edits.cuts[1].time == bar / 2, "redo replays both edits")
t.expect(not edits:redo(), "redo stops at the newest edit")
edits:undo()
edits:removeSelected()
t.expect(#edits.cuts == 0 and not edits:canRedo(), "a new edit clears redo")
edits:undo()
t.assertEqual(edits.selected, a, "undo restores the selection with the cut")
local b = edits:addCut(bar * 1.5)
t.expect(b ~= a and edits.nextId == 3, "ids keep counting across undo")
edits:clear()
edits:clear()
t.expect(edits:undo() and #edits.cuts == 2, "Remove All Cuts undoes in one step")
for i = 1, Model.undoLimit + 10 do edits:addCut(i / 1000) end
t.assertEqual(#edits.undos, Model.undoLimit, "history keeps the newest edits")
edits:open(source, {duration = 2 * bar})
t.expect(not edits:canUndo(), "opening a file starts a new history")

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


-- Wheel zoom keeps the time under the pointer where it was.
local fitted = waveform.size.width
local pointer = fitted * 0.25
bridge._waveformSend(waveform, "zoom", pointer, 2)
t.assertEqual(waveform.size.width, fitted * 2, "a wheel zoom doubles the width")
t.assertEqual(bridge._waveformSend(waveform, "scrolled"), pointer, "the time under the pointer stays under it")
bridge._waveformSend(waveform, "zoom", pointer * 2 + 100, 0.5)
t.assertEqual(waveform.size.width, fitted, "zooming out fits the window again")
t.assertEqual(bridge._waveformSend(waveform, "scrolled"), 0, "a fitted waveform is not scrolled")
controller:actions().undo()
t.assertEqual(#controller.model.cuts, 2, "Undo in the app brings the deleted cut back")
controller:actions().redo()
t.assertEqual(#controller.model.cuts, 1, "Redo deletes it again")
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

-- Playback: one button plays, pauses and resumes; the playhead follows.
local calls, onEnd = {}, nil
local fake = setmetatable({
	play = function(_, _, from, to, done) table.insert(calls, "play " .. from .. " " .. to); onEnd = done; return true end,
	pause = function() table.insert(calls, "pause") end,
	resume = function() table.insert(calls, "resume") end,
	stop = function() table.insert(calls, "stop") end,
}, {__index = audio})
local player = Controller.new({audio = fake})
local playerWindow = player:createWindow()
player:open(source)
player:actions().addCut(bar)
local function playItem()
	for _, item in ipairs(playerWindow.toolbar.items) do
		if item.itemIdentifier == "play" then return item end
	end
end
t.assertEqual(playItem().label, "Play Slice", "the toolbar starts with Play")
local view = player.content.refs.waveform
t.assertEqual(bridge._waveformSend(view, "playhead"), nil, "no playhead while silent")

player:actions().play()
t.assertEqual(calls[#calls], "play " .. bar .. " " .. 2 * bar, "Play plays the selected cut's slice")
t.assertEqual(playItem().label, "Pause", "while playing the button is Pause")
t.assertEqual(view.playState, "playing", "the waveform shows playback")
local at, moving = bridge._waveformSend(view, "playhead")
t.expect(at and math.abs(at - bar) < 0.05 and moving, "the playhead starts at the slice and moves")

player:key(" ")
t.assertEqual(calls[#calls], "pause", "Space pauses")
t.assertEqual(playItem().label, "Play Slice", "a paused audition shows Play")
local pausedAt, stillMoving = bridge._waveformSend(view, "playhead")
t.expect(pausedAt and not stillMoving, "a paused playhead stays where it is")
player:actions().play()
t.assertEqual(calls[#calls], "resume", "Play resumes a paused slice")
t.assertEqual(player.content.refs.waveform, view, "playback updates the waveform in place")

onEnd()
t.assertEqual(player.model.playback, nil, "the end of the slice stops playback")
t.assertEqual(playItem().label, "Play Slice", "the button returns to Play at the end")
t.assertEqual(bridge._waveformSend(view, "playhead"), nil, "the playhead goes when playback ends")

player:actions().play()
player:actions().stop()
t.assertEqual(calls[#calls], "stop", "Stop silences the audition")
t.expect(player.model.playback == nil and playItem().label == "Play Slice", "Stop returns to Play")

os.execute("rm -rf '" .. dir .. "'")
os.exit(t.summary() and 0 or 1)
