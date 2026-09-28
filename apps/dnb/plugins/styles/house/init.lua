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
	return self.kit.chordAt(track.mode, cycle.progression, cycle.voicings, track.tonic, n, 1),
		self.kit.keyName(track.tonic, track.mode)
end

function Composer:bar(n, settings)
	local kit, set = self.kit, self.set
	local on = function(part) return settings:plays(part) end
	local energy, complexity = settings:value("energy"), settings:value("complexity")
	local humanize = settings:value("humanize")
	local at = set:locate(n, settings)
	local section, sectionBar, phraseBar = at.section, at.sectionBar, at.phraseBar
	local track, tonic, mode = at.track, at.tonic, at.track.mode
	local cycle = self:cycle(track, at.cycleIndex)
	local chord = kit.chordAt(mode, cycle.progression, cycle.voicings, tonic, n, 1)
	local bar = kit.newBar(n, at, kit.random(self.seed, 2, n))
	bar.progression, bar.chord = kit.progressionName(mode, cycle.progression), chord
	local function hit(step, voice, gain, extra) return bar:hit(step, voice, gain, humanize, extra) end
	local groove = at.full or at.outro or section == "intro"
	local breakdown = section == "breakdown"
	local throwBar = on("throws") and phraseBar % 4 == 3 and (at.full or breakdown)

	if on("kick") and groove then bar:pattern("x...x...x...x...", "kick", 1, humanize) end
	if on("snare") and (at.full or at.outro or (section == "intro" and sectionBar >= 8)) then
		hit(4, "clap", 0.85)
		hit(12, "clap", 0.85, {throw = throwBar or nil})
		if at.fillBar then for step = 13, 15 do hit(step, "clap", 0.4 + 0.15 * (step - 13)) end end
	end
	if on("hats") and not breakdown then
		for step = 2, 14, 4 do hit(step, "openHat", 0.45) end
		if cycle.shaker and on("percussion") and (at.full or at.outro) then
			for step = 0, 15 do hit(step, "shaker", step % 2 == 0 and 0.35 or 0.22) end
		elseif at.full and energy > 0.5 then
			for step = 0, 15, 2 do if step % 4 ~= 2 then hit(step, "hat", 0.3) end end
		end
	end
	if on("ride") and at.full and sectionBar >= 16 then
		for step = 0, 15, 2 do hit(step, "ride", step % 4 == 2 and 0.35 or 0.22) end
	end
	if on("percussion") and at.full and complexity > 0.3 then
		hit(7, "conga", 0.35)
		if complexity > 0.6 then hit(10, "conga", 0.3); hit(15, "rim", 0.3) end
	end
	kit.punctuate(bar, at, settings, "clap", humanize)

	if (at.full or (at.outro and sectionBar < 8)) and (on("sub") or on("reese")) then
		for i, note in ipairs(cycle.bassLine) do
			if i == 1 or note[1] % 4 == 2 or energy > 0.4 then
				table.insert(bar.bass, {step = note[1], length = 1.5, note = chord.root + 12 + note[2], reese = 0.8})
			end
		end
	elseif breakdown and on("sub") then
		table.insert(bar.bass, {step = 0, length = 16, note = chord.root, subOnly = true})
	end

	if on("pads") and (breakdown or section == "build" or section == "intro" or (at.full and sectionBar >= 16)) and n % 2 == 0 then
		bar.pad = chord.notes
	end
	kit.blend(bar, at, settings, set, ARRANGEMENT.blendBars, function(t, m) return self:chordOf(t, m) end)
	if on("keys") and cycle.keysOn and (at.full or breakdown or at.outro) then
		for index, step in ipairs(cycle.comp) do
			if index == 1 or complexity > 0.25 then
				table.insert(bar.keys, {step = step, length = 2, notes = chord.notes, gain = index == 1 and 1 or 0.75})
			end
		end
	end
	if on("stabs") and cycle.stabsOn and at.full and energy > 0.35 then
		for _, step in ipairs({3, 6, 11}) do
			if step ~= 11 or complexity > 0.5 then
				table.insert(bar.stabs, {step = step, notes = chord.notes, throw = throwBar and step == 11 or nil})
			end
		end
	end
	if on("arp") and cycle.arpOn and (section == "build" or breakdown) then
		for step = 0, 15, 2 do
			table.insert(bar.arp, {step = step, note = chord.notes[(step // 2) % #chord.notes + 1] + 12, length = 1.5,
				gain = step % 4 == 0 and 0.9 or 0.6, pan = step % 4 == 0 and 0.4 or 0.6})
		end
	end
	if on("lead") and cycle.leadOn and ((at.full and sectionBar >= 16) or (breakdown and sectionBar >= 8)) then
		for _, note in ipairs(cycle.lead[phraseBar % 4 + 1]) do
			table.insert(bar.lead, {step = note.step, length = note.length, glide = note.glide,
				gain = breakdown and 0.6 or 0.85, note = kit.leadPitch(mode, tonic, chord.degree, note.offset)})
		end
	end
	return bar
end

return {
	api = 1,
	title = "House",
	symbol = "house.fill",
	summary = "Deep, Classic and Disco house, four to the floor",
	tempo = {min = 118, max = 128, default = 124},
	defaults = {energy = 0.6, complexity = 0.5, swing = 0.08, humanize = 0.3,
		cutoff = 0.45, wobble = 0, drive = 0.2, space = 0.45},
	parts = {"kick", "snare", "hats", "ride", "percussion", "sub", "reese", "pads", "keys", "stabs", "arp", "lead",
		"arrangement", "fills", "risers", "modulate", "throws"},
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
	create = function(kit, seed)
		return setmetatable({kit = kit, seed = seed, set = kit.newSet(seed, {
			flavours = FLAVOURS, modes = {"dorian", "minor", "major"}, arrangement = ARRANGEMENT, modulations = {0, 2, 5},
		})}, Composer)
	end,
}
