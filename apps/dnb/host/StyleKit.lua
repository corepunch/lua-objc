-- The host API every style plugin receives (read-only): seeded randomness,
-- music theory, the DJ set that sequences tracks and their sections, the
-- lane builder a style arranges tracks with, the patterns every style
-- shares, the bar score the Synth plays, and the Amen break. Styles are pure
-- composition on top of it; the sound itself belongs to the Synth, which a
-- style only tunes through its manifest's `sound` table.
local Amen = require("apps.dnb.models.Amen")

local StyleKit = {}

StyleKit.stepsPerBar = 16
StyleKit.amen = Amen

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

--- A reproducible generator for the integers given: float() in [0, 1),
--- int(n) in 1…n, pick(list), chance(p) and shuffle(list) (a new list).
function StyleKit.random(...)
	local state = hash(...)
	local rng = {}
	function rng.float()
		state = state * 6364136223846793005 + 1442695040888963407
		return ((state >> 11) & 0xFFFFFFFFFFFF) / 0x1000000000000
	end
	function rng.int(n) return math.floor(rng.float() * n) + 1 end
	function rng.pick(list) return list[rng.int(#list)] end
	function rng.chance(p) return rng.float() < p end
	function rng.shuffle(list)
		local order = {table.unpack(list)}
		for i = #order, 2, -1 do
			local j = rng.int(i)
			order[i], order[j] = order[j], order[i]
		end
		return order
	end
	return rng
end

--- Steps of a 16-character pattern: "x" hits, "." rests. Accented "X"
--- steps are also returned as a set: `steps, accents = kit.steps("X..x")`.
function StyleKit.steps(pattern)
	local steps, accents = {}, {}
	for i = 1, #pattern do
		local c = pattern:sub(i, i)
		if c ~= "." and c ~= "-" and c ~= " " then
			table.insert(steps, i - 1)
			if c == "X" then accents[i - 1] = true end
		end
	end
	return steps, accents
end

-- Theory ----------------------------------------------------------------

StyleKit.noteNames = {"C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"}
StyleKit.modes = {
	minor = {name = "minor", steps = {0, 2, 3, 5, 7, 8, 10}},
	dorian = {name = "dorian", steps = {0, 2, 3, 5, 7, 9, 10}},
	phrygian = {name = "phrygian", steps = {0, 1, 3, 5, 7, 8, 10}},
	major = {name = "major", steps = {0, 2, 4, 5, 7, 9, 11}},
	mixolydian = {name = "mixolydian", steps = {0, 2, 4, 5, 7, 9, 10}},
}
local ROMAN = {"I", "II", "III", "IV", "V", "VI", "VII"}

--- Folds a pitch into [low, low + 11].
function StyleKit.fold(pitch, low) return low + (pitch - low) % 12 end

--- Scale degree (1-based, may exceed 7) → semitones above the tonic.
function StyleKit.degreeSemis(mode, index)
	return mode.steps[(index - 1) % 7 + 1] + 12 * ((index - 1) // 7)
end
local degreeSemis = StyleKit.degreeSemis

function StyleKit.numeral(mode, degree)
	local third = degreeSemis(mode, degree + 2) - degreeSemis(mode, degree)
	local fifth = degreeSemis(mode, degree + 4) - degreeSemis(mode, degree)
	if fifth == 6 then return ROMAN[degree]:lower() .. "°" end
	return third == 3 and ROMAN[degree]:lower() or ROMAN[degree]
end
local numeral = StyleKit.numeral

function StyleKit.keyName(tonic, mode) return StyleKit.noteNames[tonic + 1] .. " " .. mode.name end

function StyleKit.progressionName(mode, progression)
	local names = {}
	for _, degree in ipairs(progression) do table.insert(names, numeral(mode, degree)) end
	return table.concat(names, "–")
end

--- Replaces degrees the mode makes diminished (dorian vi°, phrygian v°) with
--- the chord a third above, which shares two tones and has a stable root.
function StyleKit.stableProgression(mode, progression)
	local result = {}
	for i, degree in ipairs(progression) do
		result[i] = numeral(mode, degree):find("°") and (degree + 1) % 7 + 1 or degree
	end
	return result
end

--- Four-note voicings in C, voice led through the progression: every chord
--- takes the inversion nearest the previous one, so pads glide instead of
--- jumping. `intervals` are scale steps above each degree: the default
--- {2, 4, 6, 8} is rootless 3-5-7-9; {0, 2, 4, 6} is a plain seventh chord.
function StyleKit.voicings(mode, progression, intervals)
	intervals = intervals or {2, 4, 6, 8}
	local center, previous = 62, nil
	local result = {}
	for i, degree in ipairs(progression) do
		local classes = {}
		for _, k in ipairs(intervals) do table.insert(classes, degreeSemis(mode, degree + k) % 12) end
		local best, bestCost
		for low = 50, 61 do
			local notes = {}
			for _, c in ipairs(classes) do table.insert(notes, low + (c - low) % 12) end
			table.sort(notes)
			local cost = 0
			if previous then
				for j = 1, #notes do cost = cost + math.abs(notes[j] - previous[j]) end
			else
				cost = math.abs((notes[1] + notes[#notes]) / 2 - center)
			end
			if notes[#notes] - notes[1] <= 12 and (not bestCost or cost < bestCost) then best, bestCost = notes, cost end
		end
		result[i] = best
		previous = best
	end
	return result
end

--- The chord for bar n of a looping progression (`barsPerChord` bars each):
--- degree, numeral, the voicing transposed to `tonic` in the pad register,
--- and a root in the sub register, E1 up to D♯2 (41–78 Hz).
function StyleKit.chordAt(mode, progression, voicings, tonic, n, barsPerChord)
	local slot = (n // (barsPerChord or 2)) % #progression + 1
	local degree = progression[slot]
	local voicing = {}
	for i, note in ipairs(voicings[slot]) do voicing[i] = note + tonic end
	while voicing[1] > 60 do for i = 1, #voicing do voicing[i] = voicing[i] - 12 end end
	while voicing[1] < 48 do for i = 1, #voicing do voicing[i] = voicing[i] + 12 end end
	return {degree = degree, numeral = numeral(mode, degree), notes = voicing,
		root = StyleKit.fold((tonic + degreeSemis(mode, degree)) % 12, 28)}
end

-- One-beat rhythm cells for a lead: {offset, length} in 16ths.
local LEAD_CELLS = {
	{{0, 4}}, {{0, 2}, {2, 2}}, {{0, 3}, {3, 1}}, {{0, 1}, {1, 3}},
	{{2, 2}}, {{0, 2}}, {{0, 1}, {1, 1}, {2, 2}}, {},
}

--- A four-bar call and response. Notes are scale offsets from the sounding
--- chord's root, so the same line follows the harmony: strong beats land on
--- chord tones (even offsets), weak ones walk by step. The response repeats
--- the call's first bar and resolves to the root.
function StyleKit.melody(rng, cells)
	cells = cells or LEAD_CELLS
	local bars = {{}, {}, {}, {}}
	local offset = rng.pick({0, 2, 4})
	for bar = 1, 2 do
		for beat = 0, 3 do
			local cell = rng.pick(cells)
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

--- Pitch for a melody note: the chord root sits in E4–D♯5 and offsets
--- climb or fall from it in the mode.
function StyleKit.leadPitch(mode, tonic, degree, offset)
	local rootPitch = tonic + degreeSemis(mode, degree)
	local base = StyleKit.fold(rootPitch, 64) - rootPitch
	return tonic + degreeSemis(mode, degree + offset) + base
end

-- The set ------------------------------------------------------------------

-- Harmonic mixing: the next track stays in key or moves a fifth, the moves
-- a DJ's key wheel marks as compatible, with the occasional lift of a tone.
local MIXES = {0, 7, 5, 7, 5, 2}
-- Drum kits ---------------------------------------------------------------

--- The snare characters a producer picks between; the Synth voices each
--- over the style's own snare (see Synth.drumVariant). A flavour may list
--- the ones that suit it as `snares`; otherwise a track may use any.
StyleKit.snares = {"tight", "fat", "rimshot", "roomy", "crunchy", "layered", "vintage"}
local SNARE_NAMES = {}
for _, name in ipairs(StyleKit.snares) do SNARE_NAMES[name] = true end

-- Dimensions of a track's kit, each −1…1 around the style's design.
local DRUM_DIMENSIONS = {"snareTune", "kickTune", "kickLength", "kickDrive", "kickClick",
	"hatTone", "hatLength", "hatNoise", "clapSpread", "clapLength", "clapTone"}

--- A track's drum kit: its snare character and how far its kick, snare
--- tuning, hats and clap sit from the style's design. Producers pick new
--- sounds for every tune, so no two tracks in a set share a kit; the style's
--- design keeps them in its genre.
function StyleKit.drumDesign(rng, flavour)
	local design = {snare = rng.pick(flavour.snares or StyleKit.snares)}
	for _, dimension in ipairs(DRUM_DIMENSIONS) do design[dimension] = rng.float() * 2 - 1 end
	return design
end

local DEFAULT_ARRANGEMENT = {
	introBars = 8, buildBars = 8, dropBars = 32, breakdownBars = 16, rebuildBars = 8, outroBars = 16,
	blendBars = 8, phraseBars = 8, minCycles = 2, maxCycles = 3,
}

local Set = {}
Set.__index = Set

-- A track's sections, the ruler above its lanes: intro → build → (drop →
-- breakdown → build) … → drop → outro. `cycle` is the material a section
-- plays; a rebuild belongs to the next cycle, so a key change lands with its
-- riser rather than on the drop's first kick.
local function sections(A, cycles)
	local list, start = {}, 0
	local function add(id, length, cycle)
		table.insert(list, {id = id, start = start, length = length, cycle = cycle})
		start = start + length
	end
	add("intro", A.introBars, 0)
	add("build", A.buildBars, 0)
	for cycle = 0, cycles - 1 do
		add("drop", A.dropBars, cycle)
		if cycle == cycles - 1 then
			add("outro", A.outroBars, cycle)
		else
			add("breakdown", A.breakdownBars, cycle)
			add("build", A.rebuildBars, cycle + 1)
		end
	end
	return list
end

--- An endless DJ set: a sequence of tracks, each with a flavour (weighted
--- parts of the style), a mode, a key harmonically mixed from the previous
--- track, and an arrangement of intro → build → drops and breakdowns →
--- outro. `spec.flavours` are {id, name, ...}; `spec.modes` mode names;
--- `spec.arrangement` overrides DEFAULT_ARRANGEMENT fields; `spec.modulations`
--- the key changes a cycle may take.
function StyleKit.newSet(seed, spec)
	local arrangement = {}
	for k, v in pairs(DEFAULT_ARRANGEMENT) do arrangement[k] = v end
	for k, v in pairs(spec.arrangement or {}) do arrangement[k] = v end
	for _, flavour in ipairs(spec.flavours or {}) do
		for _, name in ipairs(flavour.snares or {}) do
			assert(SNARE_NAMES[name], "unknown snare character " .. tostring(name))
		end
	end
	local modes = {}
	for _, name in ipairs(spec.modes or {"minor"}) do table.insert(modes, (assert(StyleKit.modes[name], "unknown mode " .. tostring(name)))) end
	return setmetatable({seed = seed, flavours = assert(spec.flavours, "a set needs flavours"), modes = modes,
		arrangement = arrangement, modulations = spec.modulations or {5, -2, 3, 2},
		tracks = {}, hint = 0}, Set)
end
StyleKit.Set = Set

--- Track k of the set, drawn from the one before it. Built iteratively, so a
--- far bar does not recurse through every earlier track.
function Set:track(k)
	local A = self.arrangement
	for index = #self.tracks, k do
		if not self.tracks[index + 1] then
			local previous = self.tracks[index]
			local rng = StyleKit.random(self.seed, 4, index)
			local flavours = self.flavours
			local flavour = rng.pick(flavours)
			if previous and #flavours > 1 and flavour == previous.flavour then
				flavour = flavours[(rng.int(#flavours - 1) + index) % #flavours + 1]
				if flavour == previous.flavour then flavour = flavours[flavour == flavours[1] and 2 or 1] end
			end
			local cycles = A.minCycles + rng.int(A.maxCycles - A.minCycles + 1) - 1
			local track = {
				index = index, flavour = flavour, mode = rng.pick(self.modes), cycles = cycles,
				tonic = previous and (previous.tonic + rng.pick(MIXES)) % 12 or rng.int(12) - 1,
				start = previous and previous.start + previous.length or 0,
				length = A.introBars + A.buildBars + cycles * A.dropBars
					+ (cycles - 1) * (A.breakdownBars + A.rebuildBars) + A.outroBars,
				cycleCache = {}, shifts = {[0] = 0},
			}
			track.key = StyleKit.keyName(track.tonic, track.mode)
			track.sections = sections(A, cycles)
			track.phraseBars, track.blendBars = A.phraseBars, A.blendBars
			-- Its own stream, so the kit never shifts the composition.
			track.drums = StyleKit.drumDesign(StyleKit.random(self.seed, 5, index), flavour)
			self.tracks[index + 1] = track
		end
	end
	return self.tracks[k + 1]
end

--- The track playing bar n.
function Set:trackAt(n)
	local k = self.hint
	local track = self:track(k)
	while n < track.start do k = k - 1; track = self:track(k) end
	while n >= track.start + track.length do k = k + 1; track = self:track(k) end
	self.hint = k
	return track
end

--- The first bar of track k, for skipping ahead in the set.
function Set:trackStart(k)
	return self:track(k).start
end

--- Semitones a track's key has moved by a cycle, accumulated from its first.
function Set:shift(track, index)
	for i = #track.shifts + 1, index do
		track.shifts[i] = track.shifts[i - 1] + StyleKit.random(self.seed, 3, track.index, i).pick(self.modulations)
	end
	return track.shifts[index]
end

--- Material for one cycle of a track, built once by `build(rng)` and cached.
function Set:cycle(track, index, build)
	local cached = track.cycleCache[index]
	if cached then return cached end
	cached = build(StyleKit.random(self.seed, 1, track.index, index), track, index)
	track.cycleCache[index] = cached
	return cached
end

-- The score --------------------------------------------------------------

local Bar = {}
Bar.__index = Bar

--- A bar of score for the Synth. `drums` is its track's kit design. Every
--- list is in 16th steps (fractions allowed for rolls); the Synth adds swing
--- and tempo:
---   hits   {step, voice, gain, nudge, throw}   drum one-shots
---   breaks {step, slice, gain}                 Amen slices
---   bass   {step, length, note, glide, reese, subOnly, accent, wobble}
---   stabs  {step, notes, throw}   keys {step, length, notes, gain}
---   arp    {step, note, length, gain, pan}
---   lead   {step, length, note, glide, gain, throw}
---   pad    notes held two bars      riser {from, to} for one bar
--- `feel` humanizes: small reproducible timing and velocity drift per hit;
--- the kick and the backbeat stay tight, as a drummer's would.
function StyleKit.newBar(n, info, feel)
	local bar = setmetatable({
		index = n, section = info.section, sectionBar = info.sectionBar, sectionLength = info.sectionLength,
		track = info.track.index, trackBar = n - info.track.start, trackLength = info.track.length,
		style = info.track.flavour.name, key = StyleKit.keyName(info.tonic, info.track.mode), tonic = info.tonic,
		drums = info.track.drums, hits = {}, bass = {}, stabs = {}, arp = {}, lead = {}, keys = {}, breaks = {},
	}, Bar)
	bar._feel = feel
	return bar
end

--- Adds a drum hit. `humanize` (0…1) scales the drift; `extra` fields
--- (throw, …) are copied onto the hit.
function Bar:hit(step, voice, gain, humanize, extra)
	local feel = self._feel
	local anchor = voice == "kick" or ((voice == "snare" or voice == "clap") and step % 4 == 0)
	local drift = (humanize or 0) * (anchor and 0.25 or 1)
	local h = {step = step, voice = voice, gain = gain * (1 - 0.3 * drift * feel.float()),
		nudge = (feel.float() - 0.5) * 0.14 * drift}
	if extra then for k, v in pairs(extra) do h[k] = v end end
	table.insert(self.hits, h)
	return h
end

--- Adds one hit per step of a 16-character sequence (see `steps`); accents
--- play at full gain.
function Bar:sequence(sequence, voice, gain, humanize)
	local steps, accents = StyleKit.steps(sequence)
	for _, step in ipairs(steps) do self:hit(step, voice, accents[step] and 1 or gain, humanize) end
end

function Bar:note(list, fields) table.insert(self[list], fields) end

-- Arranging ----------------------------------------------------------------

local Lanes = {}
Lanes.__index = Lanes

--- A builder for a track's lanes: `add` places blocks in any order, and
--- `done()` returns them as {part, blocks} lanes (see host/Arrangement.lua).
function StyleKit.lanes(track)
	return setmetatable({track = track, list = {}, byPart = {}}, Lanes)
end

local function laneOf(self, part)
	local lane = self.byPart[part]
	if not lane then
		lane = {part = part, blocks = {}}
		self.byPart[part] = lane
		table.insert(self.list, lane)
	end
	return lane
end

--- A block of `pattern` on `part`'s lane over bars [start, start + length)
--- of the track, clipped to the track. Blocks never overlap in a lane.
function Lanes:add(part, start, length, pattern, variant)
	local stop = math.min(start + length, self.track.length)
	start = math.max(0, start)
	if stop <= start then return end
	local blocks = laneOf(self, part).blocks
	local i = #blocks
	while i > 0 and blocks[i].start > start do i = i - 1 end
	local before, after = blocks[i], blocks[i + 1]
	assert((not before or before.start + before.length <= start) and not (after and after.start < stop),
		string.format("%s block %s at bar %d overlaps its lane", part, pattern, start))
	table.insert(blocks, i + 1, {start = start, length = stop - start, pattern = pattern, variant = variant})
end

--- Blocks of `pattern` over whatever of [start, start + length) the lane
--- leaves empty, so a background part can run around earlier blocks.
function Lanes:fill(part, start, length, pattern, variant)
	local stop = math.min(start + length, self.track.length)
	local cursor = math.max(0, start)
	local blocks = {table.unpack(laneOf(self, part).blocks)}
	for _, block in ipairs(blocks) do
		if block.start >= stop then break end
		if block.start > cursor then self:add(part, cursor, block.start - cursor, pattern, variant) end
		cursor = math.max(cursor, block.start + block.length)
	end
	if cursor < stop then self:add(part, cursor, stop - cursor, pattern, variant) end
end

--- Bars [from, to) of a section; `to` defaults to the section's end.
function Lanes:within(part, section, from, to, pattern, variant)
	to = math.min(to or section.length, section.length)
	self:add(part, section.start + from, to - from, pattern, variant)
end

--- A one-bar block on the last bar of every `every` bars of a section.
function Lanes:phraseEnds(part, section, every, pattern, variant)
	for bar = every - 1, section.length - 1, every do self:add(part, section.start + bar, 1, pattern, variant) end
end

function Lanes:done() return self.list end

--- The punctuation most styles share: on the fills lane, a crash opening
--- every 16 bars of a drop or outro and each breakdown, and `fill(section,
--- phrase)`'s pattern (or none) on each phrase's last bar of a drop or
--- outro; on the risers lane, a riser through every build and a downlifter
--- out of each impact.
function StyleKit.punctuate(lanes, track, fill)
	local phrase = track.phraseBars
	for _, section in ipairs(track.sections) do
		local id = section.id
		if id == "drop" or id == "outro" then
			for bar = 0, section.length - 1, 16 do lanes:add("fills", section.start + bar, 1, "fill.crash") end
			for bar = phrase - 1, section.length - 1, phrase do
				local pattern = fill and fill(section, bar // phrase)
				if pattern then lanes:add("fills", section.start + bar, 1, pattern) end
			end
		elseif id == "breakdown" then
			lanes:add("fills", section.start, 1, "fill.crash")
		elseif id == "build" then
			lanes:add("risers", section.start, section.length, "riser.build")
		end
		if id == "drop" or id == "breakdown" then lanes:add("risers", section.start, 1, "riser.down") end
	end
end

--- The DJ blend: through the first `blendBars` of a new track's intro the
--- outgoing track's last chords keep sounding on the pads and, for the first
--- half, the sub.
function StyleKit.blendIn(lanes, track)
	if track.index == 0 then return end
	lanes:add("pads", 0, track.blendBars, "pads.blend")
	lanes:add("sub", 0, track.blendBars // 2, "sub.blend")
end

-- Patterns every style shares. A pattern renders one bar of its part into
-- the Bar; `ctx` is the bar's place (see host/Composer.lua). Structure
-- patterns render before the instruments and leave flags on `ctx` for them.

-- A roll tightening through a build: quarters, eighths, then 16ths.
local function roll(voice)
	return function(bar, ctx)
		local bars = ctx.block.length
		local progress = ctx.barInBlock / bars
		local every = progress < 0.5 and 4 or (progress < 0.75 and 2 or 1)
		for step = 0, 15, every do
			bar:hit(step, voice, 0.35 + 0.6 * (ctx.barInBlock * 16 + step) / (bars * 16), ctx.humanize)
		end
	end
end

-- A pad sounds its chord on the first bar of every `bars`.
local function pads(bar, ctx)
	if ctx.loopBar == 0 then bar.pad = ctx.chord.notes end
end

-- The outgoing track, named for the header while it mixes out.
local function blend(bar, ctx)
	local chord, key = ctx.outgoing()
	bar.blend = {key = key, style = ctx.previous.flavour.name}
	return chord
end

StyleKit.patterns = {
	{id = "fill.crash", part = "fills", render = function(bar) bar:hit(0, "crash", 0.8) end},
	{id = "riser.build", part = "risers", render = function(bar, ctx)
		bar.riser = {from = ctx.barInBlock / ctx.block.length, to = (ctx.barInBlock + 1) / ctx.block.length}
	end},
	-- The downlifter washing out of an impact.
	{id = "riser.down", part = "risers", render = function(bar) bar.riser = {from = 1, to = 0} end},
	-- A dub echo: the parts that answer it throw their last hit into the delay.
	{id = "throw", part = "throws", render = function(_, ctx) ctx.throw = true end},
	-- The switch-up: the snare moves to beat three and the arrangement thins.
	{id = "halftime", part = "halftime", render = function(bar, ctx) ctx.halftime, bar.halftime = true, true end},
	-- Break edits: the amen pattern rearranges its slices under this block.
	{id = "chops", part = "chops", render = function(_, ctx) ctx.chops = true end},
	{id = "roll.snare", part = "snare", render = roll("snare")},
	{id = "roll.clap", part = "snare", render = roll("clap")},
	{id = "pads.chords", part = "pads", bars = 2, render = pads},
	{id = "pads.long", part = "pads", bars = 4, render = pads},
	{id = "pads.blend", part = "pads", bars = 2, render = function(bar, ctx)
		local chord = blend(bar, ctx)
		if ctx.loopBar == 0 then bar.pad = chord.notes end
	end},
	{id = "sub.blend", part = "sub", render = function(bar, ctx)
		local chord = blend(bar, ctx)
		table.insert(bar.bass, {step = 0, length = 16, note = chord.root, subOnly = true})
	end},
	-- One long sub note per bar: breakdowns and tails.
	{id = "sub.hold", part = "sub", render = function(bar, ctx)
		table.insert(bar.bass, {step = 0, length = 16, note = ctx.chord.root, subOnly = true})
	end},
	-- The reese voices the sub lane's line through its detuned, filtered
	-- layer; without it the line plays on the sub alone.
	{id = "reese", part = "reese", render = function(bar)
		for _, note in ipairs(bar.bass) do note.subOnly = nil end
	end},
}

return StyleKit
