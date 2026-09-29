_G.__headless = true
local ns = require("AppKit")
local t = require("TestKit")
local Model = require("apps.dnb.Model")
local Synth = require("apps.dnb.models.Synth")
local Drums = require("apps.dnb.models.Drums")
local Visuals = require("apps.dnb.models.Visuals")
local Styles = require("apps.dnb.host.Styles")
local StyleKit = require("apps.dnb.host.StyleKit")
local Visualizers = require("apps.dnb.host.Visualizers")
local Controller = require("apps.dnb.Controller")

local SR = 11025 -- synthesis is rate-independent; a low rate keeps the suite fast

local controlIds = {}
for _, group in ipairs(Model.controlGroups) do for _, control in ipairs(group.controls) do controlIds[control.id] = true end end

-- Every style plugin honours the contract the app and Synth rely on.
local list = Styles:list()
t.expect(#list >= 7, "the generator ships drum & bass and at least six more styles")
t.assertEqual(list[1].id, "dnb", "drum & bass is the first style")
local seenTitles, flavourTotal = {}, 0
for _, style in ipairs(list) do
	local name = style.title
	t.expect(not seenTitles[name], name .. " has a unique title")
	seenTitles[name] = true
	for id in pairs(style.defaults or {}) do t.expect(controlIds[id], name .. " defaults name real controls") end
	t.expect(pcall(Synth.mix, style.mix), name .. " mix overrides real fields")
	t.expect(pcall(Drums.design, style.kit), name .. " kit overrides real fields")
	t.expect(#style.flavours >= 5, name .. " plays " .. #style.flavours .. " kinds of track")
	flavourTotal = flavourTotal + #style.flavours
	local ids = {}
	for _, flavour in ipairs(style.flavours) do
		t.expect(not ids[flavour.id], name .. " flavours have ids of their own")
		ids[flavour.id] = true
		t.expect(flavour.tempo[1] <= flavour.tempo[2] and flavour.tempo[1] >= 100 and flavour.tempo[2] <= 180,
			name .. " " .. flavour.name .. " has a tempo range")
		t.expect(flavour.swing[1] <= flavour.swing[2] and flavour.swing[2] <= 0.5, name .. " " .. flavour.name .. " has a swing range")
		t.expect(#flavour.channels <= Model.channels, name .. " " .. flavour.name .. " fits eight channels")
	end

	local model = Model.new(21, style)
	for id, value in pairs(style.defaults or {}) do t.assertEqual(model:value(id), value, name .. " sets its " .. id) end
	local a, b = Styles:create(style.id, 21), Styles:create(style.id, 21)
	local sections, flavours, voices = {}, {}, {}
	local bassOk, polyOk, stepsOk, slicesOk, patchesOk = true, true, true, true, true
	for n = 0, a:trackStart(3) - 1 do
		local bar = a:bar(n, model)
		local twin = b:bar(n, model)
		t.assertEqual(#bar.hits .. ":" .. #bar.slices .. ":" .. #bar.notes .. ":" .. bar.key,
			#twin.hits .. ":" .. #twin.slices .. ":" .. #twin.notes .. ":" .. twin.key, name .. " bar " .. n .. " is deterministic")
		sections[bar.section] = true
		flavours[bar.style] = true
		local track = a:trackAt(n)
		for _, h in ipairs(bar.hits) do
			voices[h.voice] = true
			if h.step < 0 or h.step >= 16 or h.gain <= 0 or h.gain > 1.01 then stepsOk = false end
			if not track.byRole[h.role] then patchesOk = false end
		end
		for _, slice in ipairs(bar.slices) do
			if slice.step < 0 or slice.step >= 16 or slice.slice < 0 or slice.slice >= slice.beat.slices then slicesOk = false end
			if Model.family[slice.role] ~= "drums" or not track.byRole[slice.role] then slicesOk = false end
		end
		for _, note in ipairs(bar.notes) do
			if not note.patch or #note.notes < 1 or note.step < 0 or note.step >= 16 then patchesOk = false end
			if not track.byRole[note.role] then patchesOk = false end
			if note.role == "bass" and (note.notes[1] < 24 or note.notes[1] > 64 or note.step + note.length > 16.6) then
				bassOk = false
			end
			if (note.role == "stab" or note.role == "keys" or note.role == "pad") and #note.notes < 3 then polyOk = false end
		end
		t.expect(type(bar.progression) == "string" and bar.chord ~= nil, name .. " names its harmony")
		t.expect(bar.tempo >= 100 and bar.tempo <= 180 and bar.trackTempo == track.tempo, name .. " bars carry their tempo")
	end
	for _, section in ipairs({"intro", "build", "drop", "breakdown", "outro"}) do
		t.expect(sections[section], name .. " arranges a " .. section)
	end
	local count = 0
	for _ in pairs(flavours) do count = count + 1 end
	t.expect(count >= 2, name .. " sets move between flavours")
	for voice in pairs(voices) do t.expect(Drums.place[voice], name .. " plays kit voices only: " .. voice) end
	t.expect(stepsOk, name .. " hits sit inside the bar with sane gains")
	t.expect(slicesOk, name .. " slices lie inside their loops, on drum channels")
	t.expect(patchesOk, name .. " notes play a patch on a channel of their track")
	t.expect(bassOk, name .. " bass stays in the bass register and inside the bar")
	t.expect(polyOk, name .. " chords have at least three notes")
	t.expect(a:trackStart(1) > 0 and a:trackAt(a:trackStart(1)).index == 1, name .. " exposes its tracks for Next Track")

	-- Roles it does not play produce nothing.
	local muted = Model.new(21, style)
	muted:setRoles({})
	local silent = Styles:create(style.id, 21)
	local anything = 0
	for n = 0, 80 do
		local bar = silent:bar(n, muted)
		anything = anything + #bar.hits + #bar.slices + #bar.notes
	end
	t.assertEqual(anything, 0, name .. " is silent playing no roles")

	-- The patterns it arranges exist, and its own play real roles.
	for _, pattern in ipairs(style.patterns or {}) do
		t.expect(Model.family[pattern.part], name .. " pattern " .. pattern.id .. " plays a real role")
	end
	for k = 0, 5 do
		local plan = a:arrangement(k)
		t.assertEqual(plan.length, a.set:track(k).length, name .. " arranges each track whole")
		for _, lane in ipairs(plan.lanes) do
			for _, block in ipairs(lane.blocks) do
				t.expect(a.patterns[block.pattern] ~= nil and a.patterns[block.pattern].part == lane.part,
					name .. " " .. lane.part .. " plays " .. block.pattern)
			end
		end
	end

	-- It sounds: a drop renders in range, every flavour of it.
	for _, flavour in ipairs(style.flavours) do
		local only = setmetatable({flavours = {flavour}}, {__index = style})
		local composer = require("apps.dnb.host.Composer").new(only, 21)
		local synth = Synth.new(model, SR, style)
		synth:setComposer(composer)
		local drop
		for _, section in ipairs(composer:arrangement(0).sections) do drop = drop or (section.id == "drop" and section) end
		t.expect(drop ~= nil and drop.start >= composer:arrangement(0).sections[1].length, name .. " drops after its intro")
		synth.composerBar = drop.start
		local out = {}
		synth:render(out, SR)
		local peak, sum, bad = 0, 0, false
		for i = 1, #out do
			local x = math.abs(out[i])
			if x ~= x then bad = true end
			if x > peak then peak = x end
			sum = sum + x * x
		end
		local rms = math.sqrt(sum / #out)
		t.expect(not bad and peak <= 1 and rms > 0.05,
			string.format("%s %s drop is audible and soft-clipped (%.3f)", name, flavour.name, rms))
		t.expect(rms < 0.5, string.format("%s %s drop leaves the master room (%.3f)", name, flavour.name, rms))
	end
end
t.expect(flavourTotal >= 40, "the styles play " .. flavourTotal .. " kinds of track between them")

-- Model: a style sets the controls' defaults; what plays is its tracks'.
local techno = Styles:get("techno")
local model = Model.new(3, Styles:get("dnb"))
model:setRoles({"drums"})
model:setStyle(techno)
t.assertEqual(model:value("energy"), techno.defaults.energy, "control defaults follow the style")
t.assertEqual(model:value("pitch"), 0, "and the pitch fader returns to rest")
t.expect(not model:plays("tops") and model:plays("drums"), "a style change keeps which channels sound")
local breaks = {}
for _, style in ipairs(Styles:list()) do
	for _, flavour in ipairs(style.flavours) do
		for _, channel in ipairs(flavour.channels) do
			for _, id in ipairs(channel.beats or {}) do
				if id:find("^break%.") then breaks[style.id] = true end
			end
		end
	end
end
t.expect(breaks.dnb and breaks.breakbeat and not breaks.techno and not breaks.trance, "only breakbeat styles play a record's break")

-- Synth: mix overrides, the style's kit and a style change on the bar line.
t.assertThrows(function() Synth.mix({wub = 1}) end, "unknown mix fields are rejected")
local mix = Synth.mix({pad = 1.4})
t.assertEqual(mix.pad, 1.4, "overrides replace a field")
t.assertEqual(mix.bass, Synth.mix().bass, "and keep the rest")
local houseModel = Model.new(1, Styles:get("house"))
local synth = Synth.new(houseModel, SR, Styles:get("house"))
t.expect(#synth.shots.clap > 0 and #synth.shots.crash > 0, "styles get a clap over the shared cymbals")
local dnbSynth = Synth.new(houseModel, SR, Styles:get("dnb"))
t.expect(dnbSynth.shots.kick ~= synth.shots.kick, "a style's kick design renders its own kick")
t.assertEqual(Synth.new(houseModel, SR, Styles:get("house")).shots.kick, synth.shots.kick, "kits are cached by design")
synth:setComposer(Styles:create("house", 1))
synth:render({}, 2000)
local before = synth.kit
synth:setComposer(Styles:create("techno", 1), techno)
t.expect(synth.kit == before, "a new style waits for the bar line")
synth:render({}, synth.nextBarFrame - synth.frame + 10)
t.assertEqual(synth.kit.kick.decay, techno.kit.kick.decay, "and takes over on it")
t.assertEqual(synth.styleMix.duckDepth, techno.mix.duckDepth, "with its mix")

-- Track kits: every track draws its own snare character and reshapes the
-- style's kick, hats and clap, so a set never plays one kit throughout.
for _, style in ipairs(list) do
	local composer = Styles:create(style.id, 11)
	local characters, designs = {}, {}
	for k = 0, 11 do
		local track = composer.set:track(k)
		local design = track.drums
		t.expect(design and design.snare, style.title .. " track " .. k .. " has a kit design")
		local allowed = track.flavour.snares or StyleKit.snares
		local fits = false
		for _, name in ipairs(allowed) do fits = fits or name == design.snare end
		t.expect(fits, style.title .. " picks snares that suit the flavour")
		characters[design.snare] = true
		table.insert(designs, string.format("%s %.3f %.3f", design.snare, design.snareTune, design.kickTune))
	end
	local count = 0
	for _ in pairs(characters) do count = count + 1 end
	t.expect(count >= 3, style.title .. " varies the snare character across a set")
	t.expect(designs[1] ~= designs[2], style.title .. " gives consecutive tracks different kits")
	t.assertEqual(Styles:create(style.id, 11).set:track(3).drums.snareTune, composer.set:track(3).drums.snareTune,
		style.title .. " kits are reproducible from the seed")
	t.expect(composer:bar(0, Model.new(11, style)).drums == composer.set:track(0).drums, "bars carry their track's kit")
end

local base = Drums.design()
t.expect(Drums.variant(base, nil) == base, "no design keeps the style's kit")
local function design(snare, x)
	local d = {snare = snare}
	for _, key in ipairs(Drums.dimensions) do d[key] = x or 0 end
	return d
end
local roomy = Drums.variant(base, design("roomy"))
t.expect(roomy.snare.room > 0 and base.snare.room == 0, "a character reshapes the style's snare")
t.expect(roomy.snare ~= base.snare, "in a kit of its own")
local high = Drums.variant(base, design("tight", 1))
local low = Drums.variant(base, design("tight", -1))
t.expect(math.abs(high.snare.tone / low.snare.tone - 2 ^ (6 / 12)) < 1e-9, "snare tuning spans three semitones each way")
t.expect(high.kick.base > base.kick.base and low.kick.base < base.kick.base, "the kick is retuned too")
t.expect(high.hat.decay > low.hat.decay and high.clap.bursts == 4, "hats and the clap change with the kit")
t.assertThrows(function() Drums.variant(base, design("cowbell")) end, "unknown characters are rejected")

-- Each character keeps the backbeat's level: its first 80 ms within 2.5 dB
-- of the style's own snare.
local function attack(data)
	local n, sum = math.min(#data, math.floor(0.08 * SR)), 0
	for i = 1, n do sum = sum + data[i] ^ 2 end
	return math.sqrt(sum / n)
end
local reference = attack(Drums.shots(SR, base).snare)
local distinct = {}
for _, name in ipairs(StyleKit.snares) do
	local snare = Drums.shots(SR, base, design(name)).snare
	local db = 20 * math.log(attack(snare) / reference, 10)
	t.expect(math.abs(db) < 2.5, string.format("the %s snare sits %.1f dB from the style's", name, db))
	distinct[snare] = true
end
local renders = 0
for _ in pairs(distinct) do renders = renders + 1 end
t.assertEqual(renders, #StyleKit.snares, "every character renders its own snare")

-- The Synth switches kit on a track's first bar and holds it all track.
local kitModel = Model.new(4, Styles:get("dnb"))
local kitComposer = Styles:create("dnb", 4)
local player = Synth.new(kitModel, SR, Styles:get("dnb"))
player:setComposer(kitComposer)
player:render({}, 10)
t.expect(player.design == kitComposer.set:track(0).drums, "the first track plays its own kit")
local firstSnare = player.shots.snare
player.composerBar = kitComposer:trackStart(1)
player:render({}, player.nextBarFrame - player.frame + 10)
t.expect(player.design == kitComposer.set:track(1).drums, "the next track brings its kit on its first bar")
t.expect(player.shots.snare ~= firstSnare, "and its own snare")
for k = 2, 11 do player:applyDrums(kitComposer.set:track(k).drums) end
player:applyDrums(kitComposer.set:track(1).drums)
t.expect(#player.shots.snare > 0, "a bounded kit cache still plays every kit")
-- And its instruments: the bass of one track is not the bass of the next.
do
	local source = Styles:create("dnb", 4)
	local bassModel = Model.new(4, Styles:get("dnb"))
	bassModel:setRoles({"bass"})
	local bassPlayer = Synth.new(bassModel, SR, Styles:get("dnb"))
	bassPlayer:setComposer(source)
	local heard = {}
	for k = 0, 3 do
		local track = source.set:track(k)
		local drop
		for _, section in ipairs(source:arrangement(k).sections) do drop = drop or (section.id == "drop" and section) end
		bassPlayer.composerBar = track.start + drop.start
		bassPlayer:render({}, bassPlayer.nextBarFrame - bassPlayer.frame + SR)
		local voice = bassPlayer.mono.bass
		if voice then
			t.expect(voice.patch == track.byRole.bass.patch, "track " .. k .. " plays its own bass patch")
			heard[voice.patch.id] = true
		end
	end
	local patches = 0
	for _ in pairs(heard) do patches = patches + 1 end
	t.expect(patches >= 3, "four tracks play " .. patches .. " different basses")
end

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
-- Valley Flight's terrain is nested level-of-detail strips: a whole grid of
-- 300² cells as triangles once cost ~540k vertices a frame.
local terrain = Visualizers:get("landscape").draws[1]
t.assertEqual(terrain.primitive, "triangleStrip", "the terrain draws instanced strips")
t.expect(terrain.count * terrain.instances < 100000, "the terrain stays under 100k vertices a frame")
local sky = Visualizers:get("landscape").draws[3]
t.assertEqual(sky.depth, "test", "the sky draws last, only where terrain and water leave it uncovered")
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
local technoOpener = app.composer.set:track(0)
t.assertEqual(app.refs.value_energy.text, "70%", "the sliders take the style's defaults")
t.assertEqual(app.refs.control_energy.doubleValue, techno.defaults.energy, "and move to them")
t.assertEqual(app.refs.tempo.text, tostring(technoOpener.tempo), "the header shows the new set's tempo")
t.expect(technoOpener.tempo >= 118 and technoOpener.tempo <= 140, "which is a techno tempo")
t.expect(app.refs.detail.text:find(technoOpener.flavour.name, 1, true) ~= nil, "the idle header names the new set's track")
t.expect(app.synth.composer == app.composer and app.synth.pendingStyle == techno, "the synth switches on the next bar")
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
