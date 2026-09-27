-- Infinite drum & bass arranger. `bar(n, settings)` is a pure function of the
-- track seed, the bar number and the current settings, so any bar can be
-- regenerated, tested or skipped to without replaying history. Grooves, bass
-- motifs and progressions are drawn per 48-bar cycle and repeat in 2-bar
-- units the way a producer loops a pattern; fills and crashes mark 8-bar
-- phrases.
local Composer = {}
Composer.__index = Composer

Composer.stepsPerBar = 16

local ARRANGEMENT = {
	-- The track opens on a beat: a DJ-style drum intro, then a short build.
	introBars = 4, buildBars = 4, -- only before the first drop
	dropBars = 32, breakdownBars = 8, rebuildBars = 8,
	phraseBars = 8,
}
local CYCLE = ARRANGEMENT.dropBars + ARRANGEMENT.breakdownBars + ARRANGEMENT.rebuildBars
local LEAD_IN = ARRANGEMENT.introBars + ARRANGEMENT.buildBars

local NOTE_NAMES = {"C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"}
local MINOR = {0, 2, 3, 5, 7, 8, 10}
local NUMERALS = {"i", "ii°", "III", "iv", "v", "VI", "VII"}
-- Scale degrees (1-based into MINOR), one chord per two bars.
local PROGRESSIONS = {
	{1, 6, 3, 7}, {1, 4, 6, 5}, {1, 7, 6, 7}, {1, 1, 4, 6},
	{6, 7, 1, 1}, {1, 3, 6, 7}, {1, 6, 4, 5}, {4, 6, 1, 7},
}
-- Two-step kick placements; the snare backbeat on steps 4 and 12 is fixed.
local KICKS = {
	{0, 10}, {0, 10}, {0, 6, 10}, {0, 2, 10}, {0, 10, 11}, {0, 7, 10}, {0, 10, 14},
}
local GHOST_STEPS = {7, 9, 14, 15, 2, 11, 1, 13}
local PERCUSSION = {"rim", "conga", "shaker"}
-- Bass motif intervals above the chord root, in semitones.
local BASS_INTERVALS = {0, 0, 0, 12, 7, 10, 3, 5}

-- splitmix-style integer hash: independent, reproducible streams per
-- (seed, cycle, purpose) without carrying generator state between bars.
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

function Composer.new(seed)
	local self = setmetatable({seed = seed, cycles = {}}, Composer)
	local rng = random(seed, 0)
	self.tonic = rng.int(12) - 1
	-- Tonic in the sub register, E1 up to D♯2 (41–78 Hz).
	self.bassBase = 28 + (self.tonic - 4) % 12
	self.key = NOTE_NAMES[self.tonic + 1] .. " minor"
	return self
end

function Composer:section(n, arranged)
	if not arranged then return "drop", n % ARRANGEMENT.dropBars, ARRANGEMENT.dropBars, n // CYCLE end
	if n < ARRANGEMENT.introBars then return "intro", n, ARRANGEMENT.introBars, 0 end
	if n < LEAD_IN then return "build", n - ARRANGEMENT.introBars, ARRANGEMENT.buildBars, 0 end
	local cycle, pos = (n - LEAD_IN) // CYCLE, (n - LEAD_IN) % CYCLE
	if pos < ARRANGEMENT.dropBars then return "drop", pos, ARRANGEMENT.dropBars, cycle end
	pos = pos - ARRANGEMENT.dropBars
	if pos < ARRANGEMENT.breakdownBars then return "breakdown", pos, ARRANGEMENT.breakdownBars, cycle end
	return "build", pos - ARRANGEMENT.breakdownBars, ARRANGEMENT.rebuildBars, cycle
end

-- The material one cycle loops: progression, groove and a 2-bar bass motif.
-- Energy-dependent density is decided per bar, so it is not cached here.
function Composer:cycle(index)
	local cached = self.cycles[index]
	if cached then return cached end
	local rng = random(self.seed, 1, index)
	local cycle = {
		progression = rng.pick(PROGRESSIONS),
		kicks = rng.pick(KICKS),
		altKicks = rng.pick(KICKS),
		ghostOrder = {},
		percussion = {},
		bass = {},
		stabSteps = {},
	}
	local order = {table.unpack(GHOST_STEPS)}
	for i = #order, 2, -1 do
		local j = rng.int(i)
		order[i], order[j] = order[j], order[i]
	end
	cycle.ghostOrder = order
	for step = 0, 31 do
		if step % 4 ~= 0 then
			table.insert(cycle.percussion, {step = step, voice = rng.pick(PERCUSSION), chance = rng.float()})
		end
	end
	-- Rolling bass: a long root on the downbeat of each bar, then short
	-- syncopated answers whose count grows with energy.
	for barStart = 0, 16, 16 do
		local step = barStart
		while step < barStart + 16 do
			local downbeat = step == barStart
			local length = downbeat and (4 + rng.int(3) - 1) or (1 + rng.int(3))
			table.insert(cycle.bass, {
				step = step,
				length = math.min(length, barStart + 16 - step),
				interval = downbeat and 0 or rng.pick(BASS_INTERVALS),
				glide = not downbeat and rng.float() < 0.35,
				chance = downbeat and 0 or rng.float(),
			})
			step = step + length + (rng.float() < 0.4 and 1 or 0)
		end
	end
	for _, s in ipairs({6, 14, 22, 30, 3, 19}) do
		if rng.float() < 0.45 then table.insert(cycle.stabSteps, s) end
	end
	if #cycle.stabSteps == 0 then table.insert(cycle.stabSteps, 14) end
	self.cycles[index] = cycle
	return cycle
end

-- Chord for a bar: degree, bass root (MIDI) and a close pad voicing G3–F♯4.
function Composer:chord(progression, n)
	local degree = progression[(n // 2) % #progression + 1]
	local tones = {}
	for i = 0, 3 do
		local index = degree + i * 2 - 1
		local semis = MINOR[index % 7 + 1] + 12 * (index // 7)
		local pitch = self.tonic + semis
		table.insert(tones, 55 + (pitch - 55) % 12)
	end
	table.sort(tones)
	local root = self.bassBase + MINOR[degree]
	if root >= 40 then root = root - 12 end
	return {degree = degree, numeral = NUMERALS[degree], root = root, notes = tones}
end

local function progressionName(progression)
	local names = {}
	for _, degree in ipairs(progression) do table.insert(names, NUMERALS[degree]) end
	return table.concat(names, "–")
end

-- `settings` provides enabled(part) and value(control), as Model does.
function Composer:bar(n, settings)
	local on = function(part) return settings:enabled(part) end
	local energy = settings:value("energy")
	local arranged = on("arrangement")
	local section, sectionBar, sectionLength, cycleIndex = self:section(n, arranged)
	local cycle = self:cycle(cycleIndex)
	local phraseBar = sectionBar % ARRANGEMENT.phraseBars
	local half = (n % 2) * 16 -- position inside the looping 2-bar pattern
	local fills = on("fills")
	local fillBar = fills and phraseBar == ARRANGEMENT.phraseBars - 1 and section == "drop"
	local bar = {
		index = n, section = section, sectionBar = sectionBar, sectionLength = sectionLength,
		key = self.key, tonic = self.tonic, progression = progressionName(cycle.progression),
		chord = self:chord(cycle.progression, n),
		hits = {}, bass = {}, stabs = {},
	}
	local function hit(step, voice, gain) table.insert(bar.hits, {step = step, voice = voice, gain = gain}) end

	local drums = section ~= "breakdown"
	local full = section == "drop"
	-- The intro and drop share the two-step groove; the build drops the kick
	-- and rolls the snare tighter until the drop.
	local groove = full or section == "intro"
	if on("kick") and groove then
		local kicks = (phraseBar % 4 == 3) and cycle.altKicks or cycle.kicks
		for _, step in ipairs(kicks) do
			if not (fillBar and step >= 12) then hit(step, "kick", step == 0 and 1 or 0.85) end
		end
	end
	if on("snare") then
		if groove then
			hit(4, "snare", 1)
			if not fillBar then hit(12, "snare", 1) end
		elseif section == "build" then
			local progress = sectionBar / sectionLength
			local every = progress < 0.5 and 4 or (progress < 0.75 and 2 or 1)
			for step = 0, 15, every do
				hit(step, "snare", 0.35 + 0.6 * (sectionBar * 16 + step) / (sectionLength * 16))
			end
		end
	end
	if fillBar and on("snare") then
		for step = 12, 15 do hit(step, "snare", 0.55 + 0.12 * (step - 12)) end
	end
	if on("ghosts") and full and not fillBar then
		local count = math.floor(1 + energy * 4 + 0.5)
		for i = 1, count do hit(cycle.ghostOrder[i], "ghost", 0.22 + 0.1 * ((i + n) % 3)) end
	end
	if on("hats") and drums then
		for step = 2, 15, 4 do hit(step, "hat", 0.75) end
		if section ~= "intro" then
			for step = 0, 15, 4 do hit(step, "hat", 0.35) end
			if energy > 0.45 then
				for step = 1, 15, 2 do
					if (step + n) % 4 == 3 or energy > 0.8 then hit(step, "hat", 0.22) end
				end
			end
			if phraseBar % 2 == 1 then hit(14, "openHat", 0.5) end
		end
	end
	if on("ride") and section ~= "build" then
		local step = section == "drop" and 2 or 4
		local first = section == "drop" and 2 or 0
		for s = first, 15, step do hit(s, "ride", section == "drop" and 0.4 or 0.55) end
	end
	if on("percussion") and full then
		for _, p in ipairs(cycle.percussion) do
			local step = p.step - half
			if step >= 0 and step < 16 and p.chance < energy * 0.45 then
				hit(step, p.voice, 0.35 + 0.3 * p.chance)
			end
		end
	end
	if fills and ((section == "drop" and sectionBar == 0) or (section == "breakdown" and sectionBar == 0)) then
		hit(0, "crash", 0.8)
	end
	if fills and section == "build" then
		bar.riser = {from = sectionBar / sectionLength, to = (sectionBar + 1) / sectionLength}
	end

	-- Bass: rolling motif in the drop, one long sub note per bar in the
	-- breakdown, silence in the intro and build so the drop lands.
	if full and (on("sub") or on("reese")) then
		for _, note in ipairs(cycle.bass) do
			local step = note.step - half
			if step >= 0 and step < 16 and note.chance <= energy * 0.9 + 0.1 then
				table.insert(bar.bass, {
					step = step, length = math.min(note.length, 16 - step),
					note = bar.chord.root + note.interval, glide = note.glide,
				})
			end
		end
	elseif section == "breakdown" and on("sub") then
		table.insert(bar.bass, {step = 0, length = 16, note = bar.chord.root, glide = false, subOnly = true})
	end

	-- Chords last two bars; a pad sounds the chord where it starts.
	if on("pads") and n % 2 == 0 then
		bar.pad = bar.chord.notes
	end
	if on("stabs") and full and energy > 0.25 then
		for _, s in ipairs(cycle.stabSteps) do
			local step = s - half
			if step >= 0 and step < 16 then table.insert(bar.stabs, {step = step, notes = bar.chord.notes}) end
		end
	end
	return bar
end

return Composer
