-- Dubstep: Deep, Brostep and Riddim tracks at 140, felt at half time. The
-- kick opens the bar and the snare lands on beat three; the drop is the
-- wobble — a detuned, driven bass whose filter LFO restarts with every note
-- at a rate the note chooses (quarters, eighths, triplets, sixteenths).
-- Deep tracks keep the original sub-heavy, dub-echo sound.

local FLAVOURS = {
	{id = "deep", name = "Deep Dubstep", wobble = 0.6, stabs = 0.3, rates = {0.5, 1, 1, 2}, pads = 1, snares = {"roomy", "vintage", "fat", "layered"}},
	{id = "brostep", name = "Brostep", wobble = 1, stabs = 1, rates = {1, 2, 3, 4, 6}, pads = 0.4, snares = {"crunchy", "fat", "layered", "tight"}},
	{id = "riddim", name = "Riddim", wobble = 1, stabs = 0.5, rates = {2, 3, 3, 4}, pads = 0.2, snares = {"tight", "crunchy", "rimshot", "layered"}},
}
local ARRANGEMENT = {introBars = 8, buildBars = 8, dropBars = 16, breakdownBars = 8, rebuildBars = 8,
	outroBars = 8, blendBars = 4, minCycles = 2, maxCycles = 3}
local PROGRESSIONS = {{1, 1, 1, 1}, {1, 1, 6, 7}, {1, 2, 1, 7}, {1, 6, 1, 5}}
-- Wobble phrases: {step, length, interval} over one bar.
local PHRASES = {
	{{0, 6, 0}, {6, 2, 0}, {8, 4, 12}, {12, 4, 3}},
	{{0, 4, 0}, {4, 4, 0}, {8, 8, 7}},
	{{0, 3, 0}, {3, 3, 0}, {6, 2, 12}, {10, 6, 0}},
	{{0, 8, 0}, {8, 2, 5}, {10, 2, 3}, {12, 4, 0}},
	{{0, 2, 0}, {2, 2, 0}, {6, 2, 0}, {8, 4, 1}, {12, 4, 0}},
}

local function buildCycle(kit, rng, track)
	local mode, flavour = track.mode, track.flavour
	local progression = kit.stableProgression(mode, rng.pick(PROGRESSIONS))
	local phrases = {}
	for i = 1, 4 do
		local phrase = {}
		for _, note in ipairs(rng.pick(PHRASES)) do
			table.insert(phrase, {step = note[1], length = note[2], interval = note[3], rate = rng.pick(flavour.rates)})
		end
		phrases[i] = phrase
	end
	return {
		progression = progression,
		voicings = kit.voicings(mode, progression, {0, 2, 4}),
		phrases = phrases,
		stabsOn = rng.chance(flavour.stabs),
		kicks = rng.pick({{0}, {0, 10}, {0, 3}, {0, 14}}),
		lead = kit.melody(rng),
	}
end

-- The arrangement ------------------------------------------------------------

local function arrange(kit, track, cycles)
	local lanes = kit.lanes(track)
	kit.blendIn(lanes, track)
	for _, section in ipairs(track.sections) do
		local id, cycle = section.id, cycles[section.cycle]
		if id == "intro" then
			lanes:within("kick", section, 0, nil, "kick")
			lanes:within("snare", section, 0, nil, "snare")
			lanes:within("hats", section, 0, nil, "hats")
			lanes:fill("pads", section.start, section.length, "pads.long")
			lanes:phraseEnds("throws", section, 4, "throw")
		elseif id == "build" then
			lanes:within("snare", section, 0, nil, "roll.snare")
			lanes:within("hats", section, 0, nil, "hats")
			lanes:within("sub", section, 4, nil, "sub.hold")
			lanes:within("pads", section, 0, nil, "pads.long")
		elseif id == "drop" then
			lanes:within("kick", section, 0, nil, "kick.drop")
			lanes:within("snare", section, 0, nil, "snare")
			lanes:within("ghosts", section, 0, nil, "ghosts")
			lanes:within("hats", section, 0, nil, "hats.drop")
			lanes:within("percussion", section, 0, nil, "perc")
			lanes:within("sub", section, 0, nil, "sub.wobble")
			lanes:within("reese", section, 0, nil, "reese")
			if cycle.stabsOn then lanes:within("stabs", section, 0, nil, "stabs") end
			lanes:phraseEnds("throws", section, 4, "throw")
		elseif id == "breakdown" then
			lanes:within("sub", section, 0, nil, "sub.hold")
			lanes:within("pads", section, 0, nil, "pads.long")
			lanes:within("lead", section, 0, nil, "lead")
		elseif id == "outro" then
			lanes:within("kick", section, 0, nil, "kick")
			lanes:within("snare", section, 0, nil, "snare")
			lanes:within("hats", section, 0, nil, "hats")
			lanes:within("sub", section, 0, nil, "sub.hold")
			lanes:phraseEnds("throws", section, 4, "throw")
		end
	end
	kit.punctuate(lanes, track, function() return "fill.roll" end)
	kit.produce(lanes, track)
	return lanes:done()
end

-- The patterns -----------------------------------------------------------------

local function kick(drop)
	return function(_, ctx)
		for _, step in ipairs(ctx.cycle.kicks) do ctx.hit(step, "kick", step == 0 and 1 or 0.85) end
		if drop and ctx.complexity > 0.6 then ctx.hit(11, "kick", 0.7) end
	end
end

-- Triplet-feel hats: every third 16th, the swagger over the half time.
local function hats(drop)
	return function(_, ctx)
		for step = 0, 15, 3 do ctx.hit(step, "hat", step % 6 == 0 and 0.5 or 0.3) end
		if drop and ctx.energy > 0.6 then ctx.hit(14, "openHat", 0.4) end
	end
end

local PATTERNS = {
	{id = "kick", part = "kick", render = kick(false)},
	{id = "kick.drop", part = "kick", render = kick(true)},
	-- The snare on beat three.
	{id = "snare", part = "snare", render = function(_, ctx) ctx.hit(8, "snare", 1, {throw = ctx.throw}) end},
	{id = "fill.roll", part = "fills", render = function(_, ctx)
		for step = 12, 15.5, 0.5 do ctx.hit(step, "snare", 0.35 + 0.1 * (step - 12)) end
	end},
	{id = "ghosts", part = "ghosts", render = function(_, ctx)
		for _, step in ipairs({6, 14, 15}) do if ctx.complexity > 0.3 or step == 14 then ctx.hit(step, "ghost", 0.25) end end
	end},
	{id = "hats", part = "hats", render = hats(false)},
	{id = "hats.drop", part = "hats", render = hats(true)},
	{id = "perc", part = "percussion", render = function(_, ctx) ctx.hit(12, "rim", 0.3) end},
	-- The wobble: long notes whose LFO restarts on each, at the note's rate.
	{id = "sub.wobble", part = "sub", bars = 4, render = function(bar, ctx)
		for _, note in ipairs(ctx.cycle.phrases[ctx.phraseBar % 4 + 1]) do
			if note.step == 0 or ctx.energy > 0.3 then
				table.insert(bar.bass, {step = note.step, length = note.length, note = ctx.chord.root + note.interval,
					reese = ctx.flavour.wobble, wobble = note.rate * (0.5 + ctx.energy), subOnly = true})
			end
		end
	end},
	{id = "stabs", part = "stabs", render = function(bar, ctx)
		table.insert(bar.stabs, {step = 6, notes = ctx.chord.notes, throw = ctx.throw})
		if ctx.complexity > 0.5 then table.insert(bar.stabs, {step = 14, notes = ctx.chord.notes}) end
	end},
	-- A dub melody an octave down, through the breakdown.
	{id = "lead", part = "lead", bars = 4, render = function(bar, ctx)
		for _, note in ipairs(ctx.cycle.lead[ctx.phraseBar % 4 + 1]) do
			table.insert(bar.lead, {step = note.step, length = note.length, glide = note.glide, gain = 0.6,
				note = ctx.kit.leadPitch(ctx.mode, ctx.tonic, ctx.chord.degree, note.offset) - 12})
		end
	end},
}

return {
	api = 2,
	title = "Dubstep",
	symbol = "speaker.wave.3.fill",
	summary = "Deep, Brostep and Riddim wobble at half time",
	tempo = {min = 136, max = 150, default = 140},
	defaults = {energy = 0.7, complexity = 0.5, swing = 0.05, humanize = 0.2,
		cutoff = 0.42, wobble = 0.85, drive = 0.6, space = 0.35},
	sound = {
		kick = {base = 44, sweep = 140, sweepTime = 0.022, decay = 0.26, drive = 2.4, click = 0.4, length = 0.5},
		snare = {tone = 200, bodyDecay = 0.07, noiseDecay = 0.16, noise = 0.55},
		bass = {detune = 0.009, resonance = 0.45, retrigger = true, wobbleOctaves = 4.2, glide = 0.004},
		stab = {decay = 0.18, octave = 0},
		mix = {duckDepth = 0.35, reese = 0.4, sub = 0.6, delayFeedback = 0.5, delaySteps = 3},
	},
	set = {form = {builds = {"rise", "rise", "roll", "stomp"},
		links = {"breakdown build", "breakdown build", "build", "double"}},
		flavours = FLAVOURS, modes = {"phrygian", "minor"}, arrangement = ARRANGEMENT, modulations = {0, -2}},
	barsPerChord = 4,
	material = buildCycle,
	arrange = arrange,
	patterns = PATTERNS,
}
