-- Drum & bass: an endless DJ set of Liquid, Jungle, Neurofunk and Rollers
-- tracks. Two-step grooves with ghost notes, the Amen break layered and
-- chopped, rolling reese and sub, voice-led extended chords, electric-piano
-- comping, arpeggios and a call-and-response lead; half-time switch-ups and
-- dub throws. `bar(n)` is a pure function of seed, bar and settings.

-- Flavours weight the parts a track leans on. Every part still answers to
-- its pad; a flavour only decides how much of it the track uses.
local FLAVOURS = {
	{id = "liquid", name = "Liquid", amen = 0.45, keys = 1, reese = 0.55, lead = 0.9, arp = 0.9, stabs = 0.4, halftime = 0.25},
	{id = "jungle", name = "Jungle", amen = 1, keys = 0.5, reese = 0.5, lead = 0.5, arp = 0.4, stabs = 0.7, halftime = 0.2},
	{id = "neuro", name = "Neurofunk", amen = 0, keys = 0, reese = 1, lead = 0.4, arp = 0.5, stabs = 1, halftime = 0.7},
	{id = "rollers", name = "Rollers", amen = 0.6, keys = 0.4, reese = 0.8, lead = 0.6, arp = 0.7, stabs = 0.6, halftime = 0.35},
}

local ARRANGEMENT = {
	introBars = 8, buildBars = 8, dropBars = 32, breakdownBars = 16, rebuildBars = 8, outroBars = 16,
	blendBars = 8, phraseBars = 8, minCycles = 2, maxCycles = 3,
}
local HALFTIME = {from = 16, to = 24} -- the switch-up inside a drop
local LEAD_FROM = 16                  -- the melody carries the drop's second half

-- Scale degrees, one chord per two bars.
local PROGRESSIONS = {
	{1, 6, 3, 7}, {1, 4, 6, 5}, {1, 7, 6, 7}, {1, 1, 4, 6},
	{6, 7, 1, 1}, {1, 3, 6, 7}, {1, 6, 4, 5}, {4, 6, 1, 7},
	{1, 4, 7, 3}, {6, 4, 1, 5}, {1, 2, 6, 7}, {4, 5, 3, 6},
}
-- Two-step kick placements; the snare backbeat on steps 4 and 12 is fixed.
local KICKS = {
	{0, 10}, {0, 10}, {0, 6, 10}, {0, 2, 10}, {0, 10, 11}, {0, 7, 10}, {0, 10, 14}, {0, 3, 10},
}
-- Syncopated kicks that complexity adds on top of the groove.
local KICK_EXTRAS = {7, 13, 15, 3, 11}
local GHOST_STEPS = {7, 9, 14, 15, 2, 11, 1, 13, 6, 3}
local PERCUSSION = {"rim", "conga", "shaker"}
-- Bass motif intervals above the chord root, in semitones.
local BASS_INTERVALS = {0, 0, 0, 12, 7, 10, 3, 5, 12, 7}
-- Arpeggio orders over the four chord tones (5–8 are an octave up).
local ARP_ORDERS = {
	{1, 2, 3, 4}, {4, 3, 2, 1}, {1, 2, 3, 4, 3, 2}, {1, 3, 2, 4},
	{1, 2, 3, 4, 5, 6, 7, 8}, {1, 4, 2, 5, 3, 6}, {1, 1, 3, 2, 4, 3},
}
-- Electric-piano comping: off-beat pushes around the downbeat chord.
local KEYS_STEPS = {3, 6, 7, 10, 11, 14}
local FILLS = {"roll", "toms", "stutter", "cut"}
local CHOPS = {"stutter", "swap", "swap", "shuffle"}

-- The material one cycle of a track loops: progression, grooves, bass
-- motif, break chops, comping, arpeggio and melody. Settings-dependent
-- density is decided per bar, so each note carries a threshold rather than
-- being filtered here.
local function buildCycle(kit, rng, track)
	local flavour, mode = track.flavour, track.mode
	local amen = kit.amen
	local progression = kit.stableProgression(mode, rng.pick(PROGRESSIONS))
	local cycle = {
		progression = progression,
		voicings = kit.voicings(mode, progression),
		kicks = rng.pick(KICKS),
		altKicks = rng.pick(KICKS),
		kickExtras = {},
		ghostOrder = rng.shuffle(GHOST_STEPS),
		percussion = {}, bass = {}, variation = {}, stabSteps = {}, keys = {}, chops = {}, fills = {},
		arp = {order = rng.pick(ARP_ORDERS), rate = rng.float() < 0.7 and 1 or 2, mask = {}},
		halftime = rng.float() < flavour.halftime,
		arpOn = rng.float() < flavour.arp,
		leadOn = rng.float() < flavour.lead,
	}
	for _, step in ipairs(KICK_EXTRAS) do
		table.insert(cycle.kickExtras, {step = step, threshold = rng.float()})
	end
	for step = 0, 31 do
		if step % 4 ~= 0 then
			table.insert(cycle.percussion, {step = step, voice = rng.pick(PERCUSSION), chance = rng.float()})
		end
	end
	-- Rolling bass: a long root on the downbeat of each bar, then short
	-- syncopated answers whose count grows with energy. The variation bar
	-- answers every fourth bar with octave jumps and quicker notes.
	local function motif(list, first, last, busy)
		local step = first
		while step < last do
			local downbeat = step == first
			local length = downbeat and (4 + rng.int(3) - 1) or (busy and rng.int(2) or 1 + rng.int(3))
			table.insert(list, {
				step = step,
				length = math.min(length, last - step),
				interval = downbeat and 0 or rng.pick(BASS_INTERVALS),
				glide = not downbeat and rng.float() < 0.35,
				chance = downbeat and 0 or rng.float(),
				detail = rng.float(), -- complexity threshold for the extra 16ths
			})
			step = step + length + (rng.float() < 0.4 and 1 or 0)
		end
	end
	motif(cycle.bass, 0, 16)
	motif(cycle.bass, 16, 32)
	motif(cycle.variation, 0, 16, true)
	for _, s in ipairs({6, 14, 22, 30, 3, 19, 11, 27}) do
		if rng.float() < 0.45 then table.insert(cycle.stabSteps, {step = s, threshold = rng.float()}) end
	end
	if #cycle.stabSteps == 0 then table.insert(cycle.stabSteps, {step = 14, threshold = 0}) end
	for step = 0, 15 do
		-- Downbeats always sound; the rest open up with complexity.
		cycle.arp.mask[step] = step % 4 == 0 and 0 or rng.float()
	end
	for half = 0, 16, 16 do
		table.insert(cycle.keys, {step = half, length = 6, threshold = 0})
		for _, step in ipairs(KEYS_STEPS) do
			if rng.float() < 0.4 then
				table.insert(cycle.keys, {step = half + step, length = 1 + rng.int(3), threshold = rng.float()})
			end
		end
	end
	-- Break edits, the jungle producer's craft: stutter a snare slice, swap
	-- a beat in from another bar, or drop a stray 16th somewhere new.
	for _ = 1, 10 do
		local kind = rng.pick(CHOPS)
		local chop = {kind = kind, bar = rng.int(ARRANGEMENT.phraseBars) - 1, threshold = rng.float()}
		if kind == "stutter" then
			chop.step, chop.length, chop.source = rng.pick({12, 14, 8}), rng.pick({2, 4}), rng.pick(amen.snareSlices)
		elseif kind == "swap" then
			chop.step, chop.length = (rng.int(4) - 1) * 4, 4
			chop.source = (rng.int(amen.bars) - 1) * 16 + (rng.int(4) - 1) * 4
		else
			chop.step, chop.length, chop.source = rng.int(16) - 1, 1, rng.int(amen.slices) - 1
		end
		table.insert(cycle.chops, chop)
	end
	for _ = 1, 6 do table.insert(cycle.fills, rng.pick(FILLS)) end
	cycle.lead = kit.melody(rng)
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

-- `settings` provides enabled(part) and value(control), as Model does.
function Composer:bar(n, settings)
	local kit, set = self.kit, self.set
	local amen = kit.amen
	local on = function(part) return settings:enabled(part) end
	local energy = settings:value("energy")
	local complexity = settings:value("complexity")
	local humanize = settings:value("humanize")
	local at = set:locate(n, settings)
	local section, sectionBar, sectionLength = at.section, at.sectionBar, at.sectionLength
	local track, cycleIndex, phraseBar, tonic = at.track, at.cycleIndex, at.phraseBar, at.tonic
	local flavour, mode = track.flavour, track.mode
	local cycle = self:cycle(track, cycleIndex)
	local half = (n % 2) * 16 -- position inside the looping 2-bar pattern
	local full, outro, fillBar = at.full, at.outro, at.fillBar
	local fill = fillBar and cycle.fills[sectionBar // ARRANGEMENT.phraseBars + 1]
	local chord = kit.chordAt(mode, cycle.progression, cycle.voicings, tonic, n)
	local halftime = full and on("halftime") and cycle.halftime
		and sectionBar >= HALFTIME.from and sectionBar < HALFTIME.to
	local bar = kit.newBar(n, at, kit.random(self.seed, 2, n))
	bar.progression = kit.progressionName(mode, cycle.progression)
	bar.halftime, bar.chord = halftime, chord
	local function hit(step, voice, gain, extra) return bar:hit(step, voice, gain, humanize, extra) end
	local throwBar = on("throws") and phraseBar % 4 == 3 and (full or outro or section == "breakdown")

	-- The Amen: a jungle track opens on the raw break; drops layer it under
	-- the programmed kit at the flavour's weight (liquid saves it for later
	-- drops), and a jungle build rolls it into the drop.
	local amenWeight = on("amen") and flavour.amen or 0
	local breakIntro = section == "intro" and amenWeight >= 1 and sectionBar < ARRANGEMENT.introBars / 2
	local amenGain = 0
	if amenWeight > 0 and not halftime then
		if breakIntro or (section == "intro" and amenWeight >= 1) then amenGain = 0.9
		elseif full and (flavour.id ~= "liquid" or cycleIndex > 0) then amenGain = 0.75 * amenWeight
		elseif outro then amenGain = 0.6 * amenWeight
		elseif section == "build" and amenWeight >= 1 and sectionBar >= sectionLength / 2 then amenGain = 0.6 end
	end
	if amenGain > 0 then
		local slices = {}
		for step = 0, 15 do slices[step] = (n % amen.bars) * 16 + step end
		if on("chops") and (full or outro) then
			for _, chop in ipairs(cycle.chops) do
				if chop.bar == phraseBar and chop.threshold < complexity * 0.8 + 0.1 then
					for i = 0, chop.length - 1 do
						if chop.step + i < 16 then
							slices[chop.step + i] = chop.kind == "stutter" and chop.source or (chop.source + i) % amen.slices
						end
					end
				end
			end
		end
		for step = 0, 15 do table.insert(bar.breaks, {step = step, slice = slices[step], gain = amenGain}) end
	end

	-- The intro and drop share the two-step groove; the build drops the kick
	-- and rolls the snare tighter until the drop. The outro keeps the groove
	-- for the next track's intro to mix over.
	local groove = (full or outro or section == "intro") and not breakIntro
	if on("kick") and groove then
		if halftime then
			hit(0, "kick", 1)
			hit(10, "kick", 0.85)
			if complexity > 0.5 then hit(3, "kick", 0.7) end
		else
			local kicks = (phraseBar % 4 == 3) and cycle.altKicks or cycle.kicks
			local cut = fillBar and (fill == "cut" and 8 or 12) or 16
			for _, step in ipairs(kicks) do
				if step < cut then hit(step, "kick", step == 0 and 1 or 0.85) end
			end
			if full then
				for _, extra in ipairs(cycle.kickExtras) do
					if extra.step < cut and extra.threshold < complexity * 0.6 - 0.1 then hit(extra.step, "kick", 0.7) end
				end
			end
		end
	end
	if on("snare") then
		if halftime then
			hit(8, "snare", 1, {throw = throwBar or nil})
		elseif groove then
			hit(4, "snare", 1)
			if not fillBar then hit(12, "snare", 1, {throw = throwBar or nil}) end
			-- A drag into the backbeat.
			if full and complexity > 0.65 and (n % 2 == 1) then hit(11.5, "ghost", 0.3) end
		elseif section == "build" then
			local progress = sectionBar / sectionLength
			local every = progress < 0.5 and 4 or (progress < 0.75 and 2 or 1)
			for step = 0, 15, every do
				hit(step, "snare", 0.35 + 0.6 * (sectionBar * 16 + step) / (sectionLength * 16))
			end
		end
	end
	if fillBar then
		if fill == "roll" and on("snare") then
			for step = 12, 15.5, 0.5 do hit(step, "snare", 0.4 + 0.08 * (step - 12)) end
		elseif fill == "toms" then
			local toms = {"tomHigh", "tomHigh", "tomMid", "tomMid", "tomLow", "tomLow"}
			for i, voice in ipairs(toms) do hit(9 + i, voice, 0.75) end
			if on("snare") then hit(12, "snare", 0.9) end
		elseif fill == "stutter" then
			for step = 12, 15 do
				if on("kick") and step % 2 == 0 then hit(step, "kick", 0.8) end
				if on("snare") then hit(step + 0.5, "snare", 0.5 + 0.1 * (step - 12)) end
			end
		elseif fill == "cut" and on("snare") then
			-- Drop out on beat three, then a flam into the next phrase.
			hit(14.5, "snare", 0.5)
			hit(15, "snare", 1)
		end
	end
	if on("ghosts") and (full or outro) and not fillBar and not halftime then
		local count = math.floor(1 + energy * 3 + complexity * 3 + 0.5)
		for i = 1, math.min(count, #cycle.ghostOrder) do
			hit(cycle.ghostOrder[i], "ghost", 0.22 + 0.1 * ((i + n) % 3))
		end
	end
	if on("hats") and section ~= "breakdown" and not breakIntro then
		local open = halftime and 4 or 2
		for step = open, 15, 4 do hit(step, "hat", 0.75) end
		if section ~= "intro" then
			for step = 0, 15, 4 do hit(step, "hat", 0.35) end
			if energy > 0.45 then
				for step = 1, 15, 2 do
					if (step + n) % 4 == 3 or energy > 0.8 or complexity > 0.75 then hit(step, "hat", 0.22) end
				end
			end
			if phraseBar % 2 == 1 then hit(14, "openHat", 0.5) end
			if complexity > 0.4 and phraseBar % 4 == 1 then hit(6, "openHat", 0.35) end
		end
	end
	if on("ride") and section ~= "build" and not breakIntro then
		local drop = full or outro
		for s = drop and 2 or 0, 15, drop and 2 or 4 do hit(s, "ride", drop and 0.4 or 0.55) end
	end
	if on("percussion") and full then
		for _, p in ipairs(cycle.percussion) do
			local step = p.step - half
			if step >= 0 and step < 16 and p.chance < energy * 0.3 + complexity * 0.3 then
				hit(step, p.voice, 0.35 + 0.3 * p.chance)
			end
		end
	end
	if on("fills") and (((full or outro) and sectionBar % 16 == 0) or (section == "breakdown" and sectionBar == 0)) then
		hit(0, "crash", 0.8)
	end
	if on("risers") and at.arranged then
		if section == "build" then
			bar.riser = {from = sectionBar / sectionLength, to = (sectionBar + 1) / sectionLength}
		elseif (full or section == "breakdown") and sectionBar == 0 then
			bar.riser = {from = 1, to = 0} -- the downlifter washing out of the impact
		end
	end

	-- Bass: rolling motif in the drop (with a busier answer every fourth
	-- bar), one long sub note per bar in the breakdown and the outro's tail,
	-- silence in the intro and build so the drop lands.
	local reese = flavour.reese
	if (full or (outro and sectionBar < ARRANGEMENT.outroBars / 2)) and (on("sub") or on("reese")) then
		local notes, offset = cycle.bass, half
		if phraseBar % 4 == 3 and complexity > 0.3 and not halftime then notes, offset = cycle.variation, 0 end
		for _, note in ipairs(notes) do
			local step = note.step - offset
			local keep = note.chance <= energy * 0.9 + 0.1 and (note.length > 1 or note.detail < complexity)
			if halftime then keep = step % 4 == 0 and (step == 0 or note.chance < energy * 0.6) end
			if step >= 0 and step < 16 and keep then
				local length = halftime and math.max(note.length, 4) or note.length
				table.insert(bar.bass, {
					step = step, length = math.min(length, 16 - step),
					note = chord.root + note.interval, glide = note.glide, reese = reese,
				})
			end
		end
	elseif (section == "breakdown" or outro) and on("sub") then
		table.insert(bar.bass, {step = 0, length = 16, note = chord.root, glide = false, subOnly = true})
	end

	-- Chords last two bars; a pad sounds the chord where it starts.
	if on("pads") and n % 2 == 0 then bar.pad = chord.notes end

	-- The mix: a new track's intro carries the outgoing tune's last chords
	-- and sub under its own drums, so the set flows without a gap.
	if section == "intro" and track.index > 0 and sectionBar < ARRANGEMENT.blendBars and at.arranged then
		local previous = set:track(track.index - 1)
		local last = previous.cycles - 1
		local outgoing = self:cycle(previous, last)
		local previousTonic = (previous.tonic + (on("modulate") and set:shift(previous, last) or 0)) % 12
		local previousChord = kit.chordAt(previous.mode, outgoing.progression, outgoing.voicings, previousTonic, n)
		bar.blend = {key = kit.keyName(previousTonic, previous.mode), style = previous.flavour.name}
		bar.pad = on("pads") and n % 2 == 0 and previousChord.notes or nil
		if on("sub") and sectionBar < ARRANGEMENT.blendBars / 2 then
			table.insert(bar.bass, {step = 0, length = 16, note = previousChord.root, glide = false, subOnly = true})
		end
	end

	if on("stabs") and full and energy > 0.25 and not halftime then
		for _, s in ipairs(cycle.stabSteps) do
			local step = s.step - half
			if step >= 0 and step < 16 and s.threshold <= (complexity + 0.3) * flavour.stabs then
				table.insert(bar.stabs, {step = step, notes = chord.notes, throw = throwBar and step >= 8 or nil})
			end
		end
	end

	-- Keys: an electric piano comping the chords, the liquid signature. It
	-- plays through breakdowns and outros, and in drops once the first
	-- phrase has landed.
	local keysOn = on("keys") and flavour.keys > 0 and (section == "breakdown" or outro
		or (full and sectionBar >= ARRANGEMENT.phraseBars) or (section == "intro" and flavour.keys >= 1 and not bar.blend))
	if keysOn then
		for _, k in ipairs(cycle.keys) do
			local step = k.step - half
			if step >= 0 and step < 16 and k.threshold <= complexity * 0.7 + 0.2 then
				table.insert(bar.keys, {step = step, length = k.length, notes = chord.notes,
					gain = flavour.keys * (step == 0 and 1 or 0.7)})
			end
		end
	end

	-- Arpeggio: the pad voicing an octave up, in the breakdown, the second
	-- half of builds and after the drop's first phrase.
	local arpOn = on("arp") and cycle.arpOn and ((section == "breakdown")
		or (section == "build" and sectionBar >= sectionLength / 2)
		or (full and sectionBar >= ARRANGEMENT.phraseBars and energy > 0.3))
	if arpOn then
		local order, rate = cycle.arp.order, cycle.arp.rate
		local i = 0
		for step = 0, 15, rate do
			if cycle.arp.mask[step] <= complexity * 0.9 + 0.1 then
				local index = order[(n * 16 // rate + i) % #order + 1]
				local note = chord.notes[(index - 1) % 4 + 1] + 12 * (1 + (index - 1) // 4)
				table.insert(bar.arp, {step = step, note = note, length = rate * 0.8,
					gain = step % 4 == 0 and 1 or 0.7, pan = (i % 2 == 0) and 0.3 or 0.7})
			end
			i = i + 1
		end
	end

	-- Lead: the cycle's call and response over the chords, in the second
	-- half of the drop and softly through the breakdown.
	local leadOn = on("lead") and cycle.leadOn and ((full and sectionBar >= LEAD_FROM and not halftime)
		or (section == "breakdown" and sectionBar >= ARRANGEMENT.breakdownBars / 2))
	if leadOn then
		local phrase = cycle.lead[phraseBar % 4 + 1]
		for index, note in ipairs(phrase) do
			table.insert(bar.lead, {step = note.step, length = note.length,
				note = kit.leadPitch(mode, tonic, chord.degree, note.offset),
				glide = note.glide, gain = section == "breakdown" and 0.6 or 1,
				throw = (throwBar and index == #phrase) or nil})
		end
	end
	return bar
end

return {
	api = 1,
	title = "Drum & Bass",
	symbol = "waveform.path",
	summary = "Liquid, Jungle, Neurofunk and Rollers at 174",
	tempo = {min = 160, max = 180, default = 174},
	defaults = {energy = 0.65, complexity = 0.5, swing = 0.12, humanize = 0.35,
		cutoff = 0.5, wobble = 0.3, drive = 0.35, space = 0.35},
	create = function(kit, seed)
		return setmetatable({kit = kit, seed = seed, set = kit.newSet(seed, {
			flavours = FLAVOURS, modes = {"minor", "dorian", "phrygian"},
			arrangement = ARRANGEMENT, modulations = {5, -2, 3, 2},
		})}, Composer)
	end,
}
