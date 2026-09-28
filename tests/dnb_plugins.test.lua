_G.__headless = true
local ns = require("AppKit")
local t = require("TestKit")
local Model = require("apps.dnb.Model")
local Synth = require("apps.dnb.models.Synth")
local Visuals = require("apps.dnb.models.Visuals")
local Styles = require("apps.dnb.host.Styles")
local Visualizers = require("apps.dnb.host.Visualizers")
local Controller = require("apps.dnb.Controller")

local SR = 11025 -- synthesis is rate-independent; a low rate keeps the suite fast

local partIds, controlIds = {}, {}
for _, group in ipairs(Model.partGroups) do for _, part in ipairs(group.parts) do partIds[part.id] = true end end
for _, group in ipairs(Model.controlGroups) do for _, control in ipairs(group.controls) do controlIds[control.id] = true end end
local VOICES = {kick = true, snare = true, ghost = true, clap = true, hat = true, openHat = true, ride = true,
	crash = true, rim = true, conga = true, shaker = true, tomHigh = true, tomMid = true, tomLow = true}

-- Every style plugin honours the contract the app and Synth rely on.
local list = Styles:list()
t.expect(#list >= 7, "the generator ships drum & bass and at least six more styles")
t.assertEqual(list[1].id, "dnb", "drum & bass is the first style")
local seenTitles = {}
for _, style in ipairs(list) do
	local name = style.title
	t.expect(not seenTitles[name], name .. " has a unique title")
	seenTitles[name] = true
	t.expect(style.tempo.min < style.tempo.default and style.tempo.default < style.tempo.max, name .. " tempo range holds its default")
	for id in pairs(style.defaults or {}) do t.expect(controlIds[id], name .. " defaults name real controls") end
	for _, id in ipairs(style.parts or {}) do t.expect(partIds[id], name .. " plays real parts: " .. id) end
	for id in pairs(style.labels or {}) do t.expect(partIds[id], name .. " relabels real parts") end
	local ok, err = pcall(Synth.sound, style.sound)
	t.expect(ok, name .. " sound overrides real Synth fields " .. tostring(err))

	local model = Model.new(21, style)
	t.assertEqual(model:value("tempo"), style.tempo.default, name .. " sets its tempo")
	t.assertEqual(select(2, model:range("tempo")), style.tempo.max, name .. " narrows the tempo range")
	local a, b = Styles:create(style.id, 21), Styles:create(style.id, 21)
	local sections, flavours, voices = {}, {}, {}
	local bassOk, polyOk, stepsOk = true, true, true
	for n = 0, 200 do
		local bar = a:bar(n, model)
		local twin = b:bar(n, model)
		t.assertEqual(#bar.hits .. ":" .. #bar.bass .. ":" .. bar.key, #twin.hits .. ":" .. #twin.bass .. ":" .. twin.key,
			name .. " bar " .. n .. " is deterministic")
		sections[bar.section] = true
		flavours[bar.style] = true
		for _, h in ipairs(bar.hits) do
			voices[h.voice] = true
			if h.step < 0 or h.step >= 16 or h.gain <= 0 or h.gain > 1.01 then stepsOk = false end
		end
		for _, note in ipairs(bar.bass) do
			if note.note < 24 or note.note > 64 or note.step + note.length > 16.6 then bassOk = false end
		end
		for _, list in ipairs({bar.stabs, bar.keys}) do
			for _, chord in ipairs(list) do if #chord.notes < 3 then polyOk = false end end
		end
		t.expect(type(bar.progression) == "string" and bar.chord ~= nil, name .. " names its harmony")
	end
	for _, section in ipairs({"intro", "build", "drop", "breakdown", "outro"}) do
		t.expect(sections[section], name .. " arranges a " .. section)
	end
	local count = 0
	for _ in pairs(flavours) do count = count + 1 end
	t.expect(count >= 2, name .. " sets move between flavours")
	for voice in pairs(voices) do t.expect(VOICES[voice], name .. " plays kit voices only: " .. voice) end
	t.expect(stepsOk, name .. " hits sit inside the bar with sane gains")
	t.expect(bassOk, name .. " bass stays in the bass register and inside the bar")
	t.expect(polyOk, name .. " chords have at least three notes")
	t.expect(a:trackStart(1) > 0 and a:trackAt(a:trackStart(1)).index == 1, name .. " exposes its tracks for Next Track")

	-- Parts it does not play produce nothing.
	local muted = Model.new(21, style)
	for id in pairs(partIds) do muted:setEnabled(id, false) end
	local silent = Styles:create(style.id, 21)
	local anything = 0
	for n = 0, 80 do
		local bar = silent:bar(n, muted)
		anything = anything + #bar.hits + #bar.bass + #bar.stabs + #bar.keys + #bar.arp + #bar.lead + #bar.breaks
			+ (bar.pad and 1 or 0)
	end
	t.assertEqual(anything, 0, name .. " is silent with every part muted")
	if style.parts then
		local supported = {}
		for _, id in ipairs(style.parts) do supported[id] = true end
		local breaks = 0
		for n = 0, 120 do breaks = breaks + #a:bar(n, model).breaks end
		if not supported.amen then t.assertEqual(breaks, 0, name .. " plays no break without the Amen part") end
	end

	-- It sounds: a drop renders in range.
	local flat = Model.new(21, style)
	flat:setEnabled("arrangement", false)
	local synth = Synth.new(flat, SR, style.sound)
	synth:setComposer(Styles:create(style.id, 21))
	local out = {}
	synth:render(out, SR // 2)
	local peak, sum = 0, 0
	for i = 1, #out do
		local x = math.abs(out[i])
		if x > peak then peak = x end
		sum = sum + x * x
	end
	t.expect(peak <= 1 and math.sqrt(sum / #out) > 0.05, name .. " drop is audible and soft-clipped")
end

-- Model: styles narrow ranges, set defaults, relabel and disable pads.
local techno = Styles:get("techno")
local model = Model.new(3, Styles:get("dnb"))
model:setEnabled("pads", false)
model:setStyle(techno)
t.assertEqual(model:value("tempo"), 132, "a style sets its default tempo")
t.assertEqual(model:setValue("tempo", 175), 140, "and clamps to its range")
t.assertEqual(model:value("swing"), 0, "control defaults follow the style")
t.expect(not model:enabled("pads"), "part switches survive a style change")
t.assertEqual(model:label("reese"), "Acid", "styles relabel pads")
t.assertEqual(model:label("kick"), "Kick", "unlabelled pads keep their name")
t.expect(not model:supports("amen") and model:supports("kick"), "styles disable parts they do not play")
local plain = Model.new(3)
t.expect(plain:supports("amen"), "without a style every part plays")
t.assertThrows(function() model:supports("cowbell") end, "unknown parts are rejected")

-- Synth: sound overrides, the clap and a sound change on the bar line.
t.assertThrows(function() Synth.sound({bass = {wub = 1}}) end, "unknown sound fields are rejected")
t.assertThrows(function() Synth.sound({laser = {}}) end, "unknown sound groups are rejected")
local sound = Synth.sound({kick = {decay = 0.3}})
t.assertEqual(sound.kick.decay, 0.3, "overrides replace a field")
t.assertEqual(sound.kick.base, Synth.sound().kick.base, "and keep the rest")
local clapModel = Model.new(1, Styles:get("house"))
local synth = Synth.new(clapModel, SR, Styles:get("house").sound)
t.expect(#synth.drums.clap > 0 and #synth.drums.crash > 0, "styles get a clap over the shared cymbals")
local dnbSynth = Synth.new(clapModel, SR)
t.expect(dnbSynth.drums.kick ~= synth.drums.kick, "a style's kick design renders its own kick")
t.assertEqual(Synth.new(clapModel, SR, Styles:get("house").sound).drums.kick, synth.drums.kick, "kits are cached by design")
synth:setComposer(Styles:create("house", 1))
synth:render({}, 2000)
local before = synth.sound
synth:setComposer(Styles:create("techno", 1), Synth.sound(techno.sound))
t.expect(synth.sound == before, "a new sound waits for the bar line")
synth:render({}, synth.nextBarFrame - synth.frame + 10)
t.assertEqual(synth.sound.kick.decay, techno.sound.kick.decay, "and takes over on it")

-- Visualizers: plugins link into one Metal program and draw into layers.
local scenes = Visualizers:list()
t.expect(#scenes >= 7, "seven scene plugins ship")
local program = Visualizers.program()
t.assertEqual(#program.scenes, #scenes, "every scene is linked")
t.assertEqual(program.scenes[1].entry, scenes[1].id .. "Scene", "scene functions follow the plugin id")
local meshScenes = 0
for _, scene in ipairs(scenes) do
	t.expect(#scene.sections > 0, scene.title .. " names its sections")
	local file = io.open(scene.resource(scene.shader))
	t.expect(file ~= nil, scene.title .. " ships its shader")
	if file then file:close() end
	if scene.draws then meshScenes = meshScenes + 1 end
end
t.expect(meshScenes >= 3, "trails, space and the landscape are meshes, not full-screen shaders")
for _, id in ipairs({"trails", "space", "landscape"}) do
	t.expect(Visualizers:get(id).draws ~= nil, id .. " draws meshes")
end
t.assertEqual(program.scenes[Visualizers:index("horizon")].wrapper, "horizonLayer",
	"a full-screen scene gets a layer wrapper")
t.assertEqual(program.scenes[Visualizers:index("space")].wrapper, nil, "a mesh scene needs none")
local horizonIndex, spaceIndex = Visualizers:index("horizon") - 1, Visualizers:index("space") - 1
local single = Visualizers.draws({horizonIndex})
t.assertEqual(#single, 1, "a full-screen scene is one covering draw")
t.assertEqual(single[1].vertex, "fullscreenVertex", "drawn with the framework's covering triangle")
t.assertEqual(single[1].fragment, "horizonLayer", "through its wrapper")
t.assertEqual(single[1].layer, 1, "the current scene draws into layer 1")
local fading = Visualizers.draws({horizonIndex, spaceIndex})
t.assertEqual(#fading, 1 + #Visualizers:get("space").draws, "a crossfade draws both scenes")
t.assertEqual(fading[#fading].layer, 2, "the incoming scene draws into layer 2")
t.expect(Visualizers:get("space").draws[1].layer == nil, "the plugin's own draws are copied, not changed")
t.assertThrows(function() Visualizers.draws({#scenes}) end, "only loaded scenes draw")
local xml = require("ui.xml")
local view, refs = xml.renderFile("apps/dnb/views/Visualizer.etlua", {program = program}, ns)
t.expect(view ~= nil and refs.visualizer ~= nil, "the linked visualizer compiles")
t.assertEqual(refs.visualizer.layers, 2, "the visualizer keeps a layer for each crossfading scene")
t.assertEqual(refs.visualizer.ignoresSafeArea, "all", "the visualizer runs under the title bar")
for index = 0, #scenes - 1 do
	local ok, err = pcall(function() refs.visualizer.draws = Visualizers.draws({index}) end)
	t.expect(ok, scenes[index + 1].title .. " draws compile: " .. tostring(err))
end

-- Every scene draws a frame at the default window's Retina size within a
-- budget, alone and crossfading into the next. Geometry belongs in vertices:
-- Light Trails once walked every segment per pixel and took 85 ms here on an
-- M1. A lone offscreen frame runs before the GPU clocks up, so the budget
-- catches such blowups rather than timing 60 Hz.
local FRAME = {width = 2360, height = 1720, budget = 50}
local bridge = require("AppKitNative")
local loud = Visuals.new(scenes, 40)
loud.level, loud.presence, loud.intensity, loud.travel, loud.kick = 0.8, 1, 1, 42, 0.5
for i = 1, loud.n do loud.levels[i], loud.peaks[i] = 0.6, 0.7 end
bridge._shaderFrameTime(refs.visualizer, FRAME.width, FRAME.height) -- the first frame warms the GPU
for index = 0, #scenes - 1 do
	local next = (index + 1) % #scenes
	for _, layers in ipairs({{index}, {index, next}}) do
		loud.scene, loud.nextScene, loud.fade = layers[1], layers[#layers], #layers == 2 and 0.5 or 0
		refs.visualizer.values = loud:pack()
		refs.visualizer.draws = Visualizers.draws(layers)
		local ms = bridge._shaderFrameTime(refs.visualizer, FRAME.width, FRAME.height)
		local label = scenes[index + 1].title .. (#layers == 2 and " into " .. scenes[next + 1].title or "")
		t.expect(ms < FRAME.budget, string.format("%s draws a %dx%d frame in %.1f ms", label,
			FRAME.width, FRAME.height, ms))
	end
end

-- Visuals: pools from the plugins' sections, and pinning.
local visuals = Visuals.new(scenes, 4)
local horizon = Visualizers:index("horizon") - 1
t.assertEqual(visuals.scene, horizon, "the idle scene opens the intro pool")
visuals:pin(Visualizers:index("tunnel") - 1)
local bar = {frame = 0, frames = 4000, section = "breakdown", sectionBar = 0, sectionLength = 16, number = 0}
for _ = 1, 200 do visuals:update({playing = true, bar = bar, played = 10, sampleRate = 1000}, 1 / 60) end
t.assertEqual(visuals.scene, Visualizers:index("tunnel") - 1, "a pinned scene plays whatever the section")
visuals:pin(nil)
for _ = 1, 200 do visuals:update({playing = true, bar = bar, played = 10, sampleRate = 1000}, 1 / 60) end
local pooled = false
for _, index in ipairs(visuals.pools.breakdown) do if index == visuals.scene then pooled = true end end
t.expect(pooled, "unpinned, the director returns to the section's pool")
t.assertThrows(function() visuals:pin(99) end, "only loaded scenes can be pinned")

-- Controller: style and scene pickers, and the mini player.
local function fakeOutput()
	local o = {queued = 0, played_ = 0}
	function o:start() return true end
	function o:pause() end
	function o:space() return 512 - self.queued end
	function o:write(_, frames) self.queued = self.queued + frames end
	function o:played() return self.played_ end
	function o:spectrum(bands)
		local levels = {}
		for i = 1, bands do levels[i] = 0.5 end
		return levels, 0.2
	end
	return o
end
local app = Controller.new({seed = 5, output = fakeOutput(), async = function() end})
app:createWindow()
t.assertEqual(app.refs.style.indexOfSelectedItem, 0, "the style menu opens on drum & bass")
t.assertEqual(app.window.title, "Drum & Bass", "the window is titled by its style")
app:actions().selectStyle(Styles:index("techno") - 1)
t.assertEqual(app.style.id, "techno", "the style menu switches styles")
t.assertEqual(app.window.title, "Techno", "and retitles the window")
t.assertEqual(app.refs.part_reese.title, "Acid", "pads take the style's labels")
t.expect(not app.refs.part_amen.enabled and app.refs.part_kick.enabled, "pads the style does not play are disabled")
t.assertEqual(app.refs.control_tempo.maxValue, techno.tempo.max, "the tempo slider takes the style's range")
t.assertEqual(app.refs.value_tempo.text, "132 BPM", "and its tempo")
t.assertEqual(app.refs.tempo.text, "132", "the header shows the new tempo")
t.expect(app.refs.detail.text:find("Peak Time", 1, true) or app.refs.detail.text:find("Acid", 1, true)
	or app.refs.detail.text:find("Hypnotic", 1, true), "the idle header names the new set's track")
t.expect(app.synth.composer == app.composer and app.synth.pendingSound ~= nil, "the synth switches on the next bar")
app:actions().selectStyle(Styles:index("techno") - 1)
t.assertEqual(app.model.seed, 5, "reselecting a style changes nothing")
app:actions().selectScene(Visualizers:index("crystals"))
t.assertEqual(app.visuals.pinned, Visualizers:index("crystals") - 1, "the scene menu pins a scene")
app:actions().selectScene(0)
t.assertEqual(app.visuals.pinned, nil, "Automatic returns to the director")

app:play()
app:actions().openMiniPlayer()
t.expect(app.mini ~= nil, "the mini player opens")
t.assertEqual(app.mini.window.windowLevel, "floating", "it floats above other windows")
t.expect(math.abs(app.mini.window.aspectRatio - 16 / 9) < 0.01, "and keeps a 16:9 picture")
t.expect(not app.mini.refs.play.enabled and app.mini.refs.stop.enabled, "its transport shows the playing state")
app:tick(1 / 60)
t.assertEqual(#app.mini.refs.visualizer.values, #app.refs.visualizer.values, "it plays the same visualization")
app:actions().openMiniPlayer()
local mini = app.mini
app:stop()
t.expect(mini.refs.play.enabled, "transport changes reach the mini player")
app:actions().closeMiniPlayer()
t.assertEqual(app.mini, nil, "its restore button closes it")
t.assertEqual(#app:views(), 1, "and the main window takes the display back")
app:actions().openMiniPlayer()
app.mini.window:close()
t.assertEqual(app.mini, nil, "closing its window restores the main window too")

-- The stage: the visualizer between the toolbar and the panels, measured
-- from each window's layout (window coordinates grow upward).
local function rect(y, height) return {origin = {x = 0, y = y}, size = {width = 1000, height = height}} end
local function fakeRefs(view, content, panels)
	return {visualizer = {frameInWindow = view}, content = {frameInWindow = content}, panels = {frameInWindow = panels}}
end
local stage = app:stage(fakeRefs(rect(0, 800), rect(0, 750), rect(20, 300)))
t.assertEqual(stage.y, 50 / 800, "the stage starts under the toolbar")
t.assertEqual(stage.height, (480 - 50) / 800, "and ends at the panels' top edge")
t.assertEqual(stage.x .. " " .. stage.width, "0 1", "it spans the full width")
t.assertEqual(app:stage(fakeRefs(rect(0, 0), rect(0, 0), rect(0, 0))), Visuals.fullStage,
	"an unlaid-out view falls back to the whole picture")
t.assertEqual(app:stage(fakeRefs(rect(0, 400), rect(0, 350), rect(20, 400))), Visuals.fullStage,
	"panels covering the view fall back to the whole picture")
t.expect(app.refs.content ~= nil and app.refs.panels ~= nil, "the window names its content and panels")
app:actions().openMiniPlayer()
t.expect(app.mini.refs.content ~= nil and app.mini.refs.panels ~= nil, "so does the mini player")
app:closeMiniPlayer()

-- A resting picture is resent only when its stage moves.
local sent = 0
local fakeView = setmetatable({}, {__newindex = function(_, key) if key == "values" then sent = sent + 1 end end})
local laidOut = rect(0, 800)
local resting = fakeRefs(laidOut, rect(0, 750), rect(20, 300))
resting.visualizer = setmetatable({frameInWindow = laidOut}, {__index = {}, __newindex = fakeView})
app.stop(app)
local views = app.views
app.views = function() return {resting} end
for _ = 1, 400 do app:tick(1 / 60) end
t.expect(app.visuals:settled(), "the stopped visualizer settles")
sent = 0
app:tick(1 / 60)
t.assertEqual(sent, 0, "a settled picture is not resent")
resting.panels.frameInWindow = rect(20, 200)
app:tick(1 / 60)
t.assertEqual(sent, 1, "a resize that moves the stage resends it")
app.views = views

os.exit(t.summary() and 0 or 1)
