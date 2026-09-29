_G.__headless = true
-- The arrangement as a producer leaves it: eight channels of clips with
-- fades and filter sweeps, parts that join late and drop out, the plan a
-- track is arranged from, and the timeline that draws the clips.
local t = require("TestKit")
local Model = require("apps.dnb.Model")
local Styles = require("apps.dnb.host.Styles")
local StyleKit = require("apps.dnb.host.StyleKit")
local Arrangement = require("apps.dnb.host.Arrangement")
local Composer = require("apps.dnb.host.Composer")
local Synth = require("apps.dnb.models.Synth")
local Timeline = require("apps.dnb.models.Timeline")

local SR = 22050
local dnbStyle = Styles:get("dnb")

-- The `nth` section of a plan called `id`.
local function sectionOf(plan, id, nth)
	for _, section in ipairs(plan.sections) do
		if section.id == id then
			nth = (nth or 1) - 1
			if nth == 0 then return section end
		end
	end
end
-- A style with its form pinned, and optionally one flavour whose every
-- channel plays, as tests/dnb.test.lua pins them.
local function pinned(id, form, seed, flavourId, plan)
	local style = Styles:get(id)
	local set = {form = form}
	for k, v in pairs(style.set) do set[k] = v end
	local fields = {set = set}
	if flavourId then
		for _, flavour in ipairs(style.flavours) do
			if flavour.id == flavourId then
				local copy = {}
				for k, v in pairs(flavour) do copy[k] = v end
				copy.form, copy.channels = nil, {}
				if plan then copy.plan = plan end
				for i, channel in ipairs(flavour.channels) do
					local entry = {}
					for k, v in pairs(channel) do entry[k] = v end
					entry.chance = nil
					copy.channels[i] = entry
				end
				fields.flavours = {copy}
			end
		end
	end
	return Composer.new(setmetatable(fields, {__index = style}), seed)
end
local CLASSIC = {openings = {"build"}, links = {"breakdown build"}, builds = {"roll"},
	intro = {1}, build = {1}, drop = {1}, breakdown = {1}, melodic = {1}, rebuild = {1}}
local function form(changes)
	local result = {}
	for k, v in pairs(CLASSIC) do result[k] = v end
	for k, v in pairs(changes) do result[k] = v end
	return result
end

local function near(a, b) return math.abs(a - b) < 1e-9 end
local function describe(lane)
	local parts = {}
	for _, block in ipairs(lane.blocks) do table.insert(parts, block.start .. "+" .. block.length) end
	return table.concat(parts, " ")
end

-- The lane builder: blocks carry automation; cuts and rides split them as
-- an arrange window splits clips.
local track = {length = 32}
local lanes = StyleKit.lanes(track)
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

lanes = StyleKit.lanes(track)
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
local five = StyleKit.lanes({length = 16, byRole = {drums = {}, bass = {}}})
five:add("drums", 0, 16, "drums.groove")
five:add("pad", 0, 16, "pad.chords")
five:fill("keys", 0, 16, "keys.comp")
t.assertEqual(#five:done(), 1, "a track has no lane for a channel it lacks")
t.expect(five:has("bass") and not five:has("pad"), "and knows which it has")

-- Automation reads along a block.
local level, kind, opening = Arrangement.automation({start = 0, length = 4, level = {from = 0, to = 1},
	filter = {kind = "highpass", from = 1, to = 0}}, 0.5)
t.assertEqual(level .. " " .. kind .. " " .. opening, "0.5 highpass 0.5", "halfway through, a block is halfway along its envelopes")
level, kind = Arrangement.automation({start = 0, length = 4, filter = {kind = "highpass", from = 1, to = 0}}, 0)
t.assertEqual(level .. " " .. tostring(kind), "1 nil", "an open filter is no filter")
t.assertEqual(Arrangement.automation({start = 0, length = 4}, 0.3), 1, "a plain block plays at full level")

-- The plan refuses what it cannot play.
local patterns = {["drums.groove"] = {part = "drums"}, ["bass.line"] = {part = "bass"}}
local function plan(lanes_, sections, order)
	return function()
		return Arrangement.new({track = 0, start = 0, length = 8, lanes = lanes_,
			channels = {{role = "drums", name = "Drums"}, {role = "bass", name = "Bass"}},
			sections = sections or {{id = "drop", start = 0, length = 8, cycle = 0}}}, patterns, order or {"drums", "bass"})
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
t.assertThrows(plan({}, {{id = "drop", start = 0, length = 4, cycle = 0}}), "sections cover every bar")
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

-- Flavours are checked before a set plays.
local library = require("apps.dnb.host.Library").shared()
local function flavour(channels)
	return function()
		StyleKit.newSet(1, {library = library, flavours = {{id = "x", name = "X", channels = channels}}})
	end
end
local kit = {role = "drums", beats = {"break.amen"}}
t.expect(pcall(flavour({kit, {role = "bass", patches = {"bass.sub"}}})), "a flavour names channels, beats and patches")
t.assertThrows(flavour({{role = "bass", patches = {"bass.sub"}}}), "a flavour needs drums")
t.assertThrows(flavour({kit, {role = "bass", patches = {"bass.kazoo"}}}), "patches must exist")
t.assertThrows(flavour({{role = "drums", beats = {"break.polka"}}}), "and beats")
t.assertThrows(flavour({kit, {role = "bass", patches = {"bass.sub"}, lines = {"@yodel"}}}), "and the writers of lines")
t.assertThrows(flavour({kit, {role = "lead", patches = {"lead.saw"}, hooks = {"hook.none"}}}), "and hooks")
t.assertThrows(flavour({kit, {role = "bass"}}), "a pitched channel needs patches")
t.assertThrows(flavour({kit, {role = "cowbell", patches = {"bass.sub"}}}), "roles are real")
t.assertThrows(flavour({kit, {role = "bass", patches = {"bass.sub"}}, {role = "bass", patches = {"bass.sub"}}}),
	"one channel to a role")
local crowd = {kit}
for _, role in ipairs({"tops"}) do table.insert(crowd, {role = role, beats = {"break.funk"}}) end
for _, role in ipairs({"bass", "pad", "keys", "stab", "arp", "lead", "counter"}) do
	table.insert(crowd, {role = role, patches = {"bass.sub"}})
end
t.assertThrows(flavour(crowd), "eight channels at most")
t.assertThrows(function()
	StyleKit.newSet(1, {library = library, flavours = {{id = "x", name = "X", snares = {"cowbell"}, channels = {kit}}}})
end, "flavours name real snare characters")
t.assertThrows(function()
	StyleKit.newSet(1, {library = library, form = {bridges = {1}}, flavours = {{id = "a", name = "A", channels = {kit}}}})
end, "a style's form names real fields")

-- The plan a track is arranged from: entries place blocks by bars, halves,
-- phrases and cycles.
local function arranged(plan_, options)
	options = options or {}
	local byRole = {}
	for _, role in ipairs(options.roles or {"drums", "tops", "bass", "pad", "lead", "fx"}) do byRole[role] = {role = role} end
	local subject = {index = options.index or 0, length = 64, phraseBars = 8, blendBars = 8, seed = 5, byRole = byRole,
		sections = {{id = "intro", start = 0, length = 16, cycle = 0}, {id = "drop", start = 16, length = 32, cycle = 0},
			{id = "drop", start = 48, length = 16, cycle = 1}}}
	local result = {}
	for _, lane in ipairs(StyleKit.arrange(subject, plan_, options.previous)) do result[lane.part] = lane end
	return result
end
-- The producer's moves are drawn from the seed; a plan of pads alone shows
-- the entries as they were placed.
local placed = arranged({
	intro = {pad = {"pad.chords", from = "half"}},
	drop = {pad = {{"pad.chords", to = 4, last = 0}, {"pad.chords", from = -4, cycle = 1}}, fx = {"fx.impact", every = 16}},
})
t.assertEqual(describe(placed.pad), "8+8 16+4 60+4", "entries count bars from a section's start, its half or its end")
t.assertEqual(describe(placed.fx), "16+1 32+1 48+1", "or place a bar every so many")
t.assertEqual(arranged({drop = {keys = "keys.comp"}}).keys, nil, "a role the track has no channel for plays nothing")
local blended = arranged({intro = {pad = "pad.chords", bass = {"bass.hold", from = "blend"}}},
	{index = 1, previous = {byRole = {pad = {}, bass = {}}}})
t.assertEqual(blended.pad.blocks[1].pattern .. " " .. blended.pad.blocks[1].length, "pad.blend 8",
	"a new track opens on the outgoing pad")
t.assertEqual(blended.pad.blocks[2].pattern .. " " .. blended.pad.blocks[2].start, "pad.chords 8", "its own follows the blend")
t.assertEqual(blended.bass.blocks[1].pattern .. " " .. blended.bass.blocks[1].length, "bass.blend 4", "the bass blends for half of it")
t.assertEqual(arranged({intro = {pad = "pad.chords"}}, {index = 1, previous = {byRole = {bass = {}}}}).pad.blocks[1].pattern,
	"pad.chords", "a track that follows one without a pad has nothing to blend")
local merged = StyleKit.planWith(StyleKit.plan, {drop = {lead = false, pad = "pad.chords"}})
t.assertEqual(merged.drop.lead, false, "a style silences a role with false")
t.assertEqual(merged.drop.pad, "pad.chords", "or gives it another entry")
t.assertEqual(merged.drop.bass, StyleKit.plan.drop.bass, "and leaves the rest as it was")
t.expect(StyleKit.plan.drop.lead ~= false, "without changing the plan it started from")
t.assertThrows(function() StyleKit.planWith(StyleKit.plan, {bridge = {}}) end, "a plan names real sections")
t.assertThrows(function() StyleKit.planWith(StyleKit.plan, {drop = {cowbell = "x"}}) end, "and real roles")
-- A part the plan holds to its entry is not delayed.
for seed = 1, 12 do
	local subject = {index = 0, length = 48, phraseBars = 8, blendBars = 8, seed = seed,
		byRole = {drums = {}, tops = {}, stab = {}},
		sections = {{id = "intro", start = 0, length = 16, cycle = 0}, {id = "drop", start = 16, length = 32, cycle = 0}}}
	local result = {}
	for _, lane in ipairs(StyleKit.arrange(subject, {intro = {tops = {"tops.loop", keep = true}, drums = "drums.light"},
		drop = {tops = {"tops.loop", keep = true}, drums = "drums.groove"}})) do result[lane.part] = lane end
	t.assertEqual(result.tops.blocks[1].start, 0, "a kept part opens its intro")
	local opensDrop = false
	for _, b in ipairs(result.tops.blocks) do opensDrop = opensDrop or (b.start <= 16 and b.start + b.length > 16) end
	t.expect(opensDrop, "and its drop")
end

-- Every style: the producer's moves land in the plan, from the seed alone.
for _, style in ipairs(Styles:list()) do
	local name = style.title
	local composer = Styles:create(style.id, 21)
	local counts = {blocks = 0, swept = 0, faded = 0, pieces = 0, fills = 0, lengths = {}}
	for k = 0, 3 do
		local plan_, twin = composer:arrangement(k), Styles:create(style.id, 21):arrangement(k)
		t.expect(#plan_.lanes <= Model.channels, name .. " track " .. k .. " plays on eight channels at most")
		for i, lane in ipairs(plan_.lanes) do
			t.assertEqual(describe(lane), describe(twin.lanes[i]), name .. " track " .. k .. " " .. lane.part .. " is reproducible")
			t.expect(#lane.blocks > 0, name .. " arranges no empty lane")
			t.expect(plan_:row(lane.part) ~= nil, name .. " lanes are channels of their track")
			for j, b in ipairs(lane.blocks) do
				counts.blocks = counts.blocks + 1
				counts.lengths[b.length] = true
				if b.pattern == "drums.fill" then counts.fills = counts.fills + 1 end
				if b.filter then
					counts.swept = counts.swept + 1
					t.assertEqual(b.filter.from, twin.lanes[i].blocks[j].filter.from, name .. " sweeps are reproducible")
				end
				if b.level then counts.faded = counts.faded + 1 end
				if b.offset then
					counts.pieces = counts.pieces + 1
					t.expect(b.offset + b.length <= b.whole, name .. " a piece lies inside its whole block")
				end
			end
		end
		-- The intro opens the drums up; the drop plays them open.
		local intro, drop = plan_.sections[1], sectionOf(plan_, "drop")
		local opening_ = plan_:blocksAt(intro.start + intro.length - 1).drums
		if opening_ then
			t.assertEqual(opening_.filter.kind, "lowpass", name .. " intros open the drums through a low-pass")
			t.expect(opening_.filter.to == 1 and opening_.filter.from < 1, name .. " which ends wide open")
		end
		t.assertEqual(plan_:blocksAt(drop.start).drums.filter, nil, name .. " drops land unfiltered")
		t.expect(plan_:blocksAt(drop.start).bass ~= nil, name .. " drops land on the bass")
		for i, section in ipairs(plan_.sections) do
			local sounding = 0
			for _, lane in ipairs(plan_.lanes) do
				if plan_:plays(lane.part, i) then sounding = sounding + 1 end
			end
			t.expect(sounding > 0, name .. " track " .. k .. " " .. section.id .. " has something to play")
			if section.id == "breakdown" then
				t.expect(not plan_:plays("drums", i), name .. " breakdowns have no drums")
			end
		end
	end
	local lengths = 0
	for _ in pairs(counts.lengths) do lengths = lengths + 1 end
	t.expect(counts.swept > 8, name .. " rides filters")
	t.expect(counts.faded > 2, name .. " rides fades")
	t.expect(counts.pieces > 4, name .. " cuts and splits its blocks")
	t.expect(counts.fills > 6, name .. " ends phrases on fills")
	t.expect(lengths >= 6, name .. " blocks come in many lengths, not whole sections only")
end

-- Bars take their block's automation: a channel rides it through the bar.
local composer = pinned("dnb", CLASSIC, 9, "liquid")
local model = Model.new(9, dnbStyle)
local arranged0 = composer:arrangement(0)
local first = composer:bar(0, model)
t.expect(#first.slices > 0, "the intro plays drums")
for _, slice in ipairs(first.slices) do t.assertEqual(slice.role, "drums", "a slice names the channel that plays it") end
local ride = first.automation.drums
t.expect(ride ~= nil and ride.kind == "lowpass", "the intro's drums play through a low-pass")
t.expect(ride.filter.from < ride.filter.to and ride.filter.to < 1, "which opens through the bar")
local before = 0
for n = 0, 7 do
	local opening_ = composer:bar(n, model).automation.drums.filter
	t.expect(opening_.from >= before - 1e-9 and opening_.to > opening_.from, "and bar by bar")
	before = opening_.to
end
t.expect(near(before, 1), "until it is open")
local dropBar = composer:bar(arranged0.sections[3].start, model)
t.assertEqual(dropBar.automation.drums, nil, "the drop's drums play open at full level")
for _, note in ipairs(dropBar.notes) do
	t.expect(Model.family[note.role] ~= nil and note.patch ~= nil, "a note names its channel and its patch")
end
-- The tease under a build with the drums gone: the bass opens from nearly shut.
local rising = pinned("dnb", form({builds = {"rise"}}), 9, "liquid")
local tease = rising:arrangement(0):blocksAt(12)
t.assertEqual(tease.bass.pattern, "bass.hold", "the build teases the bass")
t.assertEqual(tease.drums, nil, "with the drums gone")
local teased = rising:bar(12, model).automation.bass
t.expect(teased.kind == "lowpass" and teased.filter.from < 0.5 and teased.level.from < 1, "held low, quiet and filtered")
local later = rising:bar(15, model).automation.bass
t.expect(later.filter.to > teased.filter.to and later.level.to > teased.level.to, "and rises towards the drop")
-- A held pad rides its block through the bar.
local breakdown = arranged0.sections[4]
t.assertEqual(breakdown.id, "breakdown", "track 0 breaks down after its first drop")
local padRide = composer:bar(breakdown.start, model).automation.pad
t.assertEqual(padRide.kind, "lowpass", "the breakdown's pad opens through a low-pass")
t.expect(padRide.filter.to > padRide.filter.from, "bar by bar")
t.assertEqual(composer:bar(arranged0.sections[3].start + 26, model).automation.pad, nil, "a plain block rides nothing")

-- The synth: a closed low-pass darkens a channel, a high-pass thins it, a
-- level scales it, and open automation is no change at all.
local function settingsOf() return Model.new(9, dnbStyle) end
local function score(ride_)
	-- The drop's second phrase, over and over, with every channel on `ride_`.
	local source = pinned("dnb", CLASSIC, 9, "liquid")
	local barOf = source.bar
	return setmetatable({bar = function(self, n, settings)
		local bar = barOf(source, arranged0.sections[3].start + 8 + n % 4, settings)
		if ride_ then
			for _, channel in ipairs(bar.channels) do bar.automation[channel.role] = ride_ end
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
			for _, channel in ipairs(bar.channels) do bar.automation[channel.role] = steady(1, "lowpass", 0.2) end
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
t.expect(#pieces > 0 and worst < 1e-9, "the filtered intro renders the same in any block size")

-- Timeline: a channel's clips are its lane's blocks, with their envelopes.
for _, lane in ipairs(arranged0.lanes) do
	local clips = Timeline.clips(arranged0, lane.part)
	t.assertEqual(#clips, #lane.blocks, lane.part .. " has a clip to a block")
	local stop = 0
	for _, clip in ipairs(clips) do
		t.expect(clip.start >= stop and clip.length > 0, "a channel's clips never overlap")
		t.expect(clip.from >= 0 and clip.from <= 1 and clip.to >= 0 and clip.to <= 1, "envelopes stay within the clip")
		stop = clip.start + clip.length
	end
end
t.assertEqual(#Timeline.clips(arranged0, "counter"), 0, "a channel the track lacks has no clips")
local drumClips = Timeline.clips(arranged0, "drums")
t.expect(drumClips[1].from < 1 and drumClips[1].to == 1 and not drumClips[1].thins, "the intro's drum clip opens from below full")
local thinned = false
for k = 0, 3 do
	local plan_ = Styles:create("dnb", 9):arrangement(k)
	for _, clip in ipairs(Timeline.clips(plan_, "tops")) do thinned = thinned or clip.thins end
end
t.expect(thinned, "a high-pass clip thins from below")
local plans = Timeline.plans(composer, 0)
local data = Timeline.instances(plans)
local clipCount = 0
for _, lane in ipairs(arranged0.lanes) do clipCount = clipCount + #lane.blocks end
t.assertEqual(#data, clipCount * Timeline.stride, "the strip draws the clips and nothing else: no ruler, no notes")
t.expect(clipCount > 8, "several to a channel")
for i = 1, #data, Timeline.stride do
	t.expect(data[i] >= 0 and data[i] < Timeline.rowCount, "every instance sits on a channel's row")
	t.expect(data[i + 3] >= 0 and data[i + 3] < #Model.roles, "tinted as its role")
end

-- Forms: every track takes its own road, in whole phrases, and a style
-- does not replay another's under the same seed.
local function formOf(plan_)
	local parts = {}
	for _, section in ipairs(plan_.sections) do table.insert(parts, section.id .. section.length) end
	return table.concat(parts, " ")
end
local builds = {roll = true, stomp = true, sweep = true, rise = true}
for _, style in ipairs(Styles:list()) do
	local name = style.title
	local set = Styles:create(style.id, 9)
	local forms, kinds, count = {}, {}, 0
	for k = 0, 23 do
		local plan_ = set:arrangement(k)
		local shape = formOf(plan_)
		if not forms[shape] then forms[shape], count = true, count + 1 end
		t.assertEqual(shape, formOf(Styles:create(style.id, 9):arrangement(k)), name .. " draws a form from the seed alone")
		t.assertEqual(plan_.sections[1].id, "intro", name .. " tracks open on an intro")
		t.assertEqual(plan_.sections[#plan_.sections].id, "outro", name .. " tracks end on an outro")
		local drops, cycle = 0, -1
		for i, section in ipairs(plan_.sections) do
			t.assertEqual(section.length % 4, 0, name .. " sections run in whole half-phrases")
			if section.id ~= "build" then t.assertEqual(section.length % 8, 0, name .. " and all but builds in whole phrases") end
			if section.id == "build" then
				t.expect(builds[section.kind], name .. " builds wind up in a known way")
				t.assertEqual(plan_.sections[i + 1].id, "drop", name .. " a build leads to a drop")
				kinds[section.kind] = true
			else
				t.assertEqual(section.kind, nil, name .. " only builds have a kind")
			end
			if section.id == "drop" then
				drops = drops + 1
				t.assertEqual(section.cycle, cycle + 1, name .. " each drop plays new material")
				cycle = section.cycle
			end
		end
		t.assertEqual(drops, set.set:track(k).cycles, name .. " a track drops once per cycle")
	end
	t.expect(count >= 14, name .. " tracks take different forms: " .. count)
	local kindCount = 0
	for _ in pairs(kinds) do kindCount = kindCount + 1 end
	t.expect(kindCount >= 2, name .. " builds wind up in different ways")
end
local otherForms = 0
for k = 0, 7 do
	if formOf(Styles:create("dnb", 9):arrangement(k)) ~= formOf(Styles:create("house", 9):arrangement(k)) then
		otherForms = otherForms + 1
	end
end
t.expect(otherForms >= 6, "switching style changes the songs' forms, not only their sound")
t.assertEqual(formOf(composer:arrangement(0)), "intro8 build8 drop32 breakdown16 build8 drop32 breakdown16 build8 drop32 outro16",
	"a pinned form is played as written")

-- Builds, by kind.
local function buildOf(kind_)
	local plan_ = pinned("dnb", form({builds = {kind_}}), 9, "liquid"):arrangement(0)
	return plan_, sectionOf(plan_, "build"), sectionOf(plan_, "drop")
end
local plan_, build, drop = buildOf("roll")
t.assertEqual(plan_:blocksAt(build.start).drums.pattern, "drums.roll", "a roll winds the snare up")
t.assertEqual(plan_:blocksAt(build.start).drums.filter, nil, "and leaves it open")
plan_, build, drop = buildOf("stomp")
t.assertEqual(plan_:blocksAt(build.start).drums.pattern, "drums.stomp", "a stomp winds the kick up")
local stomping = pinned("dnb", form({builds = {"stomp"}}), 9, "liquid")
t.assertEqual(#stomping:bar(build.start, model):steps("snare"), 0, "with the snare held back")
t.expect(#stomping:bar(build.start, model):steps("kick") > 0, "under the kick")
t.expect(#stomping:bar(drop.start - 1, model):steps("snare") > 0, "until the last bars")
plan_, build, drop = buildOf("sweep")
t.assertEqual(plan_:blocksAt(build.start).drums.pattern, plan_:blocksAt(drop.start).drums.pattern,
	"a filter build plays the drop's groove early")
t.assertEqual(plan_:blocksAt(build.start).bass.pattern, plan_:blocksAt(drop.start).bass.pattern, "and its bass")
for _, lane in ipairs(plan_.lanes) do
	local swept = Arrangement.blockAt(lane, build.start)
	if swept then
		t.assertEqual(swept.filter.kind, "lowpass", "every channel plays under a low-pass")
		t.expect(swept.filter.from < 0.3, "from nearly shut")
	end
	local last = Arrangement.blockAt(lane, drop.start - 1)
	if last then t.expect(near(last.filter.to, 1), "that opens into the drop") end
end
t.assertEqual(plan_:blocksAt(drop.start).drums.filter, nil, "which plays open")
plan_, build = buildOf("rise")
for _, part in ipairs({"drums", "tops"}) do
	t.assertEqual(plan_:blocksAt(build.start + 1)[part], nil, "a rise takes the " .. part .. " away")
end
t.expect(plan_:blocksAt(build.start).fx ~= nil, "and leaves the riser")
t.expect(plan_:blocksAt(build.start + build.length - 1).bass ~= nil, "over the teased bass")
-- A breakdown with no build closes the mix for the drop to slam out of.
plan_ = pinned("dnb", form({links = {"breakdown"}}), 9, "liquid"):arrangement(0)
local down = sectionOf(plan_, "breakdown")
local closing = 0
for _, lane in ipairs(plan_.lanes) do
	local last = Arrangement.blockAt(lane, down.start + down.length - 1)
	if last then
		closing = closing + 1
		t.expect(last.filter ~= nil and last.filter.kind == "lowpass" and last.filter.to < 0.5,
			lane.part .. " closes down into the drop")
	end
end
t.expect(closing >= 2, "a breakdown that meets a drop closes the mix")
t.assertEqual(plan_:blocksAt(down.start + down.length).drums.filter, nil, "and the drop slams out of it, open")
plan_ = pinned("dnb", form({links = {"double"}}), 9, "liquid"):arrangement(0)
t.assertEqual(formOf(plan_), "intro8 build8 drop32 drop32 drop32 outro16", "a double drop runs drops back to back")

os.exit(t.summary() and 0 or 1)
