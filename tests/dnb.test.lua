_G.__headless = true
local ns = require("AppKit")
local t = require("TestKit")
local Model = require("apps.dnb.Model")
local Composer = require("apps.dnb.models.Composer")
local Synth = require("apps.dnb.models.Synth")
local Controller = require("apps.dnb.Controller")

local SR = 22050 -- half rate keeps synthesis tests fast; the code is rate-independent

-- Model: defaults, clamping and stepping.
local model = Model.new(5)
t.assertEqual(model:value("tempo"), 174, "tempo defaults to 174 BPM")
t.assertEqual(model:formatted("tempo"), "174 BPM", "tempo label shows BPM")
t.assertEqual(model:setValue("tempo", 171.6), 172, "tempo snaps to whole BPM")
t.assertEqual(model:setValue("tempo", 400), 180, "tempo clamps to its maximum")
t.assertEqual(model:setValue("energy", -1), 0, "energy clamps to its minimum")
t.assertEqual(model:formatted("energy"), "0%", "percent controls format as percent")
t.expect(model:enabled("kick") and model:enabled("pads"), "every part starts enabled")
model:setEnabled("kick", false)
t.expect(not model:enabled("kick"), "a part can be muted")
t.assertEqual(model:value("swing"), 0.12, "unrelated controls keep their values")
t.assertThrows(function() model:setEnabled("cowbell", true) end, "unknown parts are rejected")
t.assertThrows(function() model:setValue("pitch", 1) end, "unknown controls are rejected")

-- Composer: deterministic, arranged, gated by settings.
local function hits(bar, voice)
	local steps = {}
	for _, h in ipairs(bar.hits) do
		if h.voice == voice then table.insert(steps, h.step) end
	end
	table.sort(steps)
	return steps
end
local settings = Model.new(9)
local composer = Composer.new(9)
local same = Composer.new(9)
local function signature(c, n)
	local bar = c:bar(n, settings)
	local parts = {bar.section, bar.chord.root}
	for _, h in ipairs(bar.hits) do table.insert(parts, h.voice .. h.step) end
	for _, b in ipairs(bar.bass) do table.insert(parts, "b" .. b.step .. ":" .. b.note) end
	return table.concat(parts, ",")
end
t.assertEqual(signature(composer, 40), signature(same, 40), "the same seed composes the same bar")
local differs = false
for seed = 10, 14 do
	if signature(Composer.new(seed), 40) ~= signature(composer, 40) then differs = true end
end
t.expect(differs, "different seeds compose different bars")
t.assertEqual(signature(composer, 1000), signature(composer, 1000), "far bars are reproducible without history")

t.assertEqual(composer:bar(0, settings).section, "intro", "an arranged track opens with an intro")
t.assertEqual(composer:bar(4, settings).section, "build", "the intro leads into a build-up")
t.assertEqual(composer:bar(8, settings).section, "drop", "the first drop lands on bar 9")
t.assertEqual(composer:bar(40, settings).section, "breakdown", "a breakdown follows 32 drop bars")
t.assertEqual(composer:bar(48, settings).section, "build", "the breakdown builds back up")
t.assertEqual(composer:bar(56, settings).section, "drop", "and drops again, forever")
t.assertEqual(hits(composer:bar(0, settings), "kick")[1], 0, "the track opens on a kick")
t.assertEqual(table.concat(hits(composer:bar(0, settings), "snare"), ","), "4,12", "the intro already has the backbeat")
t.assertEqual(#composer:bar(0, settings).bass, 0, "the intro holds the bass back")
t.assertEqual(#hits(composer:bar(5, settings), "kick"), 0, "the build drops the kick")
t.assertEqual(#hits(composer:bar(42, settings), "kick"), 0, "the breakdown has no kick")
t.assertEqual(#composer:bar(6, settings).bass, 0, "the build holds the bass back for the drop")
t.expect(composer:bar(6, settings).riser ~= nil, "the build carries a riser")

local drop = composer:bar(9, settings)
t.assertEqual(hits(drop, "kick")[1], 0, "the drop kick lands on the downbeat")
t.assertEqual(table.concat(hits(drop, "snare"), ","), "4,12", "the snare holds the two-step backbeat")
t.expect(#drop.bass > 0, "the drop has a bass line")
t.assertEqual(drop.bass[1].step, 0, "the bass line starts on the downbeat")
for _, note in ipairs(drop.bass) do
	t.expect(note.note >= 28 and note.note <= 52, "bass notes stay in the sub register")
	t.expect(note.step + note.length <= 16, "bass notes end inside their bar")
end
t.assertEqual(#composer:bar(8, settings).pad, 4, "pads voice a four-note chord")
t.assertEqual(composer:bar(9, settings).pad, nil, "a chord is sounded once for its two bars")
local fill = composer:bar(15, settings)
t.expect(#hits(fill, "snare") >= 5, "the last bar of a phrase rolls into the next")
t.assertEqual(hits(composer:bar(8, settings), "crash")[1], 0, "a crash marks the drop")

local low, high = Model.new(9), Model.new(9)
low:setValue("energy", 0)
high:setValue("energy", 1)
local lowCount, highCount = 0, 0
for n = 8, 23 do
	lowCount = lowCount + #composer:bar(n, low).hits + #composer:bar(n, low).bass
	highCount = highCount + #composer:bar(n, high).hits + #composer:bar(n, high).bass
end
t.expect(highCount > lowCount, "energy adds hits and bass notes")

local flat = Model.new(9)
flat:setEnabled("arrangement", false)
for _, n in ipairs({0, 8, 50, 57}) do
	t.assertEqual(composer:bar(n, flat).section, "drop", "without arrangement every bar is a drop")
end
local muted = Model.new(9)
for _, group in ipairs(Model.partGroups) do
	for _, part in ipairs(group.parts) do muted:setEnabled(part.id, false) end
end
local empty = composer:bar(20, muted)
t.assertEqual(#empty.hits + #empty.bass + #empty.stabs, 0, "muting every part leaves an empty bar")
t.assertEqual(empty.pad, nil, "muted pads are not voiced")
local noFills = Model.new(9)
noFills:setEnabled("fills", false)
t.assertEqual(#hits(composer:bar(8, noFills), "crash"), 0, "fills off removes crashes")
t.assertEqual(composer:bar(6, noFills).riser, nil, "fills off removes the riser")

-- Synth: bounded, deterministic, silent when muted, sample-accurate bars.
local function render(settingsModel, frames, seed)
	local synth = Synth.new(settingsModel, SR)
	synth:setComposer(Composer.new(seed or 9))
	local out = {}
	synth:render(out, frames)
	return out, synth
end
local function stats(out)
	local peak, sum = 0, 0
	for i = 1, #out do
		local a = math.abs(out[i])
		if a > peak then peak = a end
		sum = sum + a * a
	end
	return peak, math.sqrt(sum / #out)
end
local full = Model.new(9)
full:setEnabled("arrangement", false)
local out = render(full, SR * 2)
local peak, rms = stats(out)
t.assertEqual(#out, SR * 4, "render writes interleaved stereo frames")
t.expect(peak <= 1, "output is soft-clipped into range")
t.expect(rms > 0.03, "a full drop is audible")
local again = render(full, SR * 2)
local identical = true
for i = 1, #out, 97 do if out[i] ~= again[i] then identical = false break end end
t.expect(identical, "rendering is deterministic")

local silent = render(muted, SR)
t.assertEqual(select(1, stats(silent)), 0, "muting every part renders silence")

local drumsOnly = Model.new(9)
drumsOnly:setEnabled("arrangement", false)
for _, id in ipairs({"sub", "reese", "pads", "stabs"}) do drumsOnly:setEnabled(id, false) end
local kickOnly = Model.new(9)
kickOnly:setEnabled("arrangement", false)
for _, group in ipairs(Model.partGroups) do
	for _, part in ipairs(group.parts) do
		if part.id ~= "kick" and part.id ~= "arrangement" then kickOnly:setEnabled(part.id, false) end
	end
end
kickOnly:setValue("space", 0)
local kickOut = render(kickOnly, 256)
t.expect(math.abs(kickOut[2 * 64 - 1]) > 0.05, "the kick sounds on the first downbeat")

-- Chunked rendering matches one long render: blocks carry voice state.
local chunked, whole = {}, render(full, 3000)
do
	local synth = Synth.new(full, SR)
	synth:setComposer(Composer.new(9))
	local part = {}
	for _, size in ipairs({1, 999, 1000, 1000}) do
		synth:render(part, size)
		for i = 1, size * 2 do table.insert(chunked, part[i]) end
	end
end
local matches = true
for i = 1, #whole do
	if math.abs(whole[i] - chunked[i]) > 1e-9 then matches = false break end
end
t.expect(matches, "chunked rendering is sample-identical to one block")

local tempoModel = Model.new(9)
tempoModel:setValue("tempo", 160)
local _, synth = render(tempoModel, SR * 3)
local expected = math.floor(16 * SR * 60 / 160 / 4 + 0.5)
t.assertEqual(synth.timeline[1].frames, expected, "bar length follows the tempo")
t.assertEqual(synth:barAt(expected - 1).number, 0, "the playhead maps frames to the first bar")
t.assertEqual(synth:barAt(expected).number, 1, "and to the next bar on its first frame")
tempoModel:setValue("tempo", 180)
synth:render({}, SR * 3)
local last = synth.timeline[#synth.timeline]
t.assertEqual(last.frames, math.floor(16 * SR * 60 / 180 / 4 + 0.5), "a tempo change applies at the next bar")
synth:setComposer(Composer.new(77))
synth:render({}, SR * 2)
local restarted
for _, bar in ipairs(synth.timeline) do
	if bar.key == Composer.new(77).key and bar.section == "intro" and bar.sectionBar == 0 then restarted = bar end
end
t.expect(restarted ~= nil, "a new track starts its own intro at the next bar")
t.expect(restarted and restarted.number > 0, "without restarting the timeline")

-- Visuals: bar motion, peak holds, kick flashes and the shader layout.
local Visuals = require("apps.dnb.models.Visuals")
local visuals = Visuals.new(4)
local bar = {frame = 0, frames = 4000, kicks = {0, 2500}, section = "drop", sectionBar = 3, sectionLength = 32, tonic = 6}
local v = visuals:update({bands = {1, 0.5, 0, 0}, rms = 0.2, playing = true, bar = bar, played = 100, sampleRate = 1000}, 1 / 60)
t.assertEqual(#v, 8 + 2 * 4, "values hold the header, bands and peaks")
t.expect(v[9] > 0.6 and v[9] < 1, "bars rise quickly but not instantly")
t.assertEqual(v[13], v[9], "a rising bar carries its peak")
t.expect(v[2] > 0.5, "a kick just played flashes")
t.assertEqual(v[3], 0.5, "hue comes from the tonic")
t.assertEqual(v[4], 1, "the drop runs at full intensity")
t.assertEqual(v[6], 0.1, "beat phase is the position inside the beat")
local peak = v[13]
for _ = 1, 10 do v = visuals:update({playing = true, bar = bar, played = 900, sampleRate = 1000}, 1 / 60) end
t.expect(v[9] < peak, "silence lets bars fall")
t.assertEqual(v[13], peak, "the peak holds while the bar falls")
t.expect(not visuals:settled(), "a moving visualizer is not settled")
for _ = 1, 300 do visuals:update({playing = false}, 1 / 60) end
t.expect(visuals:settled(), "without audio everything comes to rest")
t.assertEqual(visuals.presence, 0, "stopping fades the visualizer back to idle")

-- Controller: fake output, no audio device or timers.
local function fakeOutput(capacity)
	local o = {capacity = capacity, queued = 0, written = 0, playedFrames = 0, started = 0, paused = 0}
	function o:start() self.started = self.started + 1 return true end
	function o:pause() self.paused = self.paused + 1 end
	function o:space() return self.capacity - self.queued end
	function o:write(samples, frames)
		t.expect(#samples >= frames * 2, "the controller hands over whole frames")
		self.queued = self.queued + frames
		self.written = self.written + frames
		return frames
	end
	function o:played() return self.playedFrames end
	function o:spectrum(bands)
		local levels = {}
		for i = 1, bands do levels[i] = i == 1 and 0.9 or 0.2 end
		return levels, 0.3
	end
	function o:consume(frames)
		self.queued = self.queued - frames
		self.playedFrames = self.playedFrames + frames
	end
	return o
end
local output = fakeOutput(4096)
local loops = 0
local app = Controller.new({seed = 9, output = output, async = function() loops = loops + 1 end, sleep = function() end})
local window = app:createWindow()
t.expect(window ~= nil, "the controller creates its window")
t.assertEqual(app.refs.section.text, "Ready to play", "the header waits for playback")
t.expect(app.refs.detail.text:find(Composer.new(9).key, 1, true) ~= nil, "the header names the key before playing")
t.expect(app.refs.control_tempo ~= nil and app.refs.part_kick ~= nil, "controls render from the model tables")
t.expect(not app.refs.stop.enabled, "stop is disabled while stopped")
t.assertEqual(loops, 1, "the window starts one display loop")
t.assertEqual(#app.refs.visualizer.values, 8 + 2 * 40, "the shader receives header values, bands and peaks")

app:play()
t.assertEqual(output.started, 1, "play starts the output")
t.assertEqual(output.written, 4096, "play queues audio before the device asks for it")
t.expect(app.playing and not app.refs.play.enabled, "play disables itself while playing")
app:play()
t.assertEqual(output.started, 1, "pressing play twice starts the output once")
t.assertEqual(app:pump(), 0, "a full queue renders nothing")
output:consume(1000)
t.assertEqual(app:pump(), 1000, "the pump refills exactly what the device consumed")
output:consume(500)
app:tick(1 / 60)
t.assertEqual(output.written, 5596, "each display frame refills the queue")
t.assertEqual(app.refs.section.text, "Intro", "the header follows the playhead")
local values = app.refs.visualizer.values
t.expect(values[7] > 0, "playing fades the visualizer in")
t.expect(values[9] > values[10], "bars follow the analysed spectrum")
t.assertEqual(values[3], Composer.new(9).tonic / 12, "the palette follows the track key")
t.assertEqual(app.refs.position.text, "Bar 1 of 4", "and shows the bar in its section")

app.actions(app).control_cutoff(0.25)
t.assertEqual(app.model:value("cutoff"), 0.25, "a slider moves its model value")
t.assertEqual(app.refs.value_cutoff.text, "25%", "and its value label")
app:setControl("tempo", 165.4)
t.assertEqual(app.refs.value_tempo.text, "165 BPM", "tempo shows the snapped value")
app:actions().part_snare(false)
t.expect(not app.model:enabled("snare"), "a checkbox mutes its part")
t.assertEqual(app.model:value("cutoff"), 0.25, "toggling a part leaves sliders alone")

local seed = app.model.seed
app:newTrack()
t.assertEqual(app.model.seed, seed + 1, "new track advances the seed")
t.expect(app.synth.composer == app.composer and app.composer.seed == seed + 1, "the synth plays the new track")

app:stop()
t.assertEqual(output.paused, 1, "stop pauses the output")
t.expect(not app.playing and app.refs.play.enabled, "stop re-enables play")
app:stop()
t.assertEqual(output.paused, 1, "stopping twice is harmless")

local failing = fakeOutput(1024)
function failing:start() return nil, "no output device" end
local offline = Controller.new({seed = 1, output = failing, async = function() end})
offline:createWindow()
offline:play()
t.expect(not offline.playing, "a failed engine start leaves the transport stopped")
t.assertEqual(offline.refs.detail.text, "no output device", "and explains why")
local unbuilt = fakeOutput(1024)
function unbuilt:space() error("AudioStream plugin is not built") end
local missing = Controller.new({seed = 1, output = unbuilt, async = function() end})
missing:createWindow()
missing:play()
t.expect(not missing.playing, "a missing output does not raise from the Play button")
t.expect(missing.refs.detail.text:find("not built", 1, true) ~= nil, "and names the problem")

-- Native plugin: queue bookkeeping without starting the audio device.
local plugin = require("App").loadNativePlugin(assert(package.searchpath("AudioStream", package.cpath)), "AudioStream")
local stream = plugin.open(44100, 8)
t.assertEqual(plugin.space(stream), 8, "a new stream has its whole capacity free")
t.assertEqual(plugin.write(stream, {0.5, -0.5, 2, -2, 0, 0}, 3), 3, "write queues interleaved frames")
t.assertEqual(plugin.space(stream), 5, "queued frames use capacity")
t.assertEqual(plugin.write(stream, {}, 20), 5, "write never overruns unplayed audio")
t.assertEqual(plugin.space(stream), 0, "a full stream reports no space")
local played, underruns = plugin.played(stream)
t.assertEqual(played, 0, "nothing plays before start")
t.assertEqual(underruns, 0, "and nothing underruns")
t.assertThrows(function() plugin.open(1, 8) end, "absurd sample rates are rejected")
t.assertThrows(function() plugin.write(stream, {}, -1) end, "negative frame counts are rejected")
local sine = {}
for i = 0, 4095 do
	local s = 0.5 * math.sin(2 * math.pi * 55 * i / 44100)
	table.insert(sine, s)
	table.insert(sine, s)
end
local levels, level = plugin.analyze(sine, 44100, 32)
t.assertEqual(#levels, 32, "analysis returns one level per band")
local loudest = 1
for i = 2, #levels do if levels[i] > levels[loudest] then loudest = i end end
t.expect(loudest <= 5, "a 55 Hz sine peaks in the lowest bands")
t.expect(levels[loudest] > 0.85 and levels[32] < 0.3, "full-scale content reads high, empty bands low")
t.expect(math.abs(level - 0.5 / math.sqrt(2)) < 0.01, "RMS matches the sine amplitude")
local quiet = plugin.analyze({}, 44100, 8)
t.assertEqual(quiet[1], 0, "silence analyses as empty bands")
local fresh = plugin.spectrum(stream, 8)
t.assertEqual(#fresh, 8, "a stream that has not played reports empty bands")
plugin.close(stream)
t.assertThrows(function() plugin.space(stream) end, "a closed stream cannot be used")

-- Lua timers keep firing while AppKit tracks a slider drag.
local bridge = require("AppKitNative")
local fired = false
bridge._timerAfter(0, function() fired = true end)
for _ = 1, 20 do if fired then break end bridge._runLoopTick(0.02, "eventTracking") end
t.expect(fired, "timers run in the event-tracking run loop mode")

os.exit(t.summary() and 0 or 1)
