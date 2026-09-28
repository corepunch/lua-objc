_G.__headless = true
-- The arrangement as a producer leaves it: clips with fades and filter
-- sweeps, parts that join late and drop out, and the timeline that draws
-- the clips with their notes inside.
local t = require("TestKit")
local Model = require("apps.dnb.Model")
local Styles = require("apps.dnb.host.Styles")
local StyleKit = require("apps.dnb.host.StyleKit")
local Arrangement = require("apps.dnb.host.Arrangement")
local Synth = require("apps.dnb.models.Synth")
local Timeline = require("apps.dnb.models.Timeline")

local SR = 22050

-- The `nth` section of a plan called `id`.
local function sectionOf(plan, id, nth)
	for _, section in ipairs(plan.sections) do
		if section.id == id then
			nth = (nth or 1) - 1
			if nth == 0 then return section end
		end
	end
end
-- A style with its form pinned, as tests/dnb.test.lua pins the classic one.
local function pinned(id, form, seed)
	local style = Styles:get(id)
	local set = {form = form}
	for k, v in pairs(style.set) do set[k] = v end
	return require("apps.dnb.host.Composer").new(setmetatable({set = set}, {__index = style}), seed)
end
local CLASSIC = {openings = {"build"}, links = {"breakdown build"}, builds = {"roll"},
	intro = {1}, build = {1}, drop = {1}, breakdown = {1}, melodic = {1}, rebuild = {1}}

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
lanes:add("kick", 0, 16, "kick", {filter = {kind = "lowpass", from = 0.2, to = 1}})
local kick = lanes:done()[1]
t.assertEqual(kick.blocks[1].filter.kind, "lowpass", "a block carries its filter sweep")
t.assertEqual(kick.blocks[1].level, nil, "and no fade it was not given")
lanes:cut("kick", 4, 4)
kick = lanes:done()[1]
t.assertEqual(describe(kick), "0+4 8+8", "a cut leaves the block on either side")
t.expect(near(kick.blocks[1].filter.from, 0.2) and near(kick.blocks[1].filter.to, 0.4), "the first piece keeps its stretch of the sweep")
t.expect(near(kick.blocks[2].filter.from, 0.6) and near(kick.blocks[2].filter.to, 1), "and the second piece its own")
t.assertEqual(kick.blocks[2].offset .. " of " .. kick.blocks[2].whole, "8 of 16", "a piece plays on from where the block would be")
t.assertEqual(kick.blocks[1].whole, 16, "both pieces remember the whole")
lanes:cut("kick", 8, 8)
lanes:cut("kick", 0, 4)
t.assertEqual(#lanes:done(), 0, "a lane cut empty is no lane")
lanes:cut("snare", 0, 4)
t.assertEqual(#lanes:done(), 0, "cutting a lane that was never arranged does nothing")

lanes = StyleKit.lanes(track)
lanes:add("hats", 0, 8, "hats")
lanes:add("hats", 8, 8, "hats.full")
lanes:add("hats", 24, 8, "hats")
lanes:automate("hats", 4, 8, {level = {from = 0, to = 1}})
local hats = lanes:done()[1]
t.assertEqual(describe(hats), "0+4 4+4 8+4 12+4 24+8", "a ride splits the blocks at its ends")
t.assertEqual(hats.blocks[1].level, nil, "the bars before it play as they were")
t.expect(near(hats.blocks[2].level.from, 0) and near(hats.blocks[2].level.to, 0.5), "the ride crosses the first block")
t.expect(near(hats.blocks[3].level.from, 0.5) and near(hats.blocks[3].level.to, 1), "and carries on through the next")
t.assertEqual(hats.blocks[3].pattern, "hats.full", "each piece keeps its pattern")
t.assertEqual(hats.blocks[5].level, nil, "blocks outside it are untouched")
t.expect(lanes:plays("hats", 20, 8) and not lanes:plays("hats", 16, 8), "a lane knows where it plays")
t.expect(not lanes:plays("ride", 0, 32), "and a part never arranged plays nowhere")

-- Automation reads along a block.
local level, kind, opening = Arrangement.automation({start = 0, length = 4, level = {from = 0, to = 1},
	filter = {kind = "highpass", from = 1, to = 0}}, 0.5)
t.assertEqual(level .. " " .. kind .. " " .. opening, "0.5 highpass 0.5", "halfway through, a block is halfway along its envelopes")
level, kind = Arrangement.automation({start = 0, length = 4, filter = {kind = "highpass", from = 1, to = 0}}, 0)
t.assertEqual(level .. " " .. tostring(kind), "1 nil", "an open filter is no filter")
t.assertEqual(Arrangement.automation({start = 0, length = 4}, 0.3), 1, "a plain block plays at full level")

-- The plan refuses automation it cannot play.
local patterns = {kick = {part = "kick"}}
local function plan(block)
	return function()
		Arrangement.new({track = 0, start = 0, length = 8, lanes = {{part = "kick", blocks = {block}}},
			sections = {{id = "drop", start = 0, length = 8, cycle = 0}}}, patterns, Model.parts)
	end
end
t.expect(pcall(plan({start = 0, length = 8, pattern = "kick", level = {from = 0, to = 1},
	filter = {kind = "lowpass", from = 0.3, to = 1}})), "a block may fade and sweep")
t.assertThrows(plan({start = 0, length = 8, pattern = "kick", level = {from = 0, to = 2}}), "levels stay within 0…1")
t.assertThrows(plan({start = 0, length = 8, pattern = "kick", level = {from = 0}}), "a fade needs both ends")
t.assertThrows(plan({start = 0, length = 8, pattern = "kick", filter = {kind = "bandpass", from = 0, to = 1}}),
	"filters are low-pass or high-pass")

-- Every style: the producer's moves land in the plan, from the seed alone.
for _, style in ipairs(Styles:list()) do
	local name = style.title
	local composer = Styles:create(style.id, 21)
	local counts = {blocks = 0, swept = 0, faded = 0, pieces = 0, lengths = {}}
	for k = 0, 3 do
		local arranged, twin = composer:arrangement(k), Styles:create(style.id, 21):arrangement(k)
		for i, lane in ipairs(arranged.lanes) do
			t.assertEqual(describe(lane), describe(twin.lanes[i]), name .. " track " .. k .. " " .. lane.part .. " is reproducible")
			t.expect(#lane.blocks > 0, name .. " arranges no empty lane")
			for j, block in ipairs(lane.blocks) do
				counts.blocks = counts.blocks + 1
				counts.lengths[block.length] = true
				if block.filter then
					counts.swept = counts.swept + 1
					t.assertEqual(block.filter.from, twin.lanes[i].blocks[j].filter.from, name .. " sweeps are reproducible")
				end
				if block.level then counts.faded = counts.faded + 1 end
				if block.offset then
					counts.pieces = counts.pieces + 1
					t.expect(block.offset + block.length <= block.whole, name .. " a piece lies inside its whole block")
				end
			end
		end
		-- The intro opens the drums up; the drop plays them open.
		local intro, drop = arranged.sections[1], sectionOf(arranged, "drop")
		local opening = arranged:blocksAt(intro.start + intro.length - 1).kick
		if opening then
			t.assertEqual(opening.filter.kind, "lowpass", name .. " intros open the kick through a low-pass")
			t.expect(opening.filter.to == 1 and opening.filter.from < 1, name .. " which ends wide open")
		end
		t.assertEqual(arranged:blocksAt(drop.start).kick.filter, nil, name .. " drops land unfiltered")
	end
	local lengths = 0
	for _ in pairs(counts.lengths) do lengths = lengths + 1 end
	t.expect(counts.swept > 8, name .. " rides filters")
	-- A style with no melodic parts outside its drops has nothing to fade.
	if style.id == "dnb" then t.expect(counts.faded > 2, name .. " rides fades") end
	t.expect(counts.pieces > 4, name .. " cuts and splits its blocks")
	t.expect(lengths >= 6, name .. " blocks come in many lengths, not whole sections only")
end

-- Bars take their block's automation: every note knows its part, and the
-- notes under a ride carry it.
local composer = pinned("dnb", CLASSIC, 9)
local model = Model.new(9, Styles:get("dnb"))
local arranged = composer:arrangement(0)
local first = composer:bar(0, model)
t.expect(#first.hits > 0, "the intro plays drums")
for _, hit in ipairs(first.hits) do
	t.expect(Model.family[hit.part] ~= nil, "a hit names the part that played it")
	t.expect(hit.lowpass ~= nil and hit.lowpass < 1 and hit.highpass == nil, "the intro's drums play through the low-pass")
end
local kickOpening = {}
for n = 0, 7 do
	for _, hit in ipairs(composer:bar(n, model).hits) do
		if hit.part == "kick" and hit.step == 0 then table.insert(kickOpening, hit.lowpass) end
	end
end
t.assertEqual(#kickOpening, 8, "the kick plays through the intro")
for i = 2, #kickOpening do t.expect(kickOpening[i] > kickOpening[i - 1], "the filter opens bar by bar") end
local dropBar = composer:bar(arranged.sections[3].start, model)
for _, hit in ipairs(dropBar.hits) do
	if hit.part == "kick" then t.expect(hit.lowpass == nil and hit.level == nil, "the drop's kick plays open at full level") end
end
for _, note in ipairs(dropBar.bass) do t.assertEqual(note.part, "sub", "the bass line belongs to the sub") end
-- The tease under a build with the drums gone: the reese opens from
-- nearly shut.
local RISE = {}
for k, v in pairs(CLASSIC) do RISE[k] = v end
RISE.builds = {"rise"}
local rising = pinned("dnb", RISE, 9)
local tease = rising:arrangement(0):blocksAt(12)
t.assertEqual(tease.sub.pattern .. " " .. tease.reese.pattern, "sub.hold reese", "the build teases the bass")
local teased = rising:bar(12, model).bass[1]
t.expect(teased.lowpass < 0.5 and teased.level < 1 and not teased.subOnly, "held low, quiet and filtered")
local later = rising:bar(15, model).bass[1]
t.expect(later.lowpass > teased.lowpass and later.level > teased.level, "and rises towards the drop")
-- A held pad rides its block through the bar.
local breakdown = arranged.sections[4]
t.assertEqual(breakdown.id, "breakdown", "track 0 breaks down after its first drop")
local padRide = composer:bar(breakdown.start, model).automation.pads
t.assertEqual(padRide.kind, "lowpass", "the breakdown's pad opens through a low-pass")
t.expect(padRide.filter.to > padRide.filter.from, "bar by bar")
t.assertEqual(composer:bar(arranged.sections[3].start + 2, model).automation.pads, nil, "a plain block rides nothing")
-- A piece plays its pattern on from where the whole block would be.
local snare = arranged:lane("snare")
for _, block in ipairs(snare.blocks) do
	if block.pattern == "roll.snare" then
		t.assertEqual(block.offset, nil, "the build's roll is one block")
	end
end

-- The synth: a closed low-pass darkens a voice, a high-pass thins it, a
-- level scales it, and open automation is no change at all.
local function settingsOf() return Model.new(9, Styles:get("dnb")) end
local function score(note)
	-- The drop's first bar, over and over, with `note`'s automation on
	-- everything it plays.
	local source = pinned("dnb", CLASSIC, 9)
	local barOf = source.bar
	return setmetatable({bar = function(self, n, settings)
		local bar = barOf(source, arranged.sections[3].start, settings)
		for _, list in ipairs({"hits", "bass", "stabs", "breaks", "keys", "arp", "lead"}) do
			for _, played in ipairs(bar[list]) do
				played.level, played.lowpass, played.highpass = note.level, note.lowpass, note.highpass
			end
		end
		if note.pads then bar.automation.pads = note.pads end
		return bar
	end}, {__index = source})
end
local function render(note)
	local synth = Synth.new(settingsOf(), SR, Styles:get("dnb").sound)
	synth:setComposer(score(note))
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
local plain = render({})
local plainLevel, plainRough = measure(plain)
local open = render({level = 1})
local same = true
for i = 1, #plain do if plain[i] ~= open[i] then same = false end end
t.expect(same, "full level and no filter render exactly as before")
local _, darkRough = measure(render({lowpass = 0.2}))
t.expect(darkRough < plainRough * 0.5, "a closed low-pass takes the highs away")
local thinLevel = measure(render({highpass = 0.2}))
t.expect(thinLevel < plainLevel * 0.6, "a high-pass takes the weight away")
local quietLevel = measure(render({level = 0.25}))
t.expect(quietLevel < plainLevel * 0.5 and quietLevel > 0, "a level turns the part down")
local padded = render({pads = {level = {from = 0, to = 0}, filter = {from = 1, to = 1}}})
local differs = false
for i = 1, #plain do if plain[i] ~= padded[i] then differs = true end end
t.expect(differs, "the pad rides its automation")
-- Chunked rendering matches one long render under automation too.
local function chunked(size)
	local synth = Synth.new(settingsOf(), SR, Styles:get("dnb").sound)
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

-- Timeline: tracks gather parts; clips carry envelopes; notes lie inside.
local known = {}
for _, row in ipairs(Model.tracks) do
	for _, part in ipairs(row.parts) do
		t.expect(Model.family[part] ~= nil and not known[part], part .. " belongs to one track")
		known[part] = true
	end
end
t.expect(not known.halftime and not known.throws and not known.chops, "switches have no track of their own")
local plans = Timeline.plans(composer, 0)
local rows = Timeline.rows(plans)
t.expect(#rows < #arranged.lanes, "tracks merge lanes")
local bass = Timeline.clips(arranged, {"sub", "reese"})
local stop = 0
for _, clip in ipairs(bass) do
	t.expect(clip.start >= stop and clip.length > 0, "a track's clips never overlap")
	t.expect(clip.from >= 0 and clip.from <= 1 and clip.to >= 0 and clip.to <= 1, "envelopes stay within the clip")
	stop = clip.start + clip.length
end
local covered = 0
for _, clip in ipairs(bass) do covered = covered + clip.length end
local union = 0
for pos = 0, arranged.length - 1 do
	local under = arranged:blocksAt(pos)
	if under.sub or under.reese then union = union + 1 end
end
t.assertEqual(covered, union, "clips cover every bar either part plays, once")
local kickClips = Timeline.clips(arranged, {"kick"})
t.expect(kickClips[1].from < 1 and kickClips[1].to == 1 and not kickClips[1].thins, "the intro's kick clip opens from below full")
local thinned = false
for _, clip in ipairs(Timeline.clips(arranged, {"hats", "ride"})) do thinned = thinned or clip.thins end
t.expect(thinned, "a high-pass clip thins from below")
t.assertEqual(#Timeline.clips(arranged, {"keys"}), arranged:lane("keys") and #arranged:lane("keys").blocks or 0,
	"a one-part track has a clip per block")

local data = Timeline.instances(plans, rows)
local clipCount = 0
for _, row in ipairs(rows) do clipCount = clipCount + #Timeline.clips(arranged, row.parts) end
t.assertEqual(#data, clipCount * Timeline.stride, "the strip draws the clips and nothing else: no ruler, no notes")
t.expect(clipCount > #rows, "several to a track")
for i = 1, #data, Timeline.stride do
	t.expect(data[i] >= 0 and data[i] < #rows, "every instance sits on a track's row")
	t.expect(data[i + 3] >= 0 and data[i + 3] < #Model.tracks, "tinted as its track")
end

-- Forms: every track takes its own road, in whole phrases, and a style
-- does not replay another's under the same seed.
local function formOf(plan)
	local parts = {}
	for _, section in ipairs(plan.sections) do table.insert(parts, section.id .. section.length) end
	return table.concat(parts, " ")
end
local builds = {roll = true, stomp = true, sweep = true, rise = true}
for _, style in ipairs(Styles:list()) do
	local name = style.title
	local set = Styles:create(style.id, 9)
	local forms, kinds, count = {}, {}, 0
	for k = 0, 23 do
		local plan = set:arrangement(k)
		local form = formOf(plan)
		if not forms[form] then forms[form], count = true, count + 1 end
		t.assertEqual(form, formOf(Styles:create(style.id, 9):arrangement(k)), name .. " draws a form from the seed alone")
		t.assertEqual(plan.sections[1].id, "intro", name .. " tracks open on an intro")
		t.assertEqual(plan.sections[#plan.sections].id, "outro", name .. " tracks end on an outro")
		local drops, cycle = 0, -1
		for i, section in ipairs(plan.sections) do
			t.assertEqual(section.length % 4, 0, name .. " sections run in whole half-phrases")
			if section.id ~= "build" then t.assertEqual(section.length % 8, 0, name .. " and all but builds in whole phrases") end
			if section.id == "build" then
				t.expect(builds[section.kind], name .. " builds wind up in a known way")
				t.assertEqual(plan.sections[i + 1].id, "drop", name .. " a build leads to a drop")
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
	t.expect(count >= 16, name .. " tracks take different forms: " .. count)
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
t.assertThrows(function() StyleKit.newSet(1, {flavours = {{id = "a", name = "A"}}, form = {bridges = {1}}}) end,
	"a style's form names real fields")
t.assertEqual(formOf(composer:arrangement(0)), "intro8 build8 drop32 breakdown16 build8 drop32 breakdown16 build8 drop32 outro16",
	"a pinned form is played as written")

-- Builds, by kind.
local function buildOf(kind, id)
	local form = {}
	for k, v in pairs(CLASSIC) do form[k] = v end
	form.builds = {kind}
	local plan = pinned(id or "dnb", form, 9):arrangement(0)
	return plan, sectionOf(plan, "build"), sectionOf(plan, "drop")
end
local plan, build, drop = buildOf("roll")
t.assertEqual(plan:blocksAt(build.start).snare.pattern, "roll.snare", "a roll winds the snare up")
t.assertEqual(plan:lane("filter"), nil, "and leaves the mix open")
plan, build, drop = buildOf("stomp")
t.assertEqual(plan:blocksAt(build.start).kick.pattern, "roll.kick", "a stomp winds the kick up")
t.assertEqual(plan:blocksAt(build.start).snare, nil, "with the snare held back")
t.assertEqual(plan:blocksAt(drop.start - 1).snare.pattern, "roll.snare", "until the last bars")
plan, build, drop = buildOf("sweep")
t.assertEqual(plan:blocksAt(build.start).kick.pattern, plan:blocksAt(drop.start).kick.pattern,
	"a filter build plays the drop's groove early")
t.assertEqual(plan:blocksAt(build.start).snare, nil, "without a roll")
local swept = plan:blocksAt(build.start).filter
t.assertEqual(swept.pattern .. " " .. swept.filter.kind, "filter.sweep lowpass", "under a low-pass on the whole mix")
t.expect(swept.filter.from < 0.3 and swept.filter.to == 1, "that opens into the drop")
t.assertEqual(plan:blocksAt(drop.start).filter, nil, "which plays open")
plan, build = buildOf("rise")
for _, part in ipairs({"kick", "snare", "hats", "amen"}) do
	t.assertEqual(plan:blocksAt(build.start + 1)[part], nil, "a rise takes the " .. part .. " away")
end
t.expect(plan:blocksAt(build.start).risers ~= nil, "and leaves the riser")
t.expect(plan:blocksAt(build.start + build.length - 1).sub ~= nil, "over the teased bass")
-- A breakdown with no build closes the mix for the drop to slam out of.
local slam = {}
for k, v in pairs(CLASSIC) do slam[k] = v end
slam.links = {"breakdown"}
plan = pinned("dnb", slam, 9):arrangement(0)
local breakdown = sectionOf(plan, "breakdown")
local closing = plan:blocksAt(breakdown.start + breakdown.length - 1).filter
t.expect(closing ~= nil and closing.filter.from == 1 and closing.filter.to < 0.5, "a breakdown that meets a drop closes the mix")
t.assertEqual(plan:blocksAt(breakdown.start).filter, nil, "over its last bars only")
slam.links = {"double"}
plan = pinned("dnb", slam, 9):arrangement(0)
t.assertEqual(formOf(plan), "intro8 build8 drop32 drop32 drop32 outro16", "a double drop runs drops back to back")

-- The filter lane sweeps the whole mix: closed, the highs are gone; the
-- same bars play as they were once it is open.
local function mixOf(kind, from, to)
	local source = pinned("dnb", CLASSIC, 9)
	local barOf = source.bar
	local synth = Synth.new(settingsOf(), SR, Styles:get("dnb").sound)
	synth:setComposer(setmetatable({bar = function(self, n, settings)
		local bar = barOf(source, arranged.sections[3].start + n, settings)
		if kind and n == 0 then bar.automation.filter = {level = {from = 1, to = 1}, kind = kind, filter = {from = from, to = to}} end
		return bar
	end}, {__index = source}))
	local out = {}
	synth:render(out, synth:stepFrames() * 16 // 1)
	local second = {}
	synth:render(second, SR)
	return out, second
end
local openMix, openAfter = mixOf()
local closedMix, closedAfter = mixOf("lowpass", 0.2, 0.2)
local openLevel, openRough = measure(openMix)
local _, closedRough = measure(closedMix)
t.expect(closedRough < openRough * 0.4, "a closed sweep takes the highs out of the whole mix")
local thinMix = measure((mixOf("highpass", 0.2, 0.2)))
t.expect(thinMix < openLevel * 0.7, "a high-pass sweep takes its weight")
local settle = 0
for i = #openAfter - 2000, #openAfter do settle = math.max(settle, math.abs(openAfter[i] - closedAfter[i])) end
t.expect(settle < 1e-3, "after the sweep the mix plays as it was")

os.exit(t.summary() and 0 or 1)
