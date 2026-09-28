_G.__headless = true
local ns = require("AppKit")
local t = require("TestKit")
local Model = require("apps.dnb.Model")
local Styles = require("apps.dnb.host.Styles")
local StyleKit = require("apps.dnb.host.StyleKit")
local Visualizers = require("apps.dnb.host.Visualizers")
-- The drum & bass style plugin, as the app creates it.
local function dnb(seed) return Styles:create("dnb", seed) end
local Synth = require("apps.dnb.models.Synth")
local Controller = require("apps.dnb.Controller")

local SR = 22050 -- half rate keeps synthesis tests fast; the code is rate-independent

-- Every part but `...`, as a style that leaves them out names its parts.
local function except(...)
	local drop, ids = {}, {}
	for _, id in ipairs({...}) do drop[id] = true end
	for _, id in ipairs(Model.parts) do if not drop[id] then table.insert(ids, id) end end
	return ids
end
-- A model whose style plays only `ids`.
local function playing(ids)
	local m = Model.new(9)
	m:setParts(ids)
	return m
end

-- Model: defaults, clamping and stepping.
local model = Model.new(5)
t.assertEqual(model:value("tempo"), 174, "tempo defaults to 174 BPM")
t.assertEqual(model:formatted("tempo"), "174 BPM", "tempo label shows BPM")
t.assertEqual(model:setValue("tempo", 171.6), 172, "tempo snaps to whole BPM")
t.assertEqual(model:setValue("tempo", 400), 180, "tempo clamps to its maximum")
t.assertEqual(model:setValue("energy", -1), 0, "energy clamps to its minimum")
t.assertEqual(model:formatted("energy"), "0%", "percent controls format as percent")
t.expect(model:plays("kick") and model:plays("pads"), "without a style every part plays")
model:setParts({"kick", "snare"})
t.expect(model:plays("kick") and not model:plays("pads"), "a part set names exactly what plays")
t.assertEqual(model:value("swing"), 0.12, "unrelated controls keep their values")
t.assertThrows(function() model:plays("cowbell") end, "unknown parts are rejected")
t.assertThrows(function() model:setParts({"cowbell"}) end, "a part set rejects unknown parts")
t.assertThrows(function() model:setValue("pitch", 1) end, "unknown controls are rejected")
for _, id in ipairs({"drums", "bass", "chords", "melody", "pump"}) do
	t.assertEqual(model:formatted(id), "100%", id .. " starts at the style's own level")
end
-- The sliders render as a complete grid.
for _, group in ipairs(Model.controlGroups) do
	t.assertEqual(#group.controls, #Model.controlGroups[1].controls, group.title .. " fills its column of bars")
end
t.assertEqual(model:value("complexity"), 0.5, "complexity defaults to the middle")

-- Composer: an endless set of tracks, deterministic, gated by settings.
local function hits(bar, voice)
	local steps = {}
	for _, h in ipairs(bar.hits) do
		if h.voice == voice then table.insert(steps, h.step) end
	end
	table.sort(steps)
	return steps
end
local settings = Model.new(9)
local composer = dnb(9)
local same = dnb(9)
local function signature(c, n)
	local bar = c:bar(n, settings)
	local parts = {bar.section, bar.chord.root}
	for _, h in ipairs(bar.hits) do table.insert(parts, h.voice .. h.step) end
	for _, b in ipairs(bar.bass) do table.insert(parts, "b" .. b.step .. ":" .. b.note) end
	for _, b in ipairs(bar.breaks) do table.insert(parts, "a" .. b.slice) end
	return table.concat(parts, ",")
end
t.assertEqual(signature(composer, 40), signature(same, 40), "the same seed composes the same bar")
local differs = false
for seed = 10, 14 do
	if signature(dnb(seed), 40) ~= signature(composer, 40) then differs = true end
end
t.expect(differs, "different seeds compose different bars")
t.assertEqual(signature(dnb(9), 5000), signature(composer, 5000), "far bars are reproducible without history")

-- The set: consecutive tracks with their own style, key and length.
local first, second = composer.set:track(0), composer.set:track(1)
t.assertEqual(first.start, 0, "the set opens on its first track")
t.assertEqual(second.start, first.length, "each track starts where the last one ends")
local styles, lengths = {}, {}
for k = 0, 11 do
	local track = composer.set:track(k)
	styles[track.flavour.id] = true
	lengths[track.length] = true
	if k > 0 then
		local previous = composer.set:track(k - 1)
		t.expect(track.flavour ~= previous.flavour, "consecutive tracks change style")
		local move = (track.tonic - previous.tonic) % 12
		t.expect(move == 0 or move == 5 or move == 7 or move == 2, "keys move by mixable steps")
	end
	t.assertEqual(composer:trackAt(track.start).index, k, "a track's first bar belongs to it")
	t.assertEqual(composer:trackAt(track.start + track.length - 1).index, k, "and so does its last")
end
t.expect(styles.liquid and styles.jungle and styles.neuro and styles.rollers, "a set moves through every style")
local lengthCount = 0
for _ in pairs(lengths) do lengthCount = lengthCount + 1 end
t.expect(lengthCount > 1, "tracks run for different lengths")
t.assertEqual(composer:trackAt(first.length * 40).index > 20, true, "the set goes on indefinitely")

-- Material never loops back: bars a cycle apart, and tracks apart, differ.
local repeats = 0
for n = 16, 47 do
	if signature(composer, n) == signature(composer, n + first.length) then repeats = repeats + 1 end
end
t.expect(repeats < 4, "the next track does not replay the last one")

-- A track's arrangement: intro → build → drop → breakdown → build → drop … → outro.
t.assertEqual(composer:bar(0, settings).section, "intro", "a track opens with an intro")
t.assertEqual(composer:bar(8, settings).section, "build", "the intro leads into a build-up")
t.assertEqual(composer:bar(16, settings).section, "drop", "the first drop lands on bar 17")
t.assertEqual(composer:bar(48, settings).section, "breakdown", "a breakdown follows 32 drop bars")
t.assertEqual(composer:bar(64, settings).section, "build", "the breakdown builds back up")
t.assertEqual(composer:bar(72, settings).section, "drop", "and drops again")
t.assertEqual(composer:bar(first.length - 1, settings).section, "outro", "a track ends on an outro")
t.assertEqual(composer:bar(first.length, settings).section, "intro", "and the next track's intro follows")
t.assertEqual(hits(composer:bar(0, settings), "kick")[1], 0, "the set opens on a kick")
t.assertEqual(table.concat(hits(composer:bar(0, settings), "snare"), ","), "4,12", "the intro already has the backbeat")
t.assertEqual(#composer:bar(0, settings).bass, 0, "the first intro holds the bass back")
t.assertEqual(#hits(composer:bar(9, settings), "kick"), 0, "the build drops the kick")
t.assertEqual(#hits(composer:bar(50, settings), "kick"), 0, "the breakdown has no kick")
t.assertEqual(#composer:bar(12, settings).bass, 0, "the build holds the bass back for the drop")
t.expect(composer:bar(12, settings).riser ~= nil, "the build carries a riser")
t.expect(#hits(composer:bar(first.length - 2, settings), "kick") > 0, "the outro keeps a groove to mix over")

-- The mix: a new track's intro carries the outgoing tune.
local blend = composer:bar(second.start, settings)
t.expect(blend.blend ~= nil, "a new track mixes in over the outgoing tune")
t.expect(blend.pad ~= nil, "carrying its chords")
t.assertEqual(blend.track, 1, "while the drums belong to the new track")
t.assertEqual(composer:bar(second.start + 8, settings).blend, nil, "the mix completes within eight bars")
t.assertEqual(composer:bar(0, settings).blend, nil, "the set's first track has nothing to mix from")

local drop = composer:bar(17, settings)
t.assertEqual(hits(drop, "kick")[1], 0, "the drop kick lands on the downbeat")
t.assertEqual(table.concat(hits(drop, "snare"), ","), "4,12", "the snare holds the two-step backbeat")
t.expect(#drop.bass > 0, "the drop has a bass line")
t.assertEqual(drop.bass[1].step, 0, "the bass line starts on the downbeat")
for _, note in ipairs(drop.bass) do
	t.expect(note.note >= 28 and note.note <= 52, "bass notes stay in the sub register")
	t.expect(note.step + note.length <= 16, "bass notes end inside their bar")
end
t.assertEqual(#composer:bar(16, settings).pad, 4, "pads voice a four-note chord")
t.assertEqual(composer:bar(17, settings).pad, nil, "a chord is sounded once for its two bars")
t.assertEqual(hits(composer:bar(16, settings), "crash")[1], 0, "a crash marks the drop")

local low, high = Model.new(9), Model.new(9)
low:setValue("energy", 0)
high:setValue("energy", 1)
local lowCount, highCount = 0, 0
for n = 16, 31 do
	lowCount = lowCount + #composer:bar(n, low).hits + #composer:bar(n, low).bass
	highCount = highCount + #composer:bar(n, high).hits + #composer:bar(n, high).bass
end
t.expect(highCount > lowCount, "energy adds hits and bass notes")

-- The arrangement: each track is a plan of lanes and blocks, fixed before
-- its first bar plays, and bar n plays the blocks under it.
local plan = composer:arrangement(0)
t.expect(plan == composer:arrangement(0), "a track is arranged once")
t.assertEqual(plan.length, first.length, "the plan spans its track")
t.assertEqual(plan.start, first.start, "from the track's first bar")
local ids = {}
for _, section in ipairs(plan.sections) do table.insert(ids, section.id) end
t.assertEqual(table.concat(ids, " ", 1, 5), "intro build drop breakdown build", "the ruler names the sections in order")
t.assertEqual(ids[#ids], "outro", "and ends on the outro")
local order, rank = {}, {}
for i, id in ipairs(Model.parts) do rank[id] = i end
for i, lane in ipairs(plan.lanes) do
	order[i] = rank[lane.part]
	if i > 1 then t.expect(order[i] > order[i - 1], "lanes follow the timeline's part order") end
end
t.assertEqual(plan.lanes[1].part, "kick", "the kick lane leads")
local blocks = plan:blocksAt(17)
t.assertEqual(blocks.kick.pattern, "kick.drop", "the drop's kick block is under bar 17")
t.expect(blocks.sub and blocks.reese, "the drop rolls the reese over the sub")
t.assertEqual(plan:blocksAt(50).kick, nil, "the breakdown has no kick block")
t.assertEqual(plan:blocksAt(12).snare.pattern, "roll.snare", "the build rolls the snare")
t.assertEqual(plan:blocksAt(12).risers.pattern, "riser.build", "under a riser")
local sectionOf = plan:sectionAt(50)
t.assertEqual(sectionOf.id .. " " .. sectionOf.start, "breakdown 48", "a bar finds its section")
t.assertEqual(plan:sectionAt(0).id, "intro", "the first bar is the intro's")
t.assertEqual(plan:sectionAt(first.length - 1).id, "outro", "the last bar is the outro's")
for pos = 0, first.length - 1 do
	local bar = composer:bar(first.start + pos, settings)
	local section = plan:sectionAt(pos)
	if bar.section ~= section.id or bar.sectionBar ~= pos - section.start then
		t.expect(false, "bar " .. pos .. " plays its section of the plan")
	end
end
local copy = dnb(9):arrangement(3)
local reference = composer:arrangement(3)
local function describe(p)
	local parts = {}
	for _, lane in ipairs(p.lanes) do
		for _, block in ipairs(lane.blocks) do
			table.insert(parts, lane.part .. block.start .. "+" .. block.length .. block.pattern)
		end
	end
	return table.concat(parts, ",")
end
t.assertEqual(describe(copy), describe(reference), "the same seed arranges the same track")
t.expect(describe(dnb(10):arrangement(3)) ~= describe(reference), "another seed arranges it differently")
local controlled = Model.new(9)
controlled:setValue("energy", 0.1)
local lowPlan = dnb(9)
lowPlan:bar(first.length * 3 + 20, controlled)
t.assertEqual(describe(lowPlan:arrangement(3)), describe(reference), "the controls shape bars, not the plan")
for k = 0, 8 do
	for _, lane in ipairs(composer:arrangement(k).lanes) do
		local stop = 0
		for _, block in ipairs(lane.blocks) do
			if block.start < stop then t.expect(false, "blocks never overlap in a lane") end
			stop = block.start + block.length
		end
	end
end

local muted = playing({})
for _, n in ipairs({20, 60, second.start, second.start + 20}) do
	local empty = composer:bar(n, muted)
	t.assertEqual(#empty.hits + #empty.bass + #empty.stabs + #empty.breaks + #empty.keys + #empty.arp + #empty.lead, 0,
		"a style playing no parts composes empty bars")
	t.assertEqual(empty.pad, nil, "muted pads are not voiced")
end
local noFills = playing(except("fills"))
t.assertEqual(#hits(composer:bar(16, noFills), "crash"), 0, "fills off removes crashes")
t.expect(composer:bar(12, noFills).riser ~= nil, "risers are their own part")
local noRisers = playing(except("risers"))
t.assertEqual(composer:bar(12, noRisers).riser, nil, "risers off removes the build's riser")
t.assertEqual(composer:bar(16, noRisers).riser, nil, "and the drop's downlifter")
t.expect(composer:bar(16, settings).riser.from > composer:bar(16, settings).riser.to, "a drop opens on a downlifter")

-- Styles: find a track of each in the set.
local function trackOf(style)
	for k = 0, 40 do
		local track = composer.set:track(k)
		if track.flavour.id == style then return track end
	end
end
local jungle, liquid, neuro = trackOf("jungle"), trackOf("liquid"), trackOf("neuro")

-- The Amen: a jungle track opens on the raw break and layers it in drops.
local Amen = StyleKit.amen
t.assertEqual(#Amen.pattern, Amen.bars, "the break is four bars")
t.expect(#Amen.snareSlices >= 6, "the break's snares are known slices")
local opening = composer:bar(jungle.start + 1, settings)
t.assertEqual(#opening.breaks, 16, "a jungle intro plays the break in 16th slices")
t.assertEqual(#hits(opening, "kick") + #hits(opening, "snare"), 0, "on its own, the way a jungle tune opens")
for i, b in ipairs(opening.breaks) do
	t.assertEqual(b.slice, ((jungle.start + 1) % Amen.bars) * 16 + i - 1, "unchopped slices play the loop in order")
end
local jungleDrop = composer:bar(jungle.start + 17, settings)
t.assertEqual(#jungleDrop.breaks, 16, "jungle drops layer the break")
t.expect(#hits(jungleDrop, "kick") > 0, "under the programmed kick")
t.assertEqual(#composer:bar(neuro.start + 17, settings).breaks, 0, "neurofunk leaves the break out")
t.assertEqual(#composer:bar(liquid.start + 17, settings).breaks, 0, "liquid saves it for a later drop")
local noAmen = playing(except("amen"))
t.assertEqual(#composer:bar(jungle.start + 17, noAmen).breaks, 0, "a muted Amen lane leaves the break out")
local junglePlan = composer:arrangement(jungle.index)
t.assertEqual(junglePlan:lane("kick").blocks[1].start, 4, "the jungle kit joins halfway through the intro")
t.assertEqual(composer:arrangement(neuro.index):lane("amen"), nil, "neurofunk arranges no Amen lane")
t.assertEqual(composer:arrangement(liquid.index):lane("amen").blocks[1].start, 16 + 32 + 16 + 8,
	"liquid's first break block opens its second drop")

-- Chops: complexity rearranges slices; off, the break plays straight.
local chopped, straight = Model.new(9), playing(except("chops"))
chopped:setValue("complexity", 1)
local edits = 0
for n = jungle.start + 16, jungle.start + 47 do
	local plain = composer:bar(n, straight)
	local edited = composer:bar(n, chopped)
	for i, b in ipairs(edited.breaks) do
		t.expect(b.slice >= 0 and b.slice < Amen.slices, "chops stay inside the break")
		t.assertEqual(plain.breaks[i].slice, (n % Amen.bars) * 16 + i - 1, "chops off plays the loop straight")
		if b.slice ~= plain.breaks[i].slice then edits = edits + 1 end
	end
end
t.expect(edits > 8, "chops rearrange the break")

-- Keys: the electric piano comps in liquid tracks, never in neurofunk.
local keysBars = 0
for n = liquid.start + 16, liquid.start + 47 do
	local bar = composer:bar(n, settings)
	keysBars = keysBars + (#bar.keys > 0 and 1 or 0)
	for _, k in ipairs(bar.keys) do t.assertEqual(#k.notes, 4, "keys voice the chord") end
end
t.expect(keysBars > 12, "liquid drops carry the keys")
for n = neuro.start, neuro.start + 60 do
	t.assertEqual(#composer:bar(n, settings).keys, 0, "neurofunk has no keys")
end
t.expect(composer:bar(neuro.start + 17, settings).bass[1].reese > composer:bar(liquid.start + 17, settings).bass[1].reese,
	"neurofunk leans on the reese")

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
				for j = 1, 4 do moved = moved + math.abs(cycle.voicings[i][j] - cycle.voicings[i - 1][j]) end
				t.expect(moved <= 12, "each chord moves its voices by a few semitones at most")
			end
		end
	end
end
t.expect(modes.minor and modes.dorian and modes.phrygian, "tracks are drawn from several minor modes")
for _, note in ipairs(composer:bar(16, settings).pad) do
	t.expect(note >= 48 and note <= 72, "pad voicings stay in the pad register")
end

-- Modulate: each cycle may move the key; off, the track stays home.
local moved = false
for k = 0, 5 do
	local track = composer.set:track(k)
	local secondDrop = track.start + 16 + 32 + 16 + 8
	if composer:bar(secondDrop, settings).key ~= track.key then moved = true end
	for _, b in ipairs(composer:bar(secondDrop + 1, settings).bass) do
		t.expect(b.note >= 28 and b.note <= 52, "modulated bass stays in the sub register")
	end
	t.assertEqual(composer:bar(track.start + 16, settings).key, track.key, "a track's first drop is in its home key")
end
t.expect(moved, "modulation moves the key in later cycles")

-- Half-time: a switch-up inside the drop with the snare on beat three.
local htBar
for k = 0, 10 do
	local track = composer.set:track(k)
	if not htBar and composer:cycle(track, 0).halftime then htBar = track.start + 16 + 16 end
end
t.expect(htBar ~= nil, "some drops switch to half-time")
local ht = composer:bar(htBar, settings)
t.expect(ht.halftime, "the switch-up is marked for the header")
t.assertEqual(table.concat(hits(ht, "snare"), ","), "8", "half-time puts the snare on beat three")
t.expect(#ht.stabs == 0 and #ht.lead == 0 and #ht.breaks == 0, "and thins the arrangement")
local noHalftime = playing(except("halftime"))
t.assertEqual(table.concat(hits(composer:bar(htBar, noHalftime), "snare"), ","), "4,12", "half-time off keeps the two-step")

-- Fills vary by phrase.
local fillVoices = {}
for n = 0, first.length + second.length do
	local bar = composer:bar(n, settings)
	if bar.section == "drop" and bar.sectionBar % 8 == 7 then
		for _, h in ipairs(bar.hits) do fillVoices[h.voice] = true end
	end
end
t.expect(fillVoices.tomHigh and fillVoices.tomLow, "some fills roll across the toms")
local fill = composer:bar(23, settings)
t.expect(#fill.hits > 0 and #hits(fill, "snare") ~= 2, "the last bar of a phrase breaks the groove")

-- Humanize: small reproducible drift; the kick stays tight.
local tight = Model.new(9)
tight:setValue("humanize", 0)
for _, h in ipairs(composer:bar(20, tight).hits) do
	t.assertEqual(h.nudge, 0, "humanize 0 plays on the grid")
end
local loose = Model.new(9)
loose:setValue("humanize", 1)
local maxKick, maxHat = 0, 0
for n = 16, 23 do
	for _, h in ipairs(composer:bar(n, loose).hits) do
		t.expect(math.abs(h.nudge) <= 0.07, "drift stays a fraction of a 16th")
		if h.voice == "kick" then maxKick = math.max(maxKick, math.abs(h.nudge)) end
		if h.voice == "hat" then maxHat = math.max(maxHat, math.abs(h.nudge)) end
	end
end
t.expect(maxHat > 0.01 and maxKick < maxHat, "hats drift more than the kick")

-- Complexity adds syncopation and detail.
local simple, busy = Model.new(9), Model.new(9)
simple:setValue("complexity", 0)
busy:setValue("complexity", 1)
local simpleCount, busyCount = 0, 0
for n = 16, 47 do
	simpleCount = simpleCount + #composer:bar(n, simple).hits + #composer:bar(n, simple).bass + #composer:bar(n, simple).arp
	busyCount = busyCount + #composer:bar(n, busy).hits + #composer:bar(n, busy).bass + #composer:bar(n, busy).arp
end
t.expect(busyCount > simpleCount, "complexity adds hits, bass notes and arp steps")

-- Throws: dub echoes on the phrase's last backbeat.
local thrown = false
for n = 16, 23 do
	for _, h in ipairs(composer:bar(n, settings).hits) do
		if h.throw then
			thrown = true
			t.assertEqual((n - 16) % 4, 3, "throws land on every fourth bar")
		end
	end
end
t.expect(thrown, "a phrase ends on a thrown snare")
local noThrows = playing(except("throws"))
for _, h in ipairs(composer:bar(19, noThrows).hits) do t.expect(not h.throw, "throws off sends no echoes") end

-- Arp and lead, in tracks whose cycles use them.
local arpTrack, leadTrack
for k = 0, 20 do
	local track = composer.set:track(k)
	local cycle = composer:cycle(track, 0)
	if not arpTrack and cycle.arpOn and track.cycles > 1 then arpTrack = track end
	if not leadTrack and cycle.leadOn then leadTrack = track end
end
local breakdown = composer:bar(arpTrack.start + 16 + 32 + 2, settings)
t.assertEqual(breakdown.section, "breakdown", "the breakdown follows the first drop")
t.expect(#breakdown.arp > 0, "the breakdown carries the arpeggio")
t.assertEqual(#composer:bar(arpTrack.start + 16, settings).arp, 0, "the drop lands without it")
for _, a in ipairs(breakdown.arp) do
	t.expect(a.note >= 60 and a.note <= 96, "arp notes sit above the pads")
	t.expect(a.step >= 0 and a.step < 16, "arp notes stay in their bar")
end
local dropStart = leadTrack.start + 16
t.assertEqual(#composer:bar(dropStart + 4, settings).lead, 0, "the lead waits for the drop's second half")
local leadNotes = 0
for n = dropStart + 16, dropStart + 31 do
	for _, l in ipairs(composer:bar(n, settings).lead) do
		leadNotes = leadNotes + 1
		t.expect(l.note >= 55 and l.note <= 96, "lead notes stay in the lead register")
		t.expect(l.step + l.length <= 16, "lead notes end inside their bar")
	end
end
t.expect(leadNotes > 8, "the drop's second half carries a melody")
local phraseEnd = composer:bar(dropStart + 24 + 3, settings).lead
if #phraseEnd > 0 then
	t.assertEqual(phraseEnd[#phraseEnd].length, 8, "the answer resolves on a long note")
end

-- Synth: bounded, deterministic, silent when muted, sample-accurate bars.
local function render(settingsModel, frames, seed, start)
	local synth = Synth.new(settingsModel, SR)
	synth:setComposer(dnb(seed or 9))
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
local full = Model.new(9)
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
t.assertEqual(select(1, stats(silent)), 0, "no parts render silence")

local kickOnly = playing({"kick"})
kickOnly:setValue("space", 0)
kickOnly:setValue("humanize", 0)
local kickOut = render(kickOnly, 256)
t.expect(math.abs(kickOut[2 * 64 - 1]) > 0.05, "the kick sounds on the first downbeat")

-- The Mix faders scale the style's balance: the Drums fader silences a
-- drums-only render and leaves a bass-only one alone.
local function level(parts, fader, value)
	local m = playing(parts)
	m:setValue("space", 0)
	m:setValue(fader, value)
	return select(2, stats(render(m, SR // 2, nil, 16)))
end
t.assertEqual(level({"kick", "snare"}, "drums", 0), 0, "the Drums fader at zero silences the kit")
t.expect(level({"kick", "snare"}, "drums", 1.5) > level({"kick", "snare"}, "drums", 1), "and above 100% boosts it")
t.assertEqual(level({"sub"}, "drums", 0), level({"sub"}, "drums", 1), "the Drums fader leaves the bass alone")
t.assertEqual(level({"sub"}, "bass", 0), 0, "the Bass fader silences the sub")

-- A thrown snare echoes through the delay even with Space at zero.
local function echoTail(throws)
	local m = playing(throws and {"snare", "throws"} or {"snare"})
	m:setValue("space", 0)
	local synth = Synth.new(m, SR)
	synth:setComposer(dnb(9))
	synth.composerBar = 16 -- the first drop, whose fourth bar throws its snare
	local out = {}
	local barFrames = math.floor(16 * SR * 60 / 174 / 4 + 0.5)
	synth:render({}, barFrames * 4 - barFrames // 8) -- up to the thrown snare's own tail
	synth:render(out, barFrames // 4) -- straddling the bar line: the snare's tail and echoes
	local energy = 0
	for i = 1, #out do energy = energy + out[i] * out[i] end
	return energy
end
t.expect(echoTail(true) > echoTail(false) * 4, "a throw echoes into the next bar")

-- Arp and lead reach the output on their own.
local melodic = playing({"lead", "arp"})
do
	local synth = Synth.new(melodic, SR)
	synth:setComposer(dnb(9))
	synth.composerBar = leadTrack.start + 16 + 16 -- the drop's second half: arp and lead
	local out = {}
	synth:render(out, SR * 2)
	local peak, level = stats(out)
	t.expect(level > 0.005 and peak <= 1, "arp and lead are audible and bounded")
end

-- The Amen reaches the output on its own, pitched up to tempo. Played
-- straight it is one continuous sampler voice; chops start new slices.
local function soloRender(part, start, frames, configure)
	local m = playing({part, "chops"})
	if configure then configure(m) end
	local synth = Synth.new(m, SR)
	synth:setComposer(dnb(9))
	synth.composerBar = start
	local out, voices = {}, 0
	for _ = 1, frames // 512 do
		synth:render(out, 512)
		local slices = 0
		for _, v in ipairs(synth.voices) do if v.kind == "slice" then slices = slices + 1 end end
		voices = math.max(voices, slices)
	end
	return out, voices, synth
end
do
	local out, voices, synth = soloRender("amen", jungle.start, SR * 2, function(m) m:setParts({"amen"}) end)
	local peak, level = stats(out)
	t.expect(level > 0.02 and peak <= 1, "the break is audible and bounded")
	t.assertEqual(voices, 1, "a straight break plays as one continuous voice")
	t.assertEqual(#synth.amen, math.floor(Amen.slices * SR * 60 / Amen.bpm / 4 + 0.5), "the loop is four bars at the record's tempo")
	local _, choppedVoices = soloRender("amen", jungle.start + 16, SR * 6, function(m) m:setValue("complexity", 1) end)
	t.expect(choppedVoices >= 2, "a chop crossfades into a new slice")
	local keysOut = soloRender("keys", liquid.start + 24, SR * 2)
	local keysPeak, keysLevel = stats(keysOut)
	t.expect(keysLevel > 0.003 and keysPeak <= 1, "the electric piano is audible and bounded")
end

-- Chunked rendering matches one long render: blocks carry voice state.
local chunked, whole = {}, render(full, 3000, nil, 16)
do
	local synth = Synth.new(full, SR)
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
synth:setComposer(dnb(77))
synth:render({}, SR * 2)
local restarted
for _, bar in ipairs(synth.timeline) do
	if bar.key == dnb(77).set:track(0).key and bar.section == "intro" and bar.sectionBar == 0 then restarted = bar end
end
t.expect(restarted ~= nil, "a new track starts its own intro at the next bar")
t.expect(restarted and restarted.number > 0, "without restarting the timeline")

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
t.expect(window ~= nil, "the controller creates its window")
t.assertEqual(app.refs.section.text, "Ready to play", "the header waits for playback")
t.expect(app.refs.detail.text:find(dnb(9).set:track(0).key, 1, true) ~= nil, "the header names the key before playing")
for _, group in ipairs(Model.controlGroups) do
	for _, control in ipairs(group.controls) do
		t.expect(app.refs["control_" .. control.id] ~= nil, control.id .. " renders from the model tables")
	end
end
t.expect(app.refs.part_kick == nil, "the style, not the listener, decides which parts play")
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
t.assertEqual(values[3], dnb(9).set:track(0).tonic / 12, "the palette follows the track key")
t.assertEqual(app.refs.position.text, "Bar 1 of 8", "and shows the bar in its section")

app.actions(app).control_cutoff(0.25)
t.assertEqual(app.model:value("cutoff"), 0.25, "a slider moves its model value")
t.assertEqual(app.refs.value_cutoff.text, "25%", "and its value label")
app:setControl("tempo", 165.4)
t.assertEqual(app.refs.value_tempo.text, "165 BPM", "tempo shows the snapped value")
app:actions().control_drums(0.5)
t.assertEqual(app.refs.value_drums.text, "50%", "a Mix fader shows its level")
t.assertEqual(app.model:value("cutoff"), 0.25, "moving a fader leaves other sliders alone")

local seed = app.model.seed
t.expect(app.refs.detail.text:find("Track 1 · ", 1, true) == 1, "the header names the track and its style")
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

-- The ride is a wash that dies away, not a sustained ringing tone.
local ride = Synth.new(Model.new(9), SR).drums.ride
local function rms(from, to)
	local sum = 0
	for i = from, to do sum = sum + ride[i] * ride[i] end
	return math.sqrt(sum / (to - from + 1))
end
local window = SR // 20
t.expect(rms(#ride - window, #ride) < rms(1, window) * 0.05, "the ride's tail decays below 5% of its attack")
