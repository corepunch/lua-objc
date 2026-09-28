-- An endless drum & bass DJ set from one seed. The set is a sequence of
-- tracks, each with its own style, key, mode and length; each new track's
-- drum intro is mixed under the outgoing tune's chords, and keys move in
-- harmonically compatible steps, as a DJ mixes. `bar(n, settings)` is a pure
-- function of the set seed, the bar number and the current settings, so any
-- bar can be regenerated, tested or skipped to without replaying history.
-- Material is drawn per (track, cycle), so nothing repeats; inside a cycle
-- it loops in 2- and 4-bar units the way a producer loops a pattern, and
-- fills, crashes and throws mark 4- and 8-bar phrases.
local Amen = require("apps.dnb.models.Amen")

local Composer = {}
Composer.__index = Composer

Composer.stepsPerBar = 16

local ARRANGEMENT = {
	-- A track opens on a DJ-friendly drum intro, then builds to the drop.
	introBars = 8, buildBars = 8,
	dropBars = 32, breakdownBars = 16, rebuildBars = 8, outroBars = 16,
	blendBars = 8,                       -- intro bars carrying the outgoing tune
	phraseBars = 8,
	halftimeFrom = 16, halftimeTo = 24,  -- the switch-up inside a drop
	leadFrom = 16,                       -- the melody carries the drop's second half
	minCycles = 2, maxCycles = 3,        -- drops per track
}

-- Styles weight the parts a track leans on. Every part still answers to its
-- pad; a style only decides how much of it the track uses.
local STYLES = {
	{id = "liquid", name = "Liquid", amen = 0.45, keys = 1, reese = 0.55, lead = 0.9, arp = 0.9, stabs = 0.4, halftime = 0.25},
	{id = "jungle", name = "Jungle", amen = 1, keys = 0.5, reese = 0.5, lead = 0.5, arp = 0.4, stabs = 0.7, halftime = 0.2},
	{id = "neuro", name = "Neurofunk", amen = 0, keys = 0, reese = 1, lead = 0.4, arp = 0.5, stabs = 1, halftime = 0.7},
	{id = "rollers", name = "Rollers", amen = 0.6, keys = 0.4, reese = 0.8, lead = 0.6, arp = 0.7, stabs = 0.6, halftime = 0.35},
}
Composer.styles = STYLES

local NOTE_NAMES = {"C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"}
-- Minor modes: aeolian is the classic, dorian the liquid, phrygian the dark.
local MODES = {
	{name = "minor", steps = {0, 2, 3, 5, 7, 8, 10}},
	{name = "dorian", steps = {0, 2, 3, 5, 7, 9, 10}},
	{name = "phrygian", steps = {0, 1, 3, 5, 7, 8, 10}},
}
local ROMAN = {"I", "II", "III", "IV", "V", "VI", "VII"}
-- Scale degrees, one chord per two bars.
local PROGRESSIONS = {
	{1, 6, 3, 7}, {1, 4, 6, 5}, {1, 7, 6, 7}, {1, 1, 4, 6},
	{6, 7, 1, 1}, {1, 3, 6, 7}, {1, 6, 4, 5}, {4, 6, 1, 7},
	{1, 4, 7, 3}, {6, 4, 1, 5}, {1, 2, 6, 7}, {4, 5, 3, 6},
}
-- Harmonic mixing: the next track stays in key or moves a fifth, the moves
-- a DJ's key wheel marks as compatible, with the occasional energy lift of
-- a whole tone.
local MIXES = {0, 7, 5, 7, 5, 2}
-- Key changes a cycle can take inside a track.
local MODULATIONS = {5, -2, 3, 2}
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
-- One-beat rhythm cells for the lead: {offset, length} in 16ths.
local LEAD_CELLS = {
	{{0, 4}}, {{0, 2}, {2, 2}}, {{0, 3}, {3, 1}}, {{0, 1}, {1, 3}},
	{{2, 2}}, {{0, 2}}, {{0, 1}, {1, 1}, {2, 2}}, {},
}
-- Electric-piano comping: off-beat pushes around the downbeat chord.
local KEYS_STEPS = {3, 6, 7, 10, 11, 14}
local FILLS = {"roll", "toms", "stutter", "cut"}
local CHOPS = {"stutter", "swap", "swap", "shuffle"}

-- splitmix-style integer hash: independent, reproducible streams per
-- (seed, track, cycle, purpose) without carrying generator state between bars.
local function hash(...)
	local h = 0x9E3779B97F4A7C15
	for i = 1, select("#", ...) do
		h = h ~ (select(i, ...) * 0xBF58476D1CE4E5B9)
		h = (h ~ (h >> 31)) * 0x94D049BB133111EB
		h = h ~ (h >> 29)
	end
	return h
end

local function random(...)
	local state = hash(...)
	local rng = {}
	function rng.float()
		state = state * 6364136223846793005 + 1442695040888963407
		return ((state >> 11) & 0xFFFFFFFFFFFF) / 0x1000000000000
	end
	function rng.int(n) return math.floor(rng.float() * n) + 1 end
	function rng.pick(list) return list[rng.int(#list)] end
	return rng
end

local function shuffle(list, rng)
	local order = {table.unpack(list)}
	for i = #order, 2, -1 do
		local j = rng.int(i)
		order[i], order[j] = order[j], order[i]
	end
	return order
end

-- Folds a pitch into [low, low + 11].
local function fold(pitch, low) return low + (pitch - low) % 12 end

-- Scale degree (1-based, may exceed 7) → semitones above the tonic.
local function degreeSemis(mode, index)
	return mode.steps[(index - 1) % 7 + 1] + 12 * ((index - 1) // 7)
end

local function numeral(mode, degree)
	local third = degreeSemis(mode, degree + 2) - degreeSemis(mode, degree)
	local fifth = degreeSemis(mode, degree + 4) - degreeSemis(mode, degree)
	if fifth == 6 then return ROMAN[degree]:lower() .. "°" end
	return third == 3 and ROMAN[degree]:lower() or ROMAN[degree]
end
Composer.numeral = numeral

local function keyName(tonic, mode) return NOTE_NAMES[tonic + 1] .. " " .. mode.name end

function Composer.new(seed)
	return setmetatable({seed = seed, tracks = {}, hint = 0}, Composer)
end

-- Track k of the set, drawn from the one before it. Built iteratively, so a
-- far bar does not recurse through every earlier track.
function Composer:track(k)
	for index = #self.tracks, k do
		if not self.tracks[index + 1] then
			local previous = self.tracks[index]
			local rng = random(self.seed, 4, index)
			local style = rng.pick(STYLES)
			if previous and style == previous.style then style = STYLES[(rng.int(#STYLES - 1) + index) % #STYLES + 1] end
			if previous and style == previous.style then style = STYLES[style == STYLES[1] and 2 or 1] end
			local cycles = ARRANGEMENT.minCycles + rng.int(ARRANGEMENT.maxCycles - ARRANGEMENT.minCycles + 1) - 1
			local track = {
				index = index, style = style, mode = rng.pick(MODES), cycles = cycles,
				tonic = previous and (previous.tonic + rng.pick(MIXES)) % 12 or rng.int(12) - 1,
				start = previous and previous.start + previous.length or 0,
				length = ARRANGEMENT.introBars + ARRANGEMENT.buildBars + cycles * ARRANGEMENT.dropBars
					+ (cycles - 1) * (ARRANGEMENT.breakdownBars + ARRANGEMENT.rebuildBars) + ARRANGEMENT.outroBars,
				cycleCache = {}, shifts = {[0] = 0},
			}
			track.key = keyName(track.tonic, track.mode)
			self.tracks[index + 1] = track
		end
	end
	return self.tracks[k + 1]
end

-- The track playing bar n.
function Composer:trackAt(n)
	local k = self.hint
	local track = self:track(k)
	while n < track.start do k = k - 1; track = self:track(k) end
	while n >= track.start + track.length do k = k + 1; track = self:track(k) end
	self.hint = k
	return track
end

-- The first bar of a track, for skipping ahead in the set.
function Composer:trackStart(k)
	return self:track(k).start
end

-- Section of bar n within its track: name, bar in section, section length,
-- the cycle whose material it plays, and the track.
function Composer:section(n, arranged)
	local track = self:trackAt(n)
	local pos = n - track.start
	local A = ARRANGEMENT
	if not arranged then
		return "drop", pos % A.dropBars, A.dropBars, (pos // A.dropBars) % track.cycles, track
	end
	if pos < A.introBars then return "intro", pos, A.introBars, 0, track end
	pos = pos - A.introBars
	if pos < A.buildBars then return "build", pos, A.buildBars, 0, track end
	pos = pos - A.buildBars
	for cycle = 0, track.cycles - 1 do
		if pos < A.dropBars then return "drop", pos, A.dropBars, cycle, track end
		pos = pos - A.dropBars
		if cycle == track.cycles - 1 then return "outro", pos, A.outroBars, cycle, track end
		if pos < A.breakdownBars then return "breakdown", pos, A.breakdownBars, cycle, track end
		pos = pos - A.breakdownBars
		-- The rebuild belongs to the next cycle, so a key change lands with
		-- its riser rather than on the drop's first kick.
		if pos < A.rebuildBars then return "build", pos, A.rebuildBars, cycle + 1, track end
		pos = pos - A.rebuildBars
	end
end

-- Semitones a track's key has moved by a cycle, accumulated from its first.
function Composer:shift(track, index)
	for i = #track.shifts + 1, index do
		track.shifts[i] = track.shifts[i - 1] + random(self.seed, 3, track.index, i).pick(MODULATIONS)
	end
	return track.shifts[index]
end

-- Rootless extended voicings (3rd, 5th, 7th, 9th above each degree) in C,
-- voice led through the progression: every chord takes the inversion nearest
-- the previous one, so the pads glide instead of jumping.
local function voicings(mode, progression)
	local center, previous = 62, nil
	local result = {}
	for i, degree in ipairs(progression) do
		local classes = {}
		for _, k in ipairs({2, 4, 6, 8}) do table.insert(classes, degreeSemis(mode, degree + k) % 12) end
		local best, bestCost
		for low = 50, 61 do
			local notes = {}
			for _, c in ipairs(classes) do table.insert(notes, low + (c - low) % 12) end
			table.sort(notes)
			local cost = 0
			if previous then
				for j = 1, 4 do cost = cost + math.abs(notes[j] - previous[j]) end
			else
				cost = math.abs((notes[1] + notes[4]) / 2 - center)
			end
			if notes[4] - notes[1] <= 12 and (not bestCost or cost < bestCost) then best, bestCost = notes, cost end
		end
		result[i] = best
		previous = best
	end
	return result
end

-- A four-bar call and response. Notes are scale offsets from the sounding
-- chord's root, so the same line follows the harmony: strong beats land on
-- chord tones (even offsets), weak ones walk by step. The response repeats
-- the call's first bar and resolves to the root.
local function melody(rng)
	local bars = {{}, {}, {}, {}}
	local offset = rng.pick({0, 2, 4})
	for bar = 1, 2 do
		for beat = 0, 3 do
			local cell = rng.pick(LEAD_CELLS)
			if bar == 2 and beat == 3 then cell = {} end -- breathe before the answer
			for _, note in ipairs(cell) do
				local strong = note[1] == 0
				if strong then
					offset = offset + rng.pick({-2, 0, 2})
					offset = offset - offset % 2
				else
					offset = offset + rng.pick({-1, 1, 1, 2})
				end
				offset = math.max(-2, math.min(9, offset))
				table.insert(bars[bar], {step = beat * 4 + note[1], length = note[2], offset = offset,
					glide = not strong and rng.float() < 0.5})
			end
		end
	end
	for _, note in ipairs(bars[1]) do
		table.insert(bars[3], {step = note.step, length = note.length, offset = note.offset, glide = note.glide})
	end
	for _, note in ipairs(bars[2]) do
		if note.step < 8 then
			table.insert(bars[4], {step = note.step, length = note.length, offset = note.offset + 1, glide = note.glide})
		end
	end
	table.insert(bars[4], {step = 8, length = 8, offset = 0, glide = true})
	return bars
end

-- The material one cycle of a track loops: progression, grooves, bass
-- motif, break chops, comping, arpeggio and melody. Settings-dependent
-- density is decided per bar, so each note carries a threshold rather than
-- being filtered here.
function Composer:cycle(track, index)
	local cached = track.cycleCache[index]
	if cached then return cached end
	local rng = random(self.seed, 1, track.index, index)
	local style, mode = track.style, track.mode
	-- Progressions are written for aeolian; where another mode makes a degree
	-- diminished (dorian vi°, phrygian v°), take the chord a third above,
	-- which shares two of its tones and gives the bass a stable root.
	local progression = {}
	for i, degree in ipairs(rng.pick(PROGRESSIONS)) do
		progression[i] = numeral(mode, degree):find("°") and (degree + 1) % 7 + 1 or degree
	end
	local cycle = {
		progression = progression,
		voicings = voicings(mode, progression),
		kicks = rng.pick(KICKS),
		altKicks = rng.pick(KICKS),
		kickExtras = {},
		ghostOrder = shuffle(GHOST_STEPS, rng),
		percussion = {}, bass = {}, variation = {}, stabSteps = {}, keys = {}, chops = {}, fills = {},
		arp = {order = rng.pick(ARP_ORDERS), rate = rng.float() < 0.7 and 1 or 2, mask = {}},
		halftime = rng.float() < style.halftime,
		arpOn = rng.float() < style.arp,
		leadOn = rng.float() < style.lead,
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
			chop.step, chop.length, chop.source = rng.pick({12, 14, 8}), rng.pick({2, 4}), rng.pick(Amen.snareSlices)
		elseif kind == "swap" then
			chop.step, chop.length = (rng.int(4) - 1) * 4, 4
			chop.source = (rng.int(Amen.bars) - 1) * 16 + (rng.int(4) - 1) * 4
		else
			chop.step, chop.length, chop.source = rng.int(16) - 1, 1, rng.int(Amen.slices) - 1
		end
		table.insert(cycle.chops, chop)
	end
	for _ = 1, 6 do table.insert(cycle.fills, rng.pick(FILLS)) end
	cycle.lead = melody(rng)
	track.cycleCache[index] = cycle
	return cycle
end

local function progressionName(mode, progression)
	local names = {}
	for _, degree in ipairs(progression) do table.insert(names, numeral(mode, degree)) end
	return table.concat(names, "–")
end

-- Chord for bar n: degree, sub root, and the voicing transposed to `tonic`
-- and kept in the pad register.
local function chordAt(mode, cycle, tonic, n)
	local slot = (n // 2) % #cycle.progression + 1
	local degree = cycle.progression[slot]
	local voicing = {}
	for i, note in ipairs(cycle.voicings[slot]) do voicing[i] = note + tonic end
	while voicing[1] > 60 do for i = 1, 4 do voicing[i] = voicing[i] - 12 end end
	while voicing[1] < 48 do for i = 1, 4 do voicing[i] = voicing[i] + 12 end end
	-- Root in the sub register, E1 up to D♯2 (41–78 Hz).
	return {degree = degree, numeral = numeral(mode, degree), notes = voicing,
		root = fold((tonic + degreeSemis(mode, degree)) % 12, 28)}
end

-- `settings` provides enabled(part) and value(control), as Model does.
function Composer:bar(n, settings)
	local on = function(part) return settings:enabled(part) end
	local energy = settings:value("energy")
	local complexity = settings:value("complexity")
	local humanize = settings:value("humanize")
	local arranged = on("arrangement")
	local section, sectionBar, sectionLength, cycleIndex, track = self:section(n, arranged)
	local style, mode = track.style, track.mode
	local cycle = self:cycle(track, cycleIndex)
	local phraseBar = sectionBar % ARRANGEMENT.phraseBars
	local half = (n % 2) * 16 -- position inside the looping 2-bar pattern
	local fills = on("fills")
	local full = section == "drop"
	local outro = section == "outro"
	local fillBar = fills and phraseBar == ARRANGEMENT.phraseBars - 1 and (full or outro)
	local fill = fillBar and cycle.fills[sectionBar // ARRANGEMENT.phraseBars + 1]
	local tonic = (track.tonic + (on("modulate") and self:shift(track, cycleIndex) or 0)) % 12
	local chord = chordAt(mode, cycle, tonic, n)
	local halftime = full and on("halftime") and cycle.halftime
		and sectionBar >= ARRANGEMENT.halftimeFrom and sectionBar < ARRANGEMENT.halftimeTo
	local bar = {
		index = n, section = section, sectionBar = sectionBar, sectionLength = sectionLength,
		track = track.index, style = style.name, trackBar = n - track.start, trackLength = track.length,
		key = keyName(tonic, mode), tonic = tonic, progression = progressionName(mode, cycle.progression),
		halftime = halftime, chord = chord,
		hits = {}, bass = {}, stabs = {}, arp = {}, lead = {}, keys = {}, breaks = {},
	}
	-- Humanize: small, reproducible timing and velocity drift per hit. The
	-- kick and backbeat stay tight, as a drummer's would.
	local feel = random(self.seed, 2, n)
	local function hit(step, voice, gain, extra)
		local anchor = voice == "kick" or (voice == "snare" and step % 4 == 0)
		local drift = humanize * (anchor and 0.25 or 1)
		local h = {step = step, voice = voice, gain = gain * (1 - 0.3 * drift * feel.float()),
			nudge = (feel.float() - 0.5) * 0.14 * drift}
		if extra then for k, v in pairs(extra) do h[k] = v end end
		table.insert(bar.hits, h)
		return h
	end
	local throwBar = on("throws") and phraseBar % 4 == 3 and (full or outro or section == "breakdown")

	-- The Amen: a jungle track opens on the raw break; drops layer it under
	-- the programmed kit at the style's weight (liquid saves it for later
	-- drops), and a jungle build rolls it into the drop.
	local amenWeight = on("amen") and style.amen or 0
	local breakIntro = section == "intro" and amenWeight >= 1 and sectionBar < ARRANGEMENT.introBars / 2
	local amenGain = 0
	if amenWeight > 0 and not halftime then
		if breakIntro or (section == "intro" and amenWeight >= 1) then amenGain = 0.9
		elseif full and (style.id ~= "liquid" or cycleIndex > 0) then amenGain = 0.75 * amenWeight
		elseif outro then amenGain = 0.6 * amenWeight
		elseif section == "build" and amenWeight >= 1 and sectionBar >= sectionLength / 2 then amenGain = 0.6 end
	end
	if amenGain > 0 then
		local slices = {}
		for step = 0, 15 do slices[step] = (n % Amen.bars) * 16 + step end
		if on("chops") and (full or outro) then
			for _, chop in ipairs(cycle.chops) do
				if chop.bar == phraseBar and chop.threshold < complexity * 0.8 + 0.1 then
					for i = 0, chop.length - 1 do
						if chop.step + i < 16 then
							slices[chop.step + i] = chop.kind == "stutter" and chop.source or (chop.source + i) % Amen.slices
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
	if fills and (((full or outro) and sectionBar % 16 == 0) or (section == "breakdown" and sectionBar == 0)) then
		hit(0, "crash", 0.8)
	end
	if on("risers") and arranged then
		if section == "build" then
			bar.riser = {from = sectionBar / sectionLength, to = (sectionBar + 1) / sectionLength}
		elseif (full or section == "breakdown") and sectionBar == 0 then
			bar.riser = {from = 1, to = 0} -- the downlifter washing out of the impact
		end
	end

	-- Bass: rolling motif in the drop (with a busier answer every fourth
	-- bar), one long sub note per bar in the breakdown and the outro's tail,
	-- silence in the intro and build so the drop lands.
	local reese = style.reese
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
	if section == "intro" and track.index > 0 and sectionBar < ARRANGEMENT.blendBars and arranged then
		local previous = self:track(track.index - 1)
		local last = previous.cycles - 1
		local outgoing = self:cycle(previous, last)
		local previousTonic = (previous.tonic + (on("modulate") and self:shift(previous, last) or 0)) % 12
		local previousChord = chordAt(previous.mode, outgoing, previousTonic, n)
		bar.blend = {key = keyName(previousTonic, previous.mode), style = previous.style.name}
		bar.pad = on("pads") and n % 2 == 0 and previousChord.notes or nil
		if on("sub") and sectionBar < ARRANGEMENT.blendBars / 2 then
			table.insert(bar.bass, {step = 0, length = 16, note = previousChord.root, glide = false, subOnly = true})
		end
	end

	if on("stabs") and full and energy > 0.25 and not halftime then
		for _, s in ipairs(cycle.stabSteps) do
			local step = s.step - half
			if step >= 0 and step < 16 and s.threshold <= (complexity + 0.3) * style.stabs then
				table.insert(bar.stabs, {step = step, notes = chord.notes, throw = throwBar and step >= 8 or nil})
			end
		end
	end

	-- Keys: an electric piano comping the chords, the liquid signature. It
	-- plays through breakdowns and outros, and in drops once the first
	-- phrase has landed.
	local keysOn = on("keys") and style.keys > 0 and (section == "breakdown" or outro
		or (full and sectionBar >= ARRANGEMENT.phraseBars) or (section == "intro" and style.keys >= 1 and not bar.blend))
	if keysOn then
		for _, k in ipairs(cycle.keys) do
			local step = k.step - half
			if step >= 0 and step < 16 and k.threshold <= complexity * 0.7 + 0.2 then
				table.insert(bar.keys, {step = step, length = k.length, notes = chord.notes,
					gain = style.keys * (step == 0 and 1 or 0.7)})
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
	local leadOn = on("lead") and cycle.leadOn and ((full and sectionBar >= ARRANGEMENT.leadFrom and not halftime)
		or (section == "breakdown" and sectionBar >= ARRANGEMENT.breakdownBars / 2))
	if leadOn then
		local phrase = cycle.lead[phraseBar % 4 + 1]
		-- One register per chord keeps the line's contour: the chord root
		-- sits in E4–D♯5 and offsets climb or fall from it.
		local rootPitch = tonic + degreeSemis(mode, chord.degree)
		local base = fold(rootPitch, 64) - rootPitch
		for index, note in ipairs(phrase) do
			table.insert(bar.lead, {step = note.step, length = note.length,
				note = tonic + degreeSemis(mode, chord.degree + note.offset) + base,
				glide = note.glide, gain = section == "breakdown" and 0.6 or 1,
				throw = (throwBar and index == #phrase) or nil})
		end
	end
	return bar
end

return Composer
