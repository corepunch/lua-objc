-- Dubstep: Deep, Brostep and Riddim tracks at 140, felt at half time. The
-- kick opens the bar and the snare lands on beat three; the drop is the
-- wobble — a detuned, driven bass whose filter LFO restarts with every note
-- at a rate the note chooses (quarters, eighths, triplets, sixteenths).
-- Deep tracks keep the original sub-heavy, dub-echo sound.

local FLAVOURS = {
	{id = "deep", name = "Deep Dubstep", wobble = 0.6, stabs = 0.3, rates = {0.5, 1, 1, 2}, pads = 1},
	{id = "brostep", name = "Brostep", wobble = 1, stabs = 1, rates = {1, 2, 3, 4, 6}, pads = 0.4},
	{id = "riddim", name = "Riddim", wobble = 1, stabs = 0.5, rates = {2, 3, 3, 4}, pads = 0.2},
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
	return self.kit.chordAt(track.mode, cycle.progression, cycle.voicings, track.tonic, n, 4),
		self.kit.keyName(track.tonic, track.mode)
end

function Composer:bar(n, settings)
	local kit, set = self.kit, self.set
	local on = function(part) return settings:enabled(part) end
	local energy, complexity = settings:value("energy"), settings:value("complexity")
	local humanize = settings:value("humanize")
	local at = set:locate(n, settings)
	local section, sectionBar, phraseBar = at.section, at.sectionBar, at.phraseBar
	local track, tonic, flavour, mode = at.track, at.tonic, at.track.flavour, at.track.mode
	local cycle = self:cycle(track, at.cycleIndex)
	local chord = kit.chordAt(mode, cycle.progression, cycle.voicings, tonic, n, 4)
	local bar = kit.newBar(n, at, kit.random(self.seed, 2, n))
	bar.progression, bar.chord = kit.progressionName(mode, cycle.progression), chord
	local function hit(step, voice, gain, extra) return bar:hit(step, voice, gain, humanize, extra) end
	local groove = at.full or at.outro or section == "intro"
	local breakdown = section == "breakdown"
	local throwBar = on("throws") and phraseBar % 4 == 3

	if on("kick") and groove then
		for _, step in ipairs(cycle.kicks) do hit(step, "kick", step == 0 and 1 or 0.85) end
		if complexity > 0.6 and at.full then hit(11, "kick", 0.7) end
	end
	if on("snare") and groove then
		hit(8, "snare", 1, {throw = throwBar or nil})
		if at.fillBar then for step = 12, 15.5, 0.5 do hit(step, "snare", 0.35 + 0.1 * (step - 12)) end end
	end
	if on("ghosts") and at.full then
		for _, step in ipairs({6, 14, 15}) do if complexity > 0.3 or step == 14 then hit(step, "ghost", 0.25) end end
	end
	if on("hats") and not breakdown then
		-- Triplet-feel hats: every third 16th, the swagger over the half time.
		for step = 0, 15, 3 do hit(step, "hat", step % 6 == 0 and 0.5 or 0.3) end
		if energy > 0.6 and at.full then hit(14, "openHat", 0.4) end
	end
	if on("percussion") and at.full then hit(12, "rim", 0.3) end
	kit.punctuate(bar, at, settings, "snare", humanize)

	-- The wobble: long notes whose LFO restarts on each, at the note's rate.
	if at.full and (on("sub") or on("reese")) then
		for _, note in ipairs(cycle.phrases[phraseBar % 4 + 1]) do
			if note.step == 0 or energy > 0.3 then
				table.insert(bar.bass, {step = note.step, length = note.length, note = chord.root + note.interval,
					reese = flavour.wobble, wobble = note.rate * (0.5 + energy)})
			end
		end
	elseif (breakdown or at.outro or (section == "build" and sectionBar >= 4)) and on("sub") then
		table.insert(bar.bass, {step = 0, length = 16, note = chord.root, subOnly = true})
	end

	if on("pads") and n % 4 == 0 and (breakdown or section == "intro" or section == "build") then bar.pad = chord.notes end
	kit.blend(bar, at, settings, set, ARRANGEMENT.blendBars, function(t, m) return self:chordOf(t, m) end)
	if on("stabs") and cycle.stabsOn and at.full then
		table.insert(bar.stabs, {step = 6, notes = chord.notes, throw = throwBar or nil})
		if complexity > 0.5 then table.insert(bar.stabs, {step = 14, notes = chord.notes}) end
	end
	if on("lead") and breakdown then
		for _, note in ipairs(cycle.lead[phraseBar % 4 + 1]) do
			table.insert(bar.lead, {step = note.step, length = note.length, glide = note.glide, gain = 0.6,
				note = kit.leadPitch(mode, tonic, chord.degree, note.offset) - 12})
		end
	end
	return bar
end

return {
	api = 1,
	title = "Dubstep",
	symbol = "speaker.wave.3.fill",
	summary = "Deep, Brostep and Riddim wobble at half time",
	tempo = {min = 136, max = 150, default = 140},
	defaults = {energy = 0.7, complexity = 0.5, swing = 0.05, humanize = 0.2,
		cutoff = 0.42, wobble = 0.85, drive = 0.6, space = 0.35},
	parts = {"kick", "snare", "ghosts", "hats", "percussion", "sub", "reese", "pads", "stabs", "lead",
		"arrangement", "fills", "risers", "modulate", "throws"},
	labels = {reese = "Wobble"},
	sound = {
		kick = {base = 44, sweep = 140, sweepTime = 0.022, decay = 0.26, drive = 2.4, click = 0.4, length = 0.5},
		snare = {tone = 200, bodyDecay = 0.07, noiseDecay = 0.16, noise = 0.55},
		bass = {detune = 0.009, resonance = 0.45, retrigger = true, wobbleOctaves = 4.2, glide = 0.004},
		stab = {decay = 0.18, octave = 0},
		mix = {duckDepth = 0.35, reese = 0.4, sub = 0.6, delayFeedback = 0.5, delaySteps = 3},
	},
	create = function(kit, seed)
		return setmetatable({kit = kit, seed = seed, set = kit.newSet(seed, {
			flavours = FLAVOURS, modes = {"phrygian", "minor"}, arrangement = ARRANGEMENT, modulations = {0, -2},
		})}, Composer)
	end,
}
