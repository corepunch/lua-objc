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
	local throwBar = on("throws") and phraseBar % 4 == 3 and (at.full or breakdown)

	-- Four on the floor; a fill bar drops the last kick for a clap flam.
	if on("kick") and groove then
		for step = 0, 12, 4 do
			if not (at.fillBar and step == 12) then hit(step, "kick", step == 0 and 1 or 0.95) end
		end
	end
	if on("snare") and (at.full or at.outro or (section == "intro" and sectionBar >= 8)) then
		hit(4, "clap", 0.9)
		hit(12, "clap", 0.9, {throw = throwBar or nil})
		if at.fillBar then hit(14, "clap", 0.6); hit(15, "clap", 0.8) end
	end
	if on("hats") and not breakdown then
		for step = 2, 14, 4 do hit(step, "openHat", section == "intro" and 0.35 or 0.5) end
		if at.full and energy > 0.4 then
			for step = 0, 15 do
				if step % 4 ~= 2 and (step % 2 == 1 or energy > 0.75) then hit(step, "hat", step % 2 == 0 and 0.3 or 0.2) end
			end
		end
	end
	if on("ride") and at.full and at.sectionBar >= 8 then
		for step = 2, 15, 4 do hit(step, "ride", 0.3) end
	end
	if on("ghosts") and (at.full or at.outro) then
		for _, rim in ipairs(cycle.rims) do
			if rim.threshold < complexity * 0.7 then hit(rim.step, "rim", 0.35) end
		end
	end
	if on("percussion") and at.full then
		for _, p in ipairs(cycle.percussion) do
			if p.chance < energy * 0.25 + complexity * 0.25 then hit(p.step, p.voice, 0.3 + 0.2 * p.chance) end
		end
	end
	kit.punctuate(bar, at, settings, "clap", humanize)

	-- Bass: the acid line, or the rumble rolling on the two 16ths after
	-- each kick. Builds and breakdowns hold it back.
	local acid = flavour.acid >= 1 or (flavour.acid > 0 and at.cycleIndex % 2 == 1)
	if (at.full or (at.outro and sectionBar < 8)) and (on("sub") or on("reese")) then
		if acid and on("reese") then
			for i, note in ipairs(cycle.acid) do
				if note.threshold <= energy * 0.7 + complexity * 0.3 then
					local nextStep = cycle.acid[i + 1] and cycle.acid[i + 1].step or 16
					table.insert(bar.bass, {step = note.step, length = note.slide and nextStep - note.step + 0.5 or 1,
						note = chord.root + 12 + note.interval, glide = i > 1 and cycle.acid[i - 1].slide, accent = note.accent})
				end
			end
		else
			for beat = 0, 3 do
				for _, offset in ipairs({2, 3}) do
					if offset == 2 or energy > 0.5 then
						table.insert(bar.bass, {step = beat * 4 + offset, length = 1, note = chord.root, reese = flavour.rumble})
					end
				end
			end
		end
	elseif breakdown and on("sub") and sectionBar >= 8 then
		table.insert(bar.bass, {step = 0, length = 16, note = chord.root, subOnly = true})
	end

	if on("pads") and (breakdown or section == "build" or (at.full and sectionBar >= 16)) and n % 4 == 0 then
		bar.pad = chord.notes
	end
	kit.blend(bar, at, settings, set, ARRANGEMENT.blendBars, function(t, m) return self:chordOf(t, m) end)
	if on("stabs") and cycle.stabOn and (at.full or breakdown) then
		for _, s in ipairs(cycle.stabs) do
			if s.threshold <= complexity * 0.8 + 0.2 then
				table.insert(bar.stabs, {step = s.step, notes = chord.notes, throw = throwBar or on("throws") and s.step == 14 or nil})
			end
		end
	end
	if on("arp") and cycle.arpOn and (section == "build" or breakdown) then
		for step = 0, 15, 2 do
			local tone = cycle.arp[(step // 2) % #cycle.arp + 1]
			table.insert(bar.arp, {step = step, note = chord.notes[tone] + 12, length = 1.5,
				gain = step % 4 == 0 and 1 or 0.7, pan = step % 4 == 0 and 0.35 or 0.65})
		end
	end
	if on("lead") and cycle.leadOn and at.full and sectionBar >= 16 then
		for _, note in ipairs(cycle.lead[phraseBar % 4 + 1]) do
			table.insert(bar.lead, {step = note.step, length = note.length, glide = note.glide, gain = 0.8,
				note = kit.leadPitch(mode, tonic, chord.degree, note.offset)})
		end
	end
	return bar
end

return {
	api = 1,
	title = "Techno",
	symbol = "metronome.fill",
	summary = "Peak Time, Acid and Hypnotic, four to the floor",
	tempo = {min = 124, max = 140, default = 132},
	defaults = {energy = 0.7, complexity = 0.5, swing = 0, humanize = 0.15,
		cutoff = 0.32, wobble = 0.05, drive = 0.45, space = 0.4},
	parts = {"kick", "snare", "ghosts", "hats", "ride", "percussion", "sub", "reese", "pads", "stabs", "arp", "lead",
		"arrangement", "fills", "risers", "modulate", "throws"},
	labels = {snare = "Clap", ghosts = "Rims", reese = "Acid"},
	sound = {
		kick = {base = 50, sweep = 170, sweepTime = 0.018, decay = 0.3, drive = 2.6, click = 0.5, length = 0.55},
		hat = {scale = 1.9, decay = 0.012, openDecay = 0.07},
		bass = {detune = 0, resonance = 0.16, envAmount = 3.2, envDecay = 0.1, lfoRate = 1, glide = 0.004},
		stab = {decay = 0.22, octave = 0},
		mix = {duckDepth = 0.55, reese = 0.3, stab = 0.08, delayFeedback = 0.5},
	},
	create = function(kit, seed)
		return setmetatable({kit = kit, seed = seed, set = kit.newSet(seed, {
			flavours = FLAVOURS, modes = {"minor", "phrygian"}, arrangement = ARRANGEMENT, modulations = {0, 5, -2},
		})}, Composer)
	end,
}
