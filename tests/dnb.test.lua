_G.__headless = true
local ns = require("AppKit")
local t = require("TestKit")
local Model = require("apps.dnb.Model")
local Styles = require("apps.dnb.host.Styles")
local StyleKit = require("apps.dnb.host.StyleKit")
local Visualizers = require("apps.dnb.host.Visualizers")
local Composer = require("apps.dnb.host.Composer")
local Synth = require("apps.dnb.models.Synth")
local Controller = require("apps.dnb.Controller")

local SR = 22050 -- half rate keeps synthesis tests fast; the code is rate-independent

-- A style with its form pinned to the classic one (intro, build, then drops
-- joined by a breakdown and a build, all at the style's own lengths), so
-- that bars can be named by number, and optionally with one flavour only,
-- every channel of which plays. Forms and channels drawn from the seed are
-- tested below and in tests/dnb_arrangement.test.lua.
local CLASSIC = {openings = {"build"}, links = {"breakdown build"}, builds = {"roll"},
	intro = {1}, build = {1}, drop = {1}, breakdown = {1}, melodic = {1}, rebuild = {1}}
local function pinned(id, seed, flavourId)
	local style = Styles:get(id)
	local set = {form = CLASSIC}
	for k, v in pairs(style.set) do set[k] = v end
	local fields = {set = set}
	if flavourId then
		for _, flavour in ipairs(style.flavours) do
			if flavour.id == flavourId then
				local copy = {}
				for k, v in pairs(flavour) do copy[k] = v end
				copy.form, copy.channels = nil, {}
				for i, channel in ipairs(flavour.channels) do
					local entry = {}
					for k, v in pairs(channel) do entry[k] = v end
					entry.chance = nil
					copy.channels[i] = entry
				end
				fields.flavours = {copy}
			end
		end
		assert(fields.flavours, "no flavour " .. flavourId)
	end
	return Composer.new(setmetatable(fields, {__index = style}), seed)
end
local function dnb(seed) return pinned("dnb", seed) end
local dnbStyle = Styles:get("dnb")

-- A model that plays only the roles named.
local function playing(roles)
	local m = Model.new(9, dnbStyle)
	m:setRoles(roles)
	return m
end
local function except(...)
	local drop, ids = {}, {}
	for _, id in ipairs({...}) do drop[id] = true end
	for _, role in ipairs(Model.roles) do if not drop[role.id] then table.insert(ids, role.id) end end
	return ids
end

-- Model: defaults, clamping and stepping.
local model = Model.new(5)
t.assertEqual(model:value("pitch"), 0, "the pitch fader rests in the middle")
t.assertEqual(model:formatted("pitch"), "+0.0%", "and shows its share of the tempo")
t.assertEqual(model:setValue("pitch", 3.3), 3.5, "pitch snaps to half a percent")
t.assertEqual(model:setValue("pitch", 40), 8, "and clamps to its range")
t.assertEqual(model:setValue("energy", -1), 0, "energy clamps to its minimum")
t.assertEqual(model:formatted("energy"), "0%", "percent controls format as percent")
t.expect(model:plays("drums") and model:plays("pad"), "without a word every role plays")
model:setRoles({"drums", "bass"})
t.expect(model:plays("drums") and not model:plays("pad"), "a role set names exactly what plays")
t.assertEqual(model:value("swing"), 1, "unrelated controls keep their values")
t.assertThrows(function() model:plays("cowbell") end, "unknown roles are rejected")
t.assertThrows(function() model:setRoles({"cowbell"}) end, "a role set rejects unknown roles")
t.assertThrows(function() model:setValue("tempo", 1) end, "unknown controls are rejected")
for _, id in ipairs({"drums", "bass", "chords", "melody", "pump", "swing", "wobble", "drive"}) do
	t.assertEqual(model:formatted(id), "100%", id .. " starts at the track's own level")
end
-- The sliders render as a complete grid.
for _, group in ipairs(Model.controlGroups) do
	t.assertEqual(#group.controls, #Model.controlGroups[1].controls, group.title .. " fills its column of bars")
end
t.assertEqual(model:value("complexity"), 0.5, "complexity defaults to the middle")
t.assertEqual(Model.channels, 8, "a track plays on eight channels")
t.expect(#Model.roles > Model.channels, "and picks them from more roles than it has channels")
for _, role in ipairs(Model.roles) do
	t.expect(Model.family[role.id] ~= nil and Model.roleIndex[role.id] ~= nil, role.id .. " has a family and a place")
end

-- Composer: an endless set of tracks, deterministic, gated by settings.
local settings = Model.new(9, dnbStyle)
local composer = dnb(9)
local same = dnb(9)
local function signature(c, n, m)
	local bar = c:bar(n, m or settings)
	local parts = {bar.section, bar.chord.root}
	for _, h in ipairs(bar.hits) do table.insert(parts, h.voice .. h.step) end
	for _, s in ipairs(bar.slices) do table.insert(parts, s.role .. s.beat.id .. s.slice) end
	for _, note in ipairs(bar.notes) do table.insert(parts, note.role .. note.step .. ":" .. note.notes[1]) end
	return table.concat(parts, ",")
end
t.assertEqual(signature(composer, 40), signature(same, 40), "the same seed composes the same bar")
local differs = false
for seed = 10, 14 do
	if signature(dnb(seed), 40) ~= signature(composer, 40) then differs = true end
end
t.expect(differs, "different seeds compose different bars")
t.assertEqual(signature(dnb(9), 5000), signature(composer, 5000), "far bars are reproducible without history")

-- The set: consecutive tracks with their own flavour, key, tempo and length.
local first, second = composer.set:track(0), composer.set:track(1)
t.assertEqual(first.start, 0, "the set opens on its first track")
t.assertEqual(second.start, first.length, "each track starts where the last one ends")
local flavours, lengths = {}, {}
for k = 0, 23 do
	local track = composer.set:track(k)
	flavours[track.flavour.id] = true
	lengths[track.length] = true
	if k > 0 then
		local previous = composer.set:track(k - 1)
		t.expect(track.flavour ~= previous.flavour, "consecutive tracks change flavour")
		local move = (track.tonic - previous.tonic) % 12
		t.expect(move == 0 or move == 5 or move == 7 or move == 2, "keys move by mixable steps")
	end
	t.assertEqual(composer:trackAt(track.start).index, k, "a track's first bar belongs to it")
	t.assertEqual(composer:trackAt(track.start + track.length - 1).index, k, "and so does its last")
end
local flavourCount = 0
for _ in pairs(flavours) do flavourCount = flavourCount + 1 end
t.expect(flavourCount >= 7, "a set moves through most flavours: " .. flavourCount)
local lengthCount = 0
for _ in pairs(lengths) do lengthCount = lengthCount + 1 end
t.expect(lengthCount > 1, "tracks run for different lengths")
t.assertEqual(composer:trackAt(first.length * 40).index > 20, true, "the set goes on indefinitely")

-- Channels: every track plays on its own eight, and no more.
for _, style in ipairs(Styles:list()) do
	local name = style.title
	local set = Styles:create(style.id, 9)
	local twin = Styles:create(style.id, 9)
	for k = 0, 11 do
		local track = set.set:track(k)
		local flavour = track.flavour
		t.expect(#track.channels >= 3 and #track.channels <= Model.channels,
			name .. " track " .. k .. " plays on " .. #track.channels .. " channels")
		t.assertEqual(track.channels[1].role, "drums", name .. " leads with its drums")
		local seen, names = {}, {}
		for i, channel in ipairs(track.channels) do
			t.expect(not seen[channel.role], name .. " has one channel to a role")
			seen[channel.role] = true
			t.expect(track.byRole[channel.role] == channel, name .. " finds a channel by its role")
			t.expect(type(channel.name) == "string" and #channel.name > 0, name .. " names its channels")
			t.expect(channel.patch ~= nil or channel.beat ~= nil, name .. " gives " .. channel.role .. " something to play")
			if channel.beat then t.expect(channel.alt ~= nil, name .. " drums have a groove to turn to") end
			table.insert(names, channel.name)
			t.assertEqual(twin.set:track(k).channels[i].name, channel.name, name .. " channels come from the seed alone")
		end
		t.expect(track.tempo >= flavour.tempo[1] and track.tempo <= flavour.tempo[2] and math.type(track.tempo) == "integer",
			name .. " " .. flavour.name .. " plays at a tempo of its own: " .. track.tempo)
		t.expect(track.swing >= flavour.swing[1] and track.swing <= flavour.swing[2], name .. " and a swing of its own")
	end
end

-- Variety: what tells one track from the next. Across a set the channels,
-- the instruments on them, the grooves, the tempo and the tune all change.
for _, style in ipairs(Styles:list()) do
	local name = style.title
	local set = Styles:create(style.id, 4)
	local distinct = {racks = {}, basses = {}, grooves = {}, tempos = {}, hooks = {}, lines = {}, cells = {}, roles = {}}
	local repeated = 0
	local before
	for k = 0, 15 do
		local track = set.set:track(k)
		local material = set:material(track)
		local rack, roles = {}, {}
		for _, channel in ipairs(track.channels) do
			table.insert(rack, channel.name)
			table.insert(roles, channel.role)
		end
		local rackName = table.concat(rack, "+")
		if rackName == before then repeated = repeated + 1 end
		before = rackName
		distinct.racks[rackName] = true
		distinct.roles[table.concat(roles, "+")] = true
		distinct.basses[track.byRole.bass and track.byRole.bass.name or "none"] = true
		distinct.grooves[track.byRole.drums.name] = true
		distinct.tempos[track.tempo] = true
		distinct.cells[material.cell.text] = true
		local hook = {}
		for _, note in ipairs(material.hook.notes) do table.insert(hook, note.step .. ":" .. note.offset) end
		distinct.hooks[table.concat(hook, " ")] = true
		local line = {}
		for _, note in ipairs(material.line.notes) do table.insert(line, note.step .. ":" .. note.offset) end
		distinct.lines[table.concat(line, " ")] = true
	end
	local function count(set_)
		local n = 0
		for _ in pairs(set_) do n = n + 1 end
		return n
	end
	t.assertEqual(repeated, 0, name .. " never plays the same instruments twice running")
	t.expect(count(distinct.racks) >= 15, name .. " gives 16 tracks " .. count(distinct.racks) .. " different sets of instruments")
	t.expect(count(distinct.roles) >= 5, name .. " tracks differ in which channels they have: " .. count(distinct.roles))
	t.expect(count(distinct.basses) >= 5, name .. " plays " .. count(distinct.basses) .. " different basses")
	t.expect(count(distinct.grooves) >= 4, name .. " plays " .. count(distinct.grooves) .. " different grooves")
	t.expect(count(distinct.tempos) >= 5, name .. " plays at " .. count(distinct.tempos) .. " different tempos")
	t.expect(count(distinct.hooks) >= 14, name .. " plays " .. count(distinct.hooks) .. " different hooks")
	t.expect(count(distinct.lines) >= 8, name .. " plays " .. count(distinct.lines) .. " different bass lines")
	t.expect(count(distinct.cells) >= 5, name .. " tracks have rhythms of their own: " .. count(distinct.cells))
end

-- Material: a track keeps its idea through every cycle.
for k = 0, 7 do
	local track = composer.set:track(k)
	local material = composer:material(track)
	t.expect(composer:material(track) == material, "a track's material is written once")
	t.expect(#material.motif > 0 and material.hook.bars == 4, "a track has a motif and a four-bar hook")
	for index = 0, track.cycles - 1 do
		local cycle = composer:cycle(track, index)
		t.expect(cycle.line == material.line, "every cycle plays the track's bass line")
		local rhythm, home = {}, {}
		for _, note in ipairs(cycle.hook.notes) do rhythm[note.step] = true end
		for _, note in ipairs(material.hook.notes) do
			home[note.step] = true
			t.expect(rhythm[note.step], "a later drop keeps the hook's rhythm")
		end
		if index == 0 then t.expect(cycle.hook == material.hook, "the first drop plays the hook as written") end
		t.expect(#cycle.fills > 0 and cycle.grooves.drums ~= nil, "a cycle has its groove and fills")
		t.expect(cycle.grooves.drums == track.byRole.drums.beat or cycle.grooves.drums == track.byRole.drums.alt,
			"the groove is the track's, or the one it turns to")
	end
end

-- Material never loops back: bars a track apart differ.
local repeats = 0
for n = 16, 47 do
	if signature(composer, n) == signature(composer, n + first.length) then repeats = repeats + 1 end
end
t.expect(repeats < 4, "the next track does not replay the last one")

-- Tempo: a track's own, reached through the blend from the one before.
t.assertEqual(composer:bar(0, settings).tempo, first.tempo, "the set opens at its first track's tempo")
t.assertEqual(composer:bar(20, settings).trackTempo, first.tempo, "a bar knows the tempo its loops were made at")
t.assertEqual(composer.set:tempoAt(second.start), first.tempo, "a new track mixes in at the old tempo")
t.assertEqual(composer.set:tempoAt(second.start + second.blendBars), second.tempo, "and has its own once the blend is done")
local midway = composer.set:tempoAt(second.start + second.blendBars // 2)
t.expect(midway >= math.min(first.tempo, second.tempo) and midway <= math.max(first.tempo, second.tempo),
	"riding the pitch fader between the two")
t.assertEqual(composer:bar(20, settings).swing, first.swing, "a bar carries its track's swing")

-- A track's arrangement: intro → build → drop → breakdown → build → drop … → outro.
local liquid = pinned("dnb", 9, "liquid")
local track0 = liquid.set:track(0)
t.assertEqual(liquid:bar(0, settings).section, "intro", "a track opens with an intro")
t.assertEqual(liquid:bar(8, settings).section, "build", "the intro leads into a build-up")
t.assertEqual(liquid:bar(16, settings).section, "drop", "the first drop lands on bar 17")
t.assertEqual(liquid:bar(48, settings).section, "breakdown", "a breakdown follows 32 drop bars")
t.assertEqual(liquid:bar(64, settings).section, "build", "the breakdown builds back up")
t.assertEqual(liquid:bar(72, settings).section, "drop", "and drops again")
t.assertEqual(liquid:bar(track0.length - 1, settings).section, "outro", "a track ends on an outro")
t.assertEqual(liquid:bar(track0.length, settings).section, "intro", "and the next track's intro follows")
local opening = liquid:bar(0, settings)
t.assertEqual(#opening:loop("drums"), 16, "the intro plays its drums in 16th slices")
t.assertEqual(opening:loop("drums")[1].variant, "light", "the groove without its extra layers")
t.assertEqual(opening.kickSteps[1], 0, "the set opens on a kick")
t.assertEqual(#opening:of("bass"), 0, "the first intro holds the bass back")
local build = liquid:bar(9, settings)
t.assertEqual(#build:loop("drums"), 0, "the build leaves the groove")
t.expect(#build:steps("snare") > 0, "for a roll")
t.assertEqual(#build:of("bass"), 0, "and holds the bass back for the drop")
t.expect(liquid:bar(12, settings).riser ~= nil and #liquid:bar(12, settings):of("fx") == 1, "the build carries a riser")
t.expect(liquid:bar(15, settings).riser.to > liquid:bar(9, settings).riser.to, "which rises")
t.expect(#liquid:bar(15, settings):steps("snare") > #build:steps("snare"), "as the roll tightens")
t.assertEqual(#liquid:bar(50, settings):loop("drums"), 0, "the breakdown has no drums")
t.assertEqual(#liquid:bar(50, settings).kickSteps, 0, "and no kick")
t.expect(#liquid:bar(track0.length - 2, settings):loop("drums") > 0, "the outro keeps a groove to mix over")

local drop = liquid:bar(17, settings)
t.assertEqual(#drop:loop("drums"), 16, "the drop plays its groove")
t.assertEqual(drop:loop("drums")[1].variant, "full", "in full")
t.assertEqual(drop.kickSteps[1], 0, "the drop kick lands on the downbeat")
t.assertEqual(table.concat(drop.snareSteps, ","), "4,12", "the snare holds the two-step backbeat")
for i, slice in ipairs(drop:loop("drums")) do
	t.assertEqual(slice.slice, (17 % slice.beat.bars) * 16 + i - 1, "a groove plays its loop in order")
	t.assertEqual(slice.beat, liquid:cycle(track0, 0).grooves.drums, "the cycle's groove")
end
t.expect(#drop:of("bass") > 0, "the drop has a bass line")
t.assertEqual(drop:of("bass")[1].step, 0, "the bass line starts on the downbeat")
for n = 16, 47 do
	for _, note in ipairs(liquid:bar(n, settings):of("bass")) do
		t.expect(note.notes[1] >= 24 and note.notes[1] <= 60, "bass notes stay in the bass register")
		t.expect(note.step + note.length <= 16.5, "bass notes end inside their bar")
		t.expect(note.patch == track0.byRole.bass.patch, "on the track's bass patch")
	end
end
local pad = liquid:bar(24, settings):of("pad")
t.assertEqual(#pad, 1, "the pad sounds a chord")
t.assertEqual(#pad[1].notes, 4, "of four notes")
t.assertEqual(pad[1].length, 32, "held for its two bars")
t.assertEqual(#liquid:bar(25, settings):of("pad"), 0, "and sounded once")
for _, note in ipairs(pad[1].notes) do
	t.expect(note >= 48 and note <= 72, "pad voicings stay in the pad register")
end
t.assertEqual(liquid:bar(16, settings):steps("crash")[1], 0, "a crash marks the drop")
t.assertEqual(liquid:bar(16, settings).hits[1].role, "fx", "on the effects channel")
t.expect(liquid:bar(16, settings).riser.from > liquid:bar(16, settings).riser.to, "over a downlifter")
t.assertEqual(liquid:bar(48, settings):of("bass")[1].length, 16, "the breakdown holds one long bass note")

-- The mix: a new track's intro carries the outgoing tune.
local track1 = liquid.set:track(1)
local blend = liquid:bar(track1.start, settings)
t.expect(blend.blend ~= nil, "a new track mixes in over the outgoing tune")
t.assertEqual(#blend:of("pad"), 1, "carrying its chords")
t.expect(blend:of("pad")[1].patch == track0.byRole.pad.patch, "on the outgoing track's pad")
t.expect(blend:of("bass")[1].patch == track0.byRole.bass.patch, "and its bass")
t.assertEqual(blend.track, 1, "while the drums belong to the new track")
t.assertEqual(liquid:bar(track1.start + 8, settings).blend, nil, "the mix completes within eight bars")
t.assertEqual(liquid:bar(0, settings).blend, nil, "the set's first track has nothing to mix from")

-- Energy and Complexity shape the bars, not the plan.
local low, high = Model.new(9, dnbStyle), Model.new(9, dnbStyle)
low:setValue("energy", 0)
high:setValue("energy", 1)
local lowCount, highCount = 0, 0
for n = 16, 31 do
	lowCount = lowCount + #liquid:bar(n, low).notes
	highCount = highCount + #liquid:bar(n, high).notes
end
t.expect(highCount > lowCount, "energy adds notes")
t.expect(liquid:bar(17, high):loop("drums")[1].energy and not liquid:bar(17, low):loop("drums")[1].energy,
	"and lets the groove's extra layers in")
local simple, busy = Model.new(9, dnbStyle), Model.new(9, dnbStyle)
simple:setValue("complexity", 0)
busy:setValue("complexity", 1)
local simpleCount, busyCount = 0, 0
for n = 16, 47 do
	simpleCount = simpleCount + #liquid:bar(n, simple).notes
	busyCount = busyCount + #liquid:bar(n, busy).notes
end
t.expect(busyCount > simpleCount, "complexity adds detail")
t.expect(liquid:bar(17, busy):loop("drums")[1].complexity and not liquid:bar(17, simple):loop("drums")[1].complexity,
	"and the groove's ghost notes")

-- The arrangement: each track is a plan of lanes and blocks, fixed before
-- its first bar plays, and bar n plays the blocks under it.
local plan = liquid:arrangement(0)
t.expect(plan == liquid:arrangement(0), "a track is arranged once")
t.assertEqual(plan.length, track0.length, "the plan spans its track")
t.assertEqual(plan.start, track0.start, "from the track's first bar")
t.assertEqual(plan.tempo, track0.tempo, "at its tempo")
local ids = {}
for _, section in ipairs(plan.sections) do table.insert(ids, section.id) end
t.assertEqual(table.concat(ids, " ", 1, 5), "intro build drop breakdown build", "the ruler names the sections in order")
t.assertEqual(ids[#ids], "outro", "and ends on the outro")
t.assertEqual(#plan.channels, #track0.channels, "the plan names the track's channels")
t.expect(#plan.lanes <= Model.channels, "and has a lane for each, at most")
local last = 0
for _, lane in ipairs(plan.lanes) do
	local row = plan:row(lane.part)
	t.expect(row ~= nil and row > last, "lanes follow the channels' order")
	last = row
end
t.assertEqual(plan.lanes[1].part, "drums", "the drums lead")
local blocks = plan:blocksAt(17)
t.assertEqual(blocks.drums.pattern, "drums.groove", "the drop's drum block is under bar 17")
t.assertEqual(blocks.bass.pattern, "bass.line", "and the bass line's")
t.assertEqual(plan:blocksAt(50).drums, nil, "the breakdown has no drum block")
t.assertEqual(plan:blocksAt(12).drums.pattern, "drums.roll", "the build rolls")
t.assertEqual(plan:blocksAt(12).fx.pattern, "fx.riser", "under a riser")
t.assertEqual(plan:blocksAt(80).tops.pattern, "tops.loop", "liquid brings its break with the second drop")
t.assertEqual(plan:blocksAt(40).tops, nil, "having saved it through the first")
local sectionOf = plan:sectionAt(50)
t.assertEqual(sectionOf.id .. " " .. sectionOf.start, "breakdown 48", "a bar finds its section")
for pos = 0, track0.length - 1 do
	local bar = liquid:bar(track0.start + pos, settings)
	local section = plan:sectionAt(pos)
	if bar.section ~= section.id or bar.sectionBar ~= pos - section.start then
		t.expect(false, "bar " .. pos .. " plays its section of the plan")
	end
end
local function describe(p)
	local parts = {}
	for _, lane in ipairs(p.lanes) do
		for _, block in ipairs(lane.blocks) do
			table.insert(parts, lane.part .. block.start .. "+" .. block.length .. block.pattern)
		end
	end
	return table.concat(parts, ",")
end
local reference = composer:arrangement(3)
t.assertEqual(describe(dnb(9):arrangement(3)), describe(reference), "the same seed arranges the same track")
t.expect(describe(dnb(10):arrangement(3)) ~= describe(reference), "another seed arranges it differently")
local controlled = Model.new(9, dnbStyle)
controlled:setValue("energy", 0.1)
local lowPlan = dnb(9)
lowPlan:bar(first.length * 3 + 20, controlled)
t.assertEqual(describe(lowPlan:arrangement(3)), describe(reference), "the controls shape bars, not the plan")

local muted = playing({})
for _, n in ipairs({20, 60, second.start, second.start + 20}) do
	local empty = composer:bar(n, muted)
	t.assertEqual(#empty.hits + #empty.slices + #empty.notes + #empty.kickSteps, 0, "playing no roles composes empty bars")
end
local noFx = playing(except("fx"))
t.assertEqual(#liquid:bar(16, noFx):steps("crash"), 0, "effects off removes crashes")
t.assertEqual(liquid:bar(12, noFx).riser, nil, "and the build's riser")
t.assertEqual(#liquid:bar(17, noFx):loop("drums"), 16, "and leaves the drums alone")

-- Breaks: a jungle tune opens on the raw break; the kit joins halfway.
local jungle = pinned("dnb", 9, "jungle")
local jungleTrack = jungle.set:track(0)
local atRest = Model.new(9, dnbStyle)
atRest:setValue("complexity", 0)
local raw = jungle:bar(1, atRest)
local record = jungleTrack.byRole.tops.beat
t.assertEqual(record.kit, "break", "jungle plays a record's break on its second loop")
t.assertEqual(#raw:loop("tops"), 16, "a jungle intro plays the break in 16th slices")
t.assertEqual(#raw:loop("drums"), 0, "on its own, the way a jungle tune opens")
for i, slice in ipairs(raw:loop("tops")) do
	t.assertEqual(slice.slice, (1 % record.bars) * 16 + i - 1, "unchopped slices play the loop in order")
end
t.assertEqual(jungle:arrangement(0):lane("drums").blocks[1].start, 4, "the jungle kit joins halfway through the intro")
local jungleDrop = jungle:bar(17, settings)
t.expect(#jungleDrop:loop("tops") > 0 and #jungleDrop:loop("drums") > 0, "jungle drops layer the break over the kit")
t.assertEqual(#jungleDrop.kickSteps, #jungle:bar(17, playing({"drums"})).kickSteps, "only the kit's kick pumps the mix")
t.assertEqual(#jungle:bar(17, playing(except("tops"))):loop("tops"), 0, "a muted channel leaves the break out")
t.assertEqual(pinned("dnb", 9, "neuro"):arrangement(0):lane("tops"), nil, "neurofunk has no channel for a break")

-- Chops: complexity rearranges slices; at rest the break plays straight.
local chopped, straight = Model.new(9, dnbStyle), Model.new(9, dnbStyle)
chopped:setValue("complexity", 1)
straight:setValue("complexity", 0)
local edits, reversed = 0, 0
for n = 16, 47 do
	local plain = jungle:bar(n, straight)
	local edited = jungle:bar(n, chopped)
	if jungle:arrangement(0):blocksAt(n).tops then
		for i, slice in ipairs(plain:loop("tops")) do
			t.assertEqual(slice.slice, (n % record.bars) * 16 + i - 1, "at rest the loop plays straight")
		end
		local at = {}
		for _, slice in ipairs(edited:loop("tops")) do
			t.expect(slice.slice >= 0 and slice.slice < record.slices, "chops stay inside the break")
			at[slice.step] = slice
			if slice.reverse then reversed = reversed + 1 end
		end
		for step = 0, 15 do
			local slice = at[step]
			if slice and slice.slice ~= (n % record.bars) * 16 + step then edits = edits + 1 end
		end
	end
end
t.expect(edits > 8, "chops rearrange the break: " .. edits)

-- Harmony: modes, extended voice-led chords, no diminished roots.
local modes = {}
for seed = 1, 10 do
	local c = dnb(seed)
	for k = 0, 3 do
		local track = c.set:track(k)
		modes[track.mode.name] = true
		t.expect(track.key:find(track.mode.name, 1, true) ~= nil, "a track's key names its mode")
		for cycleIndex = 0, track.cycles - 1 do
			local cycle = c:cycle(track, cycleIndex)
			for _, degree in ipairs(cycle.progression) do
				t.expect(not StyleKit.numeral(track.mode, degree):find("°"), "progressions avoid diminished roots")
			end
			for i = 2, #cycle.voicings do
				local moved = 0
				for j = 1, #cycle.voicings[i] do moved = moved + math.abs(cycle.voicings[i][j] - cycle.voicings[i - 1][j]) end
				t.expect(moved <= 12, "each chord moves its voices by a few semitones at most")
			end
		end
	end
end
t.expect(modes.minor and modes.dorian and modes.phrygian, "tracks are drawn from several minor modes")

-- Modulate: each cycle may move the key.
local moved = false
for k = 0, 5 do
	local track = composer.set:track(k)
	local secondDrop = track.start + 16 + 32 + 16 + 8
	if composer:bar(secondDrop, settings).key ~= track.key then moved = true end
	for _, b in ipairs(composer:bar(secondDrop + 1, settings):of("bass")) do
		t.expect(b.notes[1] >= 24 and b.notes[1] <= 60, "modulated bass stays in the bass register")
	end
	t.assertEqual(composer:bar(track.start + 16, settings).key, track.key, "a track's first drop is in its home key")
end
t.expect(moved, "modulation moves the key in later cycles")

-- Half-time: a switch-up inside the drop with the snare on beat three.
local neuro = pinned("dnb", 9, "neuro")
local htBar, htTrack
for k = 0, 10 do
	local track = neuro.set:track(k)
	if not htBar and neuro:cycle(track, 0).halftime then htBar, htTrack = track.start + 16 + 16, track end
end
t.expect(htBar ~= nil, "some drops switch to half-time")
local ht = neuro:bar(htBar, settings)
t.expect(ht.halftime, "the switch-up is marked for the header")
t.assertEqual(ht:loop("drums")[1].beat, htTrack.byRole.drums.half, "the drums turn to their half-time beat")
t.assertEqual(table.concat(ht.snareSteps, ","), "8", "which puts the snare on beat three")
t.expect(#ht:of("stab") == 0 and #ht:of("lead") == 0, "and the arrangement thins")
t.assertEqual(neuro:bar(htBar + 8, settings).halftime, nil, "for eight bars")

-- Fills: most phrases of a drop end on one, and they vary.
local fillBars, fillKinds = 0, {}
for k = 0, 5 do
	local track = composer.set:track(k)
	local arranged = composer:arrangement(k)
	for _, section in ipairs(arranged.sections) do
		if section.id == "drop" then
			for bar = 7, section.length - 1, 8 do
				local block = arranged:blocksAt(section.start + bar).drums
				if block and block.pattern == "drums.fill" then
					fillBars = fillBars + 1
					local played = composer:bar(track.start + section.start + bar, settings)
					local natural = true
					for _, slice in ipairs(played:loop("drums")) do
						local groove = composer:cycle(track, section.cycle).grooves.drums
						if slice.beat ~= groove then fillKinds.beat = true; natural = false end
						if slice.reverse then fillKinds.reverse = true; natural = false end
						if (slice.length or 1) < 1 then fillKinds.retrigger = true; natural = false end
						if slice.rate then fillKinds.tape = true; natural = false end
						if slice.slice ~= ((track.start + section.start + bar - track.start) % slice.beat.bars) * 16 + slice.step then
							natural = false
						end
					end
					t.expect(not natural or #played:loop("drums") < 16 or played.halftime, "a fill breaks the groove")
				end
			end
		end
	end
end
t.expect(fillBars >= 8, "phrases end on fills: " .. fillBars)
t.expect(fillKinds.beat and (fillKinds.reverse or fillKinds.retrigger or fillKinds.tape),
	"some play a fill of their own, others edit the groove")

-- Throws: dub echoes on the phrase's last bar.
local thrown = false
for n = 16, 47 do
	local bar = liquid:bar(n, settings)
	for _, list in ipairs({bar.slices, bar.notes}) do
		for _, played in ipairs(list) do
			if played.throw then
				thrown = true
				t.assertEqual((n - 16) % 4, 3, "throws land on every fourth bar")
			end
		end
	end
end
t.expect(thrown, "a phrase ends on a throw")

-- Arp, lead and the voice that answers it.
local anthem = pinned("dnb", 9, "anthem")
local anthemTrack = anthem.set:track(0)
local breakdown = anthem:bar(50, settings)
t.expect(#breakdown:of("arp") > 0, "the breakdown carries the arpeggio")
for _, a in ipairs(breakdown:of("arp")) do
	t.expect(a.notes[1] >= 55 and a.notes[1] <= 100, "arp notes sit above the pads")
	t.expect(a.step >= 0 and a.step < 16, "arp notes stay in their bar")
end
t.assertEqual(#anthem:bar(20, settings):of("lead"), 0, "the lead waits for the first drop's second half")
local leadNotes, counterNotes = 0, 0
for n = 32, 47 do
	local bar = anthem:bar(n, settings)
	for _, l in ipairs(bar:of("lead")) do
		leadNotes = leadNotes + 1
		t.expect(l.notes[1] >= 55 and l.notes[1] <= 96, "lead notes stay in the lead register")
		t.expect(l.step + l.length <= 16, "lead notes end inside their bar")
		t.expect(l.patch == anthemTrack.byRole.lead.patch, "on the track's lead")
	end
	for _, c in ipairs(bar:of("counter")) do
		counterNotes = counterNotes + 1
		t.expect(c.patch == anthemTrack.byRole.counter.patch, "the answer has a voice of its own")
	end
end
t.expect(leadNotes > 8, "the drop's second half carries the hook")
t.expect(#anthem:bar(74, settings):of("lead") + #anthem:bar(75, settings):of("lead") > 0,
	"which a later drop plays from its first phrase")
-- The hook is heard the same way twice: a phrase later it returns.
local function tune(c, n)
	local notes = {}
	for _, l in ipairs(c:bar(n, settings):of("lead")) do table.insert(notes, l.step .. ":" .. l.length) end
	return table.concat(notes, " ")
end
t.assertEqual(tune(anthem, 32), tune(anthem, 36), "the hook's first bar returns four bars on")
t.assertEqual(tune(anthem, 32), tune(anthem, 40), "and again")

-- Synth: bounded, deterministic, silent when muted, sample-accurate bars.
local function render(settingsModel, frames, source, start)
	local synth = Synth.new(settingsModel, SR, dnbStyle)
	synth:setComposer(source or dnb(9))
	synth.composerBar = start or 0
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
local full = Model.new(9, dnbStyle)
local out = render(full, SR * 2, nil, 16)
local peak, rms = stats(out)
t.assertEqual(#out, SR * 4, "render writes interleaved stereo frames")
t.expect(peak <= 1, "output is soft-clipped into range")
t.expect(rms > 0.03, "a full drop is audible")
local again = render(full, SR * 2, nil, 16)
local identical = true
for i = 1, #out, 97 do if out[i] ~= again[i] then identical = false break end end
t.expect(identical, "rendering is deterministic")

local silent = render(muted, SR)
t.assertEqual(select(1, stats(silent)), 0, "no roles render silence")

local drumsOnly = playing({"drums"})
drumsOnly:setValue("space", 0)
local kickOut = render(drumsOnly, 256, liquid, 16)
t.expect(math.abs(kickOut[2 * 64 - 1]) > 0.05, "the kick sounds on the first downbeat")

-- The Mix faders scale the style's balance: the Drums fader silences a
-- drums-only render and leaves a bass-only one alone.
local function level(roles, fader, value, source, start)
	local m = playing(roles)
	m:setValue("space", 0)
	m:setValue(fader, value)
	return select(2, stats(render(m, SR // 2, source or liquid, start or 17)))
end
t.assertEqual(level({"drums"}, "drums", 0), 0, "the Drums fader at zero silences the kit")
t.expect(level({"drums"}, "drums", 1.5) > level({"drums"}, "drums", 1), "and above 100% boosts it")
t.assertEqual(level({"bass"}, "drums", 0), level({"bass"}, "drums", 1), "the Drums fader leaves the bass alone")
t.assertEqual(level({"bass"}, "bass", 0), 0, "the Bass fader silences the bass")
t.expect(level({"pad", "keys"}, "chords", 1, liquid, 24) > level({"pad", "keys"}, "chords", 0.3, liquid, 24), "Chords scales the chords")
t.assertEqual(level({"tops"}, "drums", 0, jungle), 0, "a break is drums too")
for _, role in ipairs({"bass", "pad", "keys", "arp", "lead", "tops", "fx"}) do
	local source = (role == "tops") and jungle or (role == "lead" or role == "arp") and anthem or liquid
	local start = (role == "lead" or role == "arp" or role == "pad" or role == "keys") and 40 or (role == "fx" and 12 or 17)
	if role == "tops" then start = 0 end
	local m = playing({role})
	local sound, synth = render(m, SR * 2, source, start)
	local rolePeak, roleLevel = stats(sound)
	t.expect(roleLevel > 0.002 and rolePeak <= 1, role .. " reaches the output on its own")
	t.expect(synth:level(role) > 0, role .. " moves its channel's meter")
	t.assertEqual(synth:level(role == "bass" and "pad" or "bass"), 0, "and no other's")
end

-- A thrown snare echoes through the delay even with Space at zero.
local function echoTail(throws)
	local m = playing({"drums"})
	m:setValue("space", 0)
	local source = pinned("dnb", 9, "liquid")
	local barOf = source.bar
	source.bar = function(self, n, s)
		local bar = barOf(self, n, s)
		for _, slice in ipairs(bar.slices) do if not throws then slice.throw = nil end end
		return bar
	end
	local synth = Synth.new(m, SR, dnbStyle)
	synth:setComposer(source)
	synth.composerBar = 16 -- the first drop, whose fourth bar throws its snare
	local tail = {}
	local barFrames = math.floor(16 * SR * 60 / source.set:track(0).tempo / 4 + 0.5)
	synth:render({}, barFrames * 4 - barFrames // 8) -- up to the thrown snare's own tail
	synth:render(tail, barFrames // 4) -- straddling the bar line: the snare's tail and echoes
	return tail
end
do
	local wet, dry = echoTail(true), echoTail(false)
	local echo, level = 0, 0
	for i = 1, #dry do
		echo = echo + (wet[i] - dry[i]) ^ 2
		level = level + dry[i] ^ 2
	end
	t.expect(echo > 0.02 * level, "a throw echoes into the next bar")
end

-- A straight loop is one continuous sampler voice; chops start new slices.
local function sliceVoices(m, source, start, frames)
	local synth = Synth.new(m, SR, dnbStyle)
	synth:setComposer(source)
	synth.composerBar = start
	local sound, voices = {}, 0
	for _ = 1, frames // 512 do
		synth:render(sound, 512)
		local slices = 0
		for _, v in ipairs(synth.voices) do if v.kind == "slice" then slices = slices + 1 end end
		voices = math.max(voices, slices)
	end
	return voices, synth
end
do
	local solo = playing({"tops"})
	solo:setValue("complexity", 0)
	local voices = sliceVoices(solo, jungle, 0, SR * 2)
	t.assertEqual(voices, 1, "a straight break plays as one continuous voice")
	local edited = playing({"tops"})
	edited:setValue("complexity", 1)
	t.expect(sliceVoices(edited, jungle, 16, SR * 8) >= 2, "a chop crossfades into a new slice")
end

-- Chunked rendering matches one long render: blocks carry voice state.
local chunked, whole = {}, render(full, 3000, nil, 16)
do
	local synth = Synth.new(full, SR, dnbStyle)
	synth:setComposer(dnb(9))
	synth.composerBar = 16
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

-- Tempo: bars last as long as their track says, under the pitch fader.
local pitched = Model.new(9, dnbStyle)
local _, synth = render(pitched, SR * 3)
local expected = math.floor(16 * SR * 60 / first.tempo / 4 + 0.5)
t.assertEqual(synth.timeline[1].frames, expected, "bar length follows the track's tempo")
t.assertEqual(synth:barAt(expected - 1).number, 0, "the playhead maps frames to the first bar")
t.assertEqual(synth:barAt(expected).number, 1, "and to the next bar on its first frame")
pitched:setValue("pitch", 8)
synth:render({}, SR * 3)
local lastBar = synth.timeline[#synth.timeline]
t.assertEqual(lastBar.frames, math.floor(16 * SR * 60 / (first.tempo * 1.08) / 4 + 0.5), "the pitch fader applies at the next bar")
t.expect(math.abs(lastBar.playedTempo - first.tempo * 1.08) < 1e-9, "and a bar knows the tempo it played at")
synth:setComposer(dnb(77))
synth:render({}, SR * 2)
local restarted
for _, bar in ipairs(synth.timeline) do
	if bar.key == dnb(77).set:track(0).key and bar.section == "intro" and bar.sectionBar == 0 then restarted = bar end
end
t.expect(restarted ~= nil, "a new track starts its own intro at the next bar")
t.expect(restarted and restarted.number > 0, "without restarting the timeline")
-- The next track brings its tempo, and its loops are made at it.
do
	local player = Synth.new(Model.new(9, dnbStyle), SR, dnbStyle)
	local source = dnb(9)
	player:setComposer(source)
	player.composerBar = source:trackStart(1) + 8
	player:render({}, SR)
	t.assertEqual(player.timeline[1].frames, math.floor(16 * SR * 60 / second.tempo / 4 + 0.5),
		"a track past its blend plays at its own tempo")
	t.assertEqual(player.tempo, second.tempo, "which the synth follows")
end

-- Visuals: bar motion, peak holds, kick flashes and the shader layout.
local Visuals = require("apps.dnb.models.Visuals")
local visuals = Visuals.new(Visualizers:list(), 4)
local bar = {frame = 0, frames = 4000, kicks = {0, 2500}, section = "drop", sectionBar = 3, sectionLength = 32, tonic = 6}
local v = visuals:update({bands = {1, 0.5, 0, 0}, rms = 0.2, playing = true, bar = bar, played = 100, sampleRate = 1000}, 1 / 60)
local H = Visuals.header
t.assertEqual(#v, H + 2 * 4, "values hold the header, bands and peaks")
t.expect(v[H + 1] > 0.6 and v[H + 1] < 1, "bars rise quickly but not instantly")
t.assertEqual(v[H + 5], v[H + 1], "a rising bar carries its peak")
t.expect(v[2] > 0.5, "a kick just played flashes")
t.assertEqual(v[3], 0.5, "hue comes from the tonic")
t.assertEqual(v[4], 1, "the drop runs at full intensity")
t.assertEqual(v[6], 0.1, "beat phase is the position inside the beat")
local peak = v[H + 5]
for _ = 1, 10 do v = visuals:update({playing = true, bar = bar, played = 900, sampleRate = 1000}, 1 / 60) end
t.expect(v[H + 1] < peak, "silence lets bars fall")
t.assertEqual(v[H + 5], peak, "the peak holds while the bar falls")
t.expect(not visuals:settled(), "a moving visualizer is not settled")
for _ = 1, 300 do visuals:update({playing = false}, 1 / 60) end
t.expect(visuals:settled(), "without audio everything comes to rest")
t.assertEqual(visuals.presence, 0, "stopping fades the visualizer back to idle")

-- Scenes: one per section and phrase, crossfaded, back to the horizon at rest.
local scenes = Visuals.new(Visualizers:list(), 4)
local function drop(number, sectionBar)
	return {frame = 0, frames = 4000, kicks = {0}, snares = {1000}, section = "drop", sectionBar = sectionBar,
		sectionLength = 32, number = number, tonic = 0}
end
local frameAt = function(b) return {playing = true, bar = b, played = 1100, sampleRate = 1000, bands = {0.5, 0.5, 0.5, 0.5}} end
scenes:update(frameAt({frame = 0, frames = 4000, section = "intro", sectionBar = 0, sectionLength = 4, number = 0}), 1 / 60)
t.assertEqual(scenes.scene, Visualizers:index("horizon") - 1, "the intro opens on the spectrum horizon")
local seen = {}
local current = scenes.scene
for phrase = 0, 11 do
	local b = drop(8 + phrase * 8, (phrase * 8) % 32)
	for _ = 1, 120 do scenes:update(frameAt(b), 1 / 60) end
	t.assertEqual(scenes.fade, 0, "a crossfade completes within a phrase")
	t.expect(scenes.scene ~= current or phrase == 0, "each phrase brings a new scene")
	current = scenes.scene
	seen[scenes.scene] = true
end
local count = 0
for _ in pairs(seen) do count = count + 1 end
t.expect(count >= 5, "drops run through most scenes")
scenes:update(frameAt(drop(200, 0)), 1 / 60)
local packed = scenes:pack()
t.expect(packed[11] > 0 and packed[11] < 1 and packed[9] ~= packed[10], "a new phrase crossfades between two scenes")
t.expect(packed[12] > 0.3, "a snare just played flashes")
t.expect(packed[15] > 0, "scenes travel while playing")
for _ = 1, 300 do scenes:update({playing = false}, 1 / 60) end
t.assertEqual(scenes.scene, Visualizers:index("horizon") - 1, "stopping returns to the horizon")
t.expect(scenes:settled(), "and then rests")

-- Travel: a steady cruise whatever the music does, eased in on play and
-- out on stop, and sent with its speed so shaders extrapolate between updates.
local quiet, loudRun = Visuals.new(Visualizers:list(), 4), Visuals.new(Visualizers:list(), 4)
local cruiseBar = {frame = 0, frames = 4000, section = "drop", sectionBar = 0, sectionLength = 32, number = 0}
for i = 1, 240 do
	quiet:update({playing = true, bar = cruiseBar, played = 0, sampleRate = 1000, rms = 0.01, bands = {0.1, 0.1, 0.1, 0.1}}, 1 / 60)
	loudRun:update({playing = true, bar = cruiseBar, played = 0, sampleRate = 1000, rms = i % 2 == 0 and 0.4 or 0.05,
		bands = {1, 1, 1, 1}}, 1 / 60)
end
t.assertEqual(loudRun.travel, quiet.travel, "the music never changes travel speed")
t.expect(math.abs(quiet.speed - 0.8) < 0.01, "four seconds in, scenes fly at cruise")
local cruising = quiet:pack()
t.assertEqual(cruising[21], quiet.speed, "the speed is packed for the shader to extrapolate")
local before = quiet.travel
quiet:update({playing = true, bar = cruiseBar, played = 0, sampleRate = 1000}, 1 / 30)
t.expect(math.abs(quiet.travel - before - quiet.speed / 30) < 1e-3, "a late frame travels its real interval")
local fresh = Visuals.new(Visualizers:list(), 4)
fresh:update({playing = true, bar = cruiseBar, played = 0, sampleRate = 1000}, 1 / 60)
t.expect(fresh.speed > 0 and fresh.speed < 0.05, "play eases into the flight")
local speeds = {}
for _ = 1, 60 do
	quiet:update({playing = false}, 1 / 60)
	table.insert(speeds, quiet.speed)
end
t.expect(speeds[1] < 0.8 and speeds[1] > 0.7 and speeds[60] < speeds[1] / 2, "stop glides to rest")
t.expect(not quiet:settled(), "a gliding camera is not settled")
for _ = 1, 300 do quiet:update({playing = false}, 1 / 60) end
t.assertEqual(quiet.speed, 0, "and comes to a stop")

-- The stage: the main view rect scenes centre on, packed after the header.
local stageValues = scenes:pack()
t.assertEqual(stageValues[17] .. " " .. stageValues[18] .. " " .. stageValues[19] .. " " .. stageValues[20], "0 0 1 1",
	"without a measured stage scenes use the whole view")
stageValues = scenes:pack({x = 0, y = 0.1, width = 1, height = 0.5})
t.assertEqual(stageValues[18], 0.1, "the stage's top is a fraction of the view from the top")
t.assertEqual(stageValues[20], 0.5, "and so is its height")
t.assertEqual(#stageValues, Visuals.header + 2 * 4, "the stage lives inside the header")
t.assertEqual(scenes:update({playing = false, stage = {x = 0, y = 0.2, width = 1, height = 0.4}}, 1 / 60)[18], 0.2,
	"a frame can carry its stage")

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
local opener = Styles:create("dnb", 9).set:track(0)
t.expect(window ~= nil, "the controller creates its window")
t.assertEqual(app.refs.section.text, "Ready to play", "the header waits for playback")
t.expect(app.refs.detail.text:find(opener.key, 1, true) ~= nil, "the header names the key before playing")
t.assertEqual(app.refs.tempo.text, tostring(opener.tempo), "and the first track's tempo")
for _, group in ipairs(Model.controlGroups) do
	for _, control in ipairs(group.controls) do
		t.expect(app.refs["control_" .. control.id] ~= nil, control.id .. " renders from the model tables")
	end
end
t.expect(app.refs.control_tempo == nil, "a track, not the listener, sets the tempo")
t.expect(not app.refs.stop.enabled, "stop is disabled while stopped")
t.assertEqual(loops, 1, "the window starts one display loop")
t.assertEqual(#app.refs.visualizer.values, Visuals.header + 2 * 40, "the shader receives header values, bands and peaks")

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
t.expect(values[Visuals.header + 1] > values[Visuals.header + 2], "bars follow the analysed spectrum")
t.assertEqual(values[3], opener.tonic / 12, "the palette follows the track key")
t.assertEqual(app.refs.position.text, "Bar 1 of " .. app.composer:arrangement(0).sections[1].length,
	"and shows the bar in its section")

app.actions(app).control_cutoff(0.25)
t.assertEqual(app.model:value("cutoff"), 0.25, "a slider moves its model value")
t.assertEqual(app.refs.value_cutoff.text, "25%", "and its value label")
app:setControl("pitch", 4.2)
t.assertEqual(app.refs.value_pitch.text, "+4.0%", "pitch shows the snapped value")
output:consume(4096)
app:tick(1 / 60)
for _ = 1, 40 do -- past the next bar line, where the fader lands
	output:consume(4096)
	app:pump()
end
output:consume(100)
app:tick(1 / 60)
t.assertEqual(app.refs.tempo.text, tostring(math.floor(opener.tempo * 1.04 + 0.5)), "the header shows the tempo as played")
app:setControl("pitch", 0)
app:actions().control_drums(0.5)
t.assertEqual(app.refs.value_drums.text, "50%", "a Mix fader shows its level")
t.assertEqual(app.model:value("cutoff"), 0.25, "moving a fader leaves other sliders alone")

local seed = app.model.seed
t.expect(app.refs.detail.text:find("Track 1 · ", 1, true) == 1, "the header names the track and its flavour")
local nextStart = app.composer:trackStart(1)
app:nextTrack()
t.assertEqual(app.synth.composerBar, nextStart, "next track jumps to the next track's first bar")
for _ = 1, 40 do -- a couple of bars, past the next bar line
	output:consume(4096)
	app:pump()
end
local skipped = app.synth.timeline[#app.synth.timeline]
t.assertEqual(skipped.track, 1, "the set plays on from the next track")
t.assertEqual(skipped.section, "intro", "entering on its intro")
app:nextTrack()
t.assertEqual(app.synth.composerBar, app.composer:trackStart(2), "and again from there")
app:newSet()
t.assertEqual(app.model.seed, seed + 1, "a new set advances the seed")
t.expect(app.synth.composer == app.composer and app.composer.seed == seed + 1, "the synth plays the new set")

app:stop()
t.assertEqual(output.paused, 1, "stop pauses the output")
t.expect(not app.playing and app.refs.play.enabled, "stop re-enables play")
app:stop()
t.assertEqual(output.paused, 1, "stopping twice is harmless")

-- The display loop ticks by the time that really passed, not the timer's
-- nominal interval, so late frames do not slow the flight down.
local times, loop = {10, 10, 10.05, 10.06, 12}, nil
local timed = Controller.new({seed = 3, output = fakeOutput(1024), clock = function() return table.remove(times, 1) end,
	async = function(fn) loop = coroutine.wrap(fn) end, sleep = coroutine.yield})
timed:createWindow()
local ticks = {}
function timed:tick(dt) table.insert(ticks, dt) end
for _ = 1, 4 do loop() end
t.assertEqual(ticks[1], 0, "the first frame starts the clock")
t.expect(math.abs(ticks[2] - 0.05) < 1e-9 and math.abs(ticks[3] - 0.01) < 1e-9, "frames advance by measured time")
t.assertEqual(ticks[4], 0.1, "a stalled run loop resumes rather than leaping ahead")

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

-- Timeline: the arrangement as eight rows of clips around a fixed playhead.
local Timeline = require("apps.dnb.models.Timeline")
local tc = pinned("dnb", 9, "liquid")
local shown = tc.set:track(0)
local near = Timeline.plans(tc, 20)
t.assertEqual(#near, 1, "mid-track the timeline shows one track")
local ending = Timeline.plans(tc, shown.length - 4)
t.assertEqual(#ending, 2, "near its end the next track comes into view")
t.assertEqual(ending[2].track, 1, "the next track follows")
local rows = Timeline.rows(near)
t.assertEqual(#rows, 8, "the strip always has eight rows")
for i, row in ipairs(rows) do
	local channel = shown.channels[i]
	t.assertEqual(row.role, channel and channel.role or nil, "a row is a channel of the playing track")
	t.assertEqual(row.name, channel and channel.name or "", "named after what it plays")
end
t.assertEqual(rows[1].name, shown.byRole.drums.beat.name, "the drums are named after their groove")
t.assertEqual(rows[3].name, shown.byRole.bass.patch.name, "the bass after its patch")
local sparse = Timeline.rows({pinned("dnb", 9, "minimal"):arrangement(0)})
t.assertEqual(#sparse, 8, "a track with fewer channels still has eight rows")
t.assertEqual(sparse[8].name .. tostring(sparse[8].role), "nil", "its last ones empty")
local data = Timeline.instances(near)
local blockCount = 0
for _, lane in ipairs(near[1].lanes) do blockCount = blockCount + #lane.blocks end
t.assertEqual(#data, blockCount * Timeline.stride, "every block is one clip, and one instance")
t.assertEqual(data[1] .. " " .. data[2], "0 0", "the first track's first clip opens the strip")
local rowsOk, barsOk, coloursOk = true, true, true
for i = 1, #data, Timeline.stride do
	if data[i] < 0 or data[i] >= 8 then rowsOk = false end
	if data[i + 1] < 0 or data[i + 2] <= 0 then barsOk = false end
	if data[i + 3] ~= Model.roleIndex[shown.channels[data[i] + 1].role] - 1 then coloursOk = false end
end
t.expect(rowsOk and barsOk, "instances sit on real rows at real bars")
t.expect(coloursOk, "tinted as their role")
local later = Timeline.instances(ending)
local nextStarts = false
for i = 1, #later, Timeline.stride do
	if later[i + 1] == shown.length then nextStarts = true end
end
t.expect(nextStarts, "the next track's clips start where this one ends")
t.assertEqual(Timeline.headline(near, 20), "Breakdown in 28 bars", "the headline names the next section change")
t.assertEqual(Timeline.headline(near, 47), "Breakdown in 1 bar", "in bars")
t.assertEqual(Timeline.headline(ending, shown.length - 4), "Next track in 4 bars", "and the next track from the outro")
local strip = Timeline.values(20.5, 0.7, rows, 2, {drums = 1, bass = 0.1})
t.assertEqual(strip[1] .. " " .. strip[2] .. " " .. strip[3] .. " " .. strip[6], "20.5 0.7 8 2",
	"values carry the playhead, its speed, the rows and the scale")
t.assertEqual(#strip, 6 + 2 * 8, "then a meter and a colour for every row")
t.assertEqual(strip[7], 1, "a channel at full level fills its meter")
t.expect(strip[9] > 0.4 and strip[9] < 0.7, "one 20 dB down fills about half")
t.assertEqual(strip[8], 0, "a silent one none")
t.assertEqual(strip[6 + 8 + 3], Model.roleIndex.bass - 1, "a row's colour is its role's")
t.assertEqual(Timeline.meter(0), 0, "silence reads as nothing")
t.assertEqual(Timeline.meter(1e-9), 0, "and so does what lies under the meter's range")

local timelineApp = Controller.new({seed = 9, output = fakeOutput(1024), async = function() end})
timelineApp:createWindow()
local canvas = timelineApp.timeline.refs.timelineCanvas
t.expect(canvas ~= nil, "the window hosts the arrangement strip")
t.assertEqual(#canvas.draws, 1, "clips draw as one instanced draw")
t.assertEqual(canvas.draws[1].instances, #Timeline.instances(Timeline.plans(timelineApp.composer, 0)) // Timeline.stride,
	"one instance per clip")
t.assertEqual(#canvas.draws[1].data, canvas.draws[1].instances * Timeline.stride, "whole instances only")
t.assertEqual(canvas.values[1] .. " " .. canvas.values[2], "0 0", "stopped, the playhead rests on the first bar")
t.assertEqual(canvas.values[7], 0, "and the meters on nothing")
local openingSections = timelineApp.composer:arrangement(0).sections
t.assertEqual(timelineApp.timeline.refs.timelineNext.text,
	Timeline.headline(Timeline.plans(timelineApp.composer, 0), 0), "the header names what comes next")
t.expect(timelineApp.timeline.refs.timelineNext.text:find(" in " .. openingSections[1].length .. " bars", 1, true) ~= nil,
	"when the intro ends")
local stripTrack = timelineApp.composer.set:track(0)
for i = 1, 8 do
	local channel = stripTrack.channels[i]
	t.assertEqual(timelineApp.timeline.refs["channel" .. i].text, channel and channel.name or "",
		"row " .. i .. " is labelled with its channel")
end
local rowPixels = 100 / 8
local r, _, b = require("AppKitNative")._shaderPixel(canvas, 400, 100, 150, math.floor(rowPixels * 0.5))
t.expect(r > 0.2 and r > 2 * b, "the drums' clip draws in its tint on the first row, ahead of the playhead")
timelineApp:actions().nextTrack()
t.assertEqual(canvas.values[1], timelineApp.composer:trackStart(1), "Next Track moves the strip to the next track")
t.assertEqual(timelineApp.timeline.refs.channel1.text, timelineApp.composer.set:track(1).channels[1].name,
	"and renames the rows after its channels")
timelineApp:play()
timelineApp.output:consume(512)
timelineApp:tick(1 / 60)
local moving = timelineApp.timeline.refs.timelineCanvas.values
local sounding = timelineApp.synth.timeline[1]
t.expect(math.abs(moving[2] - sounding.tempo / 240) < 1e-9, "playing, the strip scrolls at the bar's tempo")
timelineApp:stop()
t.assertEqual(timelineApp.timeline.refs.timelineCanvas.values[2], 0, "stopping freezes it")
t.assertEqual(timelineApp.timeline.refs.timelineCanvas.values[7], 0, "and rests the meters")
local rowsBefore = timelineApp.timeline.refs.timelineCanvas.frame.size.height
timelineApp:actions().selectStyle(Styles:index("techno") - 1)
t.expect(timelineApp.timelineKey:find(tostring(timelineApp.composer), 1, true) == 1,
	"a new style's lanes replace the old clips")
t.assertEqual(timelineApp.timeline.refs.timelineCanvas.frame.size.height, rowsBefore, "on the same eight rows")
t.assertEqual(rowsBefore, 8 * 28, "each 28 points high")
t.expect(timelineApp.timeline.refs.timelineCanvas.frame.size.width > 400, "at its full width")
local arrangement, controls = timelineApp.refs.timeline.frameInWindow, timelineApp.refs.controls.frameInWindow
t.expect(arrangement.origin.x < controls.origin.x, "the arrangement sits left of the controls")
t.assertEqual(arrangement.origin.y, controls.origin.y, "on the same bottom row")
t.assertEqual(arrangement.size.width, controls.size.width, "the two panels split the row evenly")
t.assertEqual(arrangement.size.height, controls.size.height, "at the same height")

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
