-- UK Garage: 2-Step, Speed Garage and Future Garage at 132. The skippy
-- two-step kick that leaves beats two and four to the snare, heavy shuffle
-- on the hats, rim shots, minor-ninth organ chords and a bouncing bass —
-- the speed-garage reese, or the washed-out chords and pitched vocal-like
-- lead of future garage.

local FLAVOURS = {
	{id = "twostep", name = "2-Step", reese = 0.5, keys = 1, lead = 0.6},
	{id = "speed", name = "Speed Garage", reese = 1, keys = 0.4, lead = 0.3},
	{id = "future", name = "Future Garage", reese = 0.3, keys = 0.7, lead = 1},
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
	local on = function(part) return settings:enabled(part) end
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
	local throwBar = on("throws") and phraseBar % 4 == 3 and (at.full or breakdown)

	if on("kick") and groove then
		bar:pattern(phraseBar % 4 == 3 and cycle.altKicks or cycle.kicks, "kick", 0.9, humanize)
	end
	if on("snare") and (at.full or at.outro or (section == "intro" and sectionBar >= 4)) then
		hit(4, "snare", 0.9)
		hit(12, "snare", 0.9, {throw = throwBar or nil})
		if flavour.id ~= "future" then hit(4, "clap", 0.5); hit(12, "clap", 0.5) end
	end
	if on("ghosts") and (at.full or at.outro) then
		for _, step in ipairs({7, 15, 9}) do if step ~= 9 or complexity > 0.5 then hit(step, "rim", 0.35) end end
	end
	if on("hats") and not breakdown then
		-- Shuffled 16ths (Swing moves the off ones late) with open hats
		-- answering the kick.
		for step = 0, 15 do
			if step % 2 == 1 or energy > 0.5 then hit(step, "hat", step % 2 == 1 and 0.35 or 0.2) end
		end
		hit(14, "openHat", 0.4)
		if complexity > 0.5 then hit(6, "openHat", 0.3) end
	end
	if on("percussion") and at.full then
		for step = 2, 15, 4 do if complexity > 0.3 then hit(step, "shaker", 0.3) end end
	end
	if at.fillBar and on("snare") then for step = 13, 15 do hit(step, "snare", 0.5 + 0.12 * (step - 13)) end end
	kit.punctuate(bar, at, settings, "snare", humanize)

	if (at.full or (at.outro and sectionBar < 8)) and (on("sub") or on("reese")) then
		for _, note in ipairs(cycle.bass) do
			if note[1] == 0 or energy > 0.35 then
				table.insert(bar.bass, {step = note[1], length = note[2], note = chord.root + note[3],
					glide = note[3] ~= 0, reese = flavour.reese})
			end
		end
	elseif breakdown and on("sub") then
		table.insert(bar.bass, {step = 0, length = 16, note = chord.root, subOnly = true})
	end

	if on("pads") and n % 2 == 0 and (breakdown or section == "build" or flavour.id == "future") then bar.pad = chord.notes end
	kit.blend(bar, at, settings, set, ARRANGEMENT.blendBars, function(t, m) return self:chordOf(t, m) end)
	if on("keys") and cycle.keysOn and (at.full or breakdown or at.outro) then
		for index, step in ipairs(cycle.comp) do
			table.insert(bar.keys, {step = step, length = 2, notes = chord.notes, gain = index == 1 and 1 or 0.7})
		end
	end
	if on("stabs") and at.full and flavour.id == "speed" then
		table.insert(bar.stabs, {step = 6, notes = chord.notes, throw = throwBar or nil})
	end
	if on("lead") and cycle.leadOn and ((at.full and sectionBar >= 16) or breakdown) then
		for _, note in ipairs(cycle.lead[phraseBar % 4 + 1]) do
			table.insert(bar.lead, {step = note.step, length = note.length, glide = true,
				gain = breakdown and 0.6 or 0.8, note = kit.leadPitch(mode, tonic, chord.degree, note.offset)})
		end
	end
	return bar
end

return {
	api = 1,
	title = "UK Garage",
	symbol = "figure.dance",
	summary = "2-Step, Speed Garage and Future Garage shuffle",
	tempo = {min = 128, max = 138, default = 132},
	defaults = {energy = 0.6, complexity = 0.55, swing = 0.3, humanize = 0.35,
		cutoff = 0.4, wobble = 0.15, drive = 0.3, space = 0.45},
	parts = {"kick", "snare", "ghosts", "hats", "percussion", "sub", "reese", "pads", "keys", "stabs", "lead",
		"arrangement", "fills", "risers", "modulate", "throws"},
	labels = {ghosts = "Rims", keys = "Organ"},
	sound = {
		kick = {base = 50, sweep = 100, sweepTime = 0.02, decay = 0.2, drive = 1.8, click = 0.3, length = 0.38},
		snare = {tone = 220, overtone = 360, bodyDecay = 0.045, noiseDecay = 0.08, noise = 0.45},
		hat = {scale = 1.8, decay = 0.014, openDecay = 0.08},
		bass = {detune = 0.006, resonance = 0.6, lfoRate = 4},
		keys = {index = 0.8, indexFloor = 0.6, tine = 0.05, decay = 0.9, autopanDepth = 0.15},
		lead = {glide = 0.001, vibratoDepth = 0.012, brightness = 0.07, square = 0.1},
		mix = {duckDepth = 0.4, keys = 0.065, lead = 0.065, delaySteps = 3},
	},
	create = function(kit, seed)
		return setmetatable({kit = kit, seed = seed, set = kit.newSet(seed, {
			flavours = FLAVOURS, modes = {"minor", "dorian"}, arrangement = ARRANGEMENT, modulations = {0, 5},
		})}, Composer)
	end,
}
