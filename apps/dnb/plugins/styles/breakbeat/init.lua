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

local Composer = {}
Composer.__index = Composer

function Composer:cycle(track, index)
	local kit = self.kit
	return self.set:cycle(track, index, function(rng) return buildCycle(kit, rng, track) end)
end
function Composer:trackAt(n) return self.set:trackAt(n) end
function Composer:trackStart(k) return self.set:trackStart(k) end

function Composer:chordOf(track, n)
	local cycle = self:cycle(track, track.cycles - 1)
	return self.kit.chordAt(track.mode, cycle.progression, cycle.voicings, track.tonic, n),
		self.kit.keyName(track.tonic, track.mode)
end

function Composer:bar(n, settings)
	local kit, set = self.kit, self.set
	local amen = kit.amen
	local on = function(part) return settings:plays(part) end
	local energy, complexity = settings:value("energy"), settings:value("complexity")
	local humanize = settings:value("humanize")
	local at = set:locate(n, settings)
	local section, sectionBar, phraseBar = at.section, at.sectionBar, at.phraseBar
	local track, tonic, flavour, mode = at.track, at.tonic, at.track.flavour, at.track.mode
	local cycle = self:cycle(track, at.cycleIndex)
	local chord = kit.chordAt(mode, cycle.progression, cycle.voicings, tonic, n)
	local bar = kit.newBar(n, at, kit.random(self.seed, 2, n))
	bar.progression, bar.chord = kit.progressionName(mode, cycle.progression), chord
	local function hit(step, voice, gain, extra) return bar:hit(step, voice, gain, humanize, extra) end
	local groove = at.full or at.outro or section == "intro"
	local breakdown = section == "breakdown"
	local throwBar = on("throws") and phraseBar % 4 == 3 and at.full

	local pattern = phraseBar % 4 == 3 and cycle.fill or cycle.groove
	if on("kick") and groove then bar:pattern(pattern.kick, "kick", 0.95, humanize) end
	if on("snare") and groove then
		local steps = kit.steps(pattern.snare)
		for _, step in ipairs(steps) do
			local ghost = pattern.snare:sub(step + 1, step + 1) == "o"
			if not ghost then hit(step, "snare", 1, {throw = throwBar and step == 12 or nil})
			elseif on("ghosts") and complexity > 0.2 then hit(step, "ghost", 0.3) end
		end
	end
	if at.fillBar then
		local toms = {"tomHigh", "tomMid", "tomMid", "tomLow"}
		for i, voice in ipairs(toms) do hit(11 + i, voice, 0.8) end
	end
	if on("hats") and not breakdown then
		for step = 0, 15, 2 do hit(step, "hat", step % 4 == 0 and 0.45 or 0.3) end
		if energy > 0.6 then hit(6, "openHat", 0.4); hit(14, "openHat", 0.4) end
	end
	if on("ride") and at.full and sectionBar >= 16 then for step = 0, 15, 4 do hit(step, "ride", 0.3) end end
	if on("percussion") and at.full and complexity > 0.4 then hit(3, "conga", 0.3); hit(11, "rim", 0.3) end
	kit.punctuate(bar, at, settings, "snare", humanize)

	-- The Amen near its own tempo, layered under the programmed break.
	if on("amen") and flavour.amen > 0 and (at.full or at.outro or (section == "intro" and flavour.amen >= 1)) then
		for step = 0, 15 do
			local slice = (n % amen.bars) * 16 + step
			if on("chops") and phraseBar % 4 == 3 and step >= 8 and complexity > 0.3 then
				slice = amen.snareSlices[(step // 2) % #amen.snareSlices + 1]
			end
			table.insert(bar.breaks, {step = step, slice = slice, gain = 0.8 * flavour.amen})
		end
	end

	if (at.full or (at.outro and sectionBar < 4)) and (on("sub") or on("reese")) then
		for i, note in ipairs(cycle.line) do
			if note.threshold <= energy * 0.8 + 0.1 then
				local nextStep = cycle.line[i + 1] and cycle.line[i + 1].step or 16
				table.insert(bar.bass, {step = note.step,
					length = note.slide and nextStep - note.step + 0.5 or math.min(2, nextStep - note.step),
					note = chord.root + (cycle.acid and 12 or 0) + note.interval,
					glide = i > 1 and cycle.line[i - 1].slide, accent = cycle.acid and note.accent or nil})
			end
		end
	elseif breakdown and on("sub") then
		table.insert(bar.bass, {step = 0, length = 16, note = chord.root, subOnly = true})
	end

	if on("pads") and n % 2 == 0 and (breakdown or section == "build") then bar.pad = chord.notes end
	kit.blend(bar, at, settings, set, ARRANGEMENT.blendBars, function(t, m) return self:chordOf(t, m) end)
	if on("stabs") and cycle.stabsOn and at.full then
		for _, step in ipairs({0, 6, 10}) do
			if step == 0 or complexity > 0.4 then
				table.insert(bar.stabs, {step = step, notes = chord.notes, throw = throwBar and step == 10 or nil})
			end
		end
	end
	if on("lead") and ((at.full and sectionBar >= 16) or (breakdown and sectionBar >= 8)) then
		for _, note in ipairs(cycle.lead[phraseBar % 4 + 1]) do
			table.insert(bar.lead, {step = note.step, length = note.length, glide = note.glide,
				gain = breakdown and 0.6 or 0.85, note = kit.leadPitch(mode, tonic, chord.degree, note.offset)})
		end
	end
	return bar
end

return {
	api = 1,
	title = "Breakbeat",
	symbol = "opticaldisc.fill",
	summary = "Big Beat, Nu Skool and Florida breaks",
	tempo = {min = 120, max = 140, default = 130},
	defaults = {energy = 0.65, complexity = 0.55, swing = 0.1, humanize = 0.4,
		cutoff = 0.35, wobble = 0.1, drive = 0.55, space = 0.3},
	parts = {"kick", "snare", "ghosts", "hats", "ride", "percussion", "amen", "sub", "reese", "pads", "stabs", "lead",
		"arrangement", "fills", "risers", "modulate", "throws", "chops"},
	sound = {
		kick = {base = 52, sweep = 120, sweepTime = 0.02, decay = 0.18, drive = 2, click = 0.4, length = 0.35},
		snare = {tone = 210, overtone = 350, bodyDecay = 0.06, noiseDecay = 0.13, noise = 0.5},
		bass = {detune = 0, resonance = 0.2, envAmount = 2.8, envDecay = 0.12},
		stab = {decay = 0.2, octave = 1},
		mix = {duckDepth = 0.35, reese = 0.3, stab = 0.08, amen = 0.8},
	},
	create = function(kit, seed)
		return setmetatable({kit = kit, seed = seed, set = kit.newSet(seed, {
			flavours = FLAVOURS, modes = {"minor", "dorian", "phrygian"}, arrangement = ARRANGEMENT,
		})}, Composer)
	end,
}
