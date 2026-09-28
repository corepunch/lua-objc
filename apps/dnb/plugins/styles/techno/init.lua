-- Techno: a four-on-the-floor set of Peak Time, Acid and Hypnotic tracks.
-- A long, driven kick with a rolling rumble in its tail, off-beat open hats,
-- claps on two and four; Acid tracks ride a squelching 303 line with slides
-- and accents, Hypnotic ones a dub chord stab thrown into the delay.

local FLAVOURS = {
	{id = "peak", name = "Peak Time", acid = 0, rumble = 1, stab = 0.4, lead = 0.5, arp = 0.6},
	{id = "acid", name = "Acid", acid = 1, rumble = 0.3, stab = 0.2, lead = 0, arp = 0.3},
	{id = "hypnotic", name = "Hypnotic", acid = 0.3, rumble = 0.7, stab = 1, lead = 0, arp = 0.8},
}
local ARRANGEMENT = {introBars = 16, buildBars = 8, dropBars = 32, breakdownBars = 16, rebuildBars = 8,
	outroBars = 16, blendBars = 8, minCycles = 2, maxCycles = 3}
-- Minor-key loops; techno lives on one or two chords.
local PROGRESSIONS = {{1, 1, 1, 1}, {1, 1, 6, 6}, {1, 7, 1, 7}, {1, 1, 4, 4}, {1, 6, 1, 7}}
-- The 303: semitones over the root, favouring the root, octave and fifth.
local ACID_NOTES = {0, 0, 0, 12, 12, 7, 3, 10, -2, 5}
local STAB_STEPS = {3, 6, 10, 14, 7}
local PERCUSSION = {"rim", "shaker", "conga"}

local function buildCycle(kit, rng, track)
	local mode, flavour = track.mode, track.flavour
	local progression = kit.stableProgression(mode, rng.pick(PROGRESSIONS))
	local cycle = {
		progression = progression,
		voicings = kit.voicings(mode, progression, {0, 2, 4}),
		acid = {}, stabs = {}, percussion = {}, rims = {},
		stabOn = rng.chance(flavour.stab), leadOn = rng.chance(flavour.lead), arpOn = rng.chance(flavour.arp),
		lead = kit.melody(rng),
		arp = rng.pick({{1, 2, 3, 2}, {1, 3, 2, 3}, {3, 2, 1, 2}}),
	}
	-- A 16-step acid line: each step may sound, slide into the next, or
	-- accent (the 303's filter snaps open further).
	for step = 0, 15 do
		if step == 0 or rng.chance(0.62) then
			table.insert(cycle.acid, {step = step, interval = step == 0 and 0 or rng.pick(ACID_NOTES),
				slide = rng.chance(0.25), accent = step % 4 == 0 and rng.chance(0.6) or rng.chance(0.2),
				threshold = step % 4 == 0 and 0 or rng.float()})
		end
	end
	for _, step in ipairs(STAB_STEPS) do
		if rng.chance(0.4) then table.insert(cycle.stabs, {step = step, threshold = rng.float()}) end
	end
	if #cycle.stabs == 0 then table.insert(cycle.stabs, {step = 6, threshold = 0}) end
	for step = 0, 15 do
		if step % 4 ~= 0 then table.insert(cycle.percussion, {step = step, voice = rng.pick(PERCUSSION), chance = rng.float()}) end
	end
	for _, step in ipairs({3, 7, 11, 13, 15, 9}) do table.insert(cycle.rims, {step = step, threshold = rng.float()}) end
	return cycle
end

-- The arrangement ------------------------------------------------------------

local function arrange(kit, track, cycles)
	local lanes = kit.lanes(track)
	local flavour = track.flavour
	kit.blendIn(lanes, track)
	for _, section in ipairs(track.sections) do
		local id, index, cycle = section.id, section.cycle, cycles[section.cycle]
		-- Acid tracks ride the 303 throughout; others bring it in on odd cycles.
		local acid = flavour.acid >= 1 or (flavour.acid > 0 and index % 2 == 1)
		if id == "intro" then
			lanes:within("kick", section, 0, nil, "kick")
			lanes:within("snare", section, 8, nil, "clap")
			lanes:within("hats", section, 0, nil, "hats.intro")
		elseif id == "build" then
			lanes:within("snare", section, 0, nil, "roll.clap")
			lanes:within("hats", section, 0, nil, "hats.open")
			lanes:within("pads", section, 0, nil, "pads.long")
			if cycle.arpOn then lanes:within("arp", section, 0, nil, "arp") end
		elseif id == "drop" then
			lanes:within("kick", section, 0, nil, "kick")
			lanes:within("snare", section, 0, nil, "clap")
			lanes:within("ghosts", section, 0, nil, "rims")
			lanes:within("hats", section, 0, nil, "hats.drop")
			lanes:within("ride", section, 8, nil, "ride")
			lanes:within("percussion", section, 0, nil, "perc")
			lanes:within("sub", section, 0, nil, acid and "sub.acid" or "sub.rumble")
			lanes:within("reese", section, 0, nil, "reese")
			lanes:within("pads", section, 16, nil, "pads.long")
			if cycle.stabOn then lanes:within("stabs", section, 0, nil, "stabs") end
			if cycle.leadOn then lanes:within("lead", section, 16, nil, "lead") end
			lanes:phraseEnds("throws", section, 4, "throw")
		elseif id == "breakdown" then
			lanes:within("sub", section, 8, nil, "sub.hold")
			lanes:within("pads", section, 0, nil, "pads.long")
			if cycle.stabOn then lanes:within("stabs", section, 0, nil, "stabs") end
			if cycle.arpOn then lanes:within("arp", section, 0, nil, "arp") end
			lanes:phraseEnds("throws", section, 4, "throw")
		elseif id == "outro" then
			lanes:within("kick", section, 0, nil, "kick")
			lanes:within("snare", section, 0, nil, "clap")
			lanes:within("ghosts", section, 0, nil, "rims")
			lanes:within("hats", section, 0, nil, "hats.open")
			lanes:within("sub", section, 0, 8, acid and "sub.acid" or "sub.rumble")
			lanes:within("reese", section, 0, 8, "reese")
		end
	end
	kit.punctuate(lanes, track, function() return "fill.flam" end)
	kit.produce(lanes, track)
	return lanes:done()
end

-- The patterns -----------------------------------------------------------------

local function hats(gain, drop)
	return function(_, ctx)
		local hit, energy = ctx.hit, ctx.energy
		for step = 2, 14, 4 do hit(step, "openHat", gain) end
		if drop and energy > 0.4 then
			for step = 0, 15 do
				if step % 4 ~= 2 and (step % 2 == 1 or energy > 0.75) then hit(step, "hat", step % 2 == 0 and 0.3 or 0.2) end
			end
		end
	end
end

local PATTERNS = {
	-- Four on the floor; a fill drops the last kick for a clap flam.
	{id = "kick", part = "kick", render = function(_, ctx)
		for step = 0, 12, 4 do
			if not (ctx.fill and step == 12) then ctx.hit(step, "kick", step == 0 and 1 or 0.95) end
		end
	end},
	{id = "clap", part = "snare", render = function(_, ctx)
		ctx.hit(4, "clap", 0.9)
		ctx.hit(12, "clap", 0.9, {throw = ctx.throw})
	end},
	{id = "fill.flam", part = "fills", render = function(_, ctx)
		ctx.fill = "flam"
		ctx.hit(14, "clap", 0.6)
		ctx.hit(15, "clap", 0.8)
	end},
	{id = "hats.intro", part = "hats", render = hats(0.35, false)},
	{id = "hats.open", part = "hats", render = hats(0.5, false)},
	{id = "hats.drop", part = "hats", render = hats(0.5, true)},
	{id = "ride", part = "ride", render = function(_, ctx)
		for step = 2, 15, 4 do ctx.hit(step, "ride", 0.3) end
	end},
	{id = "rims", part = "ghosts", render = function(_, ctx)
		for _, rim in ipairs(ctx.cycle.rims) do
			if rim.threshold < ctx.complexity * 0.7 then ctx.hit(rim.step, "rim", 0.35) end
		end
	end},
	{id = "perc", part = "percussion", render = function(_, ctx)
		for _, p in ipairs(ctx.cycle.percussion) do
			if p.chance < ctx.energy * 0.25 + ctx.complexity * 0.25 then ctx.hit(p.step, p.voice, 0.3 + 0.2 * p.chance) end
		end
	end},
	-- The 303: slides into the next note and accents that snap its filter open.
	{id = "sub.acid", part = "sub", render = function(bar, ctx)
		local acid = ctx.cycle.acid
		for i, note in ipairs(acid) do
			if note.threshold <= ctx.energy * 0.7 + ctx.complexity * 0.3 then
				local nextStep = acid[i + 1] and acid[i + 1].step or 16
				table.insert(bar.bass, {step = note.step, length = note.slide and nextStep - note.step + 0.5 or 1,
					note = ctx.chord.root + 12 + note.interval, glide = i > 1 and acid[i - 1].slide, accent = note.accent,
					subOnly = true})
			end
		end
	end},
	-- The rumble rolling on the two 16ths after each kick.
	{id = "sub.rumble", part = "sub", render = function(bar, ctx)
		for beat = 0, 3 do
			for _, offset in ipairs({2, 3}) do
				if offset == 2 or ctx.energy > 0.5 then
					table.insert(bar.bass, {step = beat * 4 + offset, length = 1, note = ctx.chord.root,
						reese = ctx.flavour.rumble, subOnly = true})
				end
			end
		end
	end},
	-- The dub stab, thrown into the delay on the phrase's turn.
	{id = "stabs", part = "stabs", render = function(bar, ctx)
		for _, s in ipairs(ctx.cycle.stabs) do
			if s.threshold <= ctx.complexity * 0.8 + 0.2 then
				table.insert(bar.stabs, {step = s.step, notes = ctx.chord.notes,
					throw = ctx.throw or s.step == 14})
			end
		end
	end},
	{id = "arp", part = "arp", render = function(bar, ctx)
		local arp, notes = ctx.cycle.arp, ctx.chord.notes
		for step = 0, 15, 2 do
			local tone = arp[(step // 2) % #arp + 1]
			table.insert(bar.arp, {step = step, note = notes[tone] + 12, length = 1.5,
				gain = step % 4 == 0 and 1 or 0.7, pan = step % 4 == 0 and 0.35 or 0.65})
		end
	end},
	{id = "lead", part = "lead", bars = 4, render = function(bar, ctx)
		for _, note in ipairs(ctx.cycle.lead[ctx.phraseBar % 4 + 1]) do
			table.insert(bar.lead, {step = note.step, length = note.length, glide = note.glide, gain = 0.8,
				note = ctx.kit.leadPitch(ctx.mode, ctx.tonic, ctx.chord.degree, note.offset)})
		end
	end},
}

return {
	api = 2,
	title = "Techno",
	symbol = "metronome.fill",
	summary = "Peak Time, Acid and Hypnotic, four to the floor",
	tempo = {min = 124, max = 140, default = 132},
	defaults = {energy = 0.7, complexity = 0.5, swing = 0, humanize = 0.15,
		cutoff = 0.32, wobble = 0.05, drive = 0.45, space = 0.4},
	sound = {
		kick = {base = 50, sweep = 170, sweepTime = 0.018, decay = 0.3, drive = 2.6, click = 0.5, length = 0.55},
		hat = {scale = 1.9, decay = 0.012, openDecay = 0.07},
		bass = {detune = 0, resonance = 0.16, envAmount = 3.2, envDecay = 0.1, lfoRate = 1, glide = 0.004},
		stab = {decay = 0.22, octave = 0},
		mix = {duckDepth = 0.55, reese = 0.3, stab = 0.08, delayFeedback = 0.5},
	},
	set = {form = {openings = {"cold", "cold", "build"}, builds = {"stomp", "sweep", "rise", "roll"},
		links = {"build", "build", "double", "breakdown build", "breakdown"}},
		flavours = FLAVOURS, modes = {"minor", "phrygian"}, arrangement = ARRANGEMENT, modulations = {0, 5, -2}},
	barsPerChord = 4,
	material = buildCycle,
	arrange = arrange,
	patterns = PATTERNS,
}
