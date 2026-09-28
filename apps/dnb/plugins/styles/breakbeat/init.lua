-- Breakbeat: Big Beat, Nu Skool and Florida Breaks at 130. Syncopated
-- funk-break drums with ghost snares, the Amen played near its own tempo,
-- tom fills, a slapping acid bassline with accents and slides, and stabs.

local FLAVOURS = {
	{id = "bigbeat", name = "Big Beat", amen = 1, acid = 0.3, stabs = 1, snares = {"fat", "crunchy", "roomy", "layered"}},
	{id = "nuskool", name = "Nu Skool", amen = 0.4, acid = 1, stabs = 0.6, snares = {"tight", "crunchy", "layered", "rimshot"}},
	{id = "florida", name = "Florida Breaks", amen = 0.2, acid = 0.6, stabs = 0.4, snares = {"tight", "layered", "rimshot", "roomy"}},
}
local ARRANGEMENT = {introBars = 8, buildBars = 8, dropBars = 32, breakdownBars = 16, rebuildBars = 8,
	outroBars = 8, blendBars = 8, minCycles = 2, maxCycles = 3}
local PROGRESSIONS = {{1, 1, 4, 1}, {1, 7, 6, 7}, {1, 4, 1, 5}, {1, 3, 4, 4}}
-- Funky breaks: kick and snare patterns over a bar; "o" is a ghost snare.
local BREAKS = {
	{kick = "x.x.......x.....", snare = "....x..o.o..x..o"},
	{kick = "x......x..x.....", snare = "....x.....o.x..."},
	{kick = "x.x...x...x..x..", snare = "....x..o....x.o."},
	{kick = "x..x......x.....", snare = "....x.o.....x..o"},
}
local BASS_NOTES = {0, 0, 12, 7, 10, 3, 0, 5}

local function buildCycle(kit, rng, track)
	local mode, flavour = track.mode, track.flavour
	local progression = kit.stableProgression(mode, rng.pick(PROGRESSIONS))
	local line = {}
	for step = 0, 15 do
		if step == 0 or rng.chance(0.5) then
			table.insert(line, {step = step, interval = step == 0 and 0 or rng.pick(BASS_NOTES),
				slide = rng.chance(0.3), accent = rng.chance(0.3), threshold = step == 0 and 0 or rng.float()})
		end
	end
	return {
		progression = progression,
		voicings = kit.voicings(mode, progression, {0, 2, 4, 6}),
		groove = rng.pick(BREAKS), fill = rng.pick(BREAKS),
		line = line,
		acid = rng.chance(flavour.acid), stabsOn = rng.chance(flavour.stabs),
		lead = kit.melody(rng),
	}
end

-- The arrangement ------------------------------------------------------------

local function arrange(kit, track, cycles)
	local lanes = kit.lanes(track)
	local flavour = track.flavour
	kit.blendIn(lanes, track)
	for _, section in ipairs(track.sections) do
		local id, cycle = section.id, cycles[section.cycle]
		if id == "intro" then
			lanes:within("kick", section, 0, nil, "kick")
			lanes:within("snare", section, 0, nil, "snare")
			lanes:within("ghosts", section, 0, nil, "ghosts")
			lanes:within("hats", section, 0, nil, "hats")
			if flavour.amen >= 1 then lanes:within("amen", section, 0, nil, "amen") end
		elseif id == "build" then
			lanes:within("snare", section, 0, nil, "roll.snare")
			lanes:within("hats", section, 0, nil, "hats")
			lanes:within("pads", section, 0, nil, "pads.chords")
		elseif id == "drop" then
			lanes:within("kick", section, 0, nil, "kick")
			lanes:within("snare", section, 0, nil, "snare")
			lanes:within("ghosts", section, 0, nil, "ghosts")
			lanes:within("hats", section, 0, nil, "hats")
			lanes:within("ride", section, 16, nil, "ride")
			lanes:within("percussion", section, 0, nil, "perc")
			if flavour.amen > 0 then
				lanes:within("amen", section, 0, nil, "amen")
				lanes:within("chops", section, 0, nil, "chops")
			end
			lanes:within("sub", section, 0, nil, "sub.line")
			lanes:within("reese", section, 0, nil, "reese")
			if cycle.stabsOn then lanes:within("stabs", section, 0, nil, "stabs") end
			lanes:within("lead", section, 16, nil, "lead")
			lanes:phraseEnds("throws", section, 4, "throw")
		elseif id == "breakdown" then
			lanes:within("sub", section, 0, nil, "sub.hold")
			lanes:within("pads", section, 0, nil, "pads.chords")
			lanes:within("lead", section, 8, nil, "lead.soft")
		elseif id == "outro" then
			lanes:within("kick", section, 0, nil, "kick")
			lanes:within("snare", section, 0, nil, "snare")
			lanes:within("ghosts", section, 0, nil, "ghosts")
			lanes:within("hats", section, 0, nil, "hats")
			if flavour.amen > 0 then
				lanes:within("amen", section, 0, nil, "amen")
				lanes:within("chops", section, 0, nil, "chops")
			end
			lanes:within("sub", section, 0, 4, "sub.line")
			lanes:within("reese", section, 0, 4, "reese")
		end
	end
	kit.punctuate(lanes, track, function() return "fill.toms" end)
	return lanes:done()
end

-- The patterns -----------------------------------------------------------------

-- The cycle's break, turned into a fill on each fourth bar.
local function groove(ctx) return ctx.phraseBar % 4 == 3 and ctx.cycle.fill or ctx.cycle.groove end

local function lead(gain)
	return function(bar, ctx)
		for _, note in ipairs(ctx.cycle.lead[ctx.phraseBar % 4 + 1]) do
			table.insert(bar.lead, {step = note.step, length = note.length, glide = note.glide,
				gain = gain, note = ctx.kit.leadPitch(ctx.mode, ctx.tonic, ctx.chord.degree, note.offset)})
		end
	end
end

local PATTERNS = {
	{id = "kick", part = "kick", render = function(bar, ctx) bar:sequence(groove(ctx).kick, "kick", 0.95, ctx.humanize) end},
	-- The break's snares; its "o" steps are the ghost notes.
	{id = "snare", part = "snare", render = function(_, ctx)
		local snare = groove(ctx).snare
		for _, step in ipairs(ctx.kit.steps(snare)) do
			if snare:sub(step + 1, step + 1) ~= "o" then ctx.hit(step, "snare", 1, {throw = ctx.throw and step == 12 or nil}) end
		end
	end},
	{id = "ghosts", part = "ghosts", render = function(_, ctx)
		if ctx.complexity <= 0.2 then return end
		local snare = groove(ctx).snare
		for _, step in ipairs(ctx.kit.steps(snare)) do
			if snare:sub(step + 1, step + 1) == "o" then ctx.hit(step, "ghost", 0.3) end
		end
	end},
	{id = "fill.toms", part = "fills", render = function(_, ctx)
		for i, voice in ipairs({"tomHigh", "tomMid", "tomMid", "tomLow"}) do ctx.hit(11 + i, voice, 0.8) end
	end},
	{id = "hats", part = "hats", render = function(_, ctx)
		for step = 0, 15, 2 do ctx.hit(step, "hat", step % 4 == 0 and 0.45 or 0.3) end
		if ctx.energy > 0.6 then ctx.hit(6, "openHat", 0.4); ctx.hit(14, "openHat", 0.4) end
	end},
	{id = "ride", part = "ride", render = function(_, ctx) for step = 0, 15, 4 do ctx.hit(step, "ride", 0.3) end end},
	{id = "perc", part = "percussion", render = function(_, ctx)
		if ctx.complexity > 0.4 then ctx.hit(3, "conga", 0.3); ctx.hit(11, "rim", 0.3) end
	end},
	-- The Amen under the programmed kit; chops stutter its snares on each
	-- fourth bar's second half.
	{id = "amen", part = "amen", render = function(bar, ctx)
		local amen = ctx.kit.amen
		for step = 0, 15 do
			local slice = (ctx.n % amen.bars) * 16 + step
			if ctx.chops and ctx.phraseBar % 4 == 3 and step >= 8 and ctx.complexity > 0.3 then
				slice = amen.snareSlices[(step // 2) % #amen.snareSlices + 1]
			end
			table.insert(bar.breaks, {step = step, slice = slice, gain = 0.8 * ctx.flavour.amen})
		end
	end},
	-- A 16-step line: an acid 303 an octave up, or a sub line.
	{id = "sub.line", part = "sub", render = function(bar, ctx)
		local line, acid = ctx.cycle.line, ctx.cycle.acid
		for i, note in ipairs(line) do
			if note.threshold <= ctx.energy * 0.8 + 0.1 then
				local nextStep = line[i + 1] and line[i + 1].step or 16
				table.insert(bar.bass, {step = note.step,
					length = note.slide and nextStep - note.step + 0.5 or math.min(2, nextStep - note.step),
					note = ctx.chord.root + (acid and 12 or 0) + note.interval,
					glide = i > 1 and line[i - 1].slide, accent = acid and note.accent or nil, subOnly = true})
			end
		end
	end},
	{id = "stabs", part = "stabs", render = function(bar, ctx)
		for _, step in ipairs({0, 6, 10}) do
			if step == 0 or ctx.complexity > 0.4 then
				table.insert(bar.stabs, {step = step, notes = ctx.chord.notes, throw = ctx.throw and step == 10 or nil})
			end
		end
	end},
	{id = "lead", part = "lead", bars = 4, render = lead(0.85)},
	{id = "lead.soft", part = "lead", bars = 4, render = lead(0.6)},
}

return {
	api = 2,
	title = "Breakbeat",
	symbol = "opticaldisc.fill",
	summary = "Big Beat, Nu Skool and Florida breaks",
	tempo = {min = 120, max = 140, default = 130},
	defaults = {energy = 0.65, complexity = 0.55, swing = 0.1, humanize = 0.4,
		cutoff = 0.35, wobble = 0.1, drive = 0.55, space = 0.3},
	sound = {
		kick = {base = 52, sweep = 120, sweepTime = 0.02, decay = 0.18, drive = 2, click = 0.4, length = 0.35},
		snare = {tone = 210, overtone = 350, bodyDecay = 0.06, noiseDecay = 0.13, noise = 0.5},
		bass = {detune = 0, resonance = 0.2, envAmount = 2.8, envDecay = 0.12},
		stab = {decay = 0.2, octave = 1},
		mix = {duckDepth = 0.35, reese = 0.3, stab = 0.08, amen = 0.8},
	},
	set = {flavours = FLAVOURS, modes = {"minor", "dorian", "phrygian"}, arrangement = ARRANGEMENT},
	material = buildCycle,
	arrange = arrange,
	patterns = PATTERNS,
}
