-- Drum & bass: an endless DJ set of Liquid, Jungle, Neurofunk and Rollers
-- tracks. Two-step grooves with ghost notes, the Amen break layered and
-- chopped, rolling reese and sub, voice-led extended chords, electric-piano
-- comping, arpeggios and a call-and-response lead; half-time switch-ups and
-- dub throws. `arrange` lays each track out as blocks from the seed alone,
-- section by section, and the kit's producer moves cut, stagger and filter
-- them; the patterns under a bar read Energy and Complexity as it plays.

-- Flavours weight the parts a track leans on: whether the arrangement gives
-- a part blocks at all, and how much of it they use. `snares`
-- are the characters its tracks' kits pick from (see StyleKit.snares).
local FLAVOURS = {
	{id = "liquid", name = "Liquid", amen = 0.45, keys = 1, reese = 0.55, lead = 0.9, arp = 0.9, stabs = 0.4, halftime = 0.25,
		snares = {"roomy", "tight", "layered", "vintage"}},
	{id = "jungle", name = "Jungle", amen = 1, keys = 0.5, reese = 0.5, lead = 0.5, arp = 0.4, stabs = 0.7, halftime = 0.2,
		snares = {"vintage", "rimshot", "roomy", "fat"}},
	{id = "neuro", name = "Neurofunk", amen = 0, keys = 0, reese = 1, lead = 0.4, arp = 0.5, stabs = 1, halftime = 0.7,
		snares = {"crunchy", "tight", "layered", "fat"}},
	{id = "rollers", name = "Rollers", amen = 0.6, keys = 0.4, reese = 0.8, lead = 0.6, arp = 0.7, stabs = 0.6, halftime = 0.35,
		snares = {"tight", "fat", "layered", "rimshot", "crunchy"}},
}

local ARRANGEMENT = {
	introBars = 8, buildBars = 8, dropBars = 32, breakdownBars = 16, rebuildBars = 8, outroBars = 16,
	blendBars = 8, phraseBars = 8, minCycles = 2, maxCycles = 3,
}
local HALFTIME = {from = 16, to = 24} -- the switch-up inside a drop
local LEAD_FROM = 16                  -- the melody carries the drop's second half

-- Scale degrees, one chord per two bars.
local PROGRESSIONS = {
	{1, 6, 3, 7}, {1, 4, 6, 5}, {1, 7, 6, 7}, {1, 1, 4, 6},
	{6, 7, 1, 1}, {1, 3, 6, 7}, {1, 6, 4, 5}, {4, 6, 1, 7},
	{1, 4, 7, 3}, {6, 4, 1, 5}, {1, 2, 6, 7}, {4, 5, 3, 6},
}
-- Two-step kick placements; the snare backbeat on steps 4 and 12 is fixed.
local KICKS = {
	{0, 10}, {0, 10}, {0, 6, 10}, {0, 2, 10}, {0, 10, 11}, {0, 7, 10}, {0, 10, 14}, {0, 3, 10},
}
-- Syncopated kicks that complexity adds on top of the groove.
local KICK_EXTRAS = {7, 13, 15, 3, 11}
local GHOST_STEPS = {7, 9, 14, 15, 2, 11, 1, 13, 6, 3}
local PERCUSSION = {"rim", "conga", "shaker"}
-- Bass motif intervals above the chord root, in semitones.
local BASS_INTERVALS = {0, 0, 0, 12, 7, 10, 3, 5, 12, 7}
-- Arpeggio orders over the four chord tones (5–8 are an octave up).
local ARP_ORDERS = {
	{1, 2, 3, 4}, {4, 3, 2, 1}, {1, 2, 3, 4, 3, 2}, {1, 3, 2, 4},
	{1, 2, 3, 4, 5, 6, 7, 8}, {1, 4, 2, 5, 3, 6}, {1, 1, 3, 2, 4, 3},
}
-- Electric-piano comping: off-beat pushes around the downbeat chord.
local KEYS_STEPS = {3, 6, 7, 10, 11, 14}
local FILLS = {"roll", "toms", "stutter", "cut"}
local CHOPS = {"stutter", "swap", "swap", "shuffle"}

-- The material one cycle of a track loops: progression, grooves, bass
-- motif, break chops, comping, arpeggio and melody. Settings-dependent
-- density is decided per bar, so each note carries a threshold rather than
-- being filtered here.
local function buildCycle(kit, rng, track)
	local flavour, mode = track.flavour, track.mode
	local amen = kit.amen
	local progression = kit.stableProgression(mode, rng.pick(PROGRESSIONS))
	local cycle = {
		progression = progression,
		voicings = kit.voicings(mode, progression),
		kicks = rng.pick(KICKS),
		altKicks = rng.pick(KICKS),
		kickExtras = {},
		ghostOrder = rng.shuffle(GHOST_STEPS),
		percussion = {}, bass = {}, variation = {}, stabSteps = {}, keys = {}, chops = {}, fills = {},
		arp = {order = rng.pick(ARP_ORDERS), rate = rng.float() < 0.7 and 1 or 2, mask = {}},
		halftime = rng.float() < flavour.halftime,
		arpOn = rng.float() < flavour.arp,
		leadOn = rng.float() < flavour.lead,
	}
	for _, step in ipairs(KICK_EXTRAS) do
		table.insert(cycle.kickExtras, {step = step, threshold = rng.float()})
	end
	for step = 0, 31 do
		if step % 4 ~= 0 then
			table.insert(cycle.percussion, {step = step, voice = rng.pick(PERCUSSION), chance = rng.float()})
		end
	end
	-- Rolling bass: a long root on the downbeat of each bar, then short
	-- syncopated answers whose count grows with energy. The variation bar
	-- answers every fourth bar with octave jumps and quicker notes.
	local function motif(list, first, last, busy)
		local step = first
		while step < last do
			local downbeat = step == first
			local length = downbeat and (4 + rng.int(3) - 1) or (busy and rng.int(2) or 1 + rng.int(3))
			table.insert(list, {
				step = step,
				length = math.min(length, last - step),
				interval = downbeat and 0 or rng.pick(BASS_INTERVALS),
				glide = not downbeat and rng.float() < 0.35,
				chance = downbeat and 0 or rng.float(),
				detail = rng.float(), -- complexity threshold for the extra 16ths
			})
			step = step + length + (rng.float() < 0.4 and 1 or 0)
		end
	end
	motif(cycle.bass, 0, 16)
	motif(cycle.bass, 16, 32)
	motif(cycle.variation, 0, 16, true)
	for _, s in ipairs({6, 14, 22, 30, 3, 19, 11, 27}) do
		if rng.float() < 0.45 then table.insert(cycle.stabSteps, {step = s, threshold = rng.float()}) end
	end
	if #cycle.stabSteps == 0 then table.insert(cycle.stabSteps, {step = 14, threshold = 0}) end
	for step = 0, 15 do
		-- Downbeats always sound; the rest open up with complexity.
		cycle.arp.mask[step] = step % 4 == 0 and 0 or rng.float()
	end
	for half = 0, 16, 16 do
		table.insert(cycle.keys, {step = half, length = 6, threshold = 0})
		for _, step in ipairs(KEYS_STEPS) do
			if rng.float() < 0.4 then
				table.insert(cycle.keys, {step = half + step, length = 1 + rng.int(3), threshold = rng.float()})
			end
		end
	end
	-- Break edits, the jungle producer's craft: stutter a snare slice, swap
	-- a beat in from another bar, or drop a stray 16th somewhere new.
	for _ = 1, 10 do
		local kind = rng.pick(CHOPS)
		local chop = {kind = kind, bar = rng.int(ARRANGEMENT.phraseBars) - 1, threshold = rng.float()}
		if kind == "stutter" then
			chop.step, chop.length, chop.source = rng.pick({12, 14, 8}), rng.pick({2, 4}), rng.pick(amen.snareSlices)
		elseif kind == "swap" then
			chop.step, chop.length = (rng.int(4) - 1) * 4, 4
			chop.source = (rng.int(amen.bars) - 1) * 16 + (rng.int(4) - 1) * 4
		else
			chop.step, chop.length, chop.source = rng.int(16) - 1, 1, rng.int(amen.slices) - 1
		end
		table.insert(cycle.chops, chop)
	end
	for _ = 1, 6 do table.insert(cycle.fills, rng.pick(FILLS)) end
	cycle.lead = kit.melody(rng)
	return cycle
end

-- The arrangement ------------------------------------------------------------

local function arrange(kit, track, cycles)
	local lanes = kit.lanes(track)
	local flavour = track.flavour
	local amen = flavour.amen
	-- A jungle track opens on the raw break alone; the kit joins halfway.
	local kitFrom = amen >= 1 and ARRANGEMENT.introBars // 2 or 0
	kit.blendIn(lanes, track)
	for _, section in ipairs(track.sections) do
		local id, cycle = section.id, cycles[section.cycle]
		-- Liquid saves the break for a later drop.
		local amenDrop = amen > 0 and (flavour.id ~= "liquid" or section.cycle > 0)
		if id == "intro" then
			if amen >= 1 then lanes:within("amen", section, 0, nil, "amen.raw") end
			lanes:within("kick", section, kitFrom, nil, "kick.groove")
			lanes:within("snare", section, kitFrom, nil, "snare.backbeat")
			lanes:within("hats", section, kitFrom, nil, "hats.open")
			lanes:within("ride", section, kitFrom, nil, "ride.soft")
			if flavour.keys >= 1 then lanes:within("keys", section, track.index > 0 and track.blendBars or 0, nil, "keys") end
		elseif id == "build" then
			local half = section.length // 2
			if amen >= 1 then lanes:within("amen", section, half, nil, "amen.build") end
			lanes:within("snare", section, 0, nil, "roll.snare")
			lanes:within("hats", section, 0, nil, "hats.full")
			if cycle.arpOn then lanes:within("arp", section, half, nil, "arp") end
		elseif id == "drop" then
			if amenDrop then
				lanes:within("amen", section, 0, nil, "amen.drop")
				lanes:within("chops", section, 0, nil, "chops")
			end
			lanes:within("kick", section, 0, nil, "kick.drop")
			lanes:within("snare", section, 0, nil, "snare.drop")
			lanes:within("ghosts", section, 0, nil, "ghosts")
			lanes:within("hats", section, 0, nil, "hats.full")
			lanes:within("ride", section, 0, nil, "ride.drop")
			lanes:within("percussion", section, 0, nil, "perc")
			lanes:within("sub", section, 0, nil, "sub.roll")
			lanes:within("reese", section, 0, nil, "reese")
			lanes:within("stabs", section, 0, nil, "stabs")
			if flavour.keys > 0 then lanes:within("keys", section, ARRANGEMENT.phraseBars, nil, "keys") end
			if cycle.arpOn then lanes:within("arp", section, ARRANGEMENT.phraseBars, nil, "arp.drop") end
			if cycle.leadOn then lanes:within("lead", section, LEAD_FROM, nil, "lead") end
			if cycle.halftime then lanes:within("halftime", section, HALFTIME.from, HALFTIME.to, "halftime") end
			lanes:phraseEnds("throws", section, 4, "throw")
		elseif id == "breakdown" then
			lanes:within("ride", section, 0, nil, "ride.soft")
			lanes:within("sub", section, 0, nil, "sub.hold")
			if flavour.keys > 0 then lanes:within("keys", section, 0, nil, "keys") end
			if cycle.arpOn then lanes:within("arp", section, 0, nil, "arp") end
			if cycle.leadOn then lanes:within("lead", section, section.length // 2, nil, "lead.soft") end
			lanes:phraseEnds("throws", section, 4, "throw")
		elseif id == "outro" then
			-- The groove carries on for the next track's intro to mix over;
			-- the bass settles onto the sub halfway.
			local half = ARRANGEMENT.outroBars // 2
			if amen > 0 then
				lanes:within("amen", section, 0, nil, "amen.outro")
				lanes:within("chops", section, 0, nil, "chops")
			end
			lanes:within("kick", section, 0, nil, "kick.groove")
			lanes:within("snare", section, 0, nil, "snare.backbeat")
			lanes:within("ghosts", section, 0, nil, "ghosts")
			lanes:within("hats", section, 0, nil, "hats.full")
			lanes:within("ride", section, 0, nil, "ride.drop")
			lanes:within("sub", section, 0, half, "sub.roll")
			lanes:within("reese", section, 0, half, "reese")
			lanes:within("sub", section, half, nil, "sub.hold")
			if flavour.keys > 0 then lanes:within("keys", section, 0, nil, "keys") end
			lanes:phraseEnds("throws", section, 4, "throw")
		end
	end
	-- Chords last two bars through the whole track, around the blend.
	lanes:fill("pads", 0, track.length, "pads.chords")
	kit.punctuate(lanes, track, function(section, phrase)
		return "fill." .. cycles[section.cycle].fills[phrase + 1]
	end)
	kit.produce(lanes, track)
	return lanes:done()
end

-- The patterns -----------------------------------------------------------------

-- The break in 16th slices; with chops, the cycle's edits for this phrase
-- bar rearrange it. Silent under a half-time switch-up.
local function breakPattern(gain)
	return function(bar, ctx)
		if ctx.halftime then return end
		local amen, cycle, n = ctx.kit.amen, ctx.cycle, ctx.n
		local slices = {}
		for step = 0, 15 do slices[step] = (n % amen.bars) * 16 + step end
		if ctx.chops then
			for _, chop in ipairs(cycle.chops) do
				if chop.bar == ctx.phraseBar and chop.threshold < ctx.complexity * 0.8 + 0.1 then
					for i = 0, chop.length - 1 do
						if chop.step + i < 16 then
							slices[chop.step + i] = chop.kind == "stutter" and chop.source or (chop.source + i) % amen.slices
						end
					end
				end
			end
		end
		local level = type(gain) == "function" and gain(ctx) or gain
		for step = 0, 15 do table.insert(bar.breaks, {step = step, slice = slices[step], gain = level}) end
	end
end

-- The two-step kick; a fill cuts it short, and in drops complexity adds
-- syncopated extras.
local function kick(extras)
	return function(_, ctx)
		local hit, cycle = ctx.hit, ctx.cycle
		if ctx.halftime then
			hit(0, "kick", 1)
			hit(10, "kick", 0.85)
			if ctx.complexity > 0.5 then hit(3, "kick", 0.7) end
			return
		end
		local kicks = (ctx.phraseBar % 4 == 3) and cycle.altKicks or cycle.kicks
		local cut = ctx.fill and (ctx.fill == "cut" and 8 or 12) or 16
		for _, step in ipairs(kicks) do
			if step < cut then hit(step, "kick", step == 0 and 1 or 0.85) end
		end
		if extras then
			for _, extra in ipairs(cycle.kickExtras) do
				if extra.step < cut and extra.threshold < ctx.complexity * 0.6 - 0.1 then hit(extra.step, "kick", 0.7) end
			end
		end
	end
end

local function backbeat(drag)
	return function(_, ctx)
		local hit = ctx.hit
		if ctx.halftime then
			hit(8, "snare", 1, {throw = ctx.throw})
			return
		end
		hit(4, "snare", 1)
		if not ctx.fill then hit(12, "snare", 1, {throw = ctx.throw}) end
		-- A drag into the backbeat.
		if drag and ctx.complexity > 0.65 and ctx.n % 2 == 1 then hit(11.5, "ghost", 0.3) end
	end
end

local function hats(full)
	return function(_, ctx)
		local hit, energy, complexity, n = ctx.hit, ctx.energy, ctx.complexity, ctx.n
		for step = ctx.halftime and 4 or 2, 15, 4 do hit(step, "hat", 0.75) end
		if not full then return end
		for step = 0, 15, 4 do hit(step, "hat", 0.35) end
		if energy > 0.45 then
			for step = 1, 15, 2 do
				if (step + n) % 4 == 3 or energy > 0.8 or complexity > 0.75 then hit(step, "hat", 0.22) end
			end
		end
		if ctx.phraseBar % 2 == 1 then hit(14, "openHat", 0.5) end
		if complexity > 0.4 and ctx.phraseBar % 4 == 1 then hit(6, "openHat", 0.35) end
	end
end

local function ride(every, gain, from)
	return function(_, ctx)
		for step = from, 15, every do ctx.hit(step, "ride", gain) end
	end
end

-- Electric-piano comping, the liquid signature.
local function keys(bar, ctx)
	local flavour, half = ctx.flavour, (ctx.n % 2) * 16
	for _, k in ipairs(ctx.cycle.keys) do
		local step = k.step - half
		if step >= 0 and step < 16 and k.threshold <= ctx.complexity * 0.7 + 0.2 then
			table.insert(bar.keys, {step = step, length = k.length, notes = ctx.chord.notes,
				gain = flavour.keys * (step == 0 and 1 or 0.7)})
		end
	end
end

-- The pad voicing an octave up.
local function arp(minEnergy)
	return function(bar, ctx)
		if ctx.energy <= minEnergy then return end
		local cycle, chord, n = ctx.cycle, ctx.chord, ctx.n
		local order, rate = cycle.arp.order, cycle.arp.rate
		local i = 0
		for step = 0, 15, rate do
			if cycle.arp.mask[step] <= ctx.complexity * 0.9 + 0.1 then
				local index = order[(n * 16 // rate + i) % #order + 1]
				local note = chord.notes[(index - 1) % 4 + 1] + 12 * (1 + (index - 1) // 4)
				table.insert(bar.arp, {step = step, note = note, length = rate * 0.8,
					gain = step % 4 == 0 and 1 or 0.7, pan = (i % 2 == 0) and 0.3 or 0.7})
			end
			i = i + 1
		end
	end
end

-- The cycle's call and response over the chords.
local function lead(gain)
	return function(bar, ctx)
		if ctx.halftime then return end
		local phrase = ctx.cycle.lead[ctx.phraseBar % 4 + 1]
		for index, note in ipairs(phrase) do
			table.insert(bar.lead, {step = note.step, length = note.length,
				note = ctx.kit.leadPitch(ctx.mode, ctx.tonic, ctx.chord.degree, note.offset),
				glide = note.glide, gain = gain, throw = (ctx.throw and index == #phrase) or nil})
		end
	end
end

local PATTERNS = {
	{id = "amen.raw", part = "amen", render = breakPattern(0.9)},
	{id = "amen.build", part = "amen", render = breakPattern(0.6)},
	{id = "amen.drop", part = "amen", render = breakPattern(function(ctx) return 0.75 * ctx.flavour.amen end)},
	{id = "amen.outro", part = "amen", render = breakPattern(function(ctx) return 0.6 * ctx.flavour.amen end)},
	{id = "kick.groove", part = "kick", render = kick(false)},
	{id = "kick.drop", part = "kick", render = kick(true)},
	{id = "snare.backbeat", part = "snare", render = backbeat(false)},
	{id = "snare.drop", part = "snare", render = backbeat(true)},
	{id = "ghosts", part = "ghosts", render = function(_, ctx)
		if ctx.fill or ctx.halftime then return end
		local order, n = ctx.cycle.ghostOrder, ctx.n
		local count = math.floor(1 + ctx.energy * 3 + ctx.complexity * 3 + 0.5)
		for i = 1, math.min(count, #order) do ctx.hit(order[i], "ghost", 0.22 + 0.1 * ((i + n) % 3)) end
	end},
	{id = "hats.open", part = "hats", render = hats(false)},
	{id = "hats.full", part = "hats", render = hats(true)},
	{id = "ride.soft", part = "ride", render = ride(4, 0.55, 0)},
	{id = "ride.drop", part = "ride", render = ride(2, 0.4, 2)},
	{id = "perc", part = "percussion", bars = 2, render = function(_, ctx)
		local half = (ctx.n % 2) * 16
		for _, p in ipairs(ctx.cycle.percussion) do
			local step = p.step - half
			if step >= 0 and step < 16 and p.chance < ctx.energy * 0.3 + ctx.complexity * 0.3 then
				ctx.hit(step, p.voice, 0.35 + 0.3 * p.chance)
			end
		end
	end},
	-- Fills, one per phrase's last bar; the kick and snare read `ctx.fill`.
	{id = "fill.roll", part = "fills", render = function(_, ctx)
		ctx.fill = "roll"
		for step = 12, 15.5, 0.5 do ctx.hit(step, "snare", 0.4 + 0.08 * (step - 12)) end
	end},
	{id = "fill.toms", part = "fills", render = function(_, ctx)
		ctx.fill = "toms"
		for i, voice in ipairs({"tomHigh", "tomHigh", "tomMid", "tomMid", "tomLow", "tomLow"}) do
			ctx.hit(9 + i, voice, 0.75)
		end
		ctx.hit(12, "snare", 0.9)
	end},
	{id = "fill.stutter", part = "fills", render = function(_, ctx)
		ctx.fill = "stutter"
		for step = 12, 15 do
			if step % 2 == 0 then ctx.hit(step, "kick", 0.8) end
			ctx.hit(step + 0.5, "snare", 0.5 + 0.1 * (step - 12))
		end
	end},
	-- Drop out on beat three, then a flam into the next phrase.
	{id = "fill.cut", part = "fills", render = function(_, ctx)
		ctx.fill = "cut"
		ctx.hit(14.5, "snare", 0.5)
		ctx.hit(15, "snare", 1)
	end},
	-- Rolling bass: a long root on each bar's downbeat, then short answers
	-- whose count grows with energy; every fourth bar a busier variation.
	{id = "sub.roll", part = "sub", bars = 2, render = function(bar, ctx)
		local cycle, halftime = ctx.cycle, ctx.halftime
		local energy, complexity = ctx.energy, ctx.complexity
		local notes, offset = cycle.bass, (ctx.n % 2) * 16
		if ctx.phraseBar % 4 == 3 and complexity > 0.3 and not halftime then notes, offset = cycle.variation, 0 end
		for _, note in ipairs(notes) do
			local step = note.step - offset
			local keep = note.chance <= energy * 0.9 + 0.1 and (note.length > 1 or note.detail < complexity)
			if halftime then keep = step % 4 == 0 and (step == 0 or note.chance < energy * 0.6) end
			if step >= 0 and step < 16 and keep then
				local length = halftime and math.max(note.length, 4) or note.length
				table.insert(bar.bass, {step = step, length = math.min(length, 16 - step), subOnly = true,
					note = ctx.chord.root + note.interval, glide = note.glide, reese = ctx.flavour.reese})
			end
		end
	end},
	{id = "stabs", part = "stabs", bars = 2, render = function(bar, ctx)
		if ctx.energy <= 0.25 or ctx.halftime then return end
		local half = (ctx.n % 2) * 16
		for _, s in ipairs(ctx.cycle.stabSteps) do
			local step = s.step - half
			if step >= 0 and step < 16 and s.threshold <= (ctx.complexity + 0.3) * ctx.flavour.stabs then
				table.insert(bar.stabs, {step = step, notes = ctx.chord.notes, throw = ctx.throw and step >= 8 or nil})
			end
		end
	end},
	{id = "keys", part = "keys", bars = 2, render = keys},
	{id = "arp", part = "arp", render = arp(-1)},
	{id = "arp.drop", part = "arp", render = arp(0.3)},
	{id = "lead", part = "lead", bars = 4, render = lead(1)},
	{id = "lead.soft", part = "lead", bars = 4, render = lead(0.6)},
}

return {
	api = 2,
	title = "Drum & Bass",
	symbol = "waveform.path",
	summary = "Liquid, Jungle, Neurofunk and Rollers at 174",
	tempo = {min = 160, max = 180, default = 174},
	defaults = {energy = 0.65, complexity = 0.5, swing = 0.12, humanize = 0.35,
		cutoff = 0.5, wobble = 0.3, drive = 0.35, space = 0.35},
	set = {flavours = FLAVOURS, modes = {"minor", "dorian", "phrygian"}, arrangement = ARRANGEMENT,
		modulations = {5, -2, 3, 2}},
	material = buildCycle,
	arrange = arrange,
	patterns = PATTERNS,
}
