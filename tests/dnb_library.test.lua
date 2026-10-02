_G.__headless = true
-- The authored library and the engines that play it: the notation beats
-- and notes are written in, the shared and per-style library of patches and
-- fills, blocks (parsing, the catalogue, the candidates a flavour may play
-- and how every role renders into a bar), a sweep over every block the
-- generator ships, patches and their loudness, and drum loops and their
-- slices.
local t = require("TestKit")
local Library = require("apps.dnb.host.Library")
local Blocks = require("apps.dnb.host.Blocks")
local Patterns = require("apps.dnb.host.Patterns")
local Composer = require("apps.dnb.host.Composer")
local StyleKit = require("apps.dnb.host.StyleKit")
local Styles = require("apps.dnb.host.Styles")
local Drums = require("apps.dnb.models.Drums")
local Instrument = require("apps.dnb.models.Instrument")
local Calibration = require("apps.dnb.models.Calibration")
local Model = require("apps.dnb.Model")

local SR = 11025

-- Notation: beats.
local beat = Library.beat({id = "test.beat", bars = 2, lanes = {
	{"kick", "X.........x.....|X.....x...x....."},
	{"snare", "....X.......X..."},
	{"hat", "x.x.x.x.x.x.x.x.", gain = 0.5, when = "energy"},
	{"ghost", ".......g........", when = "complexity", light = false},
	{"snare", "........................ggooxxXX", div = 32, when = "complexity"},
}})
t.assertEqual(beat.slices, 32, "a two-bar beat is 32 slices")
local function count(voice, when)
	local n = 0
	for _, hit in ipairs(beat.hits) do
		if hit.voice == voice and hit.when == when then n = n + 1 end
	end
	return n
end
t.assertEqual(count("kick"), 5, "a lane as long as the beat is played once")
t.assertEqual(count("hat", "energy"), 16, "a shorter lane repeats to fill it")
for _, hit in ipairs(beat.hits) do
	if hit.voice == "kick" and hit.step == 0 then t.assertEqual(hit.gain, 1, "an accent plays at full level") end
	if hit.voice == "kick" and hit.step == 10 then t.assertEqual(hit.gain, 0.8, "a plain hit a little under it") end
	if hit.voice == "hat" then t.assertEqual(hit.gain, 0.4, "a lane's gain scales its hits") end
end
local fractional = false
for _, hit in ipairs(beat.hits) do
	if hit.step % 1 ~= 0 then fractional = true end
	t.expect(hit.step >= 0 and hit.step < 32, "hits stay inside the beat")
end
t.expect(fractional, "a lane in 32nds lands between the 16ths")
t.assertEqual(table.concat(beat.snareSlices, " "), "4 12 20 28", "full snares on the grid are known slices")
for i = 2, #beat.hits do t.expect(beat.hits[i].step >= beat.hits[i - 1].step, "hits are in step order") end
t.assertThrows(function() Library.beat({id = "x", lanes = {{"cowbells", "x..."}}}) end, "a beat plays kit voices only")
t.assertThrows(function() Library.beat({id = "x", lanes = {{"kick", "x.."}}}) end, "a lane is written in whole bars")
t.assertThrows(function() Library.beat({id = "x", lanes = {{"kick", "x..?x..........."}}}) end, "unknown steps are refused")
t.assertThrows(function() Library.beat({id = "x", kit = "break", lanes = {{"kick", "x..............."}}}) end,
	"a record's break needs its tempo")
local kicks, snares = Library.accents(beat, 0, 16, "full", true, true)
t.assertEqual(table.concat(kicks, " ") .. " / " .. table.concat(snares, " "), "0 10 / 4 12 14 14.5 15 15.5",
	"a bar's accents are its kicks and full snares")
t.assertEqual(#select(2, Library.accents(beat, 0, 16, "full", true, false)), 2, "of the layers that play")
t.assertEqual(#Library.accents(beat, 0, 16, "tops", true, true), 0, "the tops carry no kick")
t.expect(Drums.plays({voice = "hat", when = "energy"}, "full", true, false), "energy lets its layers in")
t.expect(not Drums.plays({voice = "hat", when = "energy"}, "full", false, true), "and keeps them out while it is down")
t.expect(not Drums.plays({voice = "hat", when = "energy"}, "light", true, true), "the light variant has no extra layers")
t.expect(not Drums.plays({voice = "ghost", light = false}, "light", true, true), "nor what a beat keeps out of it")
t.expect(Drums.plays({voice = "kick"}, "light", false, false), "but its kick")

-- Notation: lines and hooks.
local line = Library.notes("0:0:6 8:7:2~ 12:4:3! | 0:0:8 10:2b:2? 14:-1:1.5+w3")
t.assertEqual(line.bars, 2, "bars are split by a bar line")
t.assertEqual(#line.notes, 6, "every note is read")
t.assertEqual(line.notes[2].offset .. " " .. tostring(line.notes[2].glide), "7 true", "a tilde slides into its note")
t.expect(line.notes[3].accent, "an exclamation mark accents")
t.assertEqual(line.notes[5].step .. " " .. line.notes[5].bend, "26 -1", "a flat bends a semitone, in the second bar")
t.expect(line.notes[5].chance > 0.5 and line.notes[5].detail == 0, "a question mark waits for energy")
t.assertEqual(line.notes[6].offset .. " " .. line.notes[6].rate .. " " .. line.notes[6].length, "-1 3 1.5",
	"offsets may be negative, lengths fractional and a wobble has a rate")
t.expect(line.notes[6].detail > 0.5, "a plus waits for complexity")
t.assertThrows(function() Library.notes("0:0") end, "a note needs its step, pitch and length")
t.assertThrows(function() Library.notes("16:0:1") end, "a note starts inside its bar")
t.assertThrows(function() Library.notes("0:0:1%") end, "unknown flags are refused")

-- The shared library: patches and fills parse, and are looked up by id.
local shared = Library.shared()
t.assertEqual(table.concat(Library.kinds, " "), "patches fills", "the library holds patches and fills")
t.assertEqual(Library.shared(), shared, "the shared library is built once")
local counts = {}
for _, kind in ipairs(Library.kinds) do
	counts[kind] = 0
	for id, entry in pairs(shared[kind]) do
		counts[kind] = counts[kind] + 1
		t.assertEqual(entry.id, id, kind .. " are looked up by id")
	end
end
t.expect(counts.patches >= 60, "the library holds " .. counts.patches .. " patches")
t.expect(counts.fills >= 10, "and " .. counts.fills .. " fills")
t.assertThrows(function() shared:get("patches", "bass.kazoo") end, "an unknown patch is an error")
t.assertThrows(function() shared:get("fills", "fill.kazoo") end, "an unknown fill is an error")
t.assertThrows(function() shared:get("beats", "break.amen") end, "beats, hooks and lines are gone from the library")
local _, unknownMessage = pcall(function() shared:get("fills", "fill.kazoo") end)
t.expect(tostring(unknownMessage):find("fill.kazoo", 1, true), "the error names the id")

-- Fills: one bar each, played from a step to the bar's end.
for id, fill in pairs(shared.fills) do
	t.expect(id:match("^fill%.") ~= nil, id .. " is named fill.<name>")
	t.assertEqual(fill.bars, 1, id .. " is one bar")
	t.expect(fill.from ~= nil and fill.from >= 8 and fill.from <= 14, id .. " takes the bar from step " .. tostring(fill.from))
	t.expect(#fill.hits > 0, id .. " plays something")
	t.expect(fill.kit == nil, id .. " plays on the programmed kit")
	local late = 0
	for _, hit in ipairs(fill.hits) do
		t.expect(hit.step >= 0 and hit.step < 16, id .. " hits stay inside the bar")
		if hit.step >= fill.from then late = late + 1 end
		-- The groove runs up to `from`: what a fill writes before it is never heard.
		t.expect(hit.step >= fill.from, id .. " writes nothing before the step it takes over at: " .. hit.step)
	end
	t.expect(late > 0, id .. " sounds after its start")
end
t.assertEqual(shared:get("fills", "fill.roll").from, 12, "a fill keeps its `from`")
local roll32 = false
for _, hit in ipairs(shared:get("fills", "fill.roll").hits) do
	if hit.step % 1 ~= 0 then roll32 = true end
end
t.expect(roll32, "the roll lands between the 16ths")
t.assertThrows(function() Library.beat({id = "fill.x", lanes = {{"snare", "x..............."}}, kit = "gong"}) end,
	"a fill's kit is the programmed one or a break")

-- A style's library lies over the shared one.
local fakeStyle = {title = "Fake", library = {
	patches = {{id = "bass.fake", name = "Fake", role = "bass", osc = {{wave = "saw"}}}},
	fills = {{id = "fill.fake", from = 12, lanes = {{"snare", "............xxxx"}}}},
}}
local fakeLibrary = Library.of(fakeStyle)
t.assertEqual(fakeLibrary:get("fills", "fill.fake").from, 12, "a style brings its own fills")
t.expect(fakeLibrary.patches["bass.fake"] ~= nil and shared.patches["bass.fake"] == nil, "and patches, without touching the shared library")
t.expect(fakeLibrary.patches["bass.sub"] == shared.patches["bass.sub"], "and plays the shared ones as they are")
t.expect(fakeLibrary.fills["fill.roll"] == shared.fills["fill.roll"], "fills too")
t.assertThrows(function() Library.of({title = "Bad", library = {hooks = {}}}) end, "a style's library has patches and fills only")
t.assertThrows(function()
	Library.of({title = "Bad", library = {fills = {{id = "fill.x", lanes = {{"snare", "x..............."}}},
		{id = "fill.x", lanes = {{"snare", "x..............."}}}}}})
end, "a style defines each id once")
t.assertThrows(function()
	Library.of({title = "Bad", library = {fills = {{id = "fill.x", lanes = {{"cowbells", "x..............."}}}}}})
end, "a style's fill is checked like any beat")
local shadowed = Library.of({title = "Shadow", library = {fills = {{id = "fill.roll", from = 14, lanes = {{"snare", "..............xx"}}}}}})
t.assertEqual(shadowed:get("fills", "fill.roll").from, 14, "a style may replace a shared id")
t.assertEqual(shared:get("fills", "fill.roll").from, 12, "for itself only")

for _, style in ipairs(Styles:list()) do
	local library = Library.of(style)
	t.expect(library.patches["bass.sub"] ~= nil, style.title .. " plays the shared patches")
	t.expect(library.fills["fill.roll"] ~= nil, style.title .. " plays the shared fills")
	-- What a style's channels name must exist: its patches, and fills that are
	-- library beats or the groove edits.
	local edits = {}
	for _, kind in ipairs(Patterns.fills) do edits["@" .. kind] = true end
	local lists = {style.roles and style.roles.drums and style.roles.drums.fills or {}}
	for _, flavour in ipairs(style.flavours) do
		for _, channel in ipairs(flavour.channels) do
			for _, id in ipairs(channel.patches or {}) do
				t.expect(library.patches[id] ~= nil, style.title .. " " .. flavour.id .. " names patch " .. id)
			end
			if channel.fills then table.insert(lists, channel.fills) end
		end
	end
	for _, list in ipairs(lists) do
		for _, id in ipairs(list) do
			t.expect(edits[id] or library.fills[id] ~= nil, style.title .. " names fill " .. id)
		end
	end
end


-- Blocks: parsing -----------------------------------------------------------
local function spec(over)
	local base = {id = "test.bass.001", role = "bass", bars = 2, energy = 0.5, density = 0.4, notes = "0:0:4"}
	for k, v in pairs(over or {}) do base[k] = v or nil end
	return base
end
-- A spec the parser refuses, and an error that names the block.
local function refuses(bad, message)
	local ok, err = pcall(Blocks.parse, bad)
	t.expect(not ok, message)
	if not ok and type(bad) == "table" and type(bad.id) == "string" then
		t.expect(tostring(err):find(bad.id, 1, true) ~= nil, message .. " (the error names the block: " .. tostring(err) .. ")")
	end
end

-- The header fields every role shares.
local plain = Blocks.parse(spec())
t.assertEqual(plain.id .. " " .. plain.genre .. " " .. plain.role .. " " .. plain.number, "test.bass.001 test bass 1",
	"an id is genre, role and number")
t.assertEqual(plain.bars .. " " .. plain.energy .. " " .. plain.density .. " " .. plain.brightness, "2 0.5 0.4 0.5",
	"bars, energy and density are read and brightness is 0.5 by default")
t.assertEqual(plain.name, "test.bass.001", "a block with no name is called by its id")
t.assertEqual(next(plain.tags), nil, "no tags is an empty set")
t.assertEqual(plain.flavours, nil, "no flavours means every flavour")
t.assertEqual(next(plain.excludes), nil, "and excludes nothing")
t.assertEqual(Blocks.parse(spec({bars = false})).bars, 1, "a block loops over one bar unless it says more")
local tagged = Blocks.parse(spec({name = "Pump", brightness = 0.1, tags = {"offbeat", "dark-ish"}, flavours = {"uplifting", "tech"},
	excludes = {"rolling"}}))
t.assertEqual(tagged.name .. " " .. tagged.brightness, "Pump 0.1", "name and brightness are kept")
t.expect(tagged.tags.offbeat and tagged.tags["dark-ish"], "tags are a set")
t.assertEqual(table.concat(tagged.tagList, " "), "offbeat dark-ish", "and a list in the order written")
t.expect(tagged.flavours.uplifting and tagged.flavours.tech and not tagged.flavours.psy, "flavours are a set")
t.expect(tagged.excludes.rolling, "so are exclusions")
t.assertEqual(Blocks.parse(spec({bars = 8})).bars, 8, "eight bars is the longest block")

refuses(spec({id = "bass.001"}), "an id needs a genre")
refuses(spec({id = "Test.bass.001"}), "an id is lower case")
refuses(spec({id = "test.bass.x"}), "an id ends in a number")
refuses(spec({id = "test.bass.001.2"}), "an id has three parts")
refuses(spec({role = "lead"}), "the role must be the id's")
refuses(spec({role = false}), "a block has a role")
refuses(spec({id = "test.kazoo.001", role = "kazoo"}), "an unknown role is refused")
refuses(spec({energy = false}), "a block needs an energy")
refuses(spec({density = false}), "and a density")
refuses(spec({energy = 1.2}), "energy is at most 1")
refuses(spec({density = -0.1}), "density is at least 0")
refuses(spec({energy = "high"}), "energy is a number")
refuses(spec({brightness = 2}), "brightness is a number from 0 to 1")
refuses(spec({bars = 9}), "more than eight bars is refused")
refuses(spec({bars = 0}), "a block has a bar at least")
refuses(spec({bars = 1.5}), "bars are whole")
refuses(spec({tags = {"Dark"}}), "tags are lower case")
refuses(spec({tags = {"two words"}}), "tags are one word")
refuses(spec({flavours = {"Uplifting"}}), "flavours are ids")
refuses(spec({excludes = {5}}), "exclusions are tags")
refuses(spec({tags = "dark"}), "tags are a list")
t.assertThrows(function() Blocks.parse({}) end, "a block needs an id")
t.assertThrows(function() Blocks.parse("trance.bass.001") end, "a block is a table")

-- drums, tops: lanes become a beat of the block's bars.
local drums = Blocks.parse({id = "test.drums.001", role = "drums", bars = 2, energy = 0.5, density = 0.5, tags = {"fourfloor"},
	lanes = {{"kick", "X...X...X...X...|X...X...X..xX..."}, {"hat", "..x...x...x...x.", gain = 0.5, when = "energy"},
		{"snare", "....X.......X..."}}})
t.assertEqual(drums.beat.bars .. " " .. drums.beat.slices .. " " .. drums.beat.id, "2 32 test.drums.001", "drum lanes are a beat of the block's bars")
t.assertEqual(drums.beat.when, nil, "a drum beat is not conditional itself")
local snaresPlayed = 0
for _, hit in ipairs(drums.beat.hits) do if hit.voice == "snare" then snaresPlayed = snaresPlayed + 1 end end
t.assertEqual(snaresPlayed, 4, "a one-bar lane repeats across the block")
t.assertEqual(table.concat(drums.beat.snareSlices, " "), "4 12 20 28", "snare slices are known")
t.assertEqual(drums.line, nil, "and a drum block has no notes")
local tops = Blocks.parse({id = "test.tops.001", role = "tops", bars = 2, energy = 0.3, density = 0.4,
	lanes = {{"hat", "x.x.x.x.x.x.x.x."}}})
t.assertEqual(tops.beat.slices, 32, "tops are lanes too")
local record = Blocks.parse({id = "test.tops.002", role = "tops", bars = 2, energy = 0.3, density = 0.4, kit = "break", bpm = 120,
	lanes = {{"breakKick", "X.........x.....|X.....x........."}}})
t.assertEqual(record.beat.kit .. " " .. record.beat.bpm, "break 120", "a record's break keeps its kit and tempo")
refuses({id = "test.drums.002", role = "drums", bars = 1, energy = 0.5, density = 0.5}, "drums need lanes")
refuses({id = "test.drums.002", role = "drums", bars = 1, energy = 0.5, density = 0.5, lanes = {{"cowbells", "x..............."}}},
	"drum lanes play kit voices")
refuses({id = "test.drums.002", role = "drums", bars = 1, energy = 0.5, density = 0.5, lanes = {{"kick", "x.."}}},
	"a lane is written in whole bars")
refuses({id = "test.drums.002", role = "drums", bars = 1, energy = 0.5, density = 0.5, kit = "break",
	lanes = {{"kick", "x..............."}}}, "a break needs its tempo")
refuses({id = "test.drums.002", role = "drums", bars = 1, energy = 0.5, density = 0.5, lanes = {{"kick", "x..............?"}}},
	"drum steps are known")

-- bass, lead, counter: notes in scale steps, written in at most the block's bars.
local bassBlock = Blocks.parse(spec({notes = "0:0:2 4:7:2~ | 0:2:4!", octave = 1}))
t.assertEqual(bassBlock.line.bars .. " " .. #bassBlock.line.notes .. " " .. bassBlock.line.follow .. " " .. bassBlock.line.octave,
	"2 3 chord 1", "a line follows the chord by default and keeps its octave")
t.assertEqual(Blocks.parse(spec({follow = "key"})).line.follow, "key", "or the key")
t.assertEqual(Blocks.parse(spec({bars = 4})).line.bars, 4, "a line shorter than its block loops over the block's bars")
t.assertEqual(bassBlock.beat, nil, "and a line has no beat")
for _, role in ipairs({"lead", "counter"}) do
	local line = Blocks.parse({id = "test." .. role .. ".001", role = role, bars = 4, energy = 0.5, density = 0.5,
		notes = "0:4:4 4:2:4 | 0:0:8"})
	t.assertEqual(line.line.bars .. " " .. #line.line.notes, "4 3", "a " .. role .. " is a line")
end
refuses(spec({notes = false}), "a line needs notes")
refuses(spec({notes = "0:0:2 | 0:0:2 | 0:0:2"}), "a line written in three bars does not fit two")
refuses(spec({follow = "scale"}), "a line follows the chord or the key")
refuses(spec({notes = "0:0"}), "a note needs step, pitch and length")
refuses(spec({notes = "16:0:2"}), "a note starts inside its bar")
refuses(spec({notes = "0:0:2%"}), "unknown note flags are refused")

-- pad, keys, stab: a chord rhythm with bars split by "|", or a held chord.
local comped = Blocks.parse({id = "test.keys.001", role = "keys", bars = 2, energy = 0.5, density = 0.5,
	comp = "0:3 4:2! 10:4? | 0:16+"})
t.assertEqual(#comped.comp, 4, "every chord hit is read")
t.assertEqual(comped.comp[3].bar .. " " .. comped.comp[3].step .. " " .. comped.comp[3].length, "0 10 4", "with its bar, step and length")
t.expect(comped.comp[2].accent and not comped.comp[1].accent, "an exclamation mark accents")
t.expect(comped.comp[3].chance > 0.5 and comped.comp[3].detail == 0, "a question mark waits for energy")
t.expect(comped.comp[4].detail > 0.5 and comped.comp[4].chance == 0 and comped.comp[4].bar == 1, "a plus waits for complexity, in the second bar")
t.expect(comped.comp[1].chance == 0 and comped.comp[1].detail == 0, "a plain hit always plays")
t.expect(not comped.hold, "a comp is not a hold")
t.assertEqual(Blocks.parse({id = "test.stab.001", role = "stab", bars = 4, energy = 0.5, density = 0.5, comp = "0:2 8:2"}).comp[1].bar, 0,
	"a rhythm shorter than its block is allowed (it repeats)")
local held = Blocks.parse({id = "test.pad.001", role = "pad", bars = 4, energy = 0.3, density = 0.1, hold = true})
t.assertEqual(held.hold, true, "a pad may hold the chord")
t.assertEqual(held.comp, nil, "and has no rhythm then")
local hitless = Blocks.parse({id = "test.pad.002", role = "pad", bars = 4, energy = 0.3, density = 0.1, comp = "0:16"})
t.expect(hitless.hold == false and #hitless.comp == 1, "a pad that does not hold plays its comp")
local function chordSpec(over)
	local base = {id = "test.pad.003", role = "pad", bars = 2, energy = 0.3, density = 0.1, comp = "0:16"}
	for k, v in pairs(over) do base[k] = v or nil end
	return base
end
refuses(chordSpec({comp = "0:4 | 0:4 | 0:4"}), "a comp longer than its bars is refused")
refuses(chordSpec({comp = false}), "a pad is a comp or a hold")
refuses(chordSpec({hold = true}), "a hold has no comp")
refuses(chordSpec({comp = "0:4 4"}), "a hit needs its length")
refuses(chordSpec({comp = "16:4"}), "a hit starts inside its bar")
refuses(chordSpec({comp = "0:0"}), "a hit has a length")
refuses(chordSpec({comp = "0:4%"}), "unknown comp flags are refused")
refuses(chordSpec({comp = " | "}), "a comp has hits")

-- arp: order, rate, gate, mask.
local arp = Blocks.parse({id = "test.arp.001", role = "arp", bars = 1, energy = 0.5, density = 0.5, order = {1, 2, 3, 2}})
t.assertEqual(arp.arp.rate .. " " .. arp.arp.gate .. " " .. arp.arp.octave, "1 0.7 1", "an arpeggio steps by one with a 0.7 gate by default")
t.assertEqual(table.concat(arp.arp.order, " "), "1 2 3 2", "it keeps its order")
local all = true
for step = 0, 15 do all = all and arp.arp.mask[step] == "X" end
t.expect(all, "the default mask plays every step")
local short = Blocks.parse({id = "test.arp.002", role = "arp", bars = 1, energy = 0.5, density = 0.5, order = {1, 2}, rate = 2, gate = 0.5,
	octave = 2, mask = "Xx.x"})
t.assertEqual(short.arp.rate .. " " .. short.arp.gate .. " " .. short.arp.octave, "2 0.5 2", "rate, gate and octave are read")
local pattern = {}
for step = 0, 15 do table.insert(pattern, short.arp.mask[step]) end
t.assertEqual(table.concat(pattern), "Xx.xXx.xXx.xXx.x", "a short mask repeats across the 16 steps")
local spaced = Blocks.parse({id = "test.arp.003", role = "arp", bars = 1, energy = 0.5, density = 0.5, order = {1}, mask = "X.x. X.x.|X.x. X.x."})
t.assertEqual(spaced.arp.mask[2] .. spaced.arp.mask[3] .. spaced.arp.mask[15], "x.." , "spaces and bar lines in a mask are for the eye")
t.assertEqual(Blocks.parse({id = "test.arp.004", role = "arp", bars = 1, energy = 0.5, density = 0.5, order = {1}, mask = "x"}).arp.mask[7], "x",
	"a one-step mask fills the bar")
local function arpSpec(over)
	local base = {id = "test.arp.005", role = "arp", bars = 1, energy = 0.5, density = 0.5, order = {1, 2, 3}}
	for k, v in pairs(over) do base[k] = v or nil end
	return base
end
refuses(arpSpec({order = false}), "an arpeggio needs an order")
refuses(arpSpec({order = {}}), "and chord tones")
refuses(arpSpec({order = {0, 1}}), "chord tones count from 1")
refuses(arpSpec({order = {1.5}}), "chord tones are whole")
refuses(arpSpec({rate = 3}), "an arpeggio steps by 1, 2 or 4")
refuses(arpSpec({mask = "XXX"}), "a mask divides 16 steps")
refuses(arpSpec({mask = "X?.."}), "a mask has X, x and rests")
refuses(arpSpec({mask = ""}), "a mask has steps")

-- texture, fx.
local texture = Blocks.parse({id = "test.texture.001", role = "texture", bars = 8, energy = 0.2, density = 0.1})
t.assertEqual(table.concat(texture.voices, " ") .. " " .. texture.every, "0 7 4", "a texture holds the root and the fifth every four bars")
local custom = Blocks.parse({id = "test.texture.002", role = "texture", bars = 8, energy = 0.2, density = 0.1, voices = {0, 12, 19}, every = 8})
t.assertEqual(table.concat(custom.voices, " ") .. " " .. custom.every, "0 12 19 8", "or what it says")
refuses({id = "test.texture.003", role = "texture", bars = 8, energy = 0.2, density = 0.1, voices = {0, "fifth"}}, "texture voices are semitones")
for kind in pairs({riser = true, downlifter = true, impact = true, crash = true}) do
	t.assertEqual(Blocks.parse({id = "test.fx.001", role = "fx", bars = 4, energy = 0.5, density = 0.5, kind = kind}).kind, kind,
		"an fx may be a " .. kind)
end
t.expect(Blocks.fxKinds.riser and Blocks.fxKinds.downlifter and Blocks.fxKinds.impact and Blocks.fxKinds.crash and not Blocks.fxKinds.sweep,
	"the fx kinds are the four")
refuses({id = "test.fx.002", role = "fx", bars = 4, energy = 0.5, density = 0.5, kind = "sweep"}, "an unknown fx kind is refused")
refuses({id = "test.fx.002", role = "fx", bars = 4, energy = 0.5, density = 0.5}, "an fx needs its kind")

-- Blocks: the catalogue ------------------------------------------------------
local function lead(id, over)
	local base = {id = id, role = "lead", bars = 2, energy = 0.5, density = 0.5, notes = "0:0:4"}
	for k, v in pairs(over or {}) do base[k] = v end
	return base
end
local function bass(id, over)
	local base = {id = id, role = "bass", bars = 2, energy = 0.5, density = 0.5, notes = "0:0:4"}
	for k, v in pairs(over or {}) do base[k] = v end
	return base
end
local small = Blocks.catalogue({
	{bass("trance.bass.001", {tags = {"offbeat"}, flavours = {"uplifting"}}), bass("trance.bass.002", {flavours = {"psy", "goa"}}),
		bass("trance.bass.003", {tags = {"wobble", "dark"}}), lead("trance.lead.001", {tags = {"hook"}})},
	{bass("dnb.bass.001", {tags = {"reese"}}), bass("common.bass.001", {tags = {"sub"}}), lead("common.lead.001")},
})
t.assertEqual(#small.list, 7, "a catalogue lists every block of its lists")
t.assertEqual(small:get("trance.lead.001").role, "lead", "blocks are looked up by id")
t.assertEqual(small.byId["dnb.bass.001"], small:get("dnb.bass.001"), "in byId too")
t.assertThrows(function() small:get("trance.bass.999") end, "an unknown block is an error")
local _, missing = pcall(function() small:get("trance.bass.999") end)
t.expect(tostring(missing):find("trance.bass.999", 1, true), "naming it")
t.assertEqual(#small.byRole.bass, 5, "blocks are listed by role")
t.assertEqual(#small.byRole.lead, 2, "each in its own")
for _, role in ipairs(Model.roles) do t.expect(small.byRole[role.id] ~= nil, "every role has a list: " .. role.id) end
t.assertEqual(#small.byRole.fx, 0, "even when it is empty")
t.assertEqual(small.byRole.bass[1].id, "trance.bass.001", "blocks keep the order they are written in")
t.assertThrows(function() Blocks.catalogue({{bass("trance.bass.001"), bass("trance.bass.001")}}) end, "an id is defined once in a list")
t.assertThrows(function() Blocks.catalogue({{bass("trance.bass.001")}, {bass("trance.bass.001")}}) end, "and across lists")
t.assertThrows(function() Blocks.catalogue({{bass("trance.bass.001"), bass("trance.bass.002", {energy = 3})}}) end, "a bad block fails the catalogue")
t.assertEqual(#Blocks.catalogue({}).list, 0, "an empty catalogue is empty")

local function ids(list)
	local names = {}
	for _, block in ipairs(list) do table.insert(names, block.id) end
	return table.concat(names, " ")
end
t.assertEqual(ids(small:candidates("bass", "trance", "uplifting")), "trance.bass.001 trance.bass.003 common.bass.001",
	"a genre plays its own and the shared blocks, and a flavour list keeps out the others")
t.assertEqual(ids(small:candidates("bass", "trance", "psy")), "trance.bass.002 trance.bass.003 common.bass.001",
	"another flavour takes its own")
t.assertEqual(ids(small:candidates("bass", "trance", "dream")), "trance.bass.003 common.bass.001",
	"a flavour no block names takes the unrestricted ones")
t.assertEqual(ids(small:candidates("bass", "dnb", "neuro")), "dnb.bass.001 common.bass.001", "another genre has its own")
t.assertEqual(ids(small:candidates("bass", "house", "classic")), "common.bass.001", "a genre with none of its own plays the shared")
t.assertEqual(ids(small:candidates("lead", "trance", "psy")), "trance.lead.001 common.lead.001", "candidates are of one role")
t.assertEqual(ids(small:candidates("bass", "trance", "uplifting", {wobble = true})), "trance.bass.001 common.bass.001",
	"blocks with an avoided tag are left out")
t.assertEqual(ids(small:candidates("bass", "trance", "uplifting", {offbeat = true, sub = true})), "trance.bass.003",
	"any avoided tag excludes, in any block of any genre")
t.assertEqual(ids(small:candidates("bass", "trance", "uplifting", {offbeat = true, sub = true, dark = true})), "",
	"until nothing is left")
t.assertEqual(ids(small:candidates("bass", "trance", "uplifting", {kazoo = true})), "trance.bass.001 trance.bass.003 common.bass.001",
	"an avoided tag no block has changes nothing")
t.assertEqual(ids(small:candidates("bass", "trance", "uplifting", {})), ids(small:candidates("bass", "trance", "uplifting")),
	"as does an empty list")
t.assertEqual(#small:candidates("kazoo", "trance", "uplifting"), 0, "an unknown role has no candidates")
t.assertEqual(#small:candidates("fx", "trance", "uplifting"), 0, "nor does a role with no blocks")

-- Blocks: rendering ---------------------------------------------------------
-- A bar's context as the composer builds it (host/Composer.lua), reduced to
-- what a pattern reads, with the notes, hits and slices it adds recorded.
local MINOR = StyleKit.modes.minor
local CHORDS = {
	[1] = {degree = 1, notes = {48, 51, 55}, root = 36},
	[6] = {degree = 6, notes = {44, 48, 51}, root = 32},
	[4] = {degree = 4, notes = {41, 44, 48}, root = 41},
}
local function context(over)
	over = over or {}
	local ctx = {
		kit = StyleKit, mode = over.mode or MINOR, tonic = over.tonic or 0, chord = over.chord or CHORDS[1],
		pos = 0, chordBar = 0, barsPerChord = 2, barInBlock = 0, energy = 1, complexity = 1, throw = false,
		channel = {spec = over.spec or {}, patch = {id = "test"}}, block = {start = 0, length = 4}, blockLength = 4,
		bar = {}, notes = {}, hits = {}, slices = {},
	}
	for k, v in pairs(over) do ctx[k] = v end
	function ctx.note(fields) table.insert(ctx.notes, fields) return fields end
	function ctx.hit(step, voice, gain) table.insert(ctx.hits, {step = step, voice = voice, gain = gain}) end
	function ctx.slice(fields) table.insert(ctx.slices, fields) return fields end
	return ctx
end
-- Renders `bar` of the pattern of `block`, as the bar `bar` into a block that
-- starts at track bar `start` and lasts `length` bars of the track.
local function render(block, bar, over)
	over = over or {}
	local start, length = over.start or 0, over.length or block.bars
	local ctx = context(over)
	ctx.block = {start = start, length = length}
	ctx.blockLength = length
	ctx.barInBlock, ctx.pos = bar, start + bar
	ctx.chordBar = over.chordBar or ctx.pos % ctx.barsPerChord
	Patterns.of(block).render(ctx.bar, ctx)
	return ctx
end
local function played(ctx)
	local list = {}
	for _, note in ipairs(ctx.notes) do table.insert(list, note.step .. ":" .. table.concat(note.notes, ",")) end
	return table.concat(list, " ")
end
local function span(note) return string.format("%g %g", note.from, note.to) end
local function pitch(degree, offset, bend) return StyleKit.pitch(MINOR, 0, degree, offset, 28, bend) end

local pat = Patterns.of(Blocks.parse(spec()))
t.assertEqual(pat.id .. " " .. pat.part .. " " .. pat.bars, "test.bass.001 bass 2", "a block's pattern is its id, its role's part and its bars")
t.assertEqual(type(pat.render), "function", "with a renderer")
t.expect(Patterns.of(plain).block == plain, "and the block it plays")
t.assertThrows(function() Patterns.of({role = "kazoo", bars = 1}) end, "a block of no role has no pattern")

-- The composer holds a pattern for every block of its style, and the system ones.
do
	local style = Styles:get("trance")
	local composer = Composer.new(style, 3)
	local count = 0
	for id, pattern in pairs(composer.patterns) do
		t.assertEqual(pattern.id, id, id .. " is held under its id")
		count = count + 1
	end
	t.assertEqual(count, #composer.catalogue.list + #Patterns.system, "every block and every system pattern has one")
	for _, id in ipairs({"drums.fill", "drums.roll", "bass.blend", "pad.blend"}) do
		t.expect(composer.patterns[id] ~= nil, "the system pattern " .. id)
	end
	local block = composer.catalogue.byRole.bass[1]
	t.assertEqual(composer.patterns[block.id].block, block, "a block's pattern plays that block")
	-- The composer's pattern renders as a freshly made one does.
	local ctx = context()
	ctx.block, ctx.barInBlock = {start = 0, length = block.bars}, 0
	composer.patterns[block.id].render(ctx.bar, ctx)
	local again = render(block, 0)
	t.assertEqual(played(ctx), played(again), "a composer's pattern renders the block")
end

-- Bass: a note block in bar N plays the notes written in bar N of it.
local line = Blocks.parse(spec({notes = "2:0:1.6 6:0:1.6 | 4:4:2 12:2:3!"}))
t.assertEqual(played(render(line, 0)), "2:" .. pitch(1, 0) .. " 6:" .. pitch(1, 0), "bar 0 of a bass block plays its first bar")
t.assertEqual(played(render(line, 1)), "4:" .. pitch(1, 4) .. " 12:" .. pitch(1, 2), "bar 1 its second")
t.assertEqual(pitch(1, 4), 43, "a fifth over the root folded into the bass register: G2")
t.assertEqual(played(render(line, 2)), played(render(line, 0)), "the block loops")
t.assertEqual(played(render(line, 3, {start = 5})), played(render(line, 1)), "wherever it starts")
t.expect(render(line, 1).notes[2].accent, "an accent is passed on")
t.expect(not render(line, 1).notes[1].accent, "and only to its note")
t.assertEqual(render(line, 0).notes[1].length, 1.6, "a note keeps its length")
t.assertEqual(render(line, 0).notes[1].gap, 0.15, "and a bass note a gap")
t.assertEqual(played(render(line, 0, {chord = CHORDS[6]})), "2:" .. pitch(6, 0) .. " 6:" .. pitch(6, 0), "a line moves with the chord")
t.assertEqual(pitch(6, 0), 32, "(the sixth degree's root, G#1)")
local keyed = Blocks.parse(spec({notes = "0:0:2 4:2:2", follow = "key"}))
t.assertEqual(played(render(keyed, 0, {chord = CHORDS[6]})), played(render(keyed, 0, {chord = CHORDS[1]})), "a line that follows the key holds still")
local octave = Blocks.parse(spec({notes = "0:0:2", octave = 1}))
t.assertEqual(render(octave, 0).notes[1].notes[1], pitch(1, 0) + 12, "an octave shifts the line")
t.assertEqual(render(octave, 0, {spec = {octave = -1}}).notes[1].notes[1], pitch(1, 0), "and the channel's octave adds to it")
local bent = Blocks.parse(spec({notes = "0:1b:2 4:1:2"}))
t.assertEqual(render(bent, 0).notes[1].notes[1], pitch(1, 1, -1), "a flat bends a semitone")
t.assertEqual(render(bent, 0).notes[1].notes[1] + 1, render(bent, 0).notes[2].notes[1], "below the plain note")
local tied = Blocks.parse(spec({notes = "0:0:4 4:2:4~ 8:0:20"}))
t.expect(render(tied, 0).notes[2].glide, "a slide is passed on")
t.assertEqual(render(tied, 0).notes[3].length, 8.5, "a note that would run past the bar is cut a hair beyond it")
local wobble = Blocks.parse(spec({notes = "0:0:8w4"}))
t.assertEqual(render(wobble, 0, {energy = 0.5}).notes[1].rate, 4, "a wobble rate scales with Energy: 4 * (0.5 + 0.5)")
t.assertEqual(render(wobble, 0, {energy = 1}).notes[1].rate, 6, "and rises with it")
t.assertEqual(render(line, 0).notes[1].rate, nil, "a plain note has none")

-- Energy and Complexity gate the notes that ask for them.
local gated = Blocks.parse(spec({bars = 1, notes = "0:0:2 4:0:2? 8:0:2+ 12:0:2?+"}))
local function stepsOf(ctx)
	local list = {}
	for _, note in ipairs(ctx.notes) do table.insert(list, note.step) end
	return table.concat(list, " ")
end
t.assertEqual(stepsOf(render(gated, 0, {energy = 1, complexity = 1})), "0 4 8 12", "at full Energy and Complexity every note plays")
t.assertEqual(stepsOf(render(gated, 0, {energy = 0, complexity = 0})), "0", "at none only the plain note")
t.assertEqual(stepsOf(render(gated, 0, {energy = 1, complexity = 0})), "0 4", "Energy lets the question marks in")
t.assertEqual(stepsOf(render(gated, 0, {energy = 0, complexity = 1})), "0 8", "Complexity the plus signs")
t.assertEqual(stepsOf(render(gated, 0, {energy = 0.6, complexity = 0.5})), "0 4", "more than half Energy is enough for `?`, half Complexity too little for `+`")
t.assertEqual(stepsOf(render(gated, 0, {energy = 0.6, complexity = 0.6})), "0 4 8 12", "and a little more Complexity enough, for `?+` too")
t.assertEqual(stepsOf(render(gated, 0, {energy = 0.45, complexity = 0})), "0", "a `?` note waits below an Energy of 0.5 (0.55 > 0.45 * 0.9 + 0.1)")
t.assertEqual(stepsOf(render(gated, 0, {energy = 0.55, complexity = 0})), "0 4", "and plays above it")

-- Lead and counter: the register, the throw on a phrase's last note.
local hook = Blocks.parse(lead("test.lead.001", {bars = 2, notes = "0:4:4 4:2:4 | 0:0:8 8:7:20"}))
local melodyPitch = StyleKit.pitch(MINOR, 0, 1, 4, 64)
t.assertEqual(render(hook, 0).notes[1].notes[1], melodyPitch, "a lead plays from E4: its fifth over the folded root")
t.assertEqual(stepsOf(render(hook, 1)), "0 8", "bar by bar")
t.assertEqual(render(hook, 1).notes[2].length, 8, "a lead note is cut at the bar line exactly")
t.expect(render(hook, 0).notes[1].gain == 1 and render(hook, 0).notes[1].throw == nil, "a lead plays at full gain, with no throw")
t.expect(render(hook, 1, {throw = true}).notes[2].throw and not render(hook, 1, {throw = true}).notes[1].throw,
	"a throw takes the last note of the bar")
local counter = Blocks.parse({id = "test.counter.001", role = "counter", bars = 2, energy = 0.5, density = 0.5, notes = "0:0:4 | 4:2:4"})
t.assertEqual(render(counter, 0).notes[1].notes[1], StyleKit.pitch(MINOR, 0, 1, 0, 69), "a counter plays from A4")
t.assertEqual(render(counter, 0).notes[1].gain, 0.8, "a little under the lead")
t.assertEqual(render(hook, 0, {spec = {octave = -1}}).notes[1].notes[1], melodyPitch - 12, "a channel's octave moves the melody")
t.assertEqual(stepsOf(render(counter, 0)), "0", "a counter's bar 0")
t.assertEqual(stepsOf(render(counter, 1)), "4", "and bar 1")

-- Chords: a comp plays its bar's hits, with accents and gates.
local comp = Blocks.parse({id = "test.stab.001", role = "stab", bars = 2, energy = 0.5, density = 0.5,
	comp = "0:3 6:2! 10:4? | 4:2 12:2+"})
local c0, c1 = render(comp, 0), render(comp, 1)
t.assertEqual(stepsOf(c0), "0 6 10", "a comp plays the hits of its bar")
t.assertEqual(stepsOf(c1), "4 12", "and of the next")
t.assertEqual(table.concat(c0.notes[1].notes, " "), "48 51 55", "each hit sounds the whole chord")
t.assertEqual(c0.notes[1].gain .. " " .. c0.notes[2].gain, "0.75 1", "an accent is full, a plain hit a little under")
t.assertEqual(c0.notes[1].length, 3, "hits keep their lengths")
t.assertEqual(table.concat(render(comp, 0, {chord = CHORDS[4]}).notes[1].notes, " "), "41 44 48", "and sound the chord of the moment")
t.assertEqual(stepsOf(render(comp, 0, {energy = 0})), "0 6", "a `?` hit waits for Energy")
t.assertEqual(stepsOf(render(comp, 1, {complexity = 0})), "4", "a `+` hit waits for Complexity")
t.assertEqual(stepsOf(render(comp, 2)), stepsOf(c0), "a comp loops with its block")
t.expect(c0.notes[3].throw == nil and render(comp, 0, {throw = true}).notes[3].throw, "a throw takes the last hit of the bar")
t.assertEqual(stepsOf(render(Blocks.parse({id = "test.stab.002", role = "stab", bars = 4, energy = 0.5, density = 0.5, comp = "0:2 8:2"}), 3)),
	"0 8", "a comp shorter than its block repeats in every bar")
local keys = Blocks.parse({id = "test.keys.002", role = "keys", bars = 1, energy = 0.5, density = 0.5, comp = "0:16"})
t.assertEqual(stepsOf(render(keys, 0)), "0", "keys play a comp too")

-- A hold sustains the chord across barsPerChord, and a block that starts
-- inside a chord sounds what is left of it.
local pad = Blocks.parse({id = "test.pad.001", role = "pad", bars = 8, energy = 0.3, density = 0.1, hold = true})
local function lengths(block, over, from, to)
	local list = {}
	for bar = from, to do
		local ctx = render(block, bar, over)
		for _, note in ipairs(ctx.notes) do table.insert(list, bar .. "=" .. note.length) end
	end
	return table.concat(list, " ")
end
t.assertEqual(lengths(pad, {length = 8}, 0, 7), "0=32 2=32 4=32 6=32", "a pad strikes its chord every two bars and holds it for both")
t.assertEqual(lengths(pad, {length = 8, barsPerChord = 4}, 0, 7), "0=64 4=64", "or four, as the harmony has it")
t.assertEqual(lengths(pad, {length = 8, barsPerChord = 1}, 0, 3), "0=16 1=16 2=16 3=16", "or one")
t.assertEqual(table.concat(render(pad, 0).notes[1].notes, " "), "48 51 55", "the held notes are the chord")
t.assertEqual(render(pad, 0).notes[1].gap, 0, "with no gap between")
t.assertEqual(lengths(pad, {length = 8, start = 1}, 0, 3), "0=16 1=32 3=32", "a block that starts a bar into a chord sounds the one bar left")
t.assertEqual(lengths(pad, {length = 3}, 0, 2), "0=32 2=16", "and the last chord is cut where the block ends")
t.assertEqual(lengths(pad, {length = 1}, 0, 0), "0=16", "a one-bar pad holds one bar")
t.assertEqual(#render(pad, 1, {length = 8}).notes, 0, "a bar inside a held chord adds nothing")
t.assertEqual(render(pad, 0, {chord = CHORDS[4]}).notes[1].notes[1], 41, "the held chord is the chord of the bar")

-- An arpeggio stays inside the chord, at its rate and mask.
local function pitchClasses(chord)
	local set = {}
	for _, note in ipairs(chord.notes) do set[note % 12] = true end
	return set
end
local walk = Blocks.parse({id = "test.arp.010", role = "arp", bars = 1, energy = 0.5, density = 0.5, order = {1, 2, 3, 4, 3, 2}, rate = 1,
	gate = 0.5, octave = 1, mask = "XXxX"})
for _, degree in ipairs({1, 4, 6}) do
	local chord, classes = CHORDS[degree], pitchClasses(CHORDS[degree])
	for bar = 0, 5 do
		for _, note in ipairs(render(walk, 0, {start = bar, chord = chord}).notes) do
			t.expect(classes[note.notes[1] % 12], "an arpeggio note " .. note.notes[1] .. " is in the chord of degree " .. degree)
			t.expect(note.notes[1] >= chord.notes[1] and #note.notes == 1, "above the chord's lowest, a single note")
		end
	end
end
local two = render(walk, 0, {complexity = 0})
t.assertEqual(#two.notes, 12, "the mask's x steps rest while Complexity is low (12 of 16 steps)")
t.assertEqual(#render(walk, 0, {complexity = 1}).notes, 16, "and play when it is up")
t.assertEqual(#render(walk, 0, {complexity = 0.34}).notes, 12, "just under 0.35 is still low")
t.assertEqual(#render(walk, 0, {complexity = 0.35}).notes, 16, "and 0.35 is up")
t.assertEqual(two.notes[1].length, 0.5, "a note is the gate's share of the rate")
t.assertEqual(two.notes[1].gain .. " " .. two.notes[2].gain, "1 0.7", "beats are louder than the steps between")
t.assertEqual(two.notes[1].gap, 0, "with no gap")
t.assertEqual(two.notes[1].notes[1], 48 + 12, "the octave lifts the arpeggio")
local stride = Blocks.parse({id = "test.arp.011", role = "arp", bars = 1, energy = 0.5, density = 0.5, order = {1, 2, 3}, rate = 4, mask = "X"})
t.assertEqual(stepsOf(render(stride, 0)), "0 4 8 12", "a rate of 4 plays four notes a bar")
t.assertEqual(render(stride, 0).notes[1].length, 2.8, "each 4 steps long times the gate")
local twos = Blocks.parse({id = "test.arp.012", role = "arp", bars = 1, energy = 0.5, density = 0.5, order = {1, 2, 3}, rate = 2, mask = "X."})
t.assertEqual(stepsOf(render(twos, 0)), "0 2 4 6 8 10 12 14", "a rate of 2 plays eight")
local resting = Blocks.parse({id = "test.arp.013", role = "arp", bars = 1, energy = 0.5, density = 0.5, order = {1, 2, 3}, rate = 1, mask = "X..."})
t.assertEqual(stepsOf(render(resting, 0)), "0 4 8 12", "a short mask repeats: one note in four")
local both = Blocks.parse({id = "test.arp.014", role = "arp", bars = 1, energy = 0.5, density = 0.5, order = {1, 2, 3}, rate = 1, mask = "Xx.."})
t.assertEqual(stepsOf(render(both, 0, {complexity = 0})), "0 4 8 12", "a short mask's x steps wait for Complexity")
t.assertEqual(stepsOf(render(both, 0, {complexity = 1})), "0 1 4 5 8 9 12 13", "and play when it is up")
-- The order goes on from bar to bar: the arpeggio keeps climbing.
local first, second = render(stride, 0), render(stride, 1)
t.expect(first.notes[1].notes[1] ~= second.notes[1].notes[1] or #first.notes == 0, "the order carries on into the next bar")
local up = Blocks.parse({id = "test.arp.015", role = "arp", bars = 1, energy = 0.5, density = 0.5, order = {1, 2, 3}, rate = 4, octave = 0, mask = "X"})
t.assertEqual(table.concat({render(up, 0).notes[1].notes[1], render(up, 0).notes[2].notes[1], render(up, 0).notes[3].notes[1]}, " "), "48 51 55",
	"an order of 1, 2, 3 plays the chord from the bottom")
local climb = Blocks.parse({id = "test.arp.016", role = "arp", bars = 1, energy = 0.5, density = 0.5, order = {1, 4, 7}, rate = 4, octave = 0, mask = "X"})
t.assertEqual(table.concat({render(climb, 0).notes[1].notes[1], render(climb, 0).notes[2].notes[1], render(climb, 0).notes[3].notes[1]}, " "), "48 60 72",
	"tones above the chord's last climb an octave: 4 is the root, 7 the root two octaves up")

-- Texture: a drone of the key's root, held every N bars.
local drone = Blocks.parse({id = "test.texture.010", role = "texture", bars = 8, energy = 0.2, density = 0.1, voices = {0, 7, 12}, every = 4})
t.assertEqual(lengths(drone, {length = 8}, 0, 7), "0=64 4=64", "a texture is held for `every` bars")
t.assertEqual(table.concat(render(drone, 0).notes[1].notes, " "), "48 55 60", "on the key's root and what it stacks on it")
t.assertEqual(table.concat(render(drone, 0, {tonic = 9}).notes[1].notes, " "), "57 64 69", "in the track's key (A, folded above C3)")
t.assertEqual(lengths(drone, {length = 8, start = 2}, 0, 5), "0=32 2=64", "a texture starting off the grid sounds what is left of its span")
t.assertEqual(lengths(drone, {length = 3}, 0, 2), "0=48", "and ends where its block does")
t.assertEqual(lengths(drone, {length = 8}, 1, 3), "", "nothing is added inside the held span")

-- Fx: a riser scales over the block's length.
local function fx(kind, bars) return Blocks.parse({id = "test.fx.010", role = "fx", bars = bars or 4, energy = 0.5, density = 0.5, kind = kind}) end
local riser = fx("riser")
for bar = 0, 3 do
	local ctx = render(riser, bar, {length = 4})
	local note = ctx.notes[1]
	t.assertEqual(span(note), string.format("%g %g", bar / 4, (bar + 1) / 4), "bar " .. bar .. " of a four-bar riser rises a quarter")
	t.assertEqual(span(ctx.bar.riser), span(note), "the bar knows its riser, for the visuals")
	t.assertEqual(note.length, 16, "over a whole bar")
end
local eight = render(riser, 3, {length = 8})
t.assertEqual(span(eight.notes[1]), "0.375 0.5", "the same block placed over eight bars rises more slowly")
t.assertEqual(render(riser, 7, {length = 8}).notes[1].to, 1, "and ends at the top")
t.assertEqual(span(render(riser, 0, {length = 1}).notes[1]), "0 1", "a one-bar riser takes the whole sweep")
local down = fx("downlifter")
t.assertEqual(span(render(down, 0, {length = 4}).notes[1]), "1 0.75",
	"a downlifter falls: the first bar from the top")
t.assertEqual(render(down, 3, {length = 4}).notes[1].to, 0, "to the bottom")
local previous = 2
for bar = 0, 3 do
	local note = render(down, bar, {length = 4}).notes[1]
	t.expect(note.from <= previous and note.to < note.from, "each bar of a downlifter falls on from the last")
	previous = note.to
end
local impact = fx("impact", 1)
local landing = render(impact, 0)
t.assertEqual(#landing.hits, 1, "an impact lands a crash")
t.assertEqual(landing.hits[1].step .. " " .. landing.hits[1].voice, "0 crash", "on the first step")
t.assertEqual(span(landing.notes[1]), "1 0", "with a tail of its channel's patch sweeping down")
local noPatch = context({})
noPatch.channel = {spec = {}}
noPatch.block, noPatch.barInBlock = {start = 0, length = 1}, 0
Patterns.of(impact).render(noPatch.bar, noPatch)
t.assertEqual(#noPatch.hits + #noPatch.notes, 1, "a channel with no patch plays the crash alone")
local crash = render(fx("crash", 1), 0)
t.assertEqual(#crash.hits .. " " .. #crash.notes, "1 0", "a crash is the crash alone")
t.assertEqual(#render(impact, 1, {length = 4}).notes, 0, "the impact's tail comes on its first bar only")
t.assertEqual(#render(impact, 1, {length = 4}).hits, 1, "though the crash plays in every bar it is given")

-- Drums and tops: every bar plays the beat's slices for the bar of the loop.
local groove = Blocks.parse({id = "test.drums.010", role = "drums", bars = 2, energy = 0.5, density = 0.5,
	lanes = {{"kick", "X...X...X...X...|X...X...X...X.x."}}})
local d0, d1 = render(groove, 0), render(groove, 1)
t.assertEqual(#d0.slices, 16, "a bar of a drum block plays 16 slices")
t.assertEqual(d0.slices[1].slice .. " " .. d0.slices[16].slice, "0 15", "of the loop's first bar")
t.assertEqual(d1.slices[1].slice .. " " .. d1.slices[16].slice, "16 31", "and of its second")
t.assertEqual(render(groove, 2).slices[1].slice, 0, "the loop wraps")
t.assertEqual(d0.slices[5].step, 4, "each at its step")
t.assertEqual(d0.slices[1].beat, groove.beat, "playing the block's beat")
t.assertEqual(d0.slices[1].variant, "full", "in the full variant")
local lightBlock = {start = 0, length = 2, variant = "light"}
local lightCtx = context()
lightCtx.block, lightCtx.blockLength = lightBlock, 2
Patterns.of(groove).render(lightCtx.bar, lightCtx)
t.assertEqual(lightCtx.slices[1].variant, "light", "or the light one a track's first and last bars ask for")
t.assertEqual(render(groove, 0, {spec = {gain = 0.5}}).slices[1].gain, 0.5, "at its channel's gain")
t.expect(render(groove, 0, {throw = true}).slices[13].throw and not render(groove, 0, {throw = true}).slices[12].throw,
	"a throw goes to the dub echo from the bar's last beat")
local shifted = render(groove, 0, {start = 4})
t.assertEqual(shifted.slices[1].slice, 0, "a drum block starting at track bar 4 starts its loop at 0")
t.assertEqual(#render(tops, 0).slices, 16, "tops render the same way")
-- Chops edit the groove's slices as Complexity rises.
local chopped = context({spec = {chops = true}, complexity = 1})
chopped.material = {chops = {{kind = "stutter", bar = 0, threshold = 0, source = 0, step = 12, length = 2}}}
chopped.phraseBar = 0
chopped.block = {start = 0, length = 2}
Patterns.of(Blocks.parse({id = "test.drums.011", role = "drums", bars = 1, energy = 0.5, density = 0.5,
	lanes = {{"kick", "X...X...X...X..."}, {"snare", "....X.......X..."}}})).render(chopped.bar, chopped)
local stuttered = {}
for _, s in ipairs(chopped.slices) do stuttered[s.step] = s.slice end
t.assertEqual(stuttered[12] .. " " .. stuttered[13], "4 4", "a stutter chop repeats a snare slice (the loop's first, at 4) in steps 12 and 13")
chopped.slices, chopped.complexity = {}, 0
Patterns.of(Blocks.parse({id = "test.drums.011", role = "drums", bars = 1, energy = 0.5, density = 0.5,
	lanes = {{"kick", "X...X...X...X..."}, {"snare", "....X.......X..."}}})).render(chopped.bar, chopped)
t.assertEqual(chopped.slices[13].slice, 12, "and at no Complexity the groove plays as it is written")

-- The blocks of the generator ------------------------------------------------
local GENRES = {"dnb", "techno", "house", "trance", "dubstep", "breakbeat", "garage"}
local common = require("apps.dnb.library.blocks.common")
local lists, listNames = {common}, {"common"}
for _, genre in ipairs(GENRES) do
	table.insert(lists, require("apps.dnb.plugins.styles." .. genre .. ".blocks"))
	table.insert(listNames, genre)
end
local catalogue = Blocks.catalogue(lists)
t.expect(#catalogue.list > 400, "the library holds " .. #catalogue.list .. " blocks")
local amenBeat = catalogue:get("common.tops.001").beat
t.assertEqual(amenBeat.kit .. " " .. amenBeat.bpm .. " " .. amenBeat.bars, "break 137 4", "the Amen is a four-bar break at the record's tempo")
t.expect(#amenBeat.snareSlices >= 6, "its snares are known slices")
local seenIds = {}
for _, block in ipairs(catalogue.list) do
	t.expect(not seenIds[block.id], block.id .. " is unique")
	seenIds[block.id] = true
end

-- Every block of the library renders something, across the bars of its loop,
-- at the extremes of Energy and Complexity.
local function renderedAll(block, over)
	over = over or {}
	local notes, hits, slices = {}, {}, {}
	for bar = 0, block.bars * 2 - 1 do
		local o = {energy = over.energy, complexity = over.complexity, mode = over.mode, tonic = over.tonic, chord = over.chord,
			spec = over.spec, length = block.bars * 2, start = over.start or 0}
		local ctx = render(block, bar, o)
		for _, n in ipairs(ctx.notes) do table.insert(notes, {bar = bar, note = n}) end
		for _, h in ipairs(ctx.hits) do table.insert(hits, h) end
		for _, s in ipairs(ctx.slices) do table.insert(slices, s) end
	end
	return notes, hits, slices
end
local silent = {}
for _, block in ipairs(catalogue.list) do
	for _, level in ipairs({0, 1}) do
		local notes, hits, slices = renderedAll(block, {energy = level, complexity = level})
		if #notes + #hits + #slices == 0 then table.insert(silent, block.id .. " at " .. level) end
	end
	if block.beat then
		local always = 0
		for _, hit in ipairs(block.beat.hits) do if hit.when == nil then always = always + 1 end end
		t.expect(always > 0, block.id .. " plays without Energy or Complexity")
	end
end
t.assertEqual(#silent, 0, "no block is silent: " .. table.concat(silent, ", "))

-- Notes lie inside their bars, and a lead is one voice.
for _, block in ipairs(catalogue.list) do
	if block.line then
		local last = block.line.notes[#block.line.notes]
		t.expect(last.step < block.bars * 16, block.id .. " is written inside its bars")
		for i, note in ipairs(block.line.notes) do
			t.expect(note.step % 16 + note.length <= 16.6, block.id .. " note " .. i .. " ends inside its bar (" .. note.step % 16 .. "+" .. note.length .. ")")
			t.expect(note.offset >= -7 and note.offset <= 14, block.id .. " note " .. i .. " stays near its root (" .. note.offset .. ")")
			if block.role == "lead" or block.role == "counter" then
				local before = block.line.notes[i - 1]
				t.expect(not before or note.step >= before.step + before.length - 1e-9, block.id .. " is one voice, note " .. i)
			end
		end
	end
	if block.comp then
		-- A comp shorter than its block repeats (see the render test above),
		-- so it must fit the block a whole number of times.
		t.expect(block.bars % block.compBars == 0, block.id .. " repeats its " .. block.compBars .. "-bar comp evenly in " .. block.bars .. " bars")
		for i, hit in ipairs(block.comp) do
			t.expect(hit.bar < block.bars, block.id .. " hit " .. i .. " is in a bar of the block")
			t.expect(hit.step + hit.length <= 16.6 or hit.length >= 16, block.id .. " hit " .. i .. " ends inside its bar")
		end
	end
end

-- A bass stays in the bass register in every mode, over every chord and key.
-- The root folds into E1 to D#2 (MIDI 28 to 39); a line may step a few
-- semitones under it, down to C1, and an authored octave and an octave leap
-- lift it at most two octaves over the highest root.
local LOWEST, HIGHEST = 24, StyleKit.register.bass + 11 + 12 + 12 + 2
local lowBass, lowBlock
for _, block in ipairs(catalogue.byRole.bass) do
	for modeName, mode in pairs(StyleKit.modes) do
		for _, tonic in ipairs({0, 11}) do
			for degree = 1, 7 do
				local chord = {degree = degree, notes = {48, 52, 55}, root = 36}
				local notes = renderedAll(block, {mode = mode, tonic = tonic, chord = chord})
				for _, each in ipairs(notes) do
					local p = each.note.notes[1]
					if not lowBass or p < lowBass then lowBass, lowBlock = p, block.id .. " in " .. modeName end
					if p < LOWEST or p > HIGHEST then
						t.expect(false, string.format("%s plays %d in %s over degree %d: outside the bass register", block.id, p, modeName, degree))
						goto nextBlock
					end
				end
			end
		end
	end
	::nextBlock::
end
t.expect(lowBass >= LOWEST, "the lowest bass note anywhere is " .. tostring(lowBass) .. " (" .. tostring(lowBlock) .. ")")

-- The flavours a block names exist in its style; shared blocks name none.
local flavourIds = {}
for _, style in ipairs(Styles:list()) do
	flavourIds[style.id] = {}
	for _, flavour in ipairs(style.flavours) do flavourIds[style.id][flavour.id] = true end
end
for _, block in ipairs(catalogue.list) do
	if block.genre == "common" then
		t.expect(block.flavours == nil, block.id .. " is shared, so it names no flavour")
	else
		t.expect(flavourIds[block.genre] ~= nil, block.id .. " belongs to a style that exists")
		for flavour in pairs(block.flavours or {}) do
			t.expect(flavourIds[block.genre] and flavourIds[block.genre][flavour],
				block.id .. " names flavour " .. flavour .. " that " .. block.genre .. " does not have")
		end
		for _, tag in ipairs(block.tagList) do t.expect(tag ~= "", block.id .. " has a tag") end
	end
end

-- No two blocks of one genre and role are the same loop.
local function fingerprint(block)
	local parts = {block.bars}
	local function add(...) for i = 1, select("#", ...) do table.insert(parts, tostring((select(i, ...)))) end end
	if block.beat then
		add(block.beat.kit, block.beat.bpm)
		for _, hit in ipairs(block.beat.hits) do add(hit.step, hit.voice, string.format("%.3f", hit.gain), hit.when, hit.light) end
	elseif block.line then
		add(block.line.follow, block.line.octave)
		for _, n in ipairs(block.line.notes) do add(n.step, n.offset, n.bend, n.length, n.glide, n.accent, n.chance, n.detail, n.rate) end
	elseif block.comp or block.hold then
		add(block.hold)
		for _, h in ipairs(block.comp or {}) do add(h.bar, h.step, h.length, h.accent, h.chance, h.detail) end
	elseif block.arp then
		add(table.concat(block.arp.order, ","), block.arp.rate, block.arp.gate, block.arp.octave)
		for step = 0, 15 do add(block.arp.mask[step]) end
	elseif block.voices then
		add(table.concat(block.voices, ","), block.every)
	else
		add(block.kind)
	end
	-- A block whose content is one flag or one kind differs from its sisters
	-- by its numbers alone.
	if block.hold or block.kind then add(block.energy, block.density, block.brightness) end
	return table.concat(parts, "|")
end
local seen = {}
for _, block in ipairs(catalogue.list) do
	local key = block.genre .. "." .. block.role .. ":" .. fingerprint(block)
	t.expect(not seen[key], block.id .. " has the same content as " .. tostring(seen[key]))
	seen[key] = seen[key] or block.id
end

-- Patches: checked, and levelled to their role.
t.assertThrows(function() Instrument.patch({id = "x", osc = {{wave = "kazoo"}}}) end, "unknown waves are refused")
t.assertThrows(function() Instrument.patch({id = "x", osc = {{wave = "saw"}}, wub = 1}) end, "unknown fields are refused")
t.assertThrows(function() Instrument.patch({id = "x", osc = {{wave = "saw", fm = {ratio = 2}}}}) end, "only a sine takes FM")
t.assertThrows(function() Instrument.patch({id = "x", osc = {{wave = "saw"}}, filter = {kind = "comb"}}) end,
	"unknown filters are refused")
t.assertThrows(function() Instrument.patch({id = "x"}) end, "a patch needs an oscillator")
local plain = Instrument.patch({id = "x", osc = {{wave = "saw", octave = 1, detune = 0.01}}})
t.expect(math.abs(plain.osc[1].ratio - 2.02) < 1e-9, "an oscillator's ratio is its octave and detune")
t.assertEqual(plain.amp.sustain .. " " .. tostring(plain.mono) .. " " .. plain.level, "1 false 1", "what a patch leaves out is filled in")
local byRole = {}
for id, patch in pairs(shared.patches) do
	t.expect(Model.family[patch.role] ~= nil, id .. " names a real role")
	t.expect(patch.name ~= id and #patch.name <= 14, id .. " has a name that fits a channel: " .. patch.name)
	byRole[patch.role] = (byRole[patch.role] or 0) + 1
	local offset = Calibration.offset(patch)
	t.expect(math.abs(offset) <= Calibration.tolerance, string.format("%s sits %+.1f dB from its role's level", id, offset))
end
for _, role in ipairs({"bass", "pad", "keys", "stab", "arp", "lead"}) do
	t.expect(byRole[role] >= 7, "there are " .. tostring(byRole[role]) .. " patches for the " .. role)
end

-- The instrument: voices sound, end, and differ by patch.
local function play(patch, notes, seconds, options)
	options = options or {}
	local frames = math.floor(seconds * SR)
	local out = {left = {}, right = {}, throwL = {}, throwR = {}}
	for k = 1, frames do out.left[k], out.right[k], out.throwL[k], out.throwR[k] = 0, 0, 0, 0 end
	local voice = Instrument.voice(patch, notes, {sr = SR, hold = math.floor((options.hold or 0.2) * SR), gain = 1, seed = 3,
		throw = options.throw, accent = options.accent})
	local ctx = {tempo = 120, scratchL = {}, scratchR = {}, shift = options.shift or 0, wobble = 1, drive = 1}
	local done
	local size = options.block or frames
	for first = 1, frames, size do
		done = Instrument.render(voice, first, math.min(frames, first + size - 1), out, ctx)
	end
	return out, done, voice
end
local function level(data, from, to)
	local sum = 0
	for k = from, to do sum = sum + data[k] * data[k] end
	return math.sqrt(sum / (to - from + 1))
end
-- Brightness: how much of a signal changes from one frame to the next.
local function rough(data, from, to)
	local sum = 0
	for k = from + 1, to do sum = sum + (data[k] - data[k - 1]) ^ 2 end
	return math.sqrt(sum / (to - from)) / math.max(level(data, from, to), 1e-12)
end
for id, patch in pairs(shared.patches) do
	local out, _, voice = play(patch, patch.role == "bass" and {36} or {60, 64, 67}, 0.4)
	local peak = 0
	for k = 1, #out.left do
		local a = math.abs(out.left[k])
		if a ~= a then peak = math.huge break end
		peak = math.max(peak, a)
	end
	t.expect(peak > 1e-4 and peak < 4, id .. " sounds, and stays bounded")
	t.expect(voice.tick == #out.left, id .. " renders every frame")
end
local pluck = shared:get("patches", "pluck.saw")
local out, done = play(pluck, {72}, 2, {hold = 0.1})
t.expect(done, "a plucked voice ends")
t.expect(level(out.left, 1, SR // 10) > 20 * level(out.left, SR, 2 * SR), "having died away")
local _, held = play(shared:get("patches", "pad.saw"), {60}, 0.5, {hold = 1})
t.expect(not held, "a held voice plays on")
local whole = play(shared:get("patches", "bass.reese"), {36}, 0.5, {hold = 0.3})
local chunks = play(shared:get("patches", "bass.reese"), {36}, 0.5, {hold = 0.3, block = 97})
local same = true
for k = 1, #whole.left do if whole.left[k] ~= chunks.left[k] then same = false break end end
t.expect(same, "a voice renders the same in blocks of any size")
local dark = play(shared:get("patches", "bass.reese"), {36}, 0.4, {hold = 0.4, shift = -2})
local bright = play(shared:get("patches", "bass.reese"), {36}, 0.4, {hold = 0.4, shift = 2})
t.expect(rough(bright.left, 1000, 4000) > 1.5 * rough(dark.left, 1000, 4000), "the Filter slider opens the bass")
local soft = play(shared:get("patches", "bass.acid"), {48}, 0.2, {hold = 0.2})
local accented = play(shared:get("patches", "bass.acid"), {48}, 0.2, {hold = 0.2, accent = true})
t.expect(level(accented.left, 1, 2000) > level(soft.left, 1, 2000), "an accent plays harder")
local thrown = play(pluck, {72}, 0.2, {throw = 1})
t.expect(level(thrown.throwL, 1, 1000) > 0 and level(out.throwL, 1, 1000) == 0, "a thrown voice feeds the delay")
local wide = play(shared:get("patches", "pad.supersaw"), {60, 64}, 0.6, {hold = 0.6})
local differs = false
for k = 3000, 6000 do if math.abs(wide.left[k] - wide.right[k]) > 1e-6 then differs = true break end end
t.expect(differs, "a wide patch differs from side to side")
local narrow = play(shared:get("patches", "bass.sub"), {36}, 0.2)
t.assertEqual(narrow.left[500], narrow.right[500], "a bass sits in the middle")
-- Timbre is what tells two tracks apart: patches of one role are not
-- copies of each other.
for _, role in ipairs({"bass", "pad", "lead", "arp"}) do
	local seen, distinct = {}, 0
	for id, patch in pairs(shared.patches) do
		if patch.role == role then
			local sound = play(patch, role == "bass" and {36} or {60}, 0.4, {hold = 0.4})
			local key = string.format("%.2f", math.log(rough(sound.left, 500, 4000) + 1e-9))
			if not seen[key] then seen[key], distinct = true, distinct + 1 end
		end
	end
	t.expect(distinct >= byRole[role] * 0.6, role .. " patches differ in brightness: " .. distinct .. " of " .. byRole[role])
end
-- A mono voice glides to a tied note and starts again on a struck one.
local lead = shared:get("patches", "lead.sine")
local mono = Instrument.voice(lead, {60}, {sr = SR, hold = 2000, gain = 1})
local sink = {left = {}, right = {}, throwL = {}, throwR = {}}
for k = 1, 6000 do sink.left[k], sink.right[k], sink.throwL[k], sink.throwR[k] = 0, 0, 0, 0 end
local ctx = {tempo = 120, scratchL = {}, scratchR = {}}
Instrument.render(mono, 1, 1000, sink, ctx)
Instrument.retarget(mono, 67, {hold = 2000, gain = 1, glide = true})
t.expect(mono.freq < mono.target, "a tied note starts from the pitch before it")
Instrument.render(mono, 1001, 1200, sink, ctx)
t.expect(mono.freq > Instrument.midiHz(60) and mono.freq < mono.target, "and slides towards its own")
Instrument.retarget(mono, 72, {hold = 2000, gain = 1})
t.assertEqual(mono.freq, mono.target, "a struck note starts on its pitch")
t.expect(Instrument.sounding(mono), "and the voice plays on")

-- Drums: kits, and loops rendered from beats.
local kit = Drums.design()
local shots = Drums.shots(SR, kit)
t.expect(#shots.kick > 0 and #shots.crash > 0 and #shots.cowbell > 0, "a kit has its own voices and the shared ones")
t.expect(Drums.shots(SR, kit) == shots, "kits are cached by design")
t.assertThrows(function() Drums.design({kick = {wub = 1}}) end, "unknown kit fields are refused")
t.assertThrows(function() Drums.design({gong = {}}) end, "unknown kit groups are refused")
for voice in pairs(Drums.place) do t.expect(shots[voice] ~= nil and #shots[voice] > 0, voice .. " is rendered") end
local tail = SR // 20
local ride = shots.ride
t.expect(level(ride, #ride - tail, #ride) < level(ride, 1, tail) * 0.05, "the ride's tail decays below 5% of its attack")
local options = {tempo = 170, swing = 0, humanize = 0, variant = "full", energy = true, complexity = true}
local loop = Drums.loop(SR, shots, beat, options)
t.assertEqual(loop.slices, 32, "a loop has its beat's slices")
t.assertEqual(loop.frames, math.floor(32 * SR * 60 / 170 / 4 + 0.5), "rendered at the track's tempo")
t.expect(math.abs(loop.step - SR * 60 / 170 / 4) < 1e-9, "a slice is a 16th")
t.expect(Drums.loop(SR, shots, beat, options) == loop, "loops are cached")
local function slice(data, index) return level(data, math.floor(index * loop.step) + 1, math.floor((index + 1) * loop.step)) end
t.expect(slice(loop.left, 0) > 4 * slice(loop.left, 5), "the kick's slice is louder than the one after the snare's tail")
t.expect(slice(loop.left, 4) > 0.05, "the snare sounds on the backbeat")
t.expect(loop.left ~= loop.right, "a programmed loop is stereo")
local light = Drums.loop(SR, shots, beat, {tempo = 170, variant = "light"})
t.expect(level(light.left, 1, light.frames) < level(loop.left, 1, loop.frames), "the light variant plays less")
local tops = Drums.loop(SR, shots, beat, {tempo = 170, variant = "tops", energy = true})
t.expect(slice(tops.left, 0) < slice(loop.left, 0) * 0.5, "the tops leave the kick out")
local quiet = Drums.loop(SR, shots, beat, {tempo = 170, variant = "full"})
t.expect(quiet ~= loop and level(quiet.left, 1, quiet.frames) < level(loop.left, 1, loop.frames), "energy adds its layers")
local swung = Drums.loop(SR, shots, beat, {tempo = 170, swing = 0.3, variant = "full", energy = true})
local moved = false
for k = 1, loop.frames do if swung.left[k] ~= loop.left[k] then moved = true break end end
t.expect(moved, "swing is part of the loop")
local amen = Drums.loop(SR, shots, amenBeat, {tempo = 170})
t.assertEqual(amen.frames, math.floor(64 * SR * 60 / 137 / 4 + 0.5), "a record's break is rendered at the record's tempo")
t.assertEqual(amen.tempo, 137, "and says so, to be sped up")
t.expect(amen.left == amen.right, "in mono")
local peak = 0
for k = 1, amen.frames do peak = math.max(peak, math.abs(amen.left[k])) end
t.expect(peak > 0.2 and peak <= 1.5, "at a level a channel can play")
local other = Drums.shots(SR, kit, {snare = "fat", snareTune = -1, kickTune = 1, kickLength = 0, kickDrive = 0,
	kickClick = 0, hatTone = 0, hatLength = 0, hatNoise = 0, clapSpread = 0, clapLength = 0, clapTone = 0})
t.expect(Drums.loop(SR, other, beat, options) ~= loop, "another kit plays another loop")

-- Loops a track will need are prepared a little at a time, and play the
-- same as loops rendered at once.
local ahead = {snare = "roomy", snareTune = 0.5, kickTune = -0.5, kickLength = 0.2, kickDrive = 0, kickClick = 0,
	hatTone = 0, hatLength = 0, hatNoise = 0, clapSpread = 0, clapLength = 0, clapTone = 0}
local wanted = {tempo = 172, swing = 0.1, humanize = 0.3, variant = "full", energy = true}
Drums.prepare(SR, kit, ahead, beat, wanted)
local steps_ = 0
while Drums.work(0) do steps_ = steps_ + 1 end
t.expect(steps_ > 10, "a loop is prepared in many small steps: " .. steps_)
t.expect(not Drums.work(0), "until nothing is left to do")
local clock = os.clock()
local prepared = Drums.loop(SR, Drums.shots(SR, kit, ahead), beat, wanted)
t.expect(os.clock() - clock < 0.005, "and is ready when its bar comes")
local later = {snare = "fat", snareTune = 0.5, kickTune = -0.5, kickLength = 0.2, kickDrive = 0, kickClick = 0,
	hatTone = 0, hatLength = 0, hatNoise = 0, clapSpread = 0, clapLength = 0, clapTone = 0}
Drums.prepare(SR, kit, later, beat, wanted)
Drums.work(0)
local hurried = Drums.loop(SR, Drums.shots(SR, kit, later), beat, wanted)
t.assertEqual(hurried.frames, prepared.frames, "a loop wanted before it is ready is finished at once")
t.expect(not Drums.work(0), "leaving nothing behind")
local direct = Drums.loop(SR, Drums.shots(SR, kit, later), beat, {tempo = 172, swing = 0.1, humanize = 0.3, variant = "full",
	energy = true})
t.expect(direct == hurried, "and is the loop any caller gets")
Drums.prepare(SR, kit, later, beat, wanted)
t.expect(not Drums.work(0), "a loop that is ready needs no preparing")

-- Theory: a line in scale steps stays in its key.
local minor = StyleKit.modes.minor
t.assertEqual(StyleKit.pitch(minor, 0, 1, 0, 28), 36, "the root folds into its register")
t.assertEqual(StyleKit.pitch(minor, 0, 1, 7, 28), 48, "seven steps up is an octave")
t.assertEqual(StyleKit.pitch(minor, 0, 1, 2, 28), 39, "two steps up a minor third")
t.assertEqual(StyleKit.pitch(StyleKit.modes.major, 0, 1, 2, 28), 40, "or a major one, in a major key")
t.assertEqual(StyleKit.pitch(minor, 0, 1, -1, 28), 34, "a step below the root is the seventh")
t.assertEqual(StyleKit.pitch(minor, 0, 1, 1, 28, -1), 37, "a flat bends a semitone")
for degree = 1, 7 do
	for offset = -3, 9 do
		local pitch = StyleKit.pitch(minor, 2, degree, offset, 64)
		local inKey = false
		for _, step in ipairs(minor.steps) do inKey = inKey or (pitch - 2) % 12 == step end
		t.expect(inKey, "degree " .. degree .. " offset " .. offset .. " is in the key")
	end
end

os.exit(t.summary() and 0 or 1)
