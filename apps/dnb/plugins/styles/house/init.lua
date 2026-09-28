-- House: Deep, Classic and Disco tracks at 124. A round kick on every beat
-- with a deep sidechain pump, claps on two and four, open hats on the
-- off-beats and a shaker running 16ths; seventh and ninth chords comped on
-- the electric piano, an off-beat organ bass and, in Disco tracks, octave
-- bass and filtered stabs.

local FLAVOURS = {
	{id = "deep", name = "Deep House", keys = 1, stabs = 0.3, octave = 0, lead = 0.3, arp = 0.3},
	{id = "classic", name = "Classic House", keys = 0.7, stabs = 1, octave = 0.3, lead = 0.6, arp = 0.5},
	{id = "disco", name = "Disco House", keys = 0.5, stabs = 0.8, octave = 1, lead = 0.4, arp = 0.8},
}
local ARRANGEMENT = {introBars = 16, buildBars = 8, dropBars = 32, breakdownBars = 16, rebuildBars = 8,
	outroBars = 16, blendBars = 8, minCycles = 2, maxCycles = 3}
-- Dorian and major loops of two or four chords, a bar each.
local PROGRESSIONS = {{1, 4, 1, 4}, {2, 5, 1, 1}, {1, 6, 4, 5}, {1, 7, 4, 4}, {6, 4, 1, 5}, {2, 4, 5, 5}}
-- Comping rhythms over a bar: steps where the chord is struck.
local COMPS = {{0, 3, 6, 10}, {2, 6, 10, 14}, {0, 7, 10}, {3, 6, 11, 14}, {0, 6, 8, 14}}
local BASS_LINES = {
	{{2, 0}, {6, 0}, {10, 0}, {14, 0}},             -- the off-beat organ bass
	{{0, 0}, {3, 0}, {6, 12}, {10, 0}, {14, 7}},    -- syncopated
	{{2, 0}, {3, 12}, {6, 0}, {7, 12}, {10, 0}, {11, 12}, {14, 0}, {15, 12}}, -- disco octaves
}

local function buildCycle(kit, rng, track)
	local mode, flavour = track.mode, track.flavour
	local progression = kit.stableProgression(mode, rng.pick(PROGRESSIONS))
	return {
		progression = progression,
		voicings = kit.voicings(mode, progression, {0, 2, 4, 6}),
		comp = rng.pick(COMPS),
		bassLine = flavour.octave >= 1 and BASS_LINES[3] or rng.pick({BASS_LINES[1], BASS_LINES[2]}),
		keysOn = rng.chance(flavour.keys), stabsOn = rng.chance(flavour.stabs),
		leadOn = rng.chance(flavour.lead), arpOn = rng.chance(flavour.arp),
		lead = kit.melody(rng),
		shaker = rng.chance(0.7),
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
			lanes:within("snare", section, 8, nil, "clap")
			lanes:within("hats", section, 0, nil, "hats")
			lanes:fill("pads", section.start, section.length, "pads.chords")
		elseif id == "build" then
			lanes:within("snare", section, 0, nil, "roll.clap")
			lanes:within("hats", section, 0, nil, "hats")
			lanes:within("pads", section, 0, nil, "pads.chords")
			if cycle.arpOn then lanes:within("arp", section, 0, nil, "arp") end
		elseif id == "drop" then
			lanes:within("kick", section, 0, nil, "kick")
			lanes:within("snare", section, 0, nil, "clap")
			-- A shaker running 16ths, or closed hats when the cycle has none.
			lanes:within("hats", section, 0, nil, cycle.shaker and "hats" or "hats.drop")
			lanes:within("ride", section, 16, nil, "ride")
			lanes:within("percussion", section, 0, nil, cycle.shaker and "perc.drop" or "perc.congas")
			lanes:within("sub", section, 0, nil, "sub.organ")
			lanes:within("reese", section, 0, nil, "reese")
			lanes:within("pads", section, 16, nil, "pads.chords")
			if cycle.keysOn then lanes:within("keys", section, 0, nil, "keys") end
			if cycle.stabsOn then lanes:within("stabs", section, 0, nil, "stabs") end
			if cycle.leadOn then lanes:within("lead", section, 16, nil, "lead") end
			lanes:phraseEnds("throws", section, 4, "throw")
		elseif id == "breakdown" then
			lanes:within("sub", section, 0, nil, "sub.hold")
			lanes:within("pads", section, 0, nil, "pads.chords")
			if cycle.keysOn then lanes:within("keys", section, 0, nil, "keys") end
			if cycle.arpOn then lanes:within("arp", section, 0, nil, "arp") end
			if cycle.leadOn then lanes:within("lead", section, 8, nil, "lead.soft") end
			lanes:phraseEnds("throws", section, 4, "throw")
		elseif id == "outro" then
			lanes:within("kick", section, 0, nil, "kick")
			lanes:within("snare", section, 0, nil, "clap")
			lanes:within("hats", section, 0, nil, "hats")
			if cycle.shaker then lanes:within("percussion", section, 0, nil, "perc.shaker") end
			lanes:within("sub", section, 0, 8, "sub.organ")
			lanes:within("reese", section, 0, 8, "reese")
			if cycle.keysOn then lanes:within("keys", section, 0, nil, "keys") end
		end
	end
	kit.punctuate(lanes, track, function() return "fill.claps" end)
	kit.produce(lanes, track)
	return lanes:done()
end

-- The patterns -----------------------------------------------------------------

local function shaker(ctx)
	for step = 0, 15 do ctx.hit(step, "shaker", step % 2 == 0 and 0.35 or 0.22) end
end
local function congas(ctx)
	if ctx.complexity <= 0.3 then return end
	ctx.hit(7, "conga", 0.35)
	if ctx.complexity > 0.6 then ctx.hit(10, "conga", 0.3); ctx.hit(15, "rim", 0.3) end
end

local function lead(gain)
	return function(bar, ctx)
		for _, note in ipairs(ctx.cycle.lead[ctx.phraseBar % 4 + 1]) do
			table.insert(bar.lead, {step = note.step, length = note.length, glide = note.glide,
				gain = gain, note = ctx.kit.leadPitch(ctx.mode, ctx.tonic, ctx.chord.degree, note.offset)})
		end
	end
end

local PATTERNS = {
	{id = "kick", part = "kick", render = function(bar, ctx) bar:sequence("x...x...x...x...", "kick", 1, ctx.humanize) end},
	{id = "clap", part = "snare", render = function(_, ctx)
		ctx.hit(4, "clap", 0.85)
		ctx.hit(12, "clap", 0.85, {throw = ctx.throw})
	end},
	{id = "fill.claps", part = "fills", render = function(_, ctx)
		for step = 13, 15 do ctx.hit(step, "clap", 0.4 + 0.15 * (step - 13)) end
	end},
	{id = "hats", part = "hats", render = function(_, ctx)
		for step = 2, 14, 4 do ctx.hit(step, "openHat", 0.45) end
	end},
	{id = "hats.drop", part = "hats", render = function(_, ctx)
		for step = 2, 14, 4 do ctx.hit(step, "openHat", 0.45) end
		if ctx.energy > 0.5 then
			for step = 0, 15, 2 do if step % 4 ~= 2 then ctx.hit(step, "hat", 0.3) end end
		end
	end},
	{id = "ride", part = "ride", render = function(_, ctx)
		for step = 0, 15, 2 do ctx.hit(step, "ride", step % 4 == 2 and 0.35 or 0.22) end
	end},
	{id = "perc.shaker", part = "percussion", render = function(_, ctx) shaker(ctx) end},
	{id = "perc.congas", part = "percussion", render = function(_, ctx) congas(ctx) end},
	{id = "perc.drop", part = "percussion", render = function(_, ctx) shaker(ctx); congas(ctx) end},
	-- The off-beat organ bass, syncopated or in disco octaves.
	{id = "sub.organ", part = "sub", render = function(bar, ctx)
		for i, note in ipairs(ctx.cycle.bassLine) do
			if i == 1 or note[1] % 4 == 2 or ctx.energy > 0.4 then
				table.insert(bar.bass, {step = note[1], length = 1.5, note = ctx.chord.root + 12 + note[2], reese = 0.8,
					subOnly = true})
			end
		end
	end},
	-- Seventh chords comped on the electric piano.
	{id = "keys", part = "keys", render = function(bar, ctx)
		for index, step in ipairs(ctx.cycle.comp) do
			if index == 1 or ctx.complexity > 0.25 then
				table.insert(bar.keys, {step = step, length = 2, notes = ctx.chord.notes, gain = index == 1 and 1 or 0.75})
			end
		end
	end},
	{id = "stabs", part = "stabs", render = function(bar, ctx)
		if ctx.energy <= 0.35 then return end
		for _, step in ipairs({3, 6, 11}) do
			if step ~= 11 or ctx.complexity > 0.5 then
				table.insert(bar.stabs, {step = step, notes = ctx.chord.notes, throw = ctx.throw and step == 11 or nil})
			end
		end
	end},
	{id = "arp", part = "arp", render = function(bar, ctx)
		local notes = ctx.chord.notes
		for step = 0, 15, 2 do
			table.insert(bar.arp, {step = step, note = notes[(step // 2) % #notes + 1] + 12, length = 1.5,
				gain = step % 4 == 0 and 0.9 or 0.6, pan = step % 4 == 0 and 0.4 or 0.6})
		end
	end},
	{id = "lead", part = "lead", bars = 4, render = lead(0.85)},
	{id = "lead.soft", part = "lead", bars = 4, render = lead(0.6)},
}

return {
	api = 2,
	title = "House",
	symbol = "house.fill",
	summary = "Deep, Classic and Disco house, four to the floor",
	tempo = {min = 118, max = 128, default = 124},
	defaults = {energy = 0.6, complexity = 0.5, swing = 0.08, humanize = 0.3,
		cutoff = 0.45, wobble = 0, drive = 0.2, space = 0.45},
	sound = {
		kick = {base = 52, sweep = 110, sweepTime = 0.02, decay = 0.22, drive = 1.8, click = 0.3, length = 0.4},
		clap = {decay = 0.18, level = 1},
		hat = {scale = 1.7, decay = 0.02, openDecay = 0.1},
		bass = {detune = 0.002, resonance = 0.9, envAmount = 1.2, envDecay = 0.08, shape = "square"},
		pad = {brightness = 0.05, attack = 0.3},
		stab = {decay = 0.14, octave = 1},
		keys = {decay = 1.5, autopanDepth = 0.25},
		mix = {duckDepth = 0.65, duckRelease = 0.16, keys = 0.07, reese = 0.28, sub = 0.5, delaySteps = 3},
	},
	set = {form = {openings = {"build", "cold", "melodic"}, builds = {"sweep", "sweep", "roll", "rise"}},
		flavours = FLAVOURS, modes = {"dorian", "minor", "major"}, arrangement = ARRANGEMENT, modulations = {0, 2, 5}},
	barsPerChord = 1,
	material = buildCycle,
	arrange = arrange,
	patterns = PATTERNS,
}
