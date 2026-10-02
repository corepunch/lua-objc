_G.__headless = true
-- The arrangement as a producer leaves it: lanes of blocks with fades and
-- filter sweeps, the plan a track is arranged into, the canvas that draws
-- a track's length, energy curve and palette and arranges it phrase by
-- phrase, the composer's bars over that plan, and the timeline that draws
-- the clips.
local t = require("TestKit")
local Model = require("apps.dnb.Model")
local Styles = require("apps.dnb.host.Styles")
local StyleKit = require("apps.dnb.host.StyleKit")
local Arrangement = require("apps.dnb.host.Arrangement")
local Blocks = require("apps.dnb.host.Blocks")
local Canvas = require("apps.dnb.host.Canvas")
local Lanes = require("apps.dnb.host.Lanes")
local Composer = require("apps.dnb.host.Composer")
local Synth = require("apps.dnb.models.Synth")
local Timeline = require("apps.dnb.models.Timeline")

local SR = 22050
local dnbStyle = Styles:get("dnb")

local function near(a, b) return math.abs(a - b) < 1e-9 end
local function describe(lane)
	local parts = {}
	for _, block in ipairs(lane.blocks) do table.insert(parts, block.start .. "+" .. block.length) end
	return table.concat(parts, " ")
end
local function count(set)
	local n = 0
	for _ in pairs(set) do n = n + 1 end
	return n
end
local function correlation(xs, ys)
	local n = #xs
	local mx, my = 0, 0
	for i = 1, n do mx, my = mx + xs[i], my + ys[i] end
	mx, my = mx / n, my / n
	local sxy, sxx, syy = 0, 0, 0
	for i = 1, n do
		sxy = sxy + (xs[i] - mx) * (ys[i] - my)
		sxx = sxx + (xs[i] - mx) ^ 2
		syy = syy + (ys[i] - my) ^ 2
	end
	if sxx == 0 or syy == 0 then return nil end
	return sxy / math.sqrt(sxx * syy)
end

-- The lane builder: blocks carry automation; cuts and rides split them as
-- an arrange window splits clips.
local track = {length = 32}
local lanes = Lanes.new(track)
lanes:add("drums", 0, 16, "drums.groove", {filter = {kind = "lowpass", from = 0.2, to = 1}})
local drums = lanes:done()[1]
t.assertEqual(drums.blocks[1].filter.kind, "lowpass", "a block carries its filter sweep")
t.assertEqual(drums.blocks[1].level, nil, "and no fade it was not given")
lanes:cut("drums", 4, 4)
drums = lanes:done()[1]
t.assertEqual(describe(drums), "0+4 8+8", "a cut leaves the block on either side")
t.expect(near(drums.blocks[1].filter.from, 0.2) and near(drums.blocks[1].filter.to, 0.4), "the first piece keeps its stretch of the sweep")
t.expect(near(drums.blocks[2].filter.from, 0.6) and near(drums.blocks[2].filter.to, 1), "and the second piece its own")
t.assertEqual(drums.blocks[2].offset .. " of " .. drums.blocks[2].whole, "8 of 16", "a piece plays on from where the block would be")
t.assertEqual(drums.blocks[1].whole, 16, "both pieces remember the whole")
lanes:cut("drums", 8, 8)
lanes:cut("drums", 0, 4)
t.assertEqual(#lanes:done(), 0, "a lane cut empty is no lane")
lanes:cut("bass", 0, 4)
t.assertEqual(#lanes:done(), 0, "cutting a lane that was never arranged does nothing")

lanes = Lanes.new(track)
lanes:add("tops", 0, 8, "tops.loop")
lanes:add("tops", 8, 8, "tops.light")
lanes:add("tops", 24, 8, "tops.loop")
lanes:automate("tops", 4, 8, {level = {from = 0, to = 1}})
local tops = lanes:done()[1]
t.assertEqual(describe(tops), "0+4 4+4 8+4 12+4 24+8", "a ride splits the blocks at its ends")
t.assertEqual(tops.blocks[1].level, nil, "the bars before it play as they were")
t.expect(near(tops.blocks[2].level.from, 0) and near(tops.blocks[2].level.to, 0.5), "the ride crosses the first block")
t.expect(near(tops.blocks[3].level.from, 0.5) and near(tops.blocks[3].level.to, 1), "and carries on through the next")
t.assertEqual(tops.blocks[3].pattern, "tops.light", "each piece keeps its pattern")
t.assertEqual(tops.blocks[5].level, nil, "blocks outside it are untouched")
t.expect(lanes:plays("tops", 20, 8) and not lanes:plays("tops", 16, 8), "a lane knows where it plays")
t.expect(not lanes:plays("pad", 0, 32), "and a part never arranged plays nowhere")
lanes:replace("tops", 2, 4, "tops.light")
t.assertEqual(lanes:at("tops", 3).pattern .. " " .. lanes:at("tops", 1).pattern, "tops.light tops.loop",
	"a replacement takes the bars it is given")
lanes:fill("tops", 0, 32, "tops.light")
local covered = 0
for _, block in ipairs(lanes:done()[1].blocks) do covered = covered + block.length end
t.assertEqual(covered, 32, "a fill takes what a lane leaves empty")
t.assertThrows(function() lanes:add("tops", 4, 4, "tops.loop") end, "blocks never overlap in a lane")
-- A track plays the channels it has: blocks for the rest are dropped.
local five = Lanes.new({length = 16, byRole = {drums = {}, bass = {}}})
five:add("drums", 0, 16, "drums.groove")
five:add("pad", 0, 16, "pad.chords")
five:fill("keys", 0, 16, "keys.comp")
t.assertEqual(#five:done(), 1, "a track has no lane for a channel it lacks")
t.expect(five:has("bass") and not five:has("pad"), "and knows which it has")
t.expect(Lanes.new({length = 4}):has("anything"), "a track given no channels has them all")

-- Blocks clip to the track, and carry a drum block's variant and a fill's groove.
lanes = Lanes.new({length = 16})
lanes:add("drums", 12, 8, "drums.groove", {variant = "light"})
t.assertEqual(describe(lanes:done()[1]), "12+4", "a block is clipped to the track")
lanes:add("drums", -4, 6, "drums.fill")
t.assertEqual(describe(lanes:done()[1]), "0+2 12+4", "and from before its first bar")
lanes:add("bass", 20, 4, "bass.line")
t.assertEqual(#lanes:done(), 1, "a block wholly past the track is no block")
lanes = Lanes.new({length = 16})
lanes:add("drums", 0, 8, "groove.a", {variant = "light"})
lanes:replace("drums", 3, 1, "drums.fill", {under = "groove.a", phase = 3})
local pieces = lanes:done()[1].blocks
t.assertEqual(describe(lanes:done()[1]), "0+3 3+1 4+4", "a replacement splits the block around it")
t.assertEqual(pieces[1].variant .. " " .. pieces[3].variant, "light light", "pieces keep the drum variant")
t.assertEqual(pieces[2].under .. " " .. pieces[2].phase, "groove.a 3", "a fill names the groove it interrupts")
t.assertEqual(pieces[3].offset .. " of " .. pieces[3].whole, "4 of 8", "and the groove plays on where it would have been")
lanes = Lanes.new({length = 16})
lanes:add("drums", 0, 8, "groove.a", {under = "x", phase = 2})
lanes:cut("drums", 2, 2)
pieces = lanes:done()[1].blocks
t.assertEqual(pieces[1].under .. pieces[2].under .. pieces[2].phase, "xx2", "pieces keep under and phase")
t.assertEqual(lanes:at("drums", 2), nil, "no block under a cut")
t.assertEqual(lanes:at("drums", 4).start, 4, "and the rest where it was")
lanes:within("bass", {start = 8, length = 8}, 2, 6, "bass.line")
t.assertEqual(describe(lanes:done()[2]), "10+4", "within places bars of a section")
lanes:phraseEnds("pad", {start = 0, length = 16}, 8, "pad.hit")
t.assertEqual(describe(lanes.byPart.pad), "7+1 15+1", "phraseEnds puts a bar at the end of every phrase")

-- Automation reads along a block.
local level, kind, opening = Arrangement.automation({start = 0, length = 4, level = {from = 0, to = 1},
	filter = {kind = "highpass", from = 1, to = 0}}, 0.5)
t.assertEqual(level .. " " .. kind .. " " .. opening, "0.5 highpass 0.5", "halfway through, a block is halfway along its envelopes")
level, kind = Arrangement.automation({start = 0, length = 4, filter = {kind = "highpass", from = 1, to = 0}}, 0)
t.assertEqual(level .. " " .. tostring(kind), "1 nil", "an open filter is no filter")
t.assertEqual(Arrangement.automation({start = 0, length = 4}, 0.3), 1, "a plain block plays at full level")

-- The plan refuses what it cannot play.
local patterns = {["drums.groove"] = {part = "drums"}, ["bass.line"] = {part = "bass"}}
local function plan(lanes_, phrases, order, length)
	return function()
		return Arrangement.new({track = 0, start = 0, length = length or 8, lanes = lanes_,
			channels = {{role = "drums", name = "Drums"}, {role = "bass", name = "Bass"}},
			phrases = phrases or {{start = 0, length = length or 8, energy = 0.5, label = "Groove"}}},
			patterns, order or {"drums", "bass"})
	end
end
local function block(fields)
	local result = {start = 0, length = 8, pattern = "drums.groove"}
	for k, v in pairs(fields or {}) do result[k] = v end
	return {{part = "drums", blocks = {result}}}
end
t.expect(pcall(plan(block())), "a plain plan is accepted")
t.expect(pcall(plan(block({level = {from = 0, to = 1}, filter = {kind = "lowpass", from = 0.3, to = 1}, keep = true}))),
	"a block may fade and sweep, and be kept")
t.expect(pcall(plan(block({variant = "light", under = "drums.groove", phase = 2}))), "a block may carry a variant and a groove")
t.assertThrows(plan(block({level = {from = 0, to = 2}})), "levels stay within 0…1")
t.assertThrows(plan(block({level = {from = 0}})), "a fade needs both ends")
t.assertThrows(plan(block({filter = {kind = "bandpass", from = 0, to = 1}})), "filters are low-pass or high-pass")
t.assertThrows(plan({{part = "drums", blocks = {{start = 0, length = 4, pattern = "drums.groove"},
	{start = 2, length = 4, pattern = "drums.groove"}}}}), "blocks never overlap in a lane")
t.assertThrows(plan(block({pattern = "drums.cowbell"})), "blocks play known patterns")
t.assertThrows(plan({{part = "bass", blocks = {{start = 0, length = 4, pattern = "drums.groove"}}}}),
	"a lane plays only its role's patterns")
t.assertThrows(plan(block({start = 6, length = 4})), "blocks stay inside the track")
t.assertThrows(plan(block({render = print})), "blocks are plain data")
t.assertThrows(plan(block({length = 2.5})), "blocks are whole bars")
t.assertThrows(plan({}, {{start = 0, length = 4, energy = 0.5}}), "phrases cover every bar")
t.assertThrows(plan({}, {{start = 0, length = 4, energy = 0.5}, {start = 5, length = 3, energy = 0.5}}), "phrases tile the track without gaps")
t.assertThrows(plan({}, {{start = 0, length = 4, energy = 0.5}, {start = 2, length = 6, energy = 0.5}}), "or overlaps")
t.assertThrows(plan({}, {{start = 0, length = 8, energy = 1.2}}), "a phrase's energy is within 0…1")
t.assertThrows(plan({}, {{start = 0, length = 8, energy = -0.1}}), "and not below")
t.assertThrows(plan({{part = "pad", blocks = {}}}), "lanes are channels of the track")
t.assertThrows(plan({{part = "drums", blocks = {}}, {part = "drums", blocks = {}}}), "one lane to a channel")
local nine = {}
local order = {}
for i, role in ipairs(Model.roles) do
	if i <= 9 then
		table.insert(nine, {part = role.id, blocks = {}})
		table.insert(order, role.id)
	end
end
t.assertThrows(plan(nine, nil, order), "a track plays on eight channels at most")
local arrangedPlan = plan({{part = "bass", blocks = {}}, {part = "drums", blocks = {}}})()
t.assertEqual(arrangedPlan.lanes[1].part, "drums", "lanes are sorted as the channels are")
t.assertEqual(arrangedPlan:row("bass"), 2, "and a channel knows its row")
t.assertEqual(arrangedPlan:row("pad"), nil, "one the track lacks has none")
t.assertEqual(arrangedPlan:lane("bass").part, "bass", "a plan finds a lane by its part")
t.assertEqual(arrangedPlan:lane("pad"), nil, "and none it lacks")
-- Phrases of a plan are found by bar, and carry the curve.
local phrased = plan(block({length = 4}), {{start = 0, length = 4, energy = 0.2}, {start = 4, length = 4, energy = 0.9}})()
t.assertEqual(phrased:energyAt(0) .. " " .. phrased:energyAt(3) .. " " .. phrased:energyAt(4) .. " " .. phrased:energyAt(7),
	"0.2 0.2 0.9 0.9", "the energy of a bar is its phrase's")
local at, index = phrased:phraseAt(5)
t.assertEqual(at.start .. " " .. index, "4 2", "a bar is in the phrase that holds it")
t.assertEqual(Arrangement.blockAt(phrased.lanes[1], 3).start, 0, "a block is found by bar")
t.assertEqual(Arrangement.blockAt(phrased.lanes[1], 4), nil, "and silence is no block")
t.assertEqual(phrased:blocksAt(2).drums.pattern, "drums.groove", "blocksAt lists every lane's block")
t.assertEqual(phrased.sections, nil, "a plan has no sections")

-- Flavours are checked before a set plays.
local composerForLibrary = Styles:create("dnb", 1)
local library, catalogue = composerForLibrary.library, composerForLibrary.catalogue
local function flavour(channels, extra)
	return function()
		local entry = {id = "x", name = "X", channels = channels}
		for k, v in pairs(extra or {}) do entry[k] = v end
		StyleKit.newSet(1, {library = library, catalogue = catalogue, genre = "dnb", flavours = {entry}})
	end
end
local kit = {role = "drums"}
t.expect(pcall(flavour({kit, {role = "bass", patches = {"bass.sub"}}})), "a flavour names channels and patches")
t.expect(pcall(flavour({kit, {role = "bass", patches = {"bass.sub"}, wants = {"rolling"}, avoid = {"dark"}, chance = 0.5}})),
	"a channel wants and avoids tags")
t.expect(pcall(flavour({kit, {role = "tops"}, {role = "fx"}})), "drums, tops and fx need no patches")
t.expect(pcall(flavour({kit}, {arc = {riser = 0.1}})), "a flavour may override the arc")
t.assertThrows(flavour({kit}, {arc = {sections = {}}}), "but only the arc's fields")
t.assertThrows(function()
	StyleKit.newSet(1, {library = library, catalogue = catalogue, genre = "dnb", arc = {form = {}},
		flavours = {{id = "x", name = "X", channels = {kit}}}})
end, "a style's arc names real fields")
t.assertThrows(flavour({{role = "bass", patches = {"bass.sub"}}}), "a flavour needs drums")
t.assertThrows(flavour({kit, {role = "bass", patches = {"bass.kazoo"}}}), "patches must exist")
t.assertThrows(flavour({{role = "drums", fills = {"fill.polka"}}}), "and fills")
t.assertThrows(flavour({kit, {role = "bass"}}), "a pitched channel needs patches")
t.assertThrows(flavour({kit, {role = "cowbell", patches = {"bass.sub"}}}), "roles are real")
t.assertThrows(flavour({kit, {role = "bass", patches = {"bass.sub"}}, {role = "bass", patches = {"bass.sub"}}}),
	"one channel to a role")
t.assertThrows(flavour({kit, {role = "bass", patches = {"bass.sub"}, wants = {1}}}), "wants are tags")
t.assertThrows(flavour({kit, {role = "bass", patches = {"bass.sub"}, avoid = {{}}}}), "and so are the tags to avoid")
local crowd = {kit}
for _, role in ipairs({"tops"}) do table.insert(crowd, {role = role}) end
for _, role in ipairs({"bass", "pad", "keys", "stab", "arp", "lead", "counter"}) do
	table.insert(crowd, {role = role, patches = {"bass.sub"}})
end
t.assertThrows(flavour(crowd), "eight channels at most")
t.assertThrows(flavour({kit}, {snares = {"cowbell"}}), "flavours name real snare characters")
t.assertThrows(function()
	StyleKit.newSet(1, {library = library, catalogue = Blocks.catalogue({}), genre = "dnb",
		flavours = {{id = "x", name = "X", channels = {kit}}}})
end, "a flavour needs blocks to play")
t.assertThrows(function() StyleKit.newSet(1, {library = library, genre = "dnb", flavours = {{id = "x", name = "X", channels = {kit}}}}) end,
	"a set needs a catalogue of blocks")

-- The canvas: the arc of a track ----------------------------------------------

local arc = Canvas.arc()
t.assertEqual(arc.phrase, Canvas.defaults.phrase, "an arc given nothing is the defaults")
for k, v in pairs(Canvas.defaults) do t.expect(arc[k] == v, "the default " .. k .. " is carried") end
arc.phrase = 99
t.assertEqual(Canvas.defaults.phrase, 8, "an arc is a copy: editing it leaves the defaults")
arc = Canvas.arc({riser = 0.1, fill = 0.9}, {riser = 0.2})
t.expect(arc.riser == 0.2 and arc.fill == 0.9 and arc.unit == Canvas.defaults.unit,
	"a flavour's arc wins over the style's, which wins over the defaults")
t.expect(Canvas.arc(nil, {lift = 1}).lift == 1 and Canvas.arc(nil, nil).lift == 0, "an arc may be left out")
t.assertThrows(function() Canvas.arc({bogus = 1}) end, "an unknown arc field is refused")
t.assertThrows(function() Canvas.arc({}, {sections = {}}) end, "whichever of the arcs it is in")
t.assertEqual(Canvas.defaults.phrase, 8, "phrases are eight bars")
t.assertEqual(Canvas.defaults.unit % Canvas.defaults.phrase, 0, "and a unit is a whole number of phrases")
t.assertEqual(Canvas.defaults.sections, nil, "the defaults have no sections")

-- The canvas: the layout ------------------------------------------------------

local function layout(arc_, tempo, seed, modulations)
	return Canvas.layout(arc_, tempo, modulations or {2, 5}, StyleKit.random(seed, 7))
end
for _, tempo in ipairs({86, 128, 140, 174}) do
	for seed = 1, 12 do
		local a = Canvas.arc()
		local bars, phrases = layout(a, tempo, seed)
		local name = "tempo " .. tempo .. " seed " .. seed
		t.assertEqual(math.type(bars), "integer", name .. ": a track is whole bars")
		t.assertEqual(bars % a.unit, 0, name .. ": a track is a whole number of units")
		local minutes = bars * 4 / tempo
		-- Rounded to a unit, which is half a unit either way at most.
		local slack = a.unit / 2 * 4 / tempo
		t.expect(minutes >= a.minutes[1] - slack - 1e-9 and minutes <= a.minutes[2] + slack + 1e-9,
			string.format("%s: %d bars is %.2f minutes", name, bars, minutes))
		local cursor, edges = 0, 0
		for i, phrase in ipairs(phrases) do
			t.assertEqual(phrase.start, cursor, name .. ": phrase " .. i .. " starts where the last ended")
			t.assertEqual(phrase.length, a.phrase, name .. ": phrases are eight bars")
			t.expect(phrase.energy >= 0 and phrase.energy <= 1, name .. ": energy is 0…1")
			t.expect(type(phrase.label) == "string", name .. ": a phrase has a label")
			cursor = cursor + phrase.length
			if phrase.edge then edges = edges + 1 end
		end
		t.assertEqual(cursor, bars, name .. ": phrases tile the track")
		t.assertEqual(edges, (a.intro + a.outro) // a.phrase, name .. ": the intro and the outro are the edge phrases")
	end
end
-- A slower tempo is fewer bars in the same minutes.
do
	local slow, fast = layout(Canvas.arc(), 90, 5), layout(Canvas.arc(), 180, 5)
	t.expect(fast > slow * 1.5, "the same minutes are more bars at a faster tempo: " .. slow .. " and " .. fast)
	t.expect(layout(Canvas.arc({minutes = {1, 1}}), 100, 5) >= 4 * 16, "a track is at least four units")
	t.assertEqual(layout(Canvas.arc({minutes = {6, 6}, unit = 8}), 128, 5), 192, "minutes and a unit set the length: 6 min at 128")
end
-- Intro and outro are edge; valleys are falls from a peak, never at the edge.
local valleys, tracksWithValley = 0, 0
for seed = 1, 60 do
	local a = Canvas.arc()
	local bars, phrases = layout(a, 140, seed)
	local peak, any = 0, false
	for i, phrase in ipairs(phrases) do
		local name = "seed " .. seed .. " phrase " .. i
		t.assertEqual(phrase.edge, phrase.start < a.intro or phrase.start + phrase.length > bars - a.outro,
			name .. " is edge exactly at the ends")
		if phrase.valley then
			valleys, any = valleys + 1, true
			t.expect(not phrase.edge, name .. ": a valley is never at the edge")
			t.expect(phrase.energy < a.valley, name .. ": a valley is low")
			t.expect(peak - phrase.energy >= 0.2 - 1e-9, name .. ": a valley is a fall from a peak that came before")
			t.assertEqual(phrase.label, "Breakdown", name .. " is a breakdown")
		else
			t.expect(phrase.label ~= "Breakdown", name .. ": only valleys are breakdowns")
		end
		peak = math.max(peak, phrase.energy)
	end
	if any then tracksWithValley = tracksWithValley + 1 end
	t.assertEqual(phrases[1].label, "Mix in", "a track opens by mixing in")
	t.assertEqual(phrases[#phrases].label, "Mix out", "and ends mixing out")
	t.expect(phrases[1].edge and phrases[#phrases].edge and not phrases[#phrases / 2 // 1].edge, "the middle is not edge")
	t.expect(phrases[1].energy < 0.5 and phrases[#phrases].energy < 0.5, "a track starts and ends low")
	for _, phrase in ipairs(phrases) do
		if phrase.edge then t.expect(phrase.energy <= 0.5 + 1e-9, "the ends never climb above half energy: " .. phrase.energy) end
	end
end
t.expect(valleys > 0 and tracksWithValley > 5, "the default curve draws valleys: " .. tracksWithValley .. " of 60 tracks")
do
	local flat = Canvas.arc({curve = {{0, 0.7}, {1, 0.7}}, jitter = 0})
	local _, phrases = layout(flat, 140, 3)
	for _, phrase in ipairs(phrases) do t.expect(not phrase.valley, "a flat curve has no valley") end
	local _, low = layout(Canvas.arc({curve = {{0, 0.2}, {1, 0.2}}, jitter = 0, valley = 0.9}), 140, 3)
	for _, phrase in ipairs(low) do t.expect(not phrase.valley, "a curve with no peak before it has no valley") end
end
-- The curve's anchors are reproduced where the jitter is nothing.
do
	local ramp = Canvas.arc({curve = {{0, 0.2}, {0.5, 0.8}, {1, 0.2}}, jitter = 0})
	local bars, phrases = layout(ramp, 140, 4)
	for p, phrase in ipairs(phrases) do
		local at = (p - 0.5) / #phrases
		local expected = at <= 0.5 and 0.2 + 0.6 * at / 0.5 or 0.8 - 0.6 * (at - 0.5) / 0.5
		t.expect(near(phrase.energy, expected), string.format("phrase %d reads the curve at its middle: %.4f, %.4f", p, phrase.energy, expected))
	end
	local top = 0
	for _, phrase in ipairs(phrases) do top = math.max(top, phrase.energy) end
	t.expect(top > 0.75 and top <= 0.8, "the peak anchor is reproduced to within a phrase: " .. top)
	local stepped = Canvas.arc({curve = {{0, 0.3}, {0.25, 0.3}, {0.26, 0.9}, {1, 0.9}}, jitter = 0})
	local _, steps = layout(stepped, 140, 4)
	t.assertEqual(steps[1].energy, 0.3, "a plateau holds its anchor's energy")
	t.assertEqual(steps[#steps // 2].energy, 0.9, "and so does a later one")
	-- The ends are for mixing: a curve that is high there is held down, more
	-- the nearer the track's first and last bar.
	local high = Canvas.arc({curve = {{0, 0.9}, {1, 0.9}}, jitter = 0})
	local bars_, loud = layout(high, 140, 4)
	local cap = function(into) return 0.25 + 0.25 * into end
	t.assertEqual(loud[1].energy, cap(4 / 16), "the first phrase of a loud track is held to the low end of the cap")
	t.assertEqual(loud[2].energy, cap(12 / 16), "the second rises towards its edge")
	t.assertEqual(loud[#loud].energy, cap(4 / 16), "the last is held as the first is")
	t.assertEqual(loud[#loud - 1].energy, cap(12 / 16), "and the one before as the second")
	t.assertEqual(loud[3].energy, 0.9, "the middle is as loud as the curve")
	local long = Canvas.arc({curve = {{0, 0.9}, {1, 0.9}}, jitter = 0, intro = 32, outro = 32})
	local _, slow = layout(long, 140, 4)
	t.expect(slow[2].energy < loud[2].energy and slow[1].energy < loud[1].energy, "a longer intro keeps the energy lower for longer")
	t.expect(slow[4].energy <= 0.5, "and never above half within its bars")
end
-- Jitter moves the anchors within its bounds, and every energy stays in range.
do
	local seen = {}
	for seed = 1, 20 do
		local _, phrases = layout(Canvas.arc(), 140, seed)
		local shape = {}
		for _, phrase in ipairs(phrases) do table.insert(shape, string.format("%.3f", phrase.energy)) end
		seen[table.concat(shape, " ")] = true
		for _, phrase in ipairs(phrases) do t.expect(phrase.energy >= 0.1 - 1e-9 and phrase.energy <= 1, "jittered energy stays in range") end
	end
	t.expect(count(seen) >= 18, "every seed draws its own curve: " .. count(seen) .. " of 20")
	local fixed = Canvas.arc({jitter = 0})
	local _, a = layout(fixed, 140, 1)
	local _, b = layout(fixed, 140, 2)
	local same = #a == #b
	for i = 1, same and #a or 0 do same = same and near(a[i].energy, b[i].energy) end
	t.expect(same, "with no jitter the curve is the same for every seed")
end
-- Deterministic per rng.
do
	local function shape(seed)
		local bars, phrases, lift = layout(Canvas.arc({lift = 1}), 140, seed)
		local parts = {bars, lift and lift.bar, lift and lift.semis}
		for _, phrase in ipairs(phrases) do
			table.insert(parts, string.format("%.6f%s%s", phrase.energy, phrase.valley and "v" or "", phrase.label))
		end
		return table.concat(parts, " ")
	end
	t.assertEqual(shape(8), shape(8), "a layout is reproducible from its rng")
	t.expect(shape(8) ~= shape(9), "and another rng draws another")
end
-- The key lift: only when asked for, and on the second peak.
do
	local lifted, lifts = 0, 0
	for seed = 1, 60 do
		local bars, phrases, lift = layout(Canvas.arc(), 140, seed)
		t.assertEqual(lift, nil, "no lift while arc.lift is 0")
		local _, _, never = layout(Canvas.arc({lift = 0}), 140, seed)
		t.assertEqual(never, nil, "or set to 0")
		local _, valleyPhrases, always = layout(Canvas.arc({lift = 1}), 140, seed, {2, 5})
		local seen = false
		local hasValley = false
		for _, phrase in ipairs(valleyPhrases) do hasValley = hasValley or phrase.valley end
		if always then
			lifts = lifts + 1
			t.expect(hasValley, "a lift follows a valley")
			t.assertEqual(always.bar % 8, 0, "a lift lands on a phrase")
			local phrase = valleyPhrases[always.bar // 8 + 1]
			t.expect(phrase.energy >= 0.75 and not phrase.valley, "the key lifts on a high-energy phrase")
			local first = true
			for i = 1, always.bar // 8 do
				if valleyPhrases[i].valley then seen = true end
				if seen and not valleyPhrases[i].valley and valleyPhrases[i].energy >= 0.75 then first = false end
			end
			t.expect(seen and first, "and the first one after the valley")
			t.expect(always.semis == 2 or always.semis == 5, "by one of the modulations: " .. tostring(always.semis))
		elseif hasValley then
			-- No phrase of high energy after the valley.
			local high = false
			local after = false
			for _, phrase in ipairs(valleyPhrases) do
				after = after or phrase.valley
				high = high or (after and not phrase.valley and phrase.energy >= 0.75)
			end
			t.expect(not high, "a lift is drawn whenever a second peak follows the valley")
		end
	end
	t.expect(lifts >= 20, "with arc.lift 1 most tracks lift: " .. lifts .. " of 60")
	for seed = 1, 100 do
		local _, _, lift = layout(Canvas.arc({lift = 0.3}), 140, seed)
		if lift then lifted = lifted + 1 end
	end
	t.expect(lifted > 3 and lifted < 55, "a share of tracks lift: " .. lifted .. " of 100")
end

-- The canvas: the palette -----------------------------------------------------

local function spec(role, number, fields)
	local result = {id = string.format("dnb.%s.%03d", role, number), role = role, bars = 1, energy = 0.5, density = 0.5}
	if role == "drums" then
		result.lanes = {{"kick", "X..............."}}
	elseif role == "bass" or role == "counter" or role == "lead" then
		result.notes = "0:0:4"
	elseif role == "fx" then
		result.kind = "riser"
	end
	for k, v in pairs(fields or {}) do result[k] = v end
	return result
end
local function palette(specs, channels, rng, before, flavourId, genre)
	local list = Blocks.catalogue({specs})
	local track_ = {flavour = {id = flavourId or "liquid"}, channels = channels}
	return Canvas.palette(track_, list, genre or "dnb", rng or StyleKit.random(1), before), list
end
local function channel(role, fields)
	local own = {role = role}
	for k, v in pairs(fields or {}) do own[k] = v end
	return {role = role, spec = own}
end
do
	-- Drums: a quiet mixable loop, a loud one, a middle, one more; the half-time one apart.
	local specs = {
		spec("drums", 1, {energy = 0.2, tags = {"mixable"}}),
		spec("drums", 2, {energy = 0.3, tags = {"dark"}}),
		spec("drums", 3, {energy = 0.9}),
		spec("drums", 4, {energy = 0.55}),
		spec("drums", 5, {energy = 0.8, tags = {"halftime"}}),
	}
	local p, list = palette(specs, {channel("drums")})
	local ids = {}
	for _, block in ipairs(p.drums) do table.insert(ids, block.id) end
	t.assertEqual(table.concat(ids, " "), "dnb.drums.001 dnb.drums.003 dnb.drums.004 dnb.drums.002",
		"the drums palette is a quiet mixable loop, a loud one, a middle one and one more")
	t.assertEqual(p.halftime and p.halftime.id, "dnb.drums.005", "the half-time loop stands apart")
	for _, block in ipairs(p.drums) do t.expect(not block.tags.halftime, "and is not in the palette") end
	t.expect(p.drums[1].energy < 0.5 and p.drums[1].tags.mixable, "the first drum block is quiet and mixable")
	t.assertEqual(p.bass, nil, "a role the track has no channel for has no palette")
	t.assertEqual(p.fx.riser, nil, "nor fx")

	-- A style that wants half-time plays it as any other.
	p = palette(specs, {channel("drums", {wants = {"halftime"}})})
	t.assertEqual(p.halftime, nil, "wanted half-time is no separate block")
	local has = false
	for _, block in ipairs(p.drums) do has = has or block.tags.halftime end
	t.expect(has, "it is among the drums")

	-- The quiet block need not be mixable when none is.
	local quiet = {spec("drums", 1, {energy = 0.3}), spec("drums", 2, {energy = 0.8}), spec("drums", 3, {energy = 0.5})}
	p = palette(quiet, {channel("drums")})
	t.assertEqual(p.drums[1].id, "dnb.drums.001", "with none mixable the palette still opens on the quiet one")
	t.assertEqual(#p.drums, 3, "and holds as many as there are")
	-- Only half-time drums: they are the palette.
	p = palette({spec("drums", 1, {tags = {"halftime"}})}, {channel("drums")})
	t.assertEqual(#p.drums, 1, "a flavour that has only half-time drums plays them")
	t.assertEqual(p.halftime, nil, "with no other to switch to")

	-- `avoid` is a hard filter; `wants` is preferred.
	p = palette(specs, {channel("drums", {avoid = {"dark"}})})
	for _, block in ipairs(p.drums) do t.expect(not block.tags.dark, "an avoided tag keeps a block out") end
	t.assertThrows(function() palette(specs, {channel("drums", {avoid = {"mixable", "dark", "halftime"}}), channel("bass")}) end,
		"avoiding every block (or having none for a role) is an error")
	t.assertThrows(function() palette(specs, {channel("bass")}) end, "a channel with no blocks to play is an error")
	local bass = {}
	for n = 1, 6 do table.insert(bass, spec("bass", n, {energy = 0.1 * n, tags = n == 4 and {"gallop", "rolling"} or {"plain"}})) end
	for seed = 1, 20 do
		local wanted = palette(bass, {channel("bass", {wants = {"gallop", "rolling"}})}, StyleKit.random(seed))
		t.assertEqual(wanted.bass[1].id, "dnb.bass.004", "a block with two wanted tags always leads (seed " .. seed .. ")")
		t.assertEqual(#wanted.bass, 3, "a bass palette keeps three blocks")
		local distinct = {}
		for _, block in ipairs(wanted.bass) do distinct[block.id] = true end
		t.assertEqual(count(distinct), 3, "all different")
	end
	local lead = {}
	for n = 1, 4 do table.insert(lead, spec("lead", n)) end
	local picks = {}
	for seed = 1, 20 do
		picks[palette(lead, {channel("lead")}, StyleKit.random(seed)).lead[1].id] = true
		t.assertEqual(#palette(lead, {channel("lead")}, StyleKit.random(seed)).lead, 2, "a lead palette keeps two")
	end
	t.expect(count(picks) >= 3, "without wants the first block is the rng's pick: " .. count(picks) .. " different")
	local lone = palette({spec("counter", 1), spec("counter", 2)}, {channel("counter")})
	t.assertEqual(#lone.counter, 1, "a counter-melody palette is one block")
	t.assertEqual(#palette({spec("lead", 1)}, {channel("lead")}).lead, 1, "a palette is no larger than the blocks there are")

	-- Genre and flavour: the genre's own and the shared, and the flavour's.
	local mixed = {spec("bass", 1), {id = "common.bass.001", role = "bass", bars = 1, energy = 0.5, density = 0.5, notes = "0:0:4"},
		{id = "trance.bass.001", role = "bass", bars = 1, energy = 0.5, density = 0.5, notes = "0:0:4"},
		spec("bass", 2, {flavours = {"other"}})}
	for seed = 1, 10 do
		p = palette(mixed, {channel("bass")}, StyleKit.random(seed), nil, "liquid", "dnb")
		for _, block in ipairs(p.bass) do
			t.expect(block.genre == "dnb" or block.genre == "common", "another genre's block is never drawn")
			t.expect(block.id ~= "dnb.bass.002", "nor a block of another flavour")
		end
		t.assertEqual(#p.bass, 2, "leaving the genre's and the shared block")
	end

	-- The previous track's blocks are passed over where there is a choice.
	local counters = {spec("counter", 1), spec("counter", 2), spec("counter", 3)}
	for seed = 1, 20 do
		local first = palette(counters, {channel("counter")}, StyleKit.random(seed)).counter
		local next_ = palette(counters, {channel("counter")}, StyleKit.random(seed + 100), {counter = first}).counter
		t.expect(next_[1].id ~= first[1].id, "the next track takes another counter-melody (seed " .. seed .. ")")
		local only = palette({spec("counter", 1)}, {channel("counter")}, StyleKit.random(seed), {counter = first})
		t.assertEqual(only.counter[1].id, "dnb.counter.001", "but the one block there is is still played")
	end
	local twoDrums = {spec("drums", 1, {energy = 0.2, tags = {"mixable"}}), spec("drums", 2, {energy = 0.25, tags = {"mixable"}}),
		spec("drums", 3, {energy = 0.9})}
	for seed = 1, 10 do
		local first = palette(twoDrums, {channel("drums")}, StyleKit.random(seed)).drums
		local second = palette(twoDrums, {channel("drums")}, StyleKit.random(seed), {drums = {first[1]}}).drums
		t.expect(second[1].id ~= first[1].id, "the next track mixes in on another quiet loop")
	end

	-- fx are listed by kind.
	local fx = {spec("fx", 1, {kind = "riser"}), spec("fx", 2, {kind = "riser"}), spec("fx", 3, {kind = "impact"}),
		spec("fx", 4, {kind = "downlifter"}), spec("fx", 5, {kind = "riser", flavours = {"other"}})}
	p = palette(fx, {channel("fx")})
	t.assertEqual(#p.fx.riser, 2, "the fx palette lists risers")
	for kind, list in pairs(p.fx) do
		if kind ~= "any" then
			for _, block in ipairs(list) do t.assertEqual(block.kind, kind, block.id .. " is listed under its kind") end
		end
	end
	t.assertEqual(#p.fx.impact + #p.fx.downlifter, 2, "and impacts and downlifters")
	t.assertEqual(p.fx.crash, nil, "a kind the style has none of is not listed")
	t.assertEqual(#p.fx.any, 4, "any fx is every block that suits the flavour")
	t.assertEqual(p.fx.any[1].role, "fx", "of the role")
	local risers = {spec("fx", 1, {kind = "riser"}), spec("fx", 2, {kind = "riser"})}
	local before = palette(risers, {channel("fx")}, StyleKit.random(1)).fx
	for seed = 1, 10 do
		local again = palette(risers, {channel("fx")}, StyleKit.random(seed), {fx = before})
		t.expect(#again.fx.riser == 2, "two risers are both kept")
	end
	local three = {spec("fx", 1), spec("fx", 2), spec("fx", 3)}
	local prevFx = {fx = {riser = {Blocks.catalogue({three}):get("dnb.fx.001")}}}
	for seed = 1, 10 do
		t.expect(palette(three, {channel("fx")}, StyleKit.random(seed), prevFx).fx.riser[1].id ~= "dnb.fx.001",
			"the previous track's riser is not the first this one draws")
	end
end

-- Real tracks of every style --------------------------------------------------

local SIZE = {bass = 3, tops = 2, pad = 2, keys = 2, stab = 2, arp = 2, lead = 2, counter = 1, texture = 1}
local SEEDS = {3, 17, 41}
local KINDS = {valley = true, ["return"] = true, lift = true, riser = true, drumsOut = true, halftime = true}
local samples = {}
for _, style in ipairs(Styles:list()) do
	for _, seed in ipairs(SEEDS) do
		local composer = Styles:create(style.id, seed)
		for k = 0, 3 do
			local plan_ = composer:arrangement(k)
			table.insert(samples, {style = style.id, seed = seed, k = k, composer = composer, plan = plan_,
				track = composer.set:track(k), previous = k > 0 and composer.set:track(k - 1) or nil})
		end
	end
end
local function where(s) return string.format("%s seed %d track %d", s.style, s.seed, s.k) end
local function serialize(plan_)
	local parts = {plan_.length, plan_.track}
	for _, phrase in ipairs(plan_.phrases) do
		table.insert(parts, string.format("%d:%.6f:%s:%s", phrase.start, phrase.energy, tostring(phrase.valley), phrase.label))
	end
	for _, lane in ipairs(plan_.lanes) do
		table.insert(parts, lane.part)
		for _, b in ipairs(lane.blocks) do
			table.insert(parts, string.format("%d+%d:%s:%s:%s:%s", b.start, b.length, b.pattern, tostring(b.variant), tostring(b.under),
				b.filter and string.format("%s%.4f", b.filter.kind, b.filter.from) or "-"))
		end
	end
	for _, e in ipairs(plan_.events) do table.insert(parts, e.kind .. e.bar) end
	return table.concat(parts, " ")
end
local function isBlend(block) return block.pattern:match("%.blend$") ~= nil end
local function isSystem(block) return block.pattern == "drums.fill" or block.pattern == "drums.roll" or isBlend(block) end
-- The rows of a plan, one lane per role.
local function roleBlocks(plan_, role)
	local lane = plan_:lane(role)
	return lane and lane.blocks or {}
end

-- The tracks themselves: what the set gives the canvas.
for _, s in ipairs(samples) do
	local track_, plan_ = s.track, s.plan
	local name = where(s)
	t.assertEqual(plan_.length, track_.length, name .. " the plan is as long as the track")
	t.assertEqual(plan_.length % track_.arc.unit, 0, name .. " is a whole number of units")
	local minutes = plan_.length * 4 / track_.tempo
	local slack = track_.arc.unit / 2 * 4 / track_.tempo
	t.expect(minutes >= track_.arc.minutes[1] - slack - 1e-9 and minutes <= track_.arc.minutes[2] + slack + 1e-9,
		string.format("%s lasts %.2f minutes at %d BPM (%s to %s asked for)", name, minutes, track_.tempo,
			track_.arc.minutes[1], track_.arc.minutes[2]))
	t.assertEqual(plan_.start, track_.start, name .. " starts where the set puts it")
	t.assertEqual(plan_.tempo, track_.tempo, name .. " plays at its tempo")
	local cursor = 0
	for i, phrase in ipairs(plan_.phrases) do
		t.assertEqual(phrase.start, cursor, name .. " phrases tile the track")
		cursor = cursor + phrase.length
		t.expect(phrase.energy >= 0 and phrase.energy <= 1, name .. " phrase energy is 0…1")
		t.assertEqual(phrase.edge, phrase.start < track_.arc.intro or phrase.start + phrase.length > plan_.length - track_.arc.outro,
			name .. " the intro and the outro are the edge phrases")
		t.expect(not (phrase.valley and phrase.edge), name .. " a valley is never edge")
	end
	t.assertEqual(cursor, plan_.length, name .. " phrases cover the track")
	t.assertEqual(plan_.phrases[1].label, "Mix in", name .. " mixes in")
	t.assertEqual(plan_.phrases[#plan_.phrases].label, "Mix out", name .. " mixes out")
	t.assertEqual(track_.phraseBars, track_.arc.phrase, name .. " a track knows its phrase")
	-- A lift is only where the style or flavour asks for one.
	if track_.lift then
		t.expect(track_.arc.lift > 0, name .. " lifts its key only where arc.lift > 0")
		t.assertEqual(track_.lift.bar % track_.arc.phrase, 0, name .. " the lift lands on a phrase")
		local ok = false
		for _, semis in ipairs(s.composer.set.modulations) do ok = ok or semis == track_.lift.semis end
		t.expect(ok, name .. " by one of the set's modulations")
	end
end

-- The palettes of the real tracks.
local wantedHits, wantedPool = 0, 0
local overlap, pairsSeen = 0, 0
for _, s in ipairs(samples) do
	local track_, name = s.track, where(s)
	local p, catalogue_ = track_.palette, s.composer.catalogue
	for _, channel_ in ipairs(track_.channels) do
		local role = channel_.role
		local avoid = {}
		for _, tag in ipairs(channel_.spec.avoid or {}) do avoid[tag] = true end
		local list = role == "fx" and p.fx.any or p[role]
		t.expect(list ~= nil and #list > 0, name .. " has a palette for " .. role)
		for _, block in ipairs(list or {}) do
			t.assertEqual(block.role, role, name .. " " .. block.id .. " is a " .. role .. " block")
			t.assertEqual(catalogue_:get(block.id), block, name .. " " .. block.id .. " is in the catalogue")
			t.expect(block.genre == s.style or block.genre == "common", name .. " " .. block.id .. " is the style's or shared")
			t.expect(not block.flavours or block.flavours[track_.flavour.id], name .. " " .. block.id .. " suits the flavour")
			for tag in pairs(avoid) do t.expect(not block.tags[tag], name .. " " .. block.id .. " avoids " .. tag) end
		end
		if role ~= "fx" and role ~= "drums" then
			t.expect(#list <= SIZE[role], name .. " keeps at most " .. SIZE[role] .. " " .. role .. " blocks")
		end
		if role == "drums" then
			t.expect(#list >= 1 and #list <= 4, name .. " keeps up to four drum blocks")
			local quiet = false
			for _, block in ipairs(list) do quiet = quiet or block.energy < 0.5 end
			t.expect(quiet, name .. " has a quiet drum loop to mix on")
			local ids = {}
			for _, block in ipairs(list) do
				t.expect(not ids[block.id], name .. " draws each drum block once")
				ids[block.id] = true
			end
			local wantsHalf = false
			for _, tag in ipairs(channel_.spec.wants or {}) do wantsHalf = wantsHalf or tag == "halftime" end
			if p.halftime then
				t.assertEqual(p.halftime.role, "drums", name .. " the half-time block is a drum block")
				t.expect(p.halftime.tags.halftime, name .. " and tagged half-time")
				t.expect(not ids[p.halftime.id], name .. " apart from the palette")
			end
			if not wantsHalf and p.halftime then
				for _, block in ipairs(list) do t.expect(not block.tags.halftime, name .. " keeps half-time out of the groove") end
			end
		end
		-- Wants: how often a wanted tag turns up against how often the pool has it.
		if role ~= "fx" and role ~= "drums" and #(channel_.spec.wants or {}) > 0 then
			local candidates = catalogue_:candidates(role, s.style, track_.flavour.id, avoid)
			local function wanted(block)
				for _, tag in ipairs(channel_.spec.wants) do if block.tags[tag] then return true end end
				return false
			end
			local pool = 0
			for _, block in ipairs(candidates) do if wanted(block) then pool = pool + 1 end end
			if pool > 0 and pool < #candidates then
				wantedPool = wantedPool + pool / #candidates
				for _, block in ipairs(list) do if wanted(block) then wantedHits = wantedHits + 1 / #list end end
			end
		end
	end
	for _, channel_ in ipairs(track_.channels) do
		t.assertEqual(p[channel_.role] ~= nil or channel_.role == "fx", true, name .. " " .. channel_.role .. " palette")
	end
	for role in pairs(p) do
		if role ~= "fx" and role ~= "halftime" then t.expect(track_.byRole[role] ~= nil, name .. " has no palette for a channel it lacks: " .. role) end
	end
	for kind, list in pairs(p.fx) do
		if kind ~= "any" then
			t.expect(Blocks.fxKinds[kind], name .. " fx kind " .. kind .. " is known")
			for _, block in ipairs(list) do t.assertEqual(block.kind, kind, name .. " fx " .. block.id .. " is listed as a " .. kind) end
		end
	end
	if s.previous then
		for role, list in pairs(p) do
			if role ~= "fx" and role ~= "halftime" and s.previous.palette[role] then
				for _, block in ipairs(list) do
					pairsSeen = pairsSeen + 1
					for _, other in ipairs(s.previous.palette[role]) do
						if other.id == block.id then overlap = overlap + 1 end
					end
				end
			end
		end
	end
end
t.expect(wantedPool > 0 and wantedHits > wantedPool * 1.2, string.format(
	"palettes lean to what a channel wants: %.1f of its blocks against %.1f by chance", wantedHits, wantedPool))
t.expect(pairsSeen > 100 and overlap <= pairsSeen * 0.35, string.format(
	"consecutive tracks share few blocks: %d of %d", overlap, pairsSeen))

-- The arranger: validity ----------------------------------------------------------

local function rise(phrases, start)
	local index = start // 8 + 1
	if index < 2 or not phrases[index] then return 0 end
	return phrases[index].energy - phrases[index - 1].energy
end
local ENDS = {drums = true, tops = true, texture = true, fx = true}
local PRIORITY = {"drums", "bass", "tops", "stab", "keys", "pad", "arp", "lead", "counter", "texture"}
local totals = {blocks = 0, fills = 0, rolls = 0, risers = 0, impacts = 0, cuts = 0, halftime = 0, swept = 0}
for _, s in ipairs(samples) do
	local plan_, track_, composer = s.plan, s.track, s.composer
	local name = where(s)
	local PHRASE = track_.phraseBars
	t.expect(#plan_.lanes <= Model.channels, name .. " plays on eight channels at most")
	local seen = {}
	for _, lane in ipairs(plan_.lanes) do
		t.expect(not seen[lane.part], name .. " one lane to a " .. lane.part)
		seen[lane.part] = true
		t.expect(track_.byRole[lane.part] ~= nil, name .. " " .. lane.part .. " is a channel of the track")
		t.expect(plan_:row(lane.part) ~= nil, name .. " lanes are channels of their track")
		t.expect(#lane.blocks > 0, name .. " arranges no empty lane")
		local stop = 0
		for _, b in ipairs(lane.blocks) do
			totals.blocks = totals.blocks + 1
			t.expect(b.start >= stop and b.length > 0, name .. " " .. lane.part .. " blocks never overlap")
			t.expect(b.start >= 0 and b.start + b.length <= plan_.length, name .. " " .. lane.part .. " blocks stay in the track")
			stop = b.start + b.length
			local pattern = composer.patterns[b.pattern]
			t.expect(pattern ~= nil, name .. " " .. b.pattern .. " is a pattern")
			if pattern then t.assertEqual(pattern.part, lane.part, name .. " " .. b.pattern .. " plays on its own lane") end
			-- Blocks come from the track's palette, bar the system patterns.
			if not isSystem(b) then
				local list = lane.part == "fx" and track_.palette.fx.any or track_.palette[lane.part]
				local ok = false
				for _, block in ipairs(list or {}) do ok = ok or block.id == b.pattern end
				ok = ok or (lane.part == "drums" and track_.palette.halftime and track_.palette.halftime.id == b.pattern)
				t.expect(ok, name .. " " .. b.pattern .. " is from the palette")
			end
			if b.offset then t.expect(b.offset + b.length <= b.whole, name .. " a piece lies inside its whole block") end
			if b.filter then totals.swept = totals.swept + 1 end
		end
	end
	t.expect(plan_:lane("drums") ~= nil, name .. " always has drums")

	-- Moves land on phrase boundaries: a block starts or ends on one, or is a
	-- one-to-four bar move at a phrase's end (or an impact, the bar after one).
	for _, lane in ipairs(plan_.lanes) do
		for _, b in ipairs(lane.blocks) do
			for _, edge in ipairs({b.start, b.start + b.length}) do
				if edge > 0 and edge < plan_.length then
					local toEnd = (PHRASE - edge % PHRASE) % PHRASE
					local impact = lane.part == "fx" and b.length == 1 and edge == b.start + 1 and b.start % PHRASE == 0
					t.expect(toEnd == 0 or toEnd == 1 or toEnd == 2 or toEnd == 4 or impact, string.format(
						"%s %s %s edge at bar %d is %d bars from a phrase end", name, lane.part, b.pattern, edge, toEnd))
				end
			end
		end
	end
	-- Layers change only at phrase boundaries: bars of a phrase play what its first bar does,
	-- bar the last four, which drop-outs and fills may take.
	for p, phrase in ipairs(plan_.phrases) do
		for _, role in ipairs(PRIORITY) do
			local first = false
			for _, b in ipairs(roleBlocks(plan_, role)) do
				if not isBlend(b) and b.start <= phrase.start and phrase.start < b.start + b.length then first = true end
			end
			local limit = (role == "drums" or role == "tops" or role == "bass") and 4 or PHRASE
			for bar = phrase.start, phrase.start + limit - 1 do
				local here = false
				for _, b in ipairs(roleBlocks(plan_, role)) do
					if not isBlend(b) and b.start <= bar and bar < b.start + b.length then here = true end
				end
				t.expect(here == first, string.format("%s %s enters and leaves only on phrase boundaries (phrase %d bar %d)", name, role, p, bar))
			end
		end
	end
	-- Intro and outro keep to drums, tops, texture and fx, and the blend of the DJ mix; their drums are light.
	for _, phrase in ipairs(plan_.phrases) do
		if phrase.edge then
			for _, lane in ipairs(plan_.lanes) do
				for _, b in ipairs(lane.blocks) do
					if b.start < phrase.start + phrase.length and b.start + b.length > phrase.start then
						t.expect(ENDS[lane.part] or isBlend(b), string.format("%s edge phrase at %d plays %s %s", name, phrase.start, lane.part, b.pattern))
						if lane.part == "drums" and not isSystem(b) then
							t.assertEqual(b.variant, "light", name .. " the drums of an edge phrase play their light variant")
						end
					end
				end
			end
		else
			for _, b in ipairs(roleBlocks(plan_, "drums")) do
				if not isSystem(b) and b.start >= phrase.start and b.start < phrase.start + phrase.length then
					t.assertEqual(b.variant, nil, name .. " the drums of a phrase in the middle play in full")
				end
			end
		end
	end
	-- Valley phrases.
	for p, phrase in ipairs(plan_.phrases) do
		if phrase.valley then
			local drumless = true
			for _, b in ipairs(roleBlocks(plan_, "drums")) do
				if b.start < phrase.start + phrase.length and b.start + b.length > phrase.start then drumless = false end
			end
			if drumless then
				for _, role in ipairs({"drums", "tops"}) do
					for _, b in ipairs(roleBlocks(plan_, role)) do
						t.expect(b.start >= phrase.start + phrase.length or b.start + b.length <= phrase.start,
							name .. " a drumless valley has no " .. role)
					end
				end
				local sounding = 0
				for _, lane in ipairs(plan_.lanes) do
					if lane.part ~= "fx" then
						for _, b in ipairs(lane.blocks) do
							if b.start < phrase.start + phrase.length and b.start + b.length > phrase.start then sounding = sounding + 1 end
						end
					end
				end
				t.expect(sounding >= 1, name .. " a drumless valley keeps something playing")
			end
		end
	end
	-- Fills and rolls.
	for _, b in ipairs(roleBlocks(plan_, "drums")) do
		if b.pattern == "drums.fill" then
			totals.fills = totals.fills + 1
			t.assertEqual(b.length, 1, name .. " a fill is one bar")
			t.assertEqual((b.start + 1) % PHRASE, 0, name .. " at the last bar of a phrase")
			t.expect(type(b.under) == "string" and composer.patterns[b.under] ~= nil, name .. " a fill names the groove it interrupts")
			t.assertEqual(composer.patterns[b.under].part, "drums", name .. " a drum groove")
			t.expect(not b.under:match("^drums%."), name .. " not another fill")
			t.expect(math.type(b.phase) == "integer" and b.phase >= 0, name .. " and where in it")
		elseif b.pattern == "drums.roll" then
			totals.rolls = totals.rolls + 1
			t.assertEqual((b.start + b.length) % PHRASE, 0, name .. " a roll ends at a phrase end")
			t.expect(b.length >= 1 and b.length <= 4, name .. " a roll is up to four bars")
			t.expect(type(b.under) == "string" and composer.patterns[b.under] ~= nil, name .. " a roll names its groove")
			t.expect(rise(plan_.phrases, b.start + b.length) >= 0.2 - 1e-9, name .. " and winds up to a rise")
		end
	end
	-- Events.
	local last = -1
	for _, event in ipairs(plan_.events) do
		t.expect(KINDS[event.kind], name .. " event " .. event.kind .. " is a known kind")
		t.expect(event.bar >= 0 and event.bar < plan_.length, name .. " event " .. event.kind .. " is in the track")
		t.expect(event.bar >= last, name .. " events are in order")
		last = event.bar
		if event.kind == "valley" then
			local phrase, i = plan_:phraseAt(event.bar)
			t.expect(phrase.valley and phrase.start == event.bar and not (plan_.phrases[i - 1] or {}).valley, name .. " a valley event opens a valley")
		elseif event.kind == "return" then
			local phrase, i = plan_:phraseAt(event.bar)
			t.expect(not phrase.valley and phrase.start == event.bar and plan_.phrases[i - 1].valley, name .. " a return follows a valley")
		elseif event.kind == "lift" then
			t.assertEqual(event.bar, track_.lift.bar, name .. " the lift event is the track's lift")
		elseif event.kind == "drumsOut" then
			totals.cuts = totals.cuts + 1
			t.expect(plan_:blocksAt(event.bar).drums == nil, name .. " the drums are out at a drumsOut")
			local gap = PHRASE - event.bar % PHRASE
			t.expect(gap == 1 or gap == 2 or gap == 4, name .. " for one, two or four bars at the end of a phrase")
			local phrase, i = plan_:phraseAt(event.bar)
			t.expect(not phrase.edge and not phrase.valley and phrase.energy >= 0.6, name .. " in a high phrase that is not at the edge")
		elseif event.kind == "halftime" then
			totals.halftime = totals.halftime + 1
			t.assertEqual(event.bar % PHRASE, 0, name .. " half-time begins on a phrase")
			local b = plan_:blocksAt(event.bar).drums
			t.expect(b ~= nil and track_.palette.halftime and b.pattern == track_.palette.halftime.id, name .. " on the half-time block")
			t.expect(plan_:phraseAt(event.bar).energy >= 0.6, name .. " in a high phrase")
		end
	end
	for _, phrase in ipairs(plan_.phrases) do
		local found = {}
		for _, event in ipairs(plan_.events) do if event.bar == phrase.start then found[event.kind] = true end end
		local _, i = plan_:phraseAt(phrase.start)
		local before = plan_.phrases[i - 1]
		t.assertEqual(found.valley == true, i > 1 and phrase.valley and not before.valley or false, name .. " every valley is an event at " .. phrase.start)
		t.assertEqual(found["return"] == true, i > 1 and not phrase.valley and before.valley or false, name .. " and every return at " .. phrase.start)
	end
	if track_.lift then
		local found = false
		for _, event in ipairs(plan_.events) do found = found or (event.kind == "lift" and event.bar == track_.lift.bar) end
		t.expect(found, name .. " a lift is an event")
	end

	-- Risers, impacts and downlifters.
	local fxLane = roleBlocks(plan_, "fx")
	for _, b in ipairs(fxLane) do
		local block = composer.catalogue:get(b.pattern)
		if block.kind == "riser" then
			totals.risers = totals.risers + 1
			t.expect(s.style ~= "techno" and s.style ~= "breakbeat", name .. " " .. s.style .. " plays no risers")
			t.assertEqual(b.start + b.length, math.ceil((b.start + 1) / PHRASE) * PHRASE, name .. " a riser ends on a phrase start")
			t.expect(b.length <= 8, name .. " in eight bars at most")
			t.expect(rise(plan_.phrases, b.start + b.length) >= 0.2 - 1e-9, name .. " before a rise of at least 0.2")
			local found = false
			for _, event in ipairs(plan_.events) do found = found or (event.kind == "riser" and event.bar == b.start) end
			t.expect(found, name .. " and the timeline names it")
		elseif block.kind == "impact" then
			totals.impacts = totals.impacts + 1
			t.assertEqual(b.length, 1, name .. " an impact is one bar")
			t.assertEqual(b.start % PHRASE, 0, name .. " on the first bar of a phrase")
			t.expect(rise(plan_.phrases, b.start) >= 0.2 - 1e-9, name .. " after a rise")
		elseif block.kind == "downlifter" then
			t.assertEqual((b.start + b.length) % PHRASE, 0, name .. " a downlifter ends on a phrase")
			t.expect(rise(plan_.phrases, b.start + b.length) <= -0.25 + 1e-9, name .. " before a fall")
		end
	end
	for _, event in ipairs(plan_.events) do
		if event.kind == "riser" then
			local b = Arrangement.blockAt(plan_:lane("fx"), event.bar)
			t.expect(b ~= nil and composer.catalogue:get(b.pattern).kind == "riser" and b.start == event.bar, name .. " a riser event is a riser block")
		end
	end
end
t.expect(totals.blocks > 3000, "the sample holds many blocks: " .. totals.blocks)
t.expect(totals.fills > 100 and totals.rolls >= 3 and totals.risers > 10 and totals.impacts > 5 and totals.cuts > 20
	and totals.halftime > 3, string.format("the sample holds fills %d, rolls %d, risers %d, impacts %d, drop-outs %d, half-time %d",
	totals.fills, totals.rolls, totals.risers, totals.impacts, totals.cuts, totals.halftime))

-- The active lanes follow the curve: the higher the energy, the more layers play.
local lowest = 1
for _, s in ipairs(samples) do
	local plan_ = s.plan
	local energies, active = {}, {}
	for _, phrase in ipairs(plan_.phrases) do
		local n = 0
		for _, lane in ipairs(plan_.lanes) do
			if lane.part ~= "fx" then
				for _, b in ipairs(lane.blocks) do
					if not isBlend(b) and b.start <= phrase.start and phrase.start < b.start + b.length then n = n + 1 end
				end
			end
		end
		table.insert(energies, phrase.energy)
		table.insert(active, n)
	end
	local r = correlation(energies, active)
	if r then
		lowest = math.min(lowest, r)
		t.expect(r > 0.6, string.format("%s: the layers playing follow the energy curve (correlation %.2f)", where(s), r))
	end
end

-- Risers: only before a real rise, and the dozen styles that play them play them.
do
	local playing = {}
	for _, s in ipairs(samples) do
		for _, event in ipairs(s.plan.events) do
			if event.kind == "riser" then playing[s.style] = (playing[s.style] or 0) + 1 end
		end
	end
	t.assertEqual(playing.techno, nil, "techno plays no risers")
	t.assertEqual(playing.breakbeat, nil, "nor does breakbeat")
	t.expect((playing.trance or 0) > 0 and (playing.dnb or 0) > 0 and (playing.dubstep or 0) > 0, "trance, dnb and dubstep do")
end

-- Reproducible, and not the same twice.
for _, id in ipairs({"dnb", "techno", "house", "trance", "dubstep", "breakbeat", "garage"}) do
	local first = {}
	for k = 0, 3 do
		first[k] = serialize(Styles:create(id, 11):arrangement(k))
		t.assertEqual(first[k], serialize(Styles:create(id, 11):arrangement(k)), id .. " track " .. k .. " is drawn from its seed alone")
	end
	-- Asked in another order it is the same track.
	local late = Styles:create(id, 11)
	t.assertEqual(serialize(late:arrangement(3)), first[3], id .. " track 3 is the same whether or not 0 to 2 were asked for")
	local signatures, curves, lengths = {}, {}, {}
	for seed = 1, 8 do
		local plan_ = Styles:create(id, seed):arrangement(0)
		signatures[serialize(plan_)] = true
		local energies = {}
		for _, phrase in ipairs(plan_.phrases) do table.insert(energies, string.format("%.3f", phrase.energy)) end
		curves[table.concat(energies, " ")] = true
		lengths[plan_.length] = true
	end
	t.assertEqual(count(signatures), 8, id .. " every seed arranges its own first track")
	t.expect(count(curves) >= 7, id .. " and draws its own curve: " .. count(curves))
	local tracks, tracksCurves = {}, {}
	local set = Styles:create(id, 5)
	for k = 0, 7 do
		tracks[serialize(set:arrangement(k))] = true
		local energies = {}
		for _, phrase in ipairs(set:arrangement(k).phrases) do table.insert(energies, string.format("%.3f", phrase.energy)) end
		tracksCurves[table.concat(energies, " ")] = true
	end
	t.assertEqual(count(tracks), 8, id .. " the tracks of a set are different arrangements")
	t.assertEqual(count(tracksCurves), 8, id .. " with different curves")
end
do
	-- The same seed in two styles is two different sets.
	local a, b = Styles:create("dnb", 9):arrangement(0), Styles:create("house", 9):arrangement(0)
	t.expect(serialize(a) ~= serialize(b), "two styles under one seed arrange differently")
end
-- Flavours give different shapes: a flat curve keeps its energy in a narrow band.
do
	local flatRange, defaultRange, flatCount, defaultCount = 0, 0, 0, 0
	for _, s in ipairs(samples) do
		local lo, hi = 1, 0
		for _, phrase in ipairs(s.plan.phrases) do lo, hi = math.min(lo, phrase.energy), math.max(hi, phrase.energy) end
		if s.style == "techno" then
			flatRange, flatCount = flatRange + hi - lo, flatCount + 1
		elseif s.style == "dnb" or s.style == "trance" or s.style == "dubstep" then
			defaultRange, defaultCount = defaultRange + hi - lo, defaultCount + 1
		end
	end
	t.expect(flatCount > 0 and defaultCount > 0, "the sample holds techno and the styles that build")
	t.expect(flatRange / flatCount < defaultRange / defaultCount, string.format(
		"techno's flatter curve spans less energy than the styles that build: %.2f against %.2f", flatRange / flatCount, defaultRange / defaultCount))
	-- Flavours of one style differ in what they play, not only in tempo.
	for _, id in ipairs({"dnb", "trance", "house", "garage"}) do
		local byFlavour = {}
		for _, s in ipairs(samples) do
			if s.style == id then
				local ids = {}
				for _, lane in ipairs(s.plan.lanes) do for _, b in ipairs(lane.blocks) do ids[b.pattern] = true end end
				local roles = {}
				for _, lane in ipairs(s.plan.lanes) do table.insert(roles, lane.part) end
				byFlavour[s.track.flavour.id] = byFlavour[s.track.flavour.id] or {}
				table.insert(byFlavour[s.track.flavour.id], {ids = ids, roles = table.concat(roles, " ")})
			end
		end
		local names = {}
		for flavourId in pairs(byFlavour) do table.insert(names, flavourId) end
		table.sort(names)
		t.expect(#names >= 2, id .. " plays more than one flavour in the sample")
		for i = 1, #names do
			for j = i + 1, #names do
				local shared, total = 0, 0
				for _, one in ipairs(byFlavour[names[i]]) do
					for pattern in pairs(one.ids) do
						total = total + 1
						for _, other in ipairs(byFlavour[names[j]]) do if other.ids[pattern] then shared = shared + 1 break end end
					end
				end
				t.expect(shared < total, id .. " " .. names[i] .. " and " .. names[j] .. " do not play the same blocks")
			end
		end
	end
end
-- No two consecutive tracks start on the same drums block.
do
	local clashes, pairsOf = 0, 0
	for _, s in ipairs(samples) do
		if s.previous then
			local mine, theirs = s.plan:blocksAt(0).drums, samples[1] and nil
			for _, o in ipairs(samples) do
				if o.style == s.style and o.seed == s.seed and o.k == s.k - 1 then theirs = o.plan:blocksAt(0).drums end
			end
			pairsOf = pairsOf + 1
			if mine and theirs and mine.pattern == theirs.pattern then clashes = clashes + 1 end
			t.expect(mine and theirs and mine.pattern ~= theirs.pattern,
				where(s) .. " mixes in on another drums block than the track before: " .. tostring(mine and mine.pattern))
		end
	end
	t.assertEqual(clashes, 0, "no consecutive tracks of a set begin on the same loop (of " .. pairsOf .. ")")
end
-- The mix: a new track opens on the outgoing pad and bass.
for _, s in ipairs(samples) do
	local plan_, name = s.plan, where(s)
	local pad, bass = roleBlocks(plan_, "pad")[1], roleBlocks(plan_, "bass")[1]
	if s.k == 0 then
		t.expect(not (pad and isBlend(pad)) and not (bass and isBlend(bass)), name .. " the first track has nothing to blend")
	else
		if s.previous.byRole.pad and s.track.byRole.pad then
			t.assertEqual(pad.pattern .. " " .. pad.start .. " " .. pad.length, "pad.blend 0 " .. s.track.blendBars, name .. " opens on the outgoing pad")
		end
		if s.previous.byRole.bass and s.track.byRole.bass then
			t.assertEqual(bass.pattern .. " " .. bass.start .. " " .. bass.length, "bass.blend 0 " .. s.track.blendBars // 2,
				name .. " and half as long on the outgoing bass")
		end
		if not s.previous.byRole.pad and pad then t.expect(not isBlend(pad), name .. " no pad to blend") end
	end
	local filtered = roleBlocks(plan_, "bass")
	local lastBass = filtered[#filtered]
	if lastBass and lastBass.start + lastBass.length == plan_.length and lastBass.filter then
		t.assertEqual(lastBass.filter.kind, "lowpass", name .. " the mix-out closes the bass through a low-pass")
		t.expect(lastBass.filter.to < 0.5, name .. " nearly shut at the end")
	end
end
do
	-- Canvas.blendIn alone.
	local lanes_ = Lanes.new({length = 32, index = 1, blendBars = 8})
	Canvas.blendIn(lanes_, {length = 32, index = 1, blendBars = 8}, {byRole = {pad = {}, bass = {}}})
	t.assertEqual(lanes_.byPart.pad.blocks[1].pattern .. lanes_.byPart.pad.blocks[1].length, "pad.blend8", "the pad blends for the blend")
	t.assertEqual(lanes_.byPart.bass.blocks[1].pattern .. lanes_.byPart.bass.blocks[1].length, "bass.blend4", "the bass for half of it")
	lanes_ = Lanes.new({length = 32})
	Canvas.blendIn(lanes_, {index = 0, blendBars = 8}, {byRole = {pad = {}}})
	t.assertEqual(#lanes_:done(), 0, "the first track blends nothing")
	Canvas.blendIn(lanes_, {index = 1, blendBars = 8}, nil)
	t.assertEqual(#lanes_:done(), 0, "nor one with nothing before it")
	Canvas.blendIn(lanes_, {index = 1, blendBars = 8}, {byRole = {texture = {}}})
	t.assertEqual(#lanes_:done(), 0, "a track after one without a pad or bass has nothing to blend")
end

-- Arranging a hand-made track, with every roll of the dice forced.
do
	local custom = Blocks.catalogue({{
		spec("drums", 1, {energy = 0.2, density = 0.2, tags = {"mixable"}}), spec("drums", 2, {energy = 0.9, density = 0.8}),
		spec("bass", 1, {energy = 0.5}), spec("fx", 1, {kind = "riser", energy = 0.6}), spec("fx", 2, {kind = "impact", energy = 0.6}),
		spec("pad", 1, {energy = 0.5, comp = "0:16"}),
	}})
	local function arranged(overrides, curve)
		local a = Canvas.arc(overrides)
		local phrases = {}
		for i = 0, 15 do
			table.insert(phrases, {start = i * 8, length = 8, energy = curve[i + 1], edge = i < 2 or i > 13,
				valley = false, label = "x"})
		end
		local channels = {channel("drums"), channel("bass"), channel("pad"), channel("fx")}
		local byRole = {}
		for _, c in ipairs(channels) do byRole[c.role] = c end
		local track_ = {index = 0, length = 128, arc = a, phrases = phrases, channels = channels, byRole = byRole,
			flavour = {id = "liquid"}, blendBars = 8, phraseBars = 8, tempo = 140}
		track_.palette = Canvas.palette(track_, custom, "dnb", StyleKit.random(1))
		local lanes_, events = Canvas.arrange(track_, StyleKit.random(2), nil)
		return lanes_, events, track_
	end
	local rising = {0.2, 0.25, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.2, 0.2}
	local lanes_, events = arranged({riser = 1, roll = 1, impact = 1, fill = 0, kickOut = 0, halftime = 0, fadeIn = 0,
		morph = 0, swap = 0, riserBars = {4}}, rising)
	local byPart = {}
	for _, lane in ipairs(lanes_) do byPart[lane.part] = lane end
	local kinds = {}
	for _, e in ipairs(events) do kinds[e.kind .. e.bar] = true end
	t.expect(kinds.riser60, "with riser 1 the big rise at bar 64 has a riser four bars before it")
	local roll
	for _, b in ipairs(byPart.drums.blocks) do if b.pattern == "drums.roll" then roll = b end end
	t.expect(roll and roll.start == 60 and roll.length == 4 and roll.under, "with roll 1 the drums wind up under it")
	local impact
	for _, b in ipairs(byPart.fx.blocks) do if b.pattern == "dnb.fx.002" then impact = b end end
	t.expect(impact and impact.start == 64 and impact.length == 1, "and an impact lands on the first bar after")
	local risers = 0
	for _, b in ipairs(byPart.fx.blocks) do if b.pattern == "dnb.fx.001" then risers = risers + 1 end end
	t.assertEqual(risers, 1, "one rise, one riser")
	for _, b in ipairs(byPart.drums.blocks) do t.expect(b.pattern ~= "drums.fill", "with fill 0 the phrases end on no fill") end
	-- With riser 0 there is none, and the impact still lands.
	lanes_, events = arranged({riser = 0, roll = 1, impact = 1, fill = 0, kickOut = 0, halftime = 0}, rising)
	for _, e in ipairs(events) do t.expect(e.kind ~= "riser", "riser 0 places no riser") end
	byPart = {}
	for _, lane in ipairs(lanes_) do byPart[lane.part] = lane end
	for _, b in ipairs(byPart.drums.blocks) do t.expect(b.pattern ~= "drums.roll", "and no roll winds up to nothing") end
	-- With impact 0 none lands.
	lanes_ = arranged({riser = 1, impact = 0, fill = 0, kickOut = 0, halftime = 0}, rising)
	for _, lane in ipairs(lanes_) do
		if lane.part == "fx" then for _, b in ipairs(lane.blocks) do t.expect(b.pattern ~= "dnb.fx.002", "impact 0 places no impact") end end
	end
	-- Fills: every phrase ends on one when asked.
	lanes_ = arranged({riser = 0, impact = 0, fill = 1, kickOut = 0, halftime = 0}, rising)
	local fills = {}
	for _, lane in ipairs(lanes_) do
		if lane.part == "drums" then
			for _, b in ipairs(lane.blocks) do if b.pattern == "drums.fill" then table.insert(fills, b.start) end end
		end
	end
	t.expect(#fills >= 10, "with fill 1 almost every phrase ends on a fill: " .. #fills)
	for _, start in ipairs(fills) do t.assertEqual((start + 1) % 8, 0, "each on a phrase's last bar") end
	-- A gentle curve brings no riser even when asked.
	local gentle = {}
	for i = 1, 16 do gentle[i] = 0.5 + 0.02 * i end
	_, events = arranged({riser = 1, impact = 1, kickOut = 0}, gentle)
	for _, e in ipairs(events) do t.expect(e.kind ~= "riser", "a rise of less than 0.2 has no riser") end
	-- Drop-outs: with kickOut 1 the drums leave the end of a high phrase.
	local plateau = {0.2, 0.3, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.3, 0.2}
	lanes_, events = arranged({riser = 0, impact = 0, fill = 0, kickOut = 1, kickOutBars = {2}, halftime = 0, bassOut = 1}, plateau)
	local outs = 0
	for _, e in ipairs(events) do
		if e.kind == "drumsOut" then
			outs = outs + 1
			t.assertEqual(e.bar % 8, 6, "a two-bar drop-out starts two bars before a phrase end")
		end
	end
	t.expect(outs >= 3, "drop-outs are a move, not a run: " .. outs)
	t.expect(outs <= 6, "they leave phrases between them: " .. outs)
end

-- The composer's bars over the plan ----------------------------------------------

local composer = Styles:create("dnb", 9)
local model = Model.new(9, dnbStyle)
local plan0, plan1 = composer:arrangement(0), composer:arrangement(1)
local track0, track1 = composer.set:track(0), composer.set:track(1)
for _, probe in ipairs({{0, 0}, {0, 7}, {0, 8}, {0, 13}, {0, 64}, {0, 100}, {0, plan0.length - 1}, {1, 0}, {1, 9}, {1, 70}}) do
	local plan_, track_ = probe[1] == 0 and plan0 or plan1, probe[1] == 0 and track0 or track1
	local pos = probe[2]
	local n = plan_.start + pos
	local bar = composer:bar(n, model)
	local phrase, index = plan_:phraseAt(pos)
	local name = "track " .. probe[1] .. " bar " .. pos
	t.assertEqual(bar.arc, phrase.energy, name .. " carries its phrase's energy as arc")
	t.assertEqual(bar.label, phrase.label, name .. " carries its phrase's label")
	t.assertEqual(bar.phrase, index, name .. " and its phrase's index")
	t.assertEqual(bar.phraseBar, pos % 8, name .. " and its place in the phrase")
	t.assertEqual(bar.trackBar, pos, name .. " and in the track")
	t.assertEqual(bar.trackLength, plan_.length, name .. " and the track's length")
	t.assertEqual(bar.track, probe[1], name .. " and the track")
	t.assertEqual(bar.index, n, name .. " is the set's bar")
	t.assertEqual(bar.section, nil, name .. " has no section")
	t.assertEqual(bar.sectionBar, nil, name .. " nor a bar of one")
	t.assertEqual(bar.sectionLength, nil, name .. " nor its length")
	t.assertEqual(bar.style, track_.flavour.name, name .. " plays its flavour")
	t.assertEqual(bar.composer, composer, name .. " knows the composer it came from")
	t.assertEqual(bar.key, StyleKit.keyName(composer:tonic(track_, pos), track_.mode), name .. " is in its key")
	local expected = composer:chord(track_, pos)
	t.assertEqual(bar.chord.numeral, expected.numeral, name .. " plays the chord the harmony gives")
	t.assertEqual(bar.chord.root, expected.root, name .. " on its root")
end
-- The bar under the first of the next track is that track's.
do
	local bar = composer:bar(plan1.start, model)
	t.assertEqual(bar.track .. " " .. bar.trackBar .. " " .. bar.phraseBar, "1 0 0", "the set's bar after a track's last is the next track's first")
	t.assertEqual(composer:bar(plan1.start - 1, model).trackBar, plan0.length - 1, "and the bar before is the last of the one before")
	t.assertEqual(composer:bar(plan1.start - 1, model).label, "Mix out", "which is mixing out")
end
-- Harmony: segments tile the track; chords change on barsPerChord boundaries.
for _, s in ipairs(samples) do
	if s.k < 2 then
		local material = s.composer:material(s.track)
		local name = where(s)
		local cursor = 0
		for i, segment in ipairs(material.segments) do
			t.assertEqual(segment.start, cursor, name .. " harmony segment " .. i .. " follows the last")
			t.expect(segment.length > 0 and segment.length <= material.segments[1].length, name .. " segments are as long as the first, or the last shorter")
			if i < #material.segments then t.assertEqual(segment.length, material.segments[1].length, name .. " all but the last the same length") end
			t.expect(#segment.progression > 0 and #segment.voicings == #segment.progression, name .. " each chord has its voicing")
			cursor = cursor + segment.length
		end
		t.assertEqual(cursor, s.track.length, name .. " harmony covers the track")
		t.expect(material.barsPerChord >= 1, name .. " a chord lasts bars")
		t.assertEqual(s.composer:material(s.track), material, name .. " material is written once")
		for pos = 1, s.track.length - 1 do
			local chord, chordBar, segment = s.composer:chord(s.track, pos)
			local before = s.composer:chord(s.track, pos - 1)
			local into = pos - segment.start
			t.assertEqual(chordBar, into % material.barsPerChord, name .. " bar " .. pos .. " counts bars into its chord")
			if into > 0 and chordBar ~= 0 then
				t.assertEqual(chord.numeral .. chord.root, before.numeral .. before.root, name .. " chord holds inside its " .. material.barsPerChord .. " bars at " .. pos)
			end
			if pos >= segment.start and chordBar == 0 and into > 0 and #segment.progression > 1 then
				-- A new chord begins: the degree of the slot.
				local slot = (into // material.barsPerChord) % #segment.progression + 1
				t.assertEqual(chord.degree, segment.progression[slot], name .. " bar " .. pos .. " takes the next chord of the progression")
			end
		end
	end
end
do
	-- A progression changes only at a segment boundary, and then by chance.
	local changes, segments = 0, 0
	for _, s in ipairs(samples) do
		local material = s.composer:material(s.track)
		for i = 2, #material.segments do
			segments = segments + 1
			if material.segments[i].progression ~= material.segments[i - 1].progression then changes = changes + 1 end
		end
	end
	t.expect(segments > 100 and changes > 0 and changes < segments, string.format("progressions sometimes change between segments: %d of %d", changes, segments))
end
-- Key lift and tonic continuity.
do
	local lifted
	for _, s in ipairs(samples) do
		if s.track.lift and not lifted then lifted = s end
	end
	if not lifted then
		-- None in the sample: force one.
		for seed = 1, 60 do
			local style = setmetatable({arc = {lift = 1, riser = 0.8}}, {__index = Styles:get("trance")})
			local forced = Composer.new(style, seed)
			for k = 0, 3 do
				local track_ = forced.set:track(k)
				if track_.lift and not lifted then lifted = {composer = forced, track = track_, k = k, plan = forced:arrangement(k), style = "trance", seed = seed} end
			end
		end
	end
	t.expect(lifted ~= nil, "some track lifts its key")
	if lifted then
		local c, track_, plan_ = lifted.composer, lifted.track, lifted.plan
		local at = track_.lift.bar
		t.assertEqual(c:tonic(track_, at - 1), track_.tonic % 12, "the key is the track's before its lift")
		t.assertEqual(c:tonic(track_, 0), track_.tonic % 12, "from its first bar")
		t.assertEqual(c:tonic(track_, at), (track_.tonic + track_.lift.semis) % 12, "and lifted from its lift bar")
		t.assertEqual(c:tonic(track_, plan_.length - 1), (track_.tonic + track_.lift.semis) % 12, "to its last")
		local before, after = c:bar(plan_.start + at - 1, model), c:bar(plan_.start + at, model)
		t.assertEqual(before.tonic, track_.tonic % 12, "the bar before plays in the key")
		t.assertEqual(after.tonic, (track_.tonic + track_.lift.semis) % 12, "the bar after in the lifted key")
		t.expect(before.key ~= after.key, "and names it: " .. before.key .. " then " .. after.key)
		t.assertEqual(before.chord.degree, c:chord(track_, at - 1).degree, "the chord is the one of the harmony")
		-- The same chord in a higher key: the voicing moves with it.
		local low, high = c:chord(track_, at - 1), c:chord(track_, at)
		t.expect(low.root ~= high.root or low.notes[1] ~= high.notes[1], "a lift moves the chords with the key")
		local found = false
		for _, event in ipairs(plan_.events) do found = found or (event.kind == "lift" and event.bar == at) end
		t.expect(found, "the timeline names the lift")
	end
	local flat, lifts = 0, 0
	for _, s in ipairs(samples) do
		if not s.track.lift then
			flat = flat + 1
			for _, pos in ipairs({0, 1, 33, s.track.length - 1}) do
				t.assertEqual(s.composer:tonic(s.track, pos), s.track.tonic % 12, where(s) .. " keeps its tonic at bar " .. pos)
			end
		else
			lifts = lifts + 1
		end
	end
	t.expect(flat > 50, "most tracks keep their key: " .. flat .. " of " .. (flat + lifts))
	-- Harmonic mixing: each track's key is near the one before.
	for _, s in ipairs(samples) do
		if s.previous then
			local step = (s.track.tonic - s.previous.tonic) % 12
			t.expect(step == 0 or step == 7 or step == 5 or step == 3 or step == 9 or step == 2 or step == 10, where(s) .. " is mixed in a related key (" .. step .. ")")
		end
	end
end

-- Bars take their block's automation: a channel rides it through the bar.
do
	-- A track whose intro drums open through a low-pass.
	local ride_, rider
	for seed = 1, 40 do
		local c = Styles:create("dnb", seed)
		local block = c:arrangement(0):blocksAt(0).drums
		if block and block.filter and not rider then rider, ride_ = c, seed end
	end
	t.expect(rider ~= nil, "some intros open their drums through a filter")
	local c = rider
	local plan_ = c:arrangement(0)
	local first = c:bar(0, model)
	t.expect(#first.slices > 0, "the intro plays drums")
	for _, slice in ipairs(first.slices) do t.assertEqual(slice.role, "drums", "a slice names the channel that plays it") end
	local ride = first.automation.drums
	t.expect(ride ~= nil and ride.kind == "lowpass", "the intro's drums play through a low-pass")
	t.expect(ride.filter.from < ride.filter.to and ride.filter.to < 1, "which opens through the bar")
	local before = 0
	for n = 0, 14 do
		local open = c:bar(n, model).automation.drums
		t.assertEqual(open.kind, "lowpass", "bar " .. n .. " rides a low-pass")
		t.expect(open.filter.from >= before - 1e-9 and open.filter.to > open.filter.from, "opening bar by bar")
		t.expect(near(open.filter.from, 0.3 + 0.7 * n / plan_.phrases[1].length / 2), "by an even step: " .. open.filter.from)
		before = open.filter.to
	end
	t.expect(near(c:bar(15, model).automation.drums.filter.to, 1), "until it is open")
	for _, note in ipairs(c:bar(40, model).notes) do
		t.expect(Model.family[note.role] ~= nil and note.patch ~= nil, "a note names its channel and its patch")
	end
	-- A plain block rides nothing; any block with a fade or sweep rides it.
	for _, s in ipairs(samples) do
		if s.k == 0 and s.seed == 3 then
			local plan_s = s.plan
			for pos = 0, plan_s.length - 1, 5 do
				local bar = s.composer:bar(plan_s.start + pos, model)
				for _, lane in ipairs(plan_s.lanes) do
					local b = Arrangement.blockAt(lane, pos)
					if b and model:plays(lane.part) then
						local rides = bar.automation[lane.part]
						if b.level or b.filter then
							t.expect(rides ~= nil and rides.filter ~= nil, where(s) .. " " .. lane.part .. " rides its block at " .. pos)
						else
							t.assertEqual(rides, nil, where(s) .. " " .. lane.part .. " plain block at " .. pos .. " rides nothing")
						end
					end
				end
			end
		end
	end
end
-- A bar plays every block under it, in the key.
do
	local sounds = 0
	for pos = 0, plan0.length - 1, 3 do
		local bar = composer:bar(plan0.start + pos, model)
		for _, lane in ipairs(plan0.lanes) do
			local b = Arrangement.blockAt(lane, pos)
			if b and lane.part ~= "fx" then
				local roles = {}
				for _, h in ipairs(bar.hits) do roles[h.role] = true end
				for _, h in ipairs(bar.slices) do roles[h.role] = true end
				for _, h in ipairs(bar.notes) do roles[h.role] = true end
				if roles[lane.part] then sounds = sounds + 1 end
			end
		end
	end
	t.expect(sounds > 100, "the bars sound the blocks the plan holds: " .. sounds)
end
-- Half-time blocks mark the bar.
for _, s in ipairs(samples) do
	if s.k == 0 then
		for _, event in ipairs(s.plan.events) do
			if event.kind == "halftime" and not s.halftimeChecked then
				s.halftimeChecked = true
				local bar = s.composer:bar(s.plan.start + event.bar, model)
				t.assertEqual(bar.halftime, true, where(s) .. " bar " .. event.bar .. " is half-time")
			end
		end
	end
end

-- The synth: a closed low-pass darkens a channel, a high-pass thins it, a
-- level scales it, and open automation is no change at all.
local function settingsOf() return Model.new(9, dnbStyle) end
-- The loudest phrase of the first track: drums, bass and more play.
local peak = plan0.phrases[1]
for _, phrase in ipairs(plan0.phrases) do if phrase.energy > peak.energy then peak = phrase end end
local function score(ride_)
	-- The loudest phrase's first four bars, over and over, with every channel on `ride_`.
	local source = Styles:create("dnb", 9)
	local barOf = source.bar
	return setmetatable({bar = function(self, n, settings)
		local bar = barOf(source, peak.start + n % 4, settings)
		if ride_ then
			for _, channel_ in ipairs(bar.channels) do bar.automation[channel_.role] = ride_ end
		end
		return bar
	end}, {__index = source})
end
local function render(ride_)
	local synth = Synth.new(settingsOf(), SR, dnbStyle)
	synth:setComposer(score(ride_))
	local out = {}
	synth:render(out, SR)
	return out
end
-- Energy, and how much of it changes sample to sample (brightness).
local function measure(out)
	local sum, rough = 0, 0
	for i = 3, #out, 2 do
		sum = sum + out[i] * out[i]
		rough = rough + (out[i] - out[i - 2]) ^ 2
	end
	return math.sqrt(sum / #out), math.sqrt(rough / #out)
end
local function steady(level_, kind_, opening_)
	return {level = {from = level_, to = level_}, kind = kind_, filter = {from = opening_ or 1, to = opening_ or 1}}
end
local plain = render()
local plainLevel, plainRough = measure(plain)
t.expect(plainLevel > 0, "the peak phrase makes sound")
local open = render(steady(1))
local same = true
for i = 1, #plain do if plain[i] ~= open[i] then same = false end end
t.expect(same, "full level and no filter render exactly as before")
local _, darkRough = measure(render(steady(1, "lowpass", 0.2)))
t.expect(darkRough < plainRough * 0.5, "a closed low-pass takes the highs away")
local thinLevel = measure(render(steady(1, "highpass", 0.2)))
t.expect(thinLevel < plainLevel * 0.6, "a high-pass takes the weight away")
local quietLevel = measure(render(steady(0.25)))
t.expect(quietLevel < plainLevel * 0.5 and quietLevel > 0, "a level turns the channels down")
local fading = measure(render({level = {from = 1, to = 0}, filter = {from = 1, to = 1}}))
t.expect(fading < plainLevel and fading > quietLevel * 0.5, "a fade rides through the bar")
-- After a sweep the channels play as they were.
do
	local source = score()
	local barOf = source.bar
	local swept = setmetatable({bar = function(self, n, settings)
		local bar = barOf(self, n, settings)
		if n == 0 then
			for _, channel_ in ipairs(bar.channels) do bar.automation[channel_.role] = steady(1, "lowpass", 0.2) end
		end
		return bar
	end}, {__index = source})
	local function tail(from)
		local synth = Synth.new(settingsOf(), SR, dnbStyle)
		synth:setComposer(from)
		synth:render({}, math.floor(synth:stepFrames(from:bar(0, settingsOf()).tempo) * 16 + 0.5))
		local out = {}
		synth:render(out, SR)
		return out
	end
	local openAfter, closedAfter = tail(source), tail(swept)
	local settle = 0
	for i = #openAfter - 2000, #openAfter do settle = math.max(settle, math.abs(openAfter[i] - closedAfter[i])) end
	t.expect(settle < 1e-3, "after the sweep the mix plays as it was")
end
-- Chunked rendering matches one long render under automation too.
local function chunked(size)
	local synth = Synth.new(settingsOf(), SR, dnbStyle)
	synth:setComposer(Styles:create("dnb", 9))
	local all = {}
	for _ = 1, SR * 2 // size do
		local out = {}
		synth:render(out, size)
		table.move(out, 1, 2 * size, #all + 1, all)
	end
	return all
end
local whole, pieces = chunked(SR), chunked(SR // 10)
local worst = 0
for i = 1, #pieces do worst = math.max(worst, math.abs(whole[i] - pieces[i])) end
t.expect(#pieces > 0 and worst < 1e-9, "the opening renders the same in any block size")

-- Timeline: a channel's clips are its lane's blocks, with their envelopes.
for _, lane in ipairs(plan0.lanes) do
	local clips = Timeline.clips(plan0, lane.part)
	t.assertEqual(#clips, #lane.blocks, lane.part .. " has a clip to a block")
	local stop = 0
	for _, clip in ipairs(clips) do
		t.expect(clip.start >= stop and clip.length > 0, "a channel's clips never overlap")
		t.expect(clip.from >= 0 and clip.from <= 1 and clip.to >= 0 and clip.to <= 1, "envelopes stay within the clip")
		stop = clip.start + clip.length
	end
end
t.assertEqual(#Timeline.clips(plan0, "nothing"), 0, "a channel the track lacks has no clips")
do
	local opened = Styles:create("dnb", ride_ or 1):arrangement(0)
	local drumClips = Timeline.clips(opened, "drums")
	t.expect(drumClips[1].from < 1 and drumClips[1].to > drumClips[1].from and not drumClips[1].thins, "an intro's drum clip opens from below full")
	-- A high-pass clip thins from below.
	local highpass = Arrangement.new({track = 0, start = 0, length = 8, lanes = {{part = "drums", blocks = {
		{start = 0, length = 8, pattern = "drums.groove", filter = {kind = "highpass", from = 0.2, to = 1}}}}},
		channels = {{role = "drums", name = "Drums"}}, phrases = {{start = 0, length = 8, energy = 0.5}}}, patterns, {"drums"})
	t.assertEqual(Timeline.clips(highpass, "drums")[1].thins, true, "a high-pass clip thins from below")
end
local plans = Timeline.plans(composer, 0)
local data = Timeline.instances(plans)
local clipCount = 0
for _, lane in ipairs(plan0.lanes) do clipCount = clipCount + #lane.blocks end
t.assertEqual(#plans, 1, "far from its end only the playing track is in view")
t.assertEqual(#data, clipCount * Timeline.stride, "the strip draws the clips and nothing else: no ruler, no notes")
t.expect(clipCount > 8, "several to a channel")
for i = 1, #data, Timeline.stride do
	t.expect(data[i] >= 0 and data[i] < Timeline.rowCount, "every instance sits on a channel's row")
	t.expect(data[i + 3] >= 0 and data[i + 3] < #Model.roles, "tinted as its role")
end
t.assertEqual(#Timeline.plans(composer, plan0.length - 4), 2, "near its end the next track comes into view")
-- The headline names the next event of the playing track.
do
	local first = plan0.events[1]
	t.assertEqual(Timeline.headline({plan0}, plan0.start + first.bar - 8):match("^%a[%a%- ]* in 8 bars$") ~= nil, true, "the headline counts bars to the next event")
	t.assertEqual(Timeline.headline({plan0}, plan0.start + first.bar - 1):match(" in 1 bar$") ~= nil, true, "in the singular")
	t.assertEqual(Timeline.headline({plan0}, plan0.start + plan0.length - 3), "Next track in 3 bars", "after the last event the next track")
	local valleyEvent
	for _, e in ipairs(plan0.events) do if e.kind == "valley" and not valleyEvent then valleyEvent = e end end
	if valleyEvent then
		local previous = 0
		for _, e in ipairs(plan0.events) do if e.bar < valleyEvent.bar and e.bar > previous then previous = e.bar end end
		t.assertEqual(Timeline.headline({plan0}, plan0.start + valleyEvent.bar - 8):match("^Breakdown in 8 bars$") ~= nil or previous > valleyEvent.bar - 8, true,
			"a valley is a Breakdown")
	end
end

os.exit(t.summary() and 0 or 1)
