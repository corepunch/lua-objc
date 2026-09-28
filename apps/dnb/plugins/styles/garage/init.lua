-- UK Garage: 2-Step, Speed Garage and Future Garage at 132. The skippy
-- two-step kick that leaves beats two and four to the snare, heavy shuffle
-- on the hats, rim shots, minor-ninth organ chords and a bouncing bass —
-- the speed-garage reese, or the washed-out chords and pitched vocal-like
-- lead of future garage.

local FLAVOURS = {
	{id = "twostep", name = "2-Step", reese = 0.5, keys = 1, lead = 0.6, snares = {"rimshot", "tight", "layered", "vintage"}},
	{id = "speed", name = "Speed Garage", reese = 1, keys = 0.4, lead = 0.3, snares = {"tight", "rimshot", "crunchy", "layered"}},
	{id = "future", name = "Future Garage", reese = 0.3, keys = 0.7, lead = 1, snares = {"roomy", "vintage", "rimshot", "layered"}},
}
local ARRANGEMENT = {introBars = 8, buildBars = 8, dropBars = 32, breakdownBars = 16, rebuildBars = 8,
	outroBars = 16, blendBars = 8, minCycles = 2, maxCycles = 3}
local PROGRESSIONS = {{1, 4, 1, 4}, {1, 6, 4, 5}, {4, 5, 1, 1}, {1, 7, 6, 4}, {2, 5, 1, 6}}
-- Two-step kicks: the downbeat, then a skip that avoids the backbeat.
local KICKS = {"x.........x.....", "x.........x..x..", "x......x..x.....", "x.x.......x....."}
local BASS_LINES = {
	{{0, 3, 0}, {3, 1, 0}, {6, 2, 12}, {10, 2, 0}, {13, 3, 7}},
	{{0, 2, 0}, {2, 2, 12}, {7, 2, 0}, {10, 4, 3}},
	{{0, 4, 0}, {6, 1, 0}, {7, 2, 12}, {11, 1, 10}, {12, 4, 7}},
}

local function buildCycle(kit, rng, track)
	local mode, flavour = track.mode, track.flavour
	local progression = kit.stableProgression(mode, rng.pick(PROGRESSIONS))
	return {
		progression = progression,
		voicings = kit.voicings(mode, progression, {0, 2, 4, 6, 8}),
		kicks = rng.pick(KICKS), altKicks = rng.pick(KICKS),
		bass = rng.pick(BASS_LINES),
		comp = rng.pick({{0, 6, 10}, {3, 6, 14}, {0, 3, 10, 13}}),
		keysOn = rng.chance(flavour.keys), leadOn = rng.chance(flavour.lead),
		lead = kit.melody(rng),
	}
end

-- The arrangement ------------------------------------------------------------

local function arrange(kit, track, cycles)
	local lanes = kit.lanes(track)
	local flavour = track.flavour
	kit.blendIn(lanes, track)
	-- Future Garage keeps its pads under the whole track.
	if flavour.id == "future" then lanes:fill("pads", 0, track.length, "pads.chords") end
	for _, section in ipairs(track.sections) do
		local id, cycle = section.id, cycles[section.cycle]
		if id == "intro" then
			lanes:within("kick", section, 0, nil, "kick")
			lanes:within("snare", section, 4, nil, "snare")
			lanes:within("hats", section, 0, nil, "hats")
		elseif id == "build" then
			lanes:within("snare", section, 0, nil, "roll.snare")
			lanes:within("hats", section, 0, nil, "hats")
			lanes:fill("pads", section.start, section.length, "pads.chords")
		elseif id == "drop" then
			lanes:within("kick", section, 0, nil, "kick")
			lanes:within("snare", section, 0, nil, "snare")
			lanes:within("ghosts", section, 0, nil, "rims")
			lanes:within("hats", section, 0, nil, "hats")
			lanes:within("percussion", section, 0, nil, "perc")
			lanes:within("sub", section, 0, nil, "sub.line")
			lanes:within("reese", section, 0, nil, "reese")
			if cycle.keysOn then lanes:within("keys", section, 0, nil, "keys") end
			if flavour.id == "speed" then lanes:within("stabs", section, 0, nil, "stabs") end
			if cycle.leadOn then lanes:within("lead", section, 16, nil, "lead") end
			lanes:phraseEnds("throws", section, 4, "throw")
		elseif id == "breakdown" then
			lanes:within("sub", section, 0, nil, "sub.hold")
			lanes:fill("pads", section.start, section.length, "pads.chords")
			if cycle.keysOn then lanes:within("keys", section, 0, nil, "keys") end
			if cycle.leadOn then lanes:within("lead", section, 0, nil, "lead.soft") end
			lanes:phraseEnds("throws", section, 4, "throw")
		elseif id == "outro" then
			lanes:within("kick", section, 0, nil, "kick")
			lanes:within("snare", section, 0, nil, "snare")
			lanes:within("ghosts", section, 0, nil, "rims")
			lanes:within("hats", section, 0, nil, "hats")
			lanes:within("sub", section, 0, 8, "sub.line")
			lanes:within("reese", section, 0, 8, "reese")
			if cycle.keysOn then lanes:within("keys", section, 0, nil, "keys") end
		end
	end
	kit.punctuate(lanes, track, function() return "fill.snares" end)
	kit.produce(lanes, track)
	return lanes:done()
end

-- The patterns -----------------------------------------------------------------

local function lead(gain)
	return function(bar, ctx)
		for _, note in ipairs(ctx.cycle.lead[ctx.phraseBar % 4 + 1]) do
			table.insert(bar.lead, {step = note.step, length = note.length, glide = true,
				gain = gain, note = ctx.kit.leadPitch(ctx.mode, ctx.tonic, ctx.chord.degree, note.offset)})
		end
	end
end

local PATTERNS = {
	-- The 2-step kick, answered every fourth bar.
	{id = "kick", part = "kick", render = function(bar, ctx)
		bar:sequence(ctx.phraseBar % 4 == 3 and ctx.cycle.altKicks or ctx.cycle.kicks, "kick", 0.9, ctx.humanize)
	end},
	-- The backbeat, layered with a clap except in Future Garage.
	{id = "snare", part = "snare", render = function(_, ctx)
		ctx.hit(4, "snare", 0.9)
		ctx.hit(12, "snare", 0.9, {throw = ctx.throw})
		if ctx.flavour.id ~= "future" then ctx.hit(4, "clap", 0.5); ctx.hit(12, "clap", 0.5) end
	end},
	{id = "fill.snares", part = "fills", render = function(_, ctx)
		for step = 13, 15 do ctx.hit(step, "snare", 0.5 + 0.12 * (step - 13)) end
	end},
	{id = "rims", part = "ghosts", render = function(_, ctx)
		for _, step in ipairs({7, 15, 9}) do if step ~= 9 or ctx.complexity > 0.5 then ctx.hit(step, "rim", 0.35) end end
	end},
	-- Shuffled 16ths: the off-16ths always, the rest with energy.
	{id = "hats", part = "hats", render = function(_, ctx)
		for step = 0, 15 do
			if step % 2 == 1 or ctx.energy > 0.5 then ctx.hit(step, "hat", step % 2 == 1 and 0.35 or 0.2) end
		end
		ctx.hit(14, "openHat", 0.4)
		if ctx.complexity > 0.5 then ctx.hit(6, "openHat", 0.3) end
	end},
	{id = "perc", part = "percussion", render = function(_, ctx)
		if ctx.complexity <= 0.3 then return end
		for step = 2, 15, 4 do ctx.hit(step, "shaker", 0.3) end
	end},
	{id = "sub.line", part = "sub", render = function(bar, ctx)
		for _, note in ipairs(ctx.cycle.bass) do
			if note[1] == 0 or ctx.energy > 0.35 then
				table.insert(bar.bass, {step = note[1], length = note[2], note = ctx.chord.root + note[3],
					glide = note[3] ~= 0, reese = ctx.flavour.reese, subOnly = true})
			end
		end
	end},
	{id = "keys", part = "keys", render = function(bar, ctx)
		for index, step in ipairs(ctx.cycle.comp) do
			table.insert(bar.keys, {step = step, length = 2, notes = ctx.chord.notes, gain = index == 1 and 1 or 0.7})
		end
	end},
	-- The Speed Garage organ stab.
	{id = "stabs", part = "stabs", render = function(bar, ctx)
		table.insert(bar.stabs, {step = 6, notes = ctx.chord.notes, throw = ctx.throw})
	end},
	{id = "lead", part = "lead", bars = 4, render = lead(0.8)},
	{id = "lead.soft", part = "lead", bars = 4, render = lead(0.6)},
}

return {
	api = 2,
	title = "UK Garage",
	symbol = "figure.dance",
	summary = "2-Step, Speed Garage and Future Garage shuffle",
	tempo = {min = 128, max = 138, default = 132},
	defaults = {energy = 0.6, complexity = 0.55, swing = 0.3, humanize = 0.35,
		cutoff = 0.4, wobble = 0.15, drive = 0.3, space = 0.45},
	sound = {
		kick = {base = 50, sweep = 100, sweepTime = 0.02, decay = 0.2, drive = 1.8, click = 0.3, length = 0.38},
		snare = {tone = 220, overtone = 360, bodyDecay = 0.045, noiseDecay = 0.08, noise = 0.45},
		hat = {scale = 1.8, decay = 0.014, openDecay = 0.08},
		bass = {detune = 0.006, resonance = 0.6, lfoRate = 4},
		keys = {index = 0.8, indexFloor = 0.6, tine = 0.05, decay = 0.9, autopanDepth = 0.15},
		lead = {glide = 0.001, vibratoDepth = 0.012, brightness = 0.07, square = 0.1},
		mix = {duckDepth = 0.4, keys = 0.065, lead = 0.065, delaySteps = 3},
	},
	set = {form = {openings = {"cold", "build", "melodic"}, builds = {"sweep", "rise", "roll"}},
		flavours = FLAVOURS, modes = {"minor", "dorian"}, arrangement = ARRANGEMENT, modulations = {0, 5}},
	material = buildCycle,
	arrange = arrange,
	patterns = PATTERNS,
}
