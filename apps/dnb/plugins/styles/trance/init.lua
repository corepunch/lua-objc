-- Trance: Uplifting, Progressive and Psy tracks at 138. A punchy kick on
-- every beat, an off-beat bass (galloping 16ths in Psy), wide supersaw pads
-- through long breakdowns, a gated 16th arpeggio climbing the chord and an
-- anthem lead that returns, full, on the drop after the breakdown.

local FLAVOURS = {
	{id = "uplifting", name = "Uplifting", gallop = false, lead = 1, arp = 1},
	{id = "progressive", name = "Progressive", gallop = false, lead = 0.5, arp = 0.8},
	{id = "psy", name = "Psytrance", gallop = true, lead = 0.3, arp = 0.6},
}
-- Trance lives for the breakdown: long, with the pads and melody alone.
local ARRANGEMENT = {introBars = 16, buildBars = 8, dropBars = 32, breakdownBars = 24, rebuildBars = 8,
	outroBars = 16, blendBars = 8, minCycles = 2, maxCycles = 2}
-- The trance cadences: i–VI–III–VII and its relatives, two bars a chord.
local PROGRESSIONS = {{1, 6, 3, 7}, {6, 7, 1, 1}, {1, 6, 7, 5}, {1, 4, 6, 7}, {6, 4, 1, 7}}
local ARP_ORDERS = {{1, 2, 3, 4, 5, 4, 3, 2}, {1, 3, 2, 4, 3, 5, 4, 6}, {1, 2, 3, 5, 1, 2, 4, 5}, {1, 4, 3, 5, 2, 4, 3, 6}}

local function buildCycle(kit, rng, track)
	local mode, flavour = track.mode, track.flavour
	local progression = kit.stableProgression(mode, rng.pick(PROGRESSIONS))
	return {
		progression = progression,
		voicings = kit.voicings(mode, progression, {0, 2, 4, 8}), -- add9: the open trance sound
		arp = rng.pick(ARP_ORDERS),
		gate = {},
		leadOn = rng.chance(flavour.lead), arpOn = rng.chance(flavour.arp),
		lead = kit.melody(rng),
	}
end

local Composer = {}
Composer.__index = Composer

function Composer:cycle(track, index)
	local kit = self.kit
	-- One melody per track: the anthem comes back on every drop.
	local first = self.set:cycle(track, 0, function(rng) return buildCycle(kit, rng, track) end)
	if index == 0 then return first end
	return self.set:cycle(track, index, function(rng)
		local cycle = buildCycle(kit, rng, track)
		cycle.lead, cycle.progression, cycle.voicings = first.lead, first.progression, first.voicings
		cycle.leadOn = first.leadOn
		return cycle
	end)
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
	local throwBar = on("throws") and phraseBar % 8 == 7 and (at.full or breakdown)

	if on("kick") and groove then
		for step = 0, 12, 4 do
			if not (at.fillBar and step == 12) then hit(step, "kick", 1) end
		end
	end
	if on("snare") and (at.full or at.outro) then
		hit(4, "clap", 0.75)
		hit(12, "clap", 0.75, {throw = throwBar or nil})
	end
	if on("hats") and not breakdown then
		for step = 2, 14, 4 do hit(step, "openHat", 0.5) end
		if at.full or section == "build" then
			for step = 0, 15 do if step % 4 ~= 2 then hit(step, "hat", step % 2 == 0 and 0.3 or 0.18) end end
		end
	end
	if on("ride") and at.full and sectionBar >= 16 then
		for step = 2, 15, 4 do hit(step, "ride", 0.35) end
	end
	if on("percussion") and at.full and complexity > 0.4 then
		for _, step in ipairs({3, 7, 11, 15}) do if step ~= 7 or complexity > 0.7 then hit(step, "shaker", 0.3) end end
	end
	if at.fillBar and on("snare") then
		for step = 12, 15.5, 0.5 do hit(step, "snare", 0.3 + 0.1 * (step - 12)) end
	end
	kit.punctuate(bar, at, settings, "snare", humanize)

	-- Bass: the off-beat root, or the psy gallop filling every 16th but the
	-- kick's.
	if (at.full or (at.outro and sectionBar < 8)) and (on("sub") or on("reese")) then
		for step = 0, 15 do
			local offbeat = step % 4 == 2
			local gallop = flavour.gallop and step % 4 ~= 0 and (energy > 0.3 or offbeat)
			if offbeat or gallop then
				table.insert(bar.bass, {step = step, length = offbeat and not flavour.gallop and 1.6 or 0.8,
					note = chord.root + 12, reese = 0.9, accent = offbeat and flavour.gallop or nil})
			end
		end
	elseif section == "build" and on("sub") and sectionBar >= 4 then
		for step = 2, 14, 4 do table.insert(bar.bass, {step = step, length = 1, note = chord.root + 12, subOnly = true}) end
	end

	if on("pads") and n % 2 == 0 and (breakdown or section == "build" or at.full) then bar.pad = chord.notes end
	kit.blend(bar, at, settings, set, ARRANGEMENT.blendBars, function(t, m) return self:chordOf(t, m) end)
	if on("stabs") and at.full and sectionBar >= 16 and energy > 0.5 then
		table.insert(bar.stabs, {step = 0, notes = chord.notes})
	end

	-- The gated arpeggio: 16ths climbing and falling through the chord with
	-- its octave, the trance signature.
	if on("arp") and cycle.arpOn and not (section == "intro" and sectionBar < 8) then
		for step = 0, 15 do
			if step % 2 == 0 or complexity > 0.3 or breakdown then
				local index = cycle.arp[(step % #cycle.arp) + 1]
				local note = chord.notes[(index - 1) % 4 + 1] + 12 * (1 + (index - 1) // 4)
				table.insert(bar.arp, {step = step, note = note, length = 0.7,
					gain = step % 4 == 0 and 1 or 0.65, pan = step % 2 == 0 and 0.3 or 0.7})
			end
		end
	end
	-- The anthem: softly in the second half of the breakdown, then full
	-- once the drop that follows it lands.
	local anthem = cycle.leadOn and ((breakdown and sectionBar >= 8) or (at.full and at.cycleIndex > 0) or
		(at.full and sectionBar >= 16))
	if on("lead") and anthem then
		for _, note in ipairs(cycle.lead[phraseBar % 4 + 1]) do
			table.insert(bar.lead, {step = note.step, length = note.length, glide = note.glide,
				gain = breakdown and 0.7 or 1, note = kit.leadPitch(mode, tonic, chord.degree, note.offset),
				throw = throwBar or nil})
		end
	end
	return bar
end

return {
	api = 1,
	title = "Trance",
	symbol = "sparkles",
	summary = "Uplifting, Progressive and Psy, with long breakdowns",
	tempo = {min = 132, max = 145, default = 138},
	defaults = {energy = 0.7, complexity = 0.6, swing = 0, humanize = 0.1,
		cutoff = 0.4, wobble = 0, drive = 0.3, space = 0.6},
	parts = {"kick", "snare", "hats", "ride", "percussion", "sub", "reese", "pads", "stabs", "arp", "lead",
		"arrangement", "fills", "risers", "modulate", "throws"},
	sound = {
		kick = {base = 48, sweep = 150, sweepTime = 0.02, decay = 0.2, drive = 2.2, click = 0.45, length = 0.35},
		hat = {scale = 2, decay = 0.012, openDecay = 0.06},
		bass = {detune = 0.003, resonance = 0.55, envAmount = 2, envDecay = 0.05},
		pad = {detune = 0.012, attack = 0.6, release = 1.4, brightness = 0.09},
		pluck = {decay = 0.07, sweep = 0.03, send = 1.1},
		lead = {detune = 0.008, brightness = 0.16, sweep = 0.3, vibratoDepth = 0.009, send = 0.8},
		mix = {duckDepth = 0.7, pad = 0.07, arp = 0.09, lead = 0.08, delayFeedback = 0.45, reverbSend = 1.1},
	},
	create = function(kit, seed)
		return setmetatable({kit = kit, seed = seed, set = kit.newSet(seed, {
			flavours = FLAVOURS, modes = {"minor", "phrygian"}, arrangement = ARRANGEMENT, modulations = {2, 0},
		})}, Composer)
	end,
}
