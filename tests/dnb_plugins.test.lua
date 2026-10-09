_G.__headless = true
local ns = require("AppKit")
local t = require("TestKit")
local Model = require("apps.dnb.Model")
local Synth = require("apps.dnb.models.Synth")
local Drums = require("apps.dnb.models.Drums")
local Visuals = require("apps.dnb.models.Visuals")
local Styles = require("apps.dnb.host.Styles")
local StyleKit = require("apps.dnb.host.StyleKit")
local Canvas = require("apps.dnb.host.Canvas")
local Composer = require("apps.dnb.host.Composer")
local Visualizers = require("apps.dnb.host.Visualizers")
local Controller = require("apps.dnb.Controller")

local SR = 11025 -- synthesis is rate-independent; a low rate keeps the suite fast
local TRACKS = 6 -- how many tracks of a set the per-style checks look at
local LABELS = {["Mix in"] = true, Groove = true, Lift = true, Peak = true, Release = true, Breakdown = true,
	["Mix out"] = true}
-- Genres whose arc turns risers and snare rolls off: nothing in their
-- arrangements may be a riser, though the shared blocks include some.
local NO_RISERS = {techno = true, breakbeat = true}
-- Roles that may sound in the first and last bars of a track (host/Canvas.lua):
-- the layers a DJ mixes over, and the fx that announce what follows.
local ENDS = {drums = true, tops = true, texture = true, fx = true}

local controlIds = {}
for _, group in ipairs(Model.controlGroups) do for _, control in ipairs(group.controls) do controlIds[control.id] = true end end

local function setOf(list)
	local set = {}
	for _, tag in ipairs(list or {}) do set[tag] = true end
	return set
end

-- A channel as the set sees it: the style's fallback for its role, then its own.
local function specOf(style, entry)
	local spec = {}
	for k, v in pairs(style.roles and style.roles[entry.role] or {}) do spec[k] = v end
	for k, v in pairs(entry) do spec[k] = v end
	return spec
end

-- Every block of a plan, by lane, with its catalogue entry.
local function eachBlock(composer, plan, visit)
	for _, lane in ipairs(plan.lanes) do
		for _, block in ipairs(lane.blocks) do
			visit(lane.part, block, composer.catalogue.byId[block.pattern])
		end
	end
end

local function hasEvent(plan, kind)
	for _, event in ipairs(plan.events) do
		if event.kind == kind then return true end
	end
	return false
end

-- The phrase of `plan` that is the highest in energy, and the quietest one
-- between the mix-in and the mix-out.
local function extremes(plan)
	local loud, quiet
	for _, phrase in ipairs(plan.phrases) do
		if not loud or phrase.energy > loud.energy then loud = phrase end
		if not phrase.edge and (not quiet or phrase.energy < quiet.energy) then quiet = phrase end
	end
	return loud, quiet
end

-- Renders a second from the first bar of `phrase` and measures it.
local function loudness(synth, track, phrase)
	synth.composerBar = track.start + phrase.start
	local out = {}
	synth:render(out, SR)
	local peak, sum, bad = 0, 0, false
	for i = 1, #out do
		local x = math.abs(out[i])
		if x ~= x then bad = true end
		if x > peak then peak = x end
		sum = sum + x * x
	end
	return peak, math.sqrt(sum / #out), bad
end

-- Every style plugin honours the contract the app and Synth rely on.
local list = Styles:list()
t.expect(#list >= 7, "the generator ships drum & bass and at least six more styles")
t.assertEqual(list[1].id, "dnb", "drum & bass is the first style")
local seenTitles, flavourTotal = {}, 0
local shapes = {}
for _, style in ipairs(list) do
	local name = style.title
		t.expect(not seenTitles[name], name .. " has a unique title")
	seenTitles[name] = true
	for id in pairs(style.defaults or {}) do t.expect(controlIds[id], name .. " defaults name real controls") end
	t.expect(pcall(Synth.mix, style.mix), name .. " mix overrides real fields")
	t.expect(pcall(Drums.design, style.kit), name .. " kit overrides real fields")
	t.expect(#style.flavours >= 5, name .. " plays " .. #style.flavours .. " kinds of track")
	t.expect(pcall(Canvas.arc, style.arc), name .. " has an arc of known fields")
	flavourTotal = flavourTotal + #style.flavours
	local ids = {}
	local a, b = Styles:create(style.id, 21), Styles:create(style.id, 21)
	local catalogue = a.catalogue
	for _, flavour in ipairs(style.flavours) do
		t.expect(not ids[flavour.id], name .. " flavours have ids of their own")
		ids[flavour.id] = true
		t.expect(flavour.tempo[1] <= flavour.tempo[2] and flavour.tempo[1] >= 100 and flavour.tempo[2] <= 180,
			name .. " " .. flavour.name .. " has a tempo range")
		t.expect(flavour.swing[1] <= flavour.swing[2] and flavour.swing[2] <= 0.5, name .. " " .. flavour.name .. " has a swing range")
		t.expect(#flavour.channels <= Model.channels, name .. " " .. flavour.name .. " fits eight channels")
		local ok, err = pcall(Canvas.arc, style.arc, flavour.arc)
		t.expect(ok, name .. " " .. flavour.name .. " has a valid arc: " .. tostring(err))

		-- Each channel finds blocks to play, and the tags it wants exist on
		-- some block of its role.
		local roles = {}
		for _, entry in ipairs(flavour.channels) do
			local role = entry.role
			t.expect(not roles[role], name .. " " .. flavour.name .. " has one " .. role .. " channel")
			roles[role] = true
			local spec = specOf(style, entry)
			local found = catalogue:candidates(role, style.id, flavour.id, setOf(spec.avoid))
			t.expect(#found > 0, name .. " " .. flavour.name .. " " .. role .. " finds blocks to play")
			for _, tag in ipairs(spec.wants or {}) do
				local tagged = 0
				for _, block in ipairs(found) do
					if block.tags[tag] then tagged = tagged + 1 end
				end
				t.expect(tagged > 0, name .. " " .. flavour.name .. " " .. role .. " wants '" .. tag .. "' and finds it on a block")
			end
		end
		t.expect(roles.drums, name .. " " .. flavour.name .. " has drums")
	end

	local model = Model.new(21, style)
	for id, value in pairs(style.defaults or {}) do t.assertEqual(model:value(id), value, name .. " sets its " .. id) end
	local flavours = {}
	local bassOk, polyOk, stepsOk, slicesOk, patchesOk, fieldsOk = true, true, true, true, true, true
	for n = 0, a:trackStart(3) - 1 do
		local bar = a:bar(n, model)
		local twin = b:bar(n, model)
		t.assertEqual(#bar.hits .. ":" .. #bar.slices .. ":" .. #bar.notes .. ":" .. bar.key,
			#twin.hits .. ":" .. #twin.slices .. ":" .. #twin.notes .. ":" .. twin.key, name .. " bar " .. n .. " is deterministic")
		flavours[bar.style] = true
		local track = a:trackAt(n)
		local plan = a:arrangement(track.index)
		local pos = n - track.start
		local phrase, index = plan:phraseAt(pos)
		if bar.arc ~= phrase.energy or bar.label ~= phrase.label or bar.phrase ~= index or bar.phraseBar ~= pos % track.phraseBars
			or bar.trackBar ~= pos or bar.trackLength ~= track.length or not LABELS[bar.label]
			or bar.arc < 0 or bar.arc > 1 or bar.section ~= nil then
			fieldsOk = false
		end
		for _, h in ipairs(bar.hits) do
			if not Drums.place[h.voice] then fieldsOk = false end
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
	local count = 0
	for _ in pairs(flavours) do count = count + 1 end
	t.expect(count >= 2, name .. " sets move between flavours")
	t.expect(fieldsOk, name .. " bars carry their phrase's arc, label and position, and kit voices only")
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

	-- The blocks it arranges exist, play a role of their lane, and fit the
	-- shape of the track: moves where its curve has them, a quiet mix-in.
	local used, usedFlavours, riser = {}, {}, false
	local breakdowns, kickOuts = 0, 0
	local minutes, curve = 0, {}
	for k = 0, TRACKS - 1 do
		local track = a.set:track(k)
		local plan = a:arrangement(k)
		local tname = string.format("%s track %d (%s)", name, k, track.flavour.name)
		t.assertEqual(plan.length, track.length, tname .. " is arranged whole")
		t.assertEqual(track.length % track.arc.unit, 0, tname .. " is whole units long")
		t.expect(track.length >= 4 * track.arc.unit, tname .. " is at least four units long")
		minutes = minutes + track.length * 4 / track.tempo
		t.expect(plan.phrases[1].start == 0 and #plan.phrases == track.length // track.arc.phrase, tname .. " is phrases of its arc's length")
		eachBlock(a, plan, function(part, block, entry)
			t.expect(a.patterns[block.pattern] ~= nil and a.patterns[block.pattern].part == part,
				tname .. " " .. part .. " plays " .. block.pattern)
			used[block.pattern] = true
			if entry then
				if entry.flavours then for id in pairs(entry.flavours) do usedFlavours[id] = true end end
				if entry.kind == "riser" then riser = true end
				-- A genre without risers never places one.
				t.expect(not (NO_RISERS[style.id] and entry.kind == "riser"), tname .. " places no riser")
			end
		end)
		for _, event in ipairs(plan.events) do
			if event.kind == "riser" then riser = true end
		end
		t.expect(not (NO_RISERS[style.id] and (hasEvent(plan, "riser"))), tname .. " has no riser event")

		-- Moves: every valley of its curve is a breakdown the timeline names
		-- and a return follows; a track without one still takes its kick out.
		local valleys = 0
		for _, phrase in ipairs(plan.phrases) do
			if phrase.valley then
				valleys = valleys + 1
				t.expect(not phrase.edge and phrase.label == "Breakdown", tname .. " names its valley a breakdown")
			end
		end
		if valleys > 0 then
			breakdowns = breakdowns + 1
			t.expect(hasEvent(plan, "valley") and hasEvent(plan, "return"), tname .. " has a breakdown and a way back")
		end
		if hasEvent(plan, "drumsOut") then kickOuts = kickOuts + 1 end
		-- A curve with two peaks apart (dips of 0.2 between anchors, 0.15 once
		-- the anchors are moved a little) is laid out with a first and a second.
		local anchors = track.arc.curve
		local dips = false
		for i = 1, #anchors do
			for j = i + 1, #anchors do
				for l = j + 1, #anchors do
					if anchors[i][2] >= 0.6 and anchors[l][2] >= 0.6 and anchors[j][2] <= math.min(anchors[i][2], anchors[l][2]) - 0.2 then
						dips = true
					end
				end
			end
		end
		if dips then
			local found = false
			local peaks = plan.phrases
			for q = 1, #peaks do
				local left, right = 0, 0
				for p = 1, q - 1 do left = math.max(left, peaks[p].energy) end
				for r = q + 1, #peaks do right = math.max(right, peaks[r].energy) end
				if left >= 0.55 and right >= 0.55 and peaks[q].energy <= math.min(left, right) - 0.15 then found = true end
			end
			t.expect(found, tname .. " has a first and a second peak")
		end
		if track.lift then
			local lifted = plan:phraseAt(track.lift.bar)
			t.expect(hasEvent(plan, "lift") and lifted.start == track.lift.bar and lifted.energy >= 0.75,
				tname .. " lifts its key into its second peak")
		end

		-- The mix-in and mix-out are quiet and keep to the layers a DJ mixes over.
		local outro = 0
		for _, phrase in ipairs(plan.phrases) do
			if phrase.start + phrase.length > track.length - track.arc.outro then outro = math.max(outro, phrase.energy) end
			if phrase.start < track.arc.intro then
				t.expect(phrase.energy <= 0.7 and phrase.label == "Mix in", tname .. " mixes in quietly at bar " .. phrase.start)
			end
			if phrase.start + phrase.length > track.length - track.arc.outro then
				t.expect(phrase.label == "Mix out", tname .. " labels its last phrases Mix out at bar " .. phrase.start)
			end
		end
		t.expect(outro <= 0.7, string.format("%s mixes out quietly (its mix-out reaches an energy of %.2f)", tname, outro))
		t.expect(plan.phrases[1].energy <= 0.5 and plan.phrases[#plan.phrases].energy <= 0.5,
			tname .. " begins and ends on a low energy")
		eachBlock(a, plan, function(part, block)
			local from, to = block.start, block.start + block.length
			if from < track.arc.intro or to > track.length - track.arc.outro then
				local blend = block.pattern == "pad.blend" or block.pattern == "bass.blend"
				t.expect(ENDS[part] or blend, tname .. " plays " .. block.pattern .. " at bar " .. from .. " of its mix")
			end
		end)
		local intro = plan:blocksAt(0).drums
		local introBlock = intro and a.catalogue.byId[intro.pattern]
		t.expect(introBlock and introBlock.energy <= 0.6, tname .. " starts on a quiet drum loop")
		for tenth = 0, 9 do
			curve[tenth + 1] = (curve[tenth + 1] or 0) + plan:energyAt(math.floor(track.length * (tenth + 0.5) / 10)) / TRACKS
		end
	end
	t.expect(breakdowns + kickOuts > 0, name .. " plays a breakdown or a kick-out in " .. TRACKS .. " tracks")
	if style.id == "dnb" or style.id == "trance" then
		t.expect(riser, name .. " builds on risers")
	end

	-- Across tracks the style mixes its own blocks: more than one flavour's.
	local own, flavourSpecific = 0, 0
	for id in pairs(used) do
		local block = a.catalogue.byId[id]
		if block and block.genre == style.id then own = own + 1 end
	end
	local named = 0
	for _ in pairs(usedFlavours) do named = named + 1 end
	t.expect(own >= 8, name .. " plays " .. own .. " of its own blocks in " .. TRACKS .. " tracks")
	t.expect(named >= 2, name .. " plays blocks of " .. named .. " flavour-specific lists in " .. TRACKS .. " tracks")
	table.insert(shapes, {id = style.id, length = minutes / TRACKS, curve = curve})

	-- It sounds: the highest-energy phrase of every flavour and its quietest
	-- interior one render in range.
	for _, flavour in ipairs(style.flavours) do
		local only = setmetatable({flavours = {flavour}}, {__index = style})
		local composer = Composer.new(only, 21)
		local synth = Synth.new(model, SR, style)
		synth:setComposer(composer)
		local track = composer.set:track(0)
		local loud, quiet = extremes(composer:arrangement(0))
		t.expect(loud.start >= track.arc.intro and not loud.edge, name .. " " .. flavour.name .. " peaks after its mix-in")
		t.expect(quiet ~= nil and quiet.energy < loud.energy, name .. " " .. flavour.name .. " has a quieter interior phrase")
		for _, case in ipairs({{"peak", loud}, {"quiet phrase", quiet}}) do
			local peak, rms, bad = loudness(synth, track, case[2])
			t.expect(not bad and peak <= 1 and rms > 0.05,
				string.format("%s %s %s is audible and soft-clipped (%.3f)", name, flavour.name, case[1], rms))
			t.expect(rms < 0.5, string.format("%s %s %s leaves the master room (%.3f)", name, flavour.name, case[1], rms))
		end
	end
end
t.expect(flavourTotal >= 40, "the styles play " .. flavourTotal .. " kinds of track between them")

-- Genres give their tracks different shapes: their own lengths, mix-ins and
-- energy curves, not one form with another palette.
do
	local byId = {}
	for _, shape in ipairs(shapes) do byId[shape.id] = shape; end
	local function distance(x, y)
		local sum = 0
		for i = 1, #x do sum = sum + math.abs(x[i] - y[i]) end
		return sum / #x
	end
	local lengths = {}
	for _, shape in ipairs(shapes) do lengths[string.format("%.1f", shape.length)] = true end
	local distinct = 0
	for _ in pairs(lengths) do distinct = distinct + 1 end
	t.expect(distinct >= 3, "the genres' tracks differ in length: " .. distinct .. " distinct averages")
	t.expect(distance(byId.techno.curve, byId.dnb.curve) > 0.03, "techno and drum & bass draw different energy curves")
	t.expect(distance(byId.techno.curve, byId.trance.curve) > 0.02, "techno and trance draw different energy curves")
	t.expect(byId.techno.length > byId.dnb.length, "techno tracks run longer, in minutes, than drum & bass")
	local intros = {}
	for _, style in ipairs(list) do
		local arc = Canvas.arc(style.arc)
		intros[style.id] = arc.intro
	end
	t.expect(intros.techno > intros.dnb, "techno mixes in longer than drum & bass")
end

-- Model: a style sets the controls' defaults; what plays is its tracks'.
local techno = Styles:get("techno")
local model = Model.new(3, Styles:get("dnb"))
model:setRoles({"drums"})
model:setStyle(techno)
t.assertEqual(model:value("energy"), techno.defaults.energy, "control defaults follow the style")
t.assertEqual(model:value("pitch"), 0, "and the pitch fader returns to rest")
t.expect(not model:plays("tops") and model:plays("drums"), "a style change keeps which channels sound")
-- A record's break is a block of the genre's own: only breakbeat styles write one.
local breaks = {}
for _, style in ipairs(Styles:list()) do
	for _, block in ipairs(Styles:create(style.id, 1).catalogue.list) do
		if block.genre == style.id and block.beat and block.beat.kit == "break" then breaks[style.id] = true end
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
		local loud = extremes(source:arrangement(k))
		bassPlayer.composerBar = track.start + loud.start
		bassPlayer:render({}, bassPlayer.nextBarFrame - bassPlayer.frame + SR)
		local voice = bassPlayer.mono.bass
		if voice and track.byRole.bass then
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
	t.expect(#scene.arc == 2 and scene.arc[1] >= 0 and scene.arc[2] <= 1 and scene.arc[1] < scene.arc[2],
		scene.title .. " names a range of energy")
	t.expect(scene.sections == nil, scene.title .. " has no sections")
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

-- Visuals: the director picks a scene by the energy of the moment, and pinning.
for step = 0, 100 do
	local energy = step / 100
	local pool = 0
	for _, scene in ipairs(scenes) do
		if energy >= scene.arc[1] and energy <= scene.arc[2] then pool = pool + 1 end
	end
	t.expect(pool > 0, "a scene plays at an energy of " .. energy)
end
local function inArc(index, energy)
	local scene = scenes[index + 1]
	return energy >= scene.arc[1] and energy <= scene.arc[2]
end
local visuals = Visuals.new(scenes, 4)
local horizon = Visualizers:index("horizon") - 1
t.assertEqual(visuals.scene, horizon, "the idle scene opens the quiet pool")
visuals:pin(Visualizers:index("tunnel") - 1)
local bar = {frame = 0, frames = 4000, arc = 0.2, label = "Breakdown", phrase = 3, phraseBar = 0, number = 24,
	trackBar = 24, trackLength = 96, tonic = 0}
for _ = 1, 200 do visuals:update({playing = true, bar = bar, played = 10, sampleRate = 1000}, 1 / 60) end
t.assertEqual(visuals.scene, Visualizers:index("tunnel") - 1, "a pinned scene plays whatever the energy")
visuals:pin(nil)
for _ = 1, 200 do visuals:update({playing = true, bar = bar, played = 10, sampleRate = 1000}, 1 / 60) end
t.expect(inArc(visuals.scene, 0.2), "unpinned, the director returns to a scene of the moment's energy")
t.assertThrows(function() visuals:pin(99) end, "only loaded scenes can be pinned")
t.expect(math.abs(visuals.intensity - (0.35 + 0.65 * 0.2)) < 1e-9, "intensity follows the phrase's energy")
t.expect(math.abs(visuals.progress - 24 / 96) < 0.01, "progress is the track's")

-- A scene lasts a phrase of eight bars and never repeats the one showing.
local director = Visuals.new(scenes, 4)
local function at(number, arc)
	return {arc = arc, phraseBar = number % 8, number = number}
end
for _, arc in ipairs({0.1, 0.3, 0.5, 0.58, 0.8, 1}) do
	local first, key = director:sceneFor(at(16, arc))
	t.expect(inArc(first, arc), "the scene for an energy of " .. arc .. " suits it")
	for n = 16, 23 do
		local scene, same = director:sceneFor(at(n, arc))
		t.expect(scene == first and same == key, "bars of one phrase keep one scene at " .. arc)
	end
	local later, other = director:sceneFor(at(24, arc))
	t.expect(other ~= key, "the next phrase takes a new key at " .. arc)
	t.expect(inArc(later, arc), "and a scene that suits " .. arc)
end
director.scene = (director:sceneFor(at(0, 0.8)))
t.expect(director:sceneFor(at(0, 0.8)) ~= director.scene, "a phrase does not repeat the scene already showing")
director:pin(2)
t.assertEqual(select(2, director:sceneFor(at(0, 0.8))), "pinned", "a pin overrides the director")
local quietScene = Visuals.new(scenes, 4):sceneFor({arc = 0.05, phraseBar = 0, number = 0})
local loudScene = Visuals.new(scenes, 4):sceneFor({arc = 0.95, phraseBar = 0, number = 0})
t.expect(inArc(quietScene, 0.05) and not inArc(quietScene, 0.95), "a quiet moment gets a calm scene")
t.expect(inArc(loudScene, 0.95) and not inArc(loudScene, 0.05), "and a peak gets an intense one")

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
t.assertEqual(app.controls.refs.value_energy.text, "70%", "the sliders take the style's defaults")
t.assertEqual(app.controls.refs.control_energy.doubleValue, techno.defaults.energy, "and move to them")
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
