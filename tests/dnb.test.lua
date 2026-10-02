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

-- A style optionally pinned to one flavour, every channel of which plays, so
-- that its tracks have a known set of layers. Flavours drawn from the seed
-- are tested below and in tests/dnb_arrangement.test.lua.
local function pinned(id, seed, flavourId)
	local style = Styles:get(id)
	if not flavourId then return Composer.new(style, seed) end
	local fields = {}
	for _, flavour in ipairs(style.flavours) do
		if flavour.id == flavourId then
			local copy = {}
			for k, v in pairs(flavour) do copy[k] = v end
			copy.channels = {}
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

-- Structure is found in the plan, never assumed: the blocks a bar plays, the
-- block under a bar, and the first bar of a track (set bar) that fits.
local function blockOf(composer, block) return composer.patterns[block.pattern].block end
local function isSystem(block) return block.pattern:find("^drums%.fill$") or block.pattern:find("^drums%.roll$")
	or block.pattern:find("%.blend$") end
-- Calls fn(k, plan, track, pos) for every bar of tracks first…last until it
-- returns something; returns that.
local function search(composer, first, last, fn)
	for k = first, last do
		local plan, track = composer:arrangement(k), composer.set:track(k)
		for pos = 0, track.length - 1 do
			local found = fn(k, plan, track, pos)
			if found then return found, k, plan, track, pos end
		end
	end
end
-- The first set bar whose block of `role` is a plain loop (no fill or roll)
-- inside the energy range, or nil.
local function loopBar(composer, role, first, last, low, high)
	local _, _, _, track, pos = search(composer, first or 0, last or 0, function(_, plan, tr, at)
		local block = plan:blocksAt(at)[role]
		local energy = plan:energyAt(at)
		return block and not isSystem(block) and energy >= (low or 0) and energy <= (high or 1)
	end)
	return track and track.start + pos
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
	local parts = {bar.label, bar.chord.root}
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
	t.assertEqual(track.length % track.arc.unit, 0, "a track is a whole number of units of bars")
	t.expect(track.length >= 4 * track.arc.unit, "and at least four of them")
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
		local seen = {}
		for i, channel in ipairs(track.channels) do
			t.expect(not seen[channel.role], name .. " has one channel to a role")
			seen[channel.role] = true
			t.expect(track.byRole[channel.role] == channel, name .. " finds a channel by its role")
			t.expect(type(channel.name) == "string" and #channel.name > 0, name .. " names its channels")
			-- Drums and tops play loops whose sound is the kit's; every other
			-- channel plays a patch of its own.
			local kit = channel.role == "drums" or channel.role == "tops"
			t.expect(kit or channel.patch ~= nil, name .. " gives " .. channel.role .. " a patch to play")
			-- Every channel has blocks to play: its palette.
			local palette = track.palette[channel.role]
			if channel.role == "fx" then
				t.expect(next(track.palette.fx) ~= nil, name .. " has effects blocks for its fx channel")
			else
				t.expect(palette ~= nil and #palette >= 1, name .. " draws blocks for " .. channel.role)
				for _, block in ipairs(palette or {}) do
					t.assertEqual(block.role, channel.role, name .. " palette blocks belong to their channel")
				end
			end
			t.assertEqual(twin.set:track(k).channels[i].name, channel.name, name .. " channels come from the seed alone")
		end
		t.expect(track.tempo >= flavour.tempo[1] and track.tempo <= flavour.tempo[2] and math.type(track.tempo) == "integer",
			name .. " " .. flavour.name .. " plays at a tempo of its own: " .. track.tempo)
		t.expect(track.swing >= flavour.swing[1] and track.swing <= flavour.swing[2], name .. " and a swing of its own")
		-- The canvas: phrases tile the track, one energy to a phrase, ending where
		-- a DJ mixes.
		local cursor = 0
		for _, phrase in ipairs(track.phrases) do
			t.assertEqual(phrase.start, cursor, name .. " phrases tile the track")
			t.expect(phrase.energy >= 0 and phrase.energy <= 1, name .. " phrases have an energy of 0…1")
			cursor = cursor + phrase.length
		end
		t.assertEqual(cursor, track.length, name .. " phrases cover every bar")
		t.assertEqual(track.phrases[1].label, "Mix in", name .. " opens on a mix-in")
		t.assertEqual(track.phrases[#track.phrases].label, "Mix out", name .. " closes on a mix-out")
		t.expect(track.phrases[1].energy < 0.5 and track.phrases[#track.phrases].energy < 0.5,
			name .. " mixes in and out at a low energy")
	end
end

do
-- Variety: what tells one track from the next. Across a set the channels,
-- the instruments on them, the blocks they play, the tempo and the harmony
-- all change.
for _, style in ipairs(Styles:list()) do
	local name = style.title
	local set = Styles:create(style.id, 4)
	local distinct = {racks = {}, basses = {}, grooves = {}, tempos = {}, palettes = {}, lines = {}, harmonies = {}, roles = {}}
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
		local function ids(list)
			local names = {}
			for _, block in ipairs(list or {}) do table.insert(names, block.id) end
			return table.concat(names, "+")
		end
		distinct.grooves[ids(track.palette.drums)] = true
		distinct.lines[ids(track.palette.bass)] = true
		local all = {}
		for _, role in ipairs(Model.roles) do table.insert(all, ids(track.palette[role.id])) end
		distinct.palettes[table.concat(all, "|")] = true
		distinct.tempos[track.tempo] = true
		local harmony = {}
		for _, segment in ipairs(material.segments) do table.insert(harmony, table.concat(segment.progression, "")) end
		distinct.harmonies[track.mode.name .. table.concat(harmony, "/")] = true
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
	t.expect(count(distinct.grooves) >= 4, name .. " draws " .. count(distinct.grooves) .. " different sets of grooves")
	t.expect(count(distinct.tempos) >= 5, name .. " plays at " .. count(distinct.tempos) .. " different tempos")
	t.expect(count(distinct.palettes) >= 15, name .. " draws " .. count(distinct.palettes) .. " different palettes of blocks")
	t.expect(count(distinct.lines) >= 8, name .. " draws " .. count(distinct.lines) .. " different sets of bass lines")
	t.expect(count(distinct.harmonies) >= 5, name .. " tracks have harmony of their own: " .. count(distinct.harmonies))
end
end

do
-- Material: a track keeps its harmony, fills and edits from its seed.
for k = 0, 7 do
	local track = composer.set:track(k)
	local material = composer:material(track)
	t.expect(composer:material(track) == material, "a track's material is written once")
	t.expect(#material.fills > 0 and #material.chops > 0, "a track has fills and break edits")
	t.expect(material.barsPerChord >= 1, "a chord lasts whole bars")
	local cursor = 0
	for _, segment in ipairs(material.segments) do
		t.assertEqual(segment.start, cursor, "harmony runs in segments that tile the track")
		t.expect(#segment.progression > 0 and #segment.voicings == #segment.progression, "each with a voiced progression")
		for _, degree in ipairs(segment.progression) do
			t.expect(not StyleKit.numeral(track.mode, degree):find("°"), "progressions avoid diminished roots")
		end
		for i = 2, #segment.voicings do
			local moved = 0
			for j = 1, #segment.voicings[i] do moved = moved + math.abs(segment.voicings[i][j] - segment.voicings[i - 1][j]) end
			t.expect(moved <= 12, "each chord moves its voices by a few semitones at most")
		end
		cursor = cursor + segment.length
	end
	t.assertEqual(cursor, track.length, "and cover every bar")
	for pos = 0, track.length - 1, 3 do
		local chord, chordBar, segment = composer:chord(track, pos)
		t.assertEqual(chordBar, (pos - segment.start) % material.barsPerChord, "a chord knows how many bars it has sounded")
		t.expect(#chord.notes > 0, "and has its notes")
	end
end
-- Every chord is in the track's key, and a lifted key moves it.
t.assertEqual(composer:tonic(composer.set:track(0), 0), composer.set:track(0).tonic % 12, "a track opens in its own key")
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

-- A track's canvas: phrases carrying an energy, and what plays follows it.
-- The bars of a track name their phrase, its energy and their place in it.
local liquid = pinned("dnb", 9, "liquid")
local track0 = liquid.set:track(0)
local LABELS = {["Mix in"] = true, Groove = true, Lift = true, Peak = true, Release = true, Breakdown = true, ["Mix out"] = true}
local plan0 = liquid:arrangement(0)
local anthem = pinned("dnb", 9, "anthem")
local neuro = pinned("dnb", 9, "neuro")
for pos = 0, track0.length - 1 do
	local bar = liquid:bar(track0.start + pos, settings)
	local phrase, index = plan0:phraseAt(pos)
	if bar.label ~= phrase.label or bar.arc ~= phrase.energy or bar.phrase ~= index
		or bar.phraseBar ~= pos % track0.phraseBars or bar.trackBar ~= pos or bar.trackLength ~= track0.length
		or not LABELS[bar.label] then
		t.expect(false, "bar " .. pos .. " plays its phrase of the plan")
	end
end
t.assertEqual(liquid:bar(0, settings).label, "Mix in", "a track opens with a mix-in")
t.assertEqual(liquid:bar(track0.length - 1, settings).label, "Mix out", "a track ends on a mix-out")
t.assertEqual(liquid:bar(track0.length, settings).label, "Mix in", "and the next track's mix-in follows")
t.assertEqual(liquid:bar(track0.length, settings).trackBar, 0, "on its own first bar")
local opening = liquid:bar(0, settings)
t.assertEqual(#opening:loop("drums"), 16, "the mix-in plays its drums in 16th slices")
t.assertEqual(opening:loop("drums")[1].variant, "light", "the groove without its extra layers")
t.assertEqual(opening.kickSteps[1], 0, "the set opens on a kick")
t.assertEqual(#opening:of("bass"), 0, "the first mix-in holds the bass back")
t.expect(opening.arc < 0.5, "at a low energy")

-- What may play at the ends of a track: drums, tops and texture, and the
-- outgoing track's chords, while the energy is low.
local EDGE = {drums = true, tops = true, texture = true}
for k = 0, 11 do
	local plan, track = composer:arrangement(k), composer.set:track(k)
	for _, phrase in ipairs(plan.phrases) do
		if phrase.edge then
			for pos = phrase.start, phrase.start + phrase.length - 1 do
				for role, block in pairs(plan:blocksAt(pos)) do
					t.expect(EDGE[role] or role == "fx" or block.pattern:find("%.blend$"),
						"track " .. k .. " plays no " .. role .. " while it mixes (bar " .. pos .. ")")
				end
			end
		end
	end
end

do
-- Breakdowns: a fall from a peak, in which the drums leave and the harmony
-- stays. Their bars are found from the events the plan names.
local valleys, returns = 0, 0
for k = 0, 11 do
	local plan, track = composer:arrangement(k), composer.set:track(k)
	for _, event in ipairs(plan.events) do
		if event.kind == "valley" then
			valleys = valleys + 1
			local phrase = plan:phraseAt(event.bar)
			t.assertEqual(phrase.start, event.bar, "a valley begins with its phrase")
			t.expect(phrase.valley and not plan:phraseAt(event.bar - 1).valley, "after one that is none")
			t.assertEqual(composer:bar(track.start + event.bar, settings).label, "Breakdown", "its bars are the breakdown")
			if not plan:blocksAt(event.bar).drums then
				local bar = composer:bar(track.start + event.bar, settings)
				t.assertEqual(#bar:loop("drums") + #bar.kickSteps, 0, "a drumless breakdown has no drums and no kick")
				t.expect(#bar.notes > 0, "but its harmony plays on")
			end
		elseif event.kind == "return" then
			returns = returns + 1
			t.expect(plan:phraseAt(event.bar - 1).valley and not plan:phraseAt(event.bar).valley, "the band returns after a valley")
		end
	end
end
t.expect(valleys >= 4 and returns >= 4, "sets have breakdowns and returns: " .. valleys .. ", " .. returns)
end

do
-- Risers, rolls and impacts: the build into a rise of energy.
local risers, rolls, impacts = 0, 0, 0
for k = 0, 23 do
	local plan, track = composer:arrangement(k), composer.set:track(k)
	for _, lane in ipairs(plan.lanes) do
		for _, block in ipairs(lane.blocks) do
			local pattern = composer.patterns[block.pattern]
			local kind = pattern.block and pattern.block.kind
			if lane.part == "fx" and kind == "riser" then
				risers = risers + 1
				local firstBar = composer:bar(track.start + block.start, settings)
				local lastBar = composer:bar(track.start + block.start + block.length - 1, settings)
				t.expect(firstBar.riser ~= nil and #firstBar:of("fx") == 1, "a riser block carries a riser")
				t.expect(lastBar.riser.to > firstBar.riser.to and firstBar.riser.from < firstBar.riser.to, "which rises")
			elseif lane.part == "fx" and kind == "impact" then
				impacts = impacts + 1
				local bar = composer:bar(track.start + block.start, settings)
				t.assertEqual(bar:steps("crash")[1], 0, "an impact crashes on its first step")
				t.assertEqual(bar.hits[1].role, "fx", "on the effects channel")
				t.expect(bar.riser ~= nil and bar.riser.from > bar.riser.to, "over a downlifter")
				local noFx = composer:bar(track.start + block.start, playing(except("fx")))
				t.assertEqual(#noFx:steps("crash") + (noFx.riser and 1 or 0), 0, "effects off removes crashes and risers")
			elseif block.pattern == "drums.roll" then
				rolls = rolls + 1
				t.expect(blockOf(composer, {pattern = block.under}) ~= nil and block.under ~= nil, "a roll names the groove it interrupts")
				local firstBar = composer:bar(track.start + block.start, settings)
				local lastBar = composer:bar(track.start + block.start + block.length - 1, settings)
				t.assertEqual(#firstBar:loop("drums"), 0, "a roll leaves the groove")
				t.expect(#lastBar.hits >= #firstBar.hits and #firstBar.hits > 0, "and tightens: " .. #firstBar.hits .. " to " .. #lastBar.hits)
			end
		end
	end
end
t.expect(risers >= 4 and rolls >= 2 and impacts >= 4, "sets build with risers, rolls and impacts: " .. risers .. ", " .. rolls .. ", " .. impacts)
end

-- The groove under a bar: a drums block plays its loop in order from the
-- bar it has reached, in 16th slices.
local dropBar = assert(loopBar(liquid, "drums", 0, 0, 0.6), "liquid has a groove at a high energy")
local drop = liquid:bar(dropBar, settings)
local dropBlock = plan0:blocksAt(dropBar - liquid.set:track(0).start).drums
local dropPos = dropBar - track0.start
t.assertEqual(#drop:loop("drums"), 16, "a drop plays its groove")
t.assertEqual(drop:loop("drums")[1].variant, "full", "in full")
t.assertEqual(drop.kickSteps[1], 0, "its kick lands on the downbeat")
local beat = blockOf(liquid, dropBlock).beat
for i, slice in ipairs(drop:loop("drums")) do
	t.assertEqual(slice.slice, ((dropPos - dropBlock.start + (dropBlock.offset or 0)) % beat.bars) * 16 + i - 1,
		"a groove plays its loop in order")
	t.assertEqual(slice.beat, beat, "the beat of the block under the bar")
end
-- Backbeats: two-step blocks put the snare on two and four, half-time on three.
local backbeats = 0
local atRestModel = Model.new(9, dnbStyle)
atRestModel:setValue("complexity", 0)
for k = 0, 11 do
	search(composer, k, k, function(_, plan, track, pos)
		local block = plan:blocksAt(pos).drums
		if block and not isSystem(block) and not block.variant then
			-- Without Complexity, whose chops stutter snares into the last beat.
			local bar = composer:bar(track.start + pos, atRestModel)
			local halftime = blockOf(composer, block).tags.halftime
			local at = {}
			for _, step in ipairs(bar.snareSteps) do at[step] = true end
			if #bar.snareSteps > 0 then
				backbeats = backbeats + 1
				if halftime then
					t.expect(at[8], "a half-time block snares on beat three")
					t.expect(not at[4] and not at[12], "and not on two and four")
				else
					t.expect(at[4] and at[12], "a block of the two-step snares on two and four")
				end
			end
			if halftime then t.expect(bar.halftime, "a half-time block marks its bar for the header") end
		end
	end)
end
t.expect(backbeats > 100, "backbeats were checked: " .. backbeats)

do
-- Bass: lines in the bass register, inside their bars, on the track's patch.
local bassBars = 0
for pos = 0, track0.length - 1 do
	local bar = liquid:bar(track0.start + pos, settings)
	local block = plan0:blocksAt(pos).bass
	for _, note in ipairs(bar:of("bass")) do
		bassBars = bassBars + 1
		t.expect(note.notes[1] >= 24 and note.notes[1] <= 64, "bass notes stay in the bass register: " .. note.notes[1])
		t.expect(note.step + note.length <= 16.5, "bass notes end inside their bar")
		t.expect(note.patch == track0.byRole.bass.patch, "on the track's bass patch")
	end
	t.expect(block ~= nil or #bar:of("bass") == 0, "no bass block, no bass")
end
t.expect(bassBars > 100, "the bass plays: " .. bassBars)
-- Pads: a held chord sounds once for as long as it lasts, in the pad register.
local pads = 0
for pos = 0, track0.length - 1 do
	local block = plan0:blocksAt(pos).pad
	if block and not block.pattern:find("%.blend$") and blockOf(liquid, block).hold then
		local pad = liquid:bar(track0.start + pos, settings):of("pad")
		if #pad > 0 then
			pads = pads + 1
			t.assertEqual(#pad, 1, "a held pad sounds one chord")
			t.assertEqual(#pad[1].notes, 4, "of four notes")
			t.assertEqual(pad[1].length % 16, 0, "held for whole bars")
			t.expect(pad[1].length <= 32, "for the two bars of the chord")
			for _, note in ipairs(pad[1].notes) do
				t.expect(note >= 44 and note <= 76, "pad voicings stay in the pad register: " .. note)
			end
		end
	end
end
t.expect(pads > 0, "held pads sound: " .. pads)
end

-- The mix: a new track's mix-in carries the outgoing tune.
local track1 = liquid.set:track(1)
local blend = liquid:bar(track1.start, settings)
t.expect(blend.blend ~= nil, "a new track mixes in over the outgoing tune")
t.assertEqual(#blend:of("pad"), 1, "carrying its chords")
t.expect(blend:of("pad")[1].patch == track0.byRole.pad.patch, "on the outgoing track's pad")
t.expect(blend:of("bass")[1].patch == track0.byRole.bass.patch, "and its bass")
t.assertEqual(blend.track, 1, "while the drums belong to the new track")
t.assertEqual(liquid:bar(track1.start + 8, settings).blend, nil, "the mix completes within eight bars")
t.assertEqual(liquid:bar(0, settings).blend, nil, "the set's first track has nothing to mix from")
t.assertEqual(liquid:bar(track1.start, settings).label, "Mix in", "and it plays under the new track's mix-in")

-- Energy and Complexity shape the bars, not the plan.
local low, high = Model.new(9, dnbStyle), Model.new(9, dnbStyle)
low:setValue("energy", 0)
high:setValue("energy", 1)
local lowCount, highCount = 0, 0
local peakBars = {}
for pos = 0, track0.length - 1 do
	if plan0:energyAt(pos) >= 0.6 and #peakBars < 48 then table.insert(peakBars, track0.start + pos) end
end
for _, n in ipairs(peakBars) do
	lowCount = lowCount + #liquid:bar(n, low).notes
	highCount = highCount + #liquid:bar(n, high).notes
end
t.expect(highCount > lowCount, "energy adds notes")
t.expect(liquid:bar(dropBar, high):loop("drums")[1].energy and not liquid:bar(dropBar, low):loop("drums")[1].energy,
	"and lets the groove's extra layers in")
local simple, busy = Model.new(9, dnbStyle), Model.new(9, dnbStyle)
simple:setValue("complexity", 0)
busy:setValue("complexity", 1)
local simpleCount, busyCount = 0, 0
for _, n in ipairs(peakBars) do
	simpleCount = simpleCount + #liquid:bar(n, simple).notes
	busyCount = busyCount + #liquid:bar(n, busy).notes
end
t.expect(busyCount > simpleCount, "complexity adds detail")
t.expect(liquid:bar(dropBar, busy):loop("drums")[1].complexity and not liquid:bar(dropBar, simple):loop("drums")[1].complexity,
	"and the groove's ghost notes")

-- The arrangement: each track is a plan of lanes and blocks, fixed before
-- its first bar plays, and bar n plays the blocks under it.
local plan = plan0
t.expect(plan == liquid:arrangement(0), "a track is arranged once")
t.assertEqual(plan.length, track0.length, "the plan spans its track")
t.assertEqual(plan.start, track0.start, "from the track's first bar")
t.assertEqual(plan.tempo, track0.tempo, "at its tempo")
t.assertEqual(plan.phrases[1].label, "Mix in", "the ruler opens on a mix-in")
t.assertEqual(plan.phrases[#plan.phrases].label, "Mix out", "and ends on a mix-out")
for i, phrase in ipairs(plan.phrases) do
	t.assertEqual(phrase.energy, track0.phrases[i].energy, "each phrase carries its energy")
	t.assertEqual(plan:energyAt(phrase.start), phrase.energy, "which the plan reads back")
end
local KINDS = {valley = true, ["return"] = true, lift = true, riser = true, drumsOut = true, halftime = true}
for k = 0, 11 do
	for _, event in ipairs(composer:arrangement(k).events) do
		t.expect(KINDS[event.kind], "events are of a known kind: " .. tostring(event.kind))
		t.expect(event.bar >= 0 and event.bar < composer.set:track(k).length, "and inside their track")
	end
	local previous = -1
	for _, event in ipairs(composer:arrangement(k).events) do
		t.expect(event.bar >= previous, "events are in order")
		previous = event.bar
	end
end
t.assertEqual(#plan.channels, #track0.channels, "the plan names the track's channels")
t.expect(#plan.lanes <= Model.channels, "and has a lane for each, at most")
local last = 0
for _, lane in ipairs(plan.lanes) do
	local row = plan:row(lane.part)
	t.expect(row ~= nil and row > last, "lanes follow the channels' order")
	last = row
end
t.assertEqual(plan.lanes[1].part, "drums", "the drums lead")
-- Every block of a lane is a block of the track's palette (or a fill, a roll
-- or the blend), of the lane's own role.
for k = 0, 11 do
	local arranged, track = composer:arrangement(k), composer.set:track(k)
	local palette = {}
	local function add(list) for _, block in ipairs(list or {}) do palette[block.id] = true end end
	for role, list in pairs(track.palette) do
		if role == "fx" then for _, fx in pairs(list) do add(fx) end elseif role == "halftime" then if list then palette[list.id] = true end else add(list) end
	end
	for _, lane in ipairs(arranged.lanes) do
		for _, block in ipairs(lane.blocks) do
			local pattern = composer.patterns[block.pattern]
			t.assertEqual(pattern.part, lane.part, "a lane plays patterns of its role")
			t.expect(isSystem(block) or palette[block.pattern], "track " .. k .. " plays only blocks of its palette: " .. block.pattern)
		end
	end
end
local blocks = plan:blocksAt(dropPos)
t.assertEqual(blocks.drums.pattern, dropBlock.pattern, "the drum block is under its bar")
for role, block in pairs(blocks) do
	t.expect(block.start <= dropPos and dropPos < block.start + block.length, "every block under a bar covers it: " .. role)
end
for pos = 0, track0.length - 1 do
	local block = plan:blocksAt(pos).drums
	if block and block.pattern == "drums.fill" then
		local under = plan:blocksAt(pos - 1).drums
		t.expect(under ~= nil and block.under == (under.under or under.pattern), "a fill names the groove it ends")
		t.assertEqual(block.length, 1, "and takes one bar")
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
local fxBar = search(anthem, 0, 11, function(_, p, track, pos)
	local block = p:blocksAt(pos).fx
	if block and anthem.patterns[block.pattern].block.kind == "riser" then return track.start + pos end
end)
t.assertEqual(anthem:bar(fxBar, noFx).riser, nil, "effects off removes the build's riser")
t.expect(anthem:bar(fxBar, settings).riser ~= nil, "which is there otherwise")
t.assertEqual(#liquid:bar(dropBar, noFx):loop("drums"), 16, "and leaves the drums alone")

-- Breaks: a jungle tune plays a record's break on its tops channel, layered
-- over the kit; the kit's kick alone pumps the mix.
local jungle = pinned("dnb", 9, "jungle")
local jungleTrack = jungle.set:track(0)
local atRest = Model.new(9, dnbStyle)
atRest:setValue("complexity", 0)
local jungleBar = assert(search(jungle, 0, 3, function(_, p, track, pos)
	local blocks = p:blocksAt(pos)
	if blocks.tops and blocks.drums and not isSystem(blocks.drums) and not isSystem(blocks.tops) then return track.start + pos end
end), "jungle layers its break over the kit somewhere")
local jungleAt = jungle:trackAt(jungleBar)
local jungleBlock = jungle:arrangement(jungleAt.index):blocksAt(jungleBar - jungleAt.start).tops
local record = blockOf(jungle, jungleBlock).beat
local raw = jungle:bar(jungleBar, atRest)
t.assertEqual(record.kit, "break", "jungle's tops are a record's break")
t.assertEqual(#raw:loop("tops"), 16, "the break plays in 16th slices")
for i, slice in ipairs(raw:loop("tops")) do
	t.assertEqual(slice.slice, ((jungleBar - jungleAt.start - jungleBlock.start + (jungleBlock.offset or 0)) % record.bars) * 16 + i - 1,
		"unchopped slices play the loop in order")
end
t.expect(#raw:loop("drums") > 0, "over the kit")
t.assertEqual(#raw.kickSteps, #jungle:bar(jungleBar, playing({"drums"})).kickSteps, "only the kit's kick pumps the mix")
t.assertEqual(#jungle:bar(jungleBar, playing(except("tops"))):loop("tops"), 0, "a muted channel leaves the break out")
t.assertEqual(pinned("dnb", 9, "neuro"):arrangement(0):lane("tops"), nil, "neurofunk has no channel for a break")

do
-- Chops: complexity rearranges slices; at rest the break plays straight.
local chopped, straight = Model.new(9, dnbStyle), Model.new(9, dnbStyle)
chopped:setValue("complexity", 1)
straight:setValue("complexity", 0)
local edits, reversed, straightBars = 0, 0, 0
for k = 0, 2 do
	local jplan, jtrack = jungle:arrangement(k), jungle.set:track(k)
	for pos = 0, jtrack.length - 1 do
		local block = jplan:blocksAt(pos).tops
		if block and not isSystem(block) then
			local n = jtrack.start + pos
			local tops = blockOf(jungle, block).beat
			local base = ((pos - block.start + (block.offset or 0)) % tops.bars) * 16
			straightBars = straightBars + 1
			for i, slice in ipairs(jungle:bar(n, straight):loop("tops")) do
				t.assertEqual(slice.slice, base + i - 1, "at rest the loop plays straight")
			end
			local at = {}
			for _, slice in ipairs(jungle:bar(n, chopped):loop("tops")) do
				t.expect(slice.slice >= 0 and slice.slice < tops.slices, "chops stay inside the break")
				at[slice.step] = slice
				if slice.reverse then reversed = reversed + 1 end
			end
			for step = 0, 15 do
				local slice = at[step]
				if slice and slice.slice ~= base + step then edits = edits + 1 end
			end
		end
	end
end
t.expect(straightBars > 40 and edits > 8, "chops rearrange the break: " .. edits .. " in " .. straightBars .. " bars")
end

do
-- Harmony: modes, extended voice-led chords, no diminished roots.
local modes = {}
for seed = 1, 10 do
	local c = dnb(seed)
	for k = 0, 3 do modes[c.set:track(k).mode.name] = true end
end
for k = 0, 3 do
	local track = composer.set:track(k)
	t.expect(track.key:find(track.mode.name, 1, true) ~= nil, "a track's key names its mode")
end
t.expect(modes.minor and modes.dorian and modes.phrygian, "tracks are drawn from several minor modes")
end

do
-- Modulate: a track may lift its key for its second peak, at the bar its
-- event names.
local lifted = 0
for k = 0, 40 do
	local track, arranged = anthem.set:track(k), anthem:arrangement(k)
	if track.lift then
		lifted = lifted + 1
		local at = track.start + track.lift.bar
		t.expect(anthem:bar(at, settings).key ~= anthem:bar(at - 1, settings).key, "a lift moves the key")
		t.assertEqual(anthem:bar(at, settings).tonic, (track.tonic + track.lift.semis) % 12, "by the semitones it names")
		t.assertEqual(anthem:bar(at - 1, settings).tonic, track.tonic % 12, "from the key it was in")
		local named = false
		for _, event in ipairs(arranged.events) do
			if event.kind == "lift" and event.bar == track.lift.bar then named = true end
		end
		t.expect(named, "and the timeline announces it")
		for pos = track.lift.bar, math.min(track.length - 1, track.lift.bar + 15) do
			for _, b in ipairs(anthem:bar(track.start + pos, settings):of("bass")) do
				t.expect(b.notes[1] >= 24 and b.notes[1] <= 66, "lifted bass stays in the bass register: " .. b.notes[1])
			end
		end
	else
		t.assertEqual(anthem:bar(track.start + 20, settings).tonic, track.tonic % 12, "a track without a lift holds its key")
	end
end
t.expect(lifted >= 3, "some tracks lift their key: " .. lifted)
end

do
-- Half-time: a switch-up with the snare on beat three, named for the header.
local htBar, htTrack, htPlan = search(neuro, 0, 10, function(_, p, track)
	for _, event in ipairs(p.events) do
		if event.kind == "halftime" then return track.start + event.bar end
	end
end)
t.expect(htBar ~= nil, "some phrases switch to half-time")
local ht = neuro:bar(htBar, settings)
t.expect(ht.halftime, "the switch-up is marked for the header")
t.expect(blockOf(neuro, neuro:arrangement(neuro:trackAt(htBar).index):blocksAt(htBar - neuro:trackAt(htBar).start).drums).tags.halftime,
	"on a half-time block")
t.assertEqual(#ht:loop("drums"), 16, "the drums turn to their half-time beat")
t.assertEqual(table.concat(ht.snareSteps, ","):gsub("8,8", "8"), "8", "which puts the snare on beat three")
do
	local before = neuro:arrangement(neuro:trackAt(htBar).index):blocksAt(htBar - 1 - neuro:trackAt(htBar).start).drums
	t.expect(not (before and blockOf(neuro, {pattern = before.under or before.pattern}).tags.halftime), "the drums before it are not")
end
end

do
-- Fills: most phrases end on one, and they vary. A fill is a one-bar block
-- under the groove it ends.
local fillBars, fillKinds = 0, {}
for k = 0, 5 do
	local track = composer.set:track(k)
	local arranged = composer:arrangement(k)
	for pos = 1, track.length - 1 do
		local block = arranged:blocksAt(pos).drums
		if block and block.pattern == "drums.fill" then
			fillBars = fillBars + 1
			t.assertEqual((pos + 1) % track.phraseBars, 0, "a fill ends its phrase")
			local played = composer:bar(track.start + pos, settings)
			local groove = composer.patterns[block.under].block.beat
			local natural = true
			for _, slice in ipairs(played:loop("drums")) do
				if slice.beat ~= groove then fillKinds.beat = true; natural = false end
				if slice.reverse then fillKinds.reverse = true; natural = false end
				if (slice.length or 1) < 1 then fillKinds.retrigger = true; natural = false end
				if slice.rate then fillKinds.tape = true; natural = false end
				if slice.slice ~= ((block.phase) % groove.bars) * 16 + slice.step then natural = false end
			end
			t.expect(not natural or #played:loop("drums") < 16, "a fill breaks the groove")
		end
	end
end
t.expect(fillBars >= 8, "phrases end on fills: " .. fillBars)
t.expect(fillKinds.beat and (fillKinds.reverse or fillKinds.retrigger or fillKinds.tape),
	"some play a fill of their own, others edit the groove")
end

do
-- Throws: dub echoes on the phrase's last bar.
local thrown = false
for pos = 0, track0.length - 1 do
	local bar = liquid:bar(track0.start + pos, settings)
	for _, list in ipairs({bar.slices, bar.notes}) do
		for _, played in ipairs(list) do
			if played.throw then
				thrown = true
				t.assertEqual(pos % 4, 3, "throws land on every fourth bar")
			end
		end
	end
end
t.expect(thrown, "a phrase ends on a throw")
end

-- Arp, lead and the voice that answers it.
local anthemTrack = anthem.set:track(0)
local anthemPlan = anthem:arrangement(0)
local arps, leadNotes, counterNotes = 0, 0, 0
for pos = 0, anthemTrack.length - 1 do
	local bar = anthem:bar(anthemTrack.start + pos, settings)
	for _, a in ipairs(bar:of("arp")) do
		arps = arps + 1
		t.expect(a.notes[1] >= 55 and a.notes[1] <= 108, "arp notes sit above the pads: " .. a.notes[1])
		t.expect(a.step >= 0 and a.step < 16, "arp notes stay in their bar")
	end
	for _, l in ipairs(bar:of("lead")) do
		leadNotes = leadNotes + 1
		t.expect(l.notes[1] >= 55 and l.notes[1] <= 100, "lead notes stay in the lead register: " .. l.notes[1])
		t.expect(l.step + l.length <= 16, "lead notes end inside their bar")
		t.expect(l.patch == anthemTrack.byRole.lead.patch, "on the track's lead")
	end
	for _, c in ipairs(bar:of("counter")) do
		counterNotes = counterNotes + 1
		t.expect(c.patch == anthemTrack.byRole.counter.patch, "the answer has a voice of its own")
	end
end
t.expect(arps > 16 and leadNotes > 16 and counterNotes > 8, "the track carries arpeggio, hook and answer: "
	.. arps .. ", " .. leadNotes .. ", " .. counterNotes)
-- The hook is heard the same way twice: a block loops, so a loop later it
-- returns, in rhythm.
local function tune(c, n)
	local notes = {}
	for _, l in ipairs(c:bar(n, settings):of("lead")) do table.insert(notes, l.step .. ":" .. l.length) end
	return table.concat(notes, " ")
end
local returns = 0
for _, block in ipairs(anthemPlan:lane("lead").blocks) do
	local bars = blockOf(anthem, block).bars
	for pos = block.start, block.start + block.length - 1 - bars do
		returns = returns + 1
		t.assertEqual(tune(anthem, anthemTrack.start + pos), tune(anthem, anthemTrack.start + pos + bars),
			"the hook's bar returns a loop on")
	end
end
t.expect(returns > 8, "hooks loop: " .. returns)


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
-- A bar in which `role` sounds (a note, a hit or a slice starts in it), and
-- one from which a loop of `role` runs for `bars` bars.
local function soundingBar(source, role)
	local only = playing({role})
	return assert(search(source, 0, 3, function(_, _, track, pos)
		local bar = source:bar(track.start + pos, only)
		return #bar.notes + #bar.slices + #bar.hits > 0 and track.start + pos
	end), role .. " sounds somewhere in the first tracks")
end
local function runBar(source, role, bars)
	return assert(search(source, 0, 3, function(_, plan, track, pos)
		local block = plan:blocksAt(pos)[role]
		if not block or isSystem(block) then return false end
		for at = pos + 1, pos + bars - 1 do
			if plan:blocksAt(at)[role] ~= block then return false end
		end
		return track.start + pos
	end), role .. " plays a block for " .. bars .. " bars")
end
local full = Model.new(9, dnbStyle)
local fullBar = assert(loopBar(composer, "drums", 0, 0, 0.6), "the opening track has a groove at a high energy")
local out = render(full, SR * 2, nil, fullBar)
local peak, rms = stats(out)
t.assertEqual(#out, SR * 4, "render writes interleaved stereo frames")
t.expect(peak <= 1, "output is soft-clipped into range")
t.expect(rms > 0.03, "a full drop is audible")
local again = render(full, SR * 2, nil, fullBar)
local identical = true
for i = 1, #out, 97 do if out[i] ~= again[i] then identical = false break end end
t.expect(identical, "rendering is deterministic")

local silent = render(muted, SR)
t.assertEqual(select(1, stats(silent)), 0, "no roles render silence")

local drumsOnly = playing({"drums"})
drumsOnly:setValue("space", 0)
local kickOut = render(drumsOnly, 256, liquid, dropBar)
t.expect(math.abs(kickOut[2 * 64 - 1]) > 0.05, "the kick sounds on the first downbeat")

-- The Mix faders scale the style's balance: the Drums fader silences a
-- drums-only render and leaves a bass-only one alone.
local function level(roles, fader, value, source, start)
	local m = playing(roles)
	m:setValue("space", 0)
	m:setValue(fader, value)
	return select(2, stats(render(m, SR // 2, source or liquid, start or dropBar)))
end
t.assertEqual(level({"drums"}, "drums", 0), 0, "the Drums fader at zero silences the kit")
t.expect(level({"drums"}, "drums", 1.5) > level({"drums"}, "drums", 1), "and above 100% boosts it")
t.assertEqual(level({"bass"}, "drums", 0), level({"bass"}, "drums", 1), "the Drums fader leaves the bass alone")
t.assertEqual(level({"bass"}, "bass", 0), 0, "the Bass fader silences the bass")
t.expect(level({"pad", "keys"}, "chords", 1, liquid, soundingBar(liquid, "keys")) > level({"pad", "keys"}, "chords", 0.3, liquid, soundingBar(liquid, "keys")), "Chords scales the chords")
t.assertEqual(level({"tops"}, "drums", 0, jungle, jungleBar), 0, "a break is drums too")
for _, role in ipairs({"bass", "pad", "keys", "arp", "lead", "tops", "fx"}) do
	local source = (role == "tops") and jungle or (role == "lead" or role == "arp") and anthem or liquid
	local start = soundingBar(source, role)
	local m = playing({role})
	local sound, synth = render(m, SR * 2, source, start)
	local rolePeak, roleLevel = stats(sound)
	t.expect(roleLevel > 0.002 and rolePeak <= 1, role .. " reaches the output on its own")
	t.expect(synth:level(role) > 0, role .. " moves its channel's meter")
	t.assertEqual(synth:level(role == "bass" and "pad" or "bass"), 0, "and no other's")
end

-- A thrown snare echoes through the delay even with Space at zero. The
-- throw comes on the last bar of a four-bar run of the plan, after the blend.
local throwBar = assert(search(liquid, 0, 3, function(_, p, track, pos)
	if pos % 4 ~= 0 or pos < track.blendBars then return false end
	local last = p:blocksAt(pos + 3).drums
	return last and not isSystem(last) and track.start + pos
end), "liquid throws a snare somewhere")
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
	synth.composerBar = throwBar -- whose fourth bar throws its snare
	local tail = {}
	local barFrames = math.floor(16 * SR * 60 / source:trackAt(throwBar).tempo / 4 + 0.5)
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
	local voices = sliceVoices(solo, jungle, runBar(jungle, "tops", 3), SR * 2)
	t.assertEqual(voices, 1, "a straight break plays as one continuous voice")
	local edited = playing({"tops"})
	edited:setValue("complexity", 1)
	t.expect(sliceVoices(edited, jungle, runBar(jungle, "tops", 8), SR * 8) >= 2, "a chop crossfades into a new slice")
end

-- Chunked rendering matches one long render: blocks carry voice state.
local chunked, whole = {}, render(full, 3000, nil, fullBar)
do
	local synth = Synth.new(full, SR, dnbStyle)
	synth:setComposer(dnb(9))
	synth.composerBar = fullBar
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

-- Across a breakdown and a riser the synth stays bounded, deterministic and
-- never goes dead where the music plays on.
do
	local function across(source, model, from, bars)
		local synth = Synth.new(model, SR, dnbStyle)
		synth:setComposer(source)
		synth.composerBar = from
		local frames = math.floor((bars + 0.2) * 16 * SR * 60 / source:trackAt(from).tempo / 4)
		local sound = {}
		synth:render(sound, frames)
		local levels = {}
		for i = 1, bars do
			local bar = synth.timeline[i]
			local peak, sum = 0, 0
			local sane = true
			for frame = bar.frame, bar.frame + bar.frames - 1 do
				for channel = 1, 2 do
					local x = sound[frame * 2 + channel]
					sane = sane and x == x and math.abs(x) <= 1
					peak, sum = math.max(peak, math.abs(x)), sum + x * x
				end
			end
			t.expect(sane, "samples of bar " .. i .. " are finite and in range")
			levels[i] = {rms = math.sqrt(sum / (2 * bar.frames)), peak = peak, bar = bar}
		end
		return levels, sound
	end
	-- A breakdown: the drums leave and the harmony plays on.
	local valleyBar = assert(search(neuro, 0, 10, function(_, p, track)
		for _, event in ipairs(p.events) do
			if event.kind == "valley" then return track.start + event.bar end
		end
	end), "neurofunk has a breakdown")
	local vplan = neuro:arrangement(neuro:trackAt(valleyBar).index)
	local levels, sound = across(neuro, Model.new(9, dnbStyle), valleyBar - 1, 3)
	t.assertEqual(levels[1].bar.label ~= "Breakdown" and levels[2].bar.label, "Breakdown", "the render crosses into the breakdown")
	for i, level in ipairs(levels) do
		t.expect(level.rms > 0.005, "bar " .. i .. " around the breakdown is audible: " .. level.rms)
	end
	local again = select(2, across(neuro, Model.new(9, dnbStyle), valleyBar - 1, 2))
	local same = true
	for i = 1, #again - 4000, 53 do if sound[i] ~= again[i] then same = false break end end
	t.expect(same, "and rendering it twice gives the same samples")
	if not vplan:blocksAt(valleyBar - neuro:trackAt(valleyBar).start).drums then
		t.expect(#levels[2].bar.kicks == 0, "a drumless breakdown has no kicks to flash")
		t.expect(levels[2].rms < levels[1].rms or levels[2].peak < levels[1].peak, "and is the quieter for it")
	end
	-- A riser: an effects channel rising through its block.
	local only = playing({"fx"})
	local rises = across(anthem, only, fxBar, 3)
	for i, level in ipairs(rises) do
		t.expect(level.rms > 0.0005, "riser bar " .. i .. " is audible on its own: " .. level.rms)
		t.expect(level.bar.riser ~= nil, "and marks itself for the visualizer")
	end
	t.expect(rises[3].bar.riser.to > rises[1].bar.riser.to, "rising through the block")
end

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
	if bar.key == dnb(77).set:track(0).key and bar.label == "Mix in" and bar.trackBar == 0 then restarted = bar end
end
t.expect(restarted ~= nil, "a new track starts its own mix-in at the next bar")
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
local bar = {frame = 0, frames = 4000, kicks = {0, 2500}, arc = 1, phraseBar = 3, trackBar = 3, trackLength = 32, number = 3,
	tonic = 6}
local v = visuals:update({bands = {1, 0.5, 0, 0}, rms = 0.2, playing = true, bar = bar, played = 100, sampleRate = 1000}, 1 / 60)
local H = Visuals.header
t.assertEqual(#v, H + 2 * 4, "values hold the header, bands and peaks")
t.expect(v[H + 1] > 0.6 and v[H + 1] < 1, "bars rise quickly but not instantly")
t.assertEqual(v[H + 5], v[H + 1], "a rising bar carries its peak")
t.expect(v[2] > 0.5, "a kick just played flashes")
t.assertEqual(v[3], 0.5, "hue comes from the tonic")
t.assertEqual(v[4], 1, "a peak runs at full intensity")
t.assertEqual(v[5], (3 + 100 / 4000) / 32, "progress is the share of the track played")
t.assertEqual(v[6], 0.1, "beat phase is the position inside the beat")
local peak = v[H + 5]
for _ = 1, 10 do v = visuals:update({playing = true, bar = bar, played = 900, sampleRate = 1000}, 1 / 60) end
t.expect(v[H + 1] < peak, "silence lets bars fall")
t.assertEqual(v[H + 5], peak, "the peak holds while the bar falls")
t.expect(not visuals:settled(), "a moving visualizer is not settled")
for _ = 1, 300 do visuals:update({playing = false}, 1 / 60) end
t.expect(visuals:settled(), "without audio everything comes to rest")
t.assertEqual(visuals.presence, 0, "stopping fades the visualizer back to idle")

-- Scenes: one per phrase, chosen by its energy, crossfaded, back to the
-- horizon at rest.
local scenes = Visuals.new(Visualizers:list(), 4)
local function peakBar(number)
	return {frame = 0, frames = 4000, kicks = {0}, snares = {1000}, arc = 0.9, phraseBar = 0, trackBar = number,
		trackLength = 208, number = number, tonic = 0}
end
local frameAt = function(b) return {playing = true, bar = b, played = 1100, sampleRate = 1000, bands = {0.5, 0.5, 0.5, 0.5}} end
scenes:update(frameAt({frame = 0, frames = 4000, arc = 0.25, phraseBar = 0, trackBar = 0, trackLength = 208, number = 0}), 1 / 60)
t.assertEqual(scenes.scene, Visualizers:index("horizon") - 1, "a low energy opens on the spectrum horizon")
local seen = {}
local current = scenes.scene
for phrase = 0, 11 do
	local b = peakBar(8 + phrase * 8)
	for _ = 1, 120 do scenes:update(frameAt(b), 1 / 60) end
	t.assertEqual(scenes.fade, 0, "a crossfade completes within a phrase")
	t.expect(scenes.scene ~= current or phrase == 0, "each phrase brings a new scene")
	current = scenes.scene
	seen[scenes.scene] = true
	local plugin = Visualizers:list()[scenes.scene + 1]
	t.expect(plugin.arc[1] <= b.arc and b.arc <= plugin.arc[2], plugin.title .. " is a scene for an energy of " .. b.arc)
end
local count = 0
for _ in pairs(seen) do count = count + 1 end
t.expect(count >= 3, "a peak runs through the scenes that suit it: " .. count)
-- Scenes are chosen by energy: a calm phrase gets calm scenes, and nothing
-- changes in the middle of a phrase.
do
	local calm = Visuals.new(Visualizers:list(), 4)
	for phrase = 0, 7 do
		local b = {frame = 0, frames = 4000, arc = 0.1, phraseBar = 0, trackBar = phrase * 8, trackLength = 208,
			number = phrase * 8, tonic = 0}
		for _ = 1, 120 do calm:update(frameAt(b), 1 / 60) end
		local plugin = Visualizers:list()[calm.scene + 1]
		t.expect(plugin.arc[1] <= 0.1, plugin.title .. " is calm enough for an energy of 0.1")
		local shown = calm.scene
		for bar = 1, 7 do
			b.phraseBar, b.number = bar, phrase * 8 + bar
			calm:update(frameAt(b), 1 / 60)
		end
		t.assertEqual(calm.scene, shown, "the scene holds through the phrase's bars")
		t.assertEqual(calm.nextScene, shown, "without a cut in sight")
	end
	t.expect(math.abs(calm.intensity - (0.35 + 0.65 * 0.1)) < 1e-9 and scenes.intensity > calm.intensity, "and the intensity follows the energy")
end
scenes:update(frameAt(peakBar(200)), 1 / 60)
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
local cruiseBar = {frame = 0, frames = 4000, arc = 0.9, phraseBar = 0, trackBar = 0, trackLength = 32, number = 0}
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
t.assertEqual(app.refs.moment.text, "Ready to play", "the header waits for playback")
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
t.assertEqual(app.refs.moment.text, "Mix in", "the header names the phrase the playhead is in")
local values = app.refs.visualizer.values
t.expect(values[7] > 0, "playing fades the visualizer in")
t.expect(values[Visuals.header + 1] > values[Visuals.header + 2], "bars follow the analysed spectrum")
t.assertEqual(values[3], opener.tonic / 12, "the palette follows the track key")
t.assertEqual(app.refs.position.text, "Bar 1 of " .. opener.length, "and shows the bar of the track")

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
t.assertEqual(skipped.label, "Mix in", "entering on its mix-in")
t.expect(skipped.trackBar < 8, "a few bars in")
t.expect(skipped.blend ~= nil, "mixing in over the tune it left")
-- The header follows the energy: a phrase's word, along the whole track.
do
	local c = app.composer
	local plan = c:arrangement(2)
	local first = c:trackStart(2)
	local words, changes, previous = {}, 0, nil
	for pos = 0, plan.length - 1 do
		local bar = c:bar(first + pos, app.model)
		local info = app:nowPlaying(bar)
		local expected = bar.blend and "Mixing in" or (bar.halftime and bar.label == "Peak") and "Half-time"
			or plan:phraseAt(pos).label
		t.assertEqual(info.moment, expected, "bar " .. pos .. " is headed by its phrase")
		t.assertEqual(info.position, string.format("Bar %d of %d", pos + 1, plan.length), "and counted in its track")
		t.assertEqual(info.progress, pos / plan.length, "with the track's progress")
		words[info.moment] = true
		if info.moment ~= previous then changes = changes + 1 end
		previous = info.moment
	end
	local distinct = 0
	for _ in pairs(words) do distinct = distinct + 1 end
	t.expect(distinct >= 5 and changes >= 6, "the header changes along a track: " .. distinct .. " words, " .. changes .. " changes")
	t.assertEqual(app:nowPlaying(c:bar(0, app.model)).moment, "Mix in", "it opens on the mix-in")
	t.assertEqual(app:nowPlaying(c:bar(first + plan.length - 1, app.model)).moment, "Mix out", "and closes on the mix-out")
	t.assertEqual(app:nowPlaying().moment, "Ready to play", "and waits while nothing plays")
	-- A new track mixes in over the last: "Mixing in" while the outgoing
	-- chords sound, then its own phrase's word.
	-- (liquid has the pad and the bass the blend carries.)
	local start = liquid:trackStart(1)
	for pos = 0, liquid.set:track(1).blendBars - 1 do
		t.assertEqual(app:nowPlaying(liquid:bar(start + pos, app.model)).moment, "Mixing in", "bar " .. pos .. " of a new track mixes in")
	end
	t.assertEqual(app:nowPlaying(liquid:bar(start + liquid.set:track(1).blendBars, app.model)).moment, "Mix in",
		"and then plays its own mix-in")
	t.assertEqual(app:nowPlaying(liquid:bar(start, app.model)).detail:find("Track 2", 1, true), 1, "naming the new track")
	-- A half-time phrase of a peak is named for what the drums do.
	local hbar = search(neuro, 0, 10, function(_, p, track, pos)
		local bar = neuro:bar(track.start + pos, app.model)
		return bar.halftime and bar.label == "Peak" and bar
	end)
	t.assertEqual(app:nowPlaying(hbar).moment, "Half-time", "a half-time peak is headed so")
end
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
t.assertEqual(rows[1].name, shown.byRole.drums.name, "the drums are named after their channel")
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
-- The headline names the next event of the plan, in bars, and once the
-- last has passed, the next track.
local TITLES = {valley = "Breakdown", ["return"] = "Full band", lift = "Key lift", riser = "Riser", drumsOut = "Drums out",
	halftime = "Half-time"}
local liquidPlan = near[1]
local firstEvent = assert(liquidPlan.events[1], "liquid has events")
t.assertEqual(Timeline.headline(near, liquidPlan.start + firstEvent.bar - 5), TITLES[firstEvent.kind] .. " in 5 bars",
	"the headline names the next event")
t.assertEqual(Timeline.headline(near, liquidPlan.start + firstEvent.bar - 1), TITLES[firstEvent.kind] .. " in 1 bar", "in bars")
t.assertEqual(Timeline.headline(ending, shown.length - 4), "Next track in 4 bars", "and the next track from the mix-out")
t.assertEqual(Timeline.headline(ending, shown.length - 1), "Next track in 1 bar", "down to the last bar")
local valleyAt
for _, event in ipairs(liquidPlan.events) do
	if event.kind == "valley" and not valleyAt then valleyAt = event.bar end
end
if valleyAt then
	t.assertEqual(Timeline.headline(near, liquidPlan.start + valleyAt - 8), "Breakdown in 8 bars", "a valley is a breakdown")
end
-- Across whole tracks the headline never names anything the plan lacks, and
-- always names the soonest of what it has.
do
	local c, named = dnb(9), {}
	for k = 0, 11 do
		local track, arranged = c.set:track(k), c:arrangement(k)
		local events = {}
		for _, event in ipairs(arranged.events) do events[TITLES[event.kind]] = true end
		for pos = 0, track.length - 1 do
			local n = track.start + pos
			local text = Timeline.headline(Timeline.plans(c, n), n)
			local title, bars = text:match("^(.-) in (%d+) bars?$")
			t.expect(title ~= nil, "a headline is 'Title in N bars': " .. text)
			if title == "Next track" then
				t.assertEqual(n + tonumber(bars), track.start + track.length, "the next track comes when this one ends")
				for _, event in ipairs(arranged.events) do
					t.expect(event.bar <= pos, "and only after the last event of track " .. k .. " (bar " .. pos .. ")")
				end
			else
				named[title] = true
				t.expect(events[title], "track " .. k .. " names only events it has: " .. title)
				local soonest
				for _, event in ipairs(arranged.events) do
					if event.bar > pos then soonest = soonest or event end
				end
				t.assertEqual(soonest.bar - pos, tonumber(bars), "the next event is the soonest")
				t.assertEqual(TITLES[soonest.kind], title, "of its kind")
			end
		end
	end
	t.expect(named.Breakdown and named.Riser and named["Drums out"], "a set's headlines run through its events")
end
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
local openingPlan = timelineApp.composer:arrangement(0)
t.assertEqual(timelineApp.timeline.refs.timelineNext.text,
	Timeline.headline(Timeline.plans(timelineApp.composer, 0), 0), "the header names what comes next")
t.expect(timelineApp.timeline.refs.timelineNext.text:find(TITLES[openingPlan.events[1].kind] .. " in "
	.. openingPlan.events[1].bar .. " bar", 1, true) ~= nil, "when the first event comes")
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
