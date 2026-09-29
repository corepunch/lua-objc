-- The host API every style plugin receives (read-only): seeded randomness,
-- music theory, the DJ set that sequences tracks and gives each its tempo,
-- kit and eight channels, the lane builder and the plan a track is arranged
-- from, the producer's moves, the patterns every style shares, and the bar
-- score the Synth plays. Styles are data on top of it: flavours, beats,
-- lines and hooks; the sound belongs to the patches and the Synth.
local Model = require("apps.dnb.Model")
local Drums = require("apps.dnb.models.Drums")
local Library = require("apps.dnb.host.Library")
local Motif = require("apps.dnb.host.Motif")

local StyleKit = {}

StyleKit.stepsPerBar = 16
StyleKit.motif = Motif
StyleKit.steps = Library.steps
StyleKit.snares = Drums.snares

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
	function rng.between(range) return range[1] + (range[2] - range[1]) * rng.float() end
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
-- Registers, as the lowest MIDI note a part's root may take: the sub from
-- E1 (41 Hz), the hook from E4.
local REGISTER = {bass = 28, lead = 64, counter = 69}
StyleKit.register = REGISTER

--- Folds a pitch into [low, low + 11].
function StyleKit.fold(pitch, low) return low + (pitch - low) % 12 end

--- Scale degree (1-based, may exceed 7 or fall below 1) → semitones above
--- the tonic.
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

--- Voicings in C, voice led through the progression: every chord takes the
--- inversion nearest the previous one, so pads glide instead of jumping.
--- `intervals` are scale steps above each degree: the default {2, 4, 6, 8}
--- is rootless 3-5-7-9; {0, 2, 4, 6} is a plain seventh chord.
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
		root = StyleKit.fold((tonic + degreeSemis(mode, degree)) % 12, REGISTER.bass)}
end

--- The pitch `offset` scale steps above scale degree `degree`, with that
--- degree's own pitch folded into the octave from `low`: a line written in
--- scale steps stays in the key whatever chord it is played over.
function StyleKit.pitch(mode, tonic, degree, offset, low, bend)
	local root = tonic + degreeSemis(mode, degree)
	return StyleKit.fold(root, low) + degreeSemis(mode, degree + offset) - degreeSemis(mode, degree) + (bend or 0)
end

-- Drum kits ---------------------------------------------------------------

--- A track's drum kit: its snare character and how far its kick, snare
--- tuning, hats and clap sit from the style's design. Producers pick new
--- sounds for every tune, so no two tracks in a set share a kit; the style's
--- design keeps them in its genre.
function StyleKit.drumDesign(rng, flavour)
	local design = {snare = rng.pick(flavour.snares or Drums.snares)}
	for _, dimension in ipairs(Drums.dimensions) do design[dimension] = rng.float() * 2 - 1 end
	return design
end

-- The set ------------------------------------------------------------------

-- Harmonic mixing: the next track stays in key or moves a fifth, the moves
-- a DJ's key wheel marks as compatible, with the occasional lift of a tone.
local MIXES = {0, 7, 5, 7, 5, 2}

local DEFAULT_ARRANGEMENT = {
	introBars = 8, buildBars = 8, dropBars = 32, breakdownBars = 16, rebuildBars = 8, outroBars = 16,
	blendBars = 8, phraseBars = 8, minCycles = 2, maxCycles = 3,
}
-- What a flavour leaves out: a tempo and a swing of no range.
local DEFAULT_FEEL = {tempo = {120, 120}, swing = {0, 0}}

local Set = {}
Set.__index = Set

-- How a track's form is drawn. Dance music is written in phrases (eight
-- bars here, as a tracker's 64-row pattern is four), so that two records
-- line up in a mix; but sections differ in length, and no two tunes need
-- the same road through them. Lengths are the style's own, scaled. A style
-- overrides any of these in its set's `form`, and a flavour in its own; an
-- entry listed more often is drawn more often.
local FORM = {
	-- How a track reaches its first drop: through a build, straight out of
	-- the intro, or by way of a melodic passage.
	openings = {"build", "build", "build", "cold", "melodic"},
	-- What joins one drop to the next: a breakdown and a build, a build
	-- alone, a breakdown the drop slams out of, or nothing (a double drop).
	links = {"breakdown build", "breakdown build", "breakdown build", "build", "breakdown", "double"},
	-- How a build winds up: a snare roll, a kick roll, the drop's groove
	-- opening through a filter, or the drums gone under the riser.
	builds = {"roll", "roll", "stomp", "sweep", "rise"},
	intro = {1, 1, 2}, build = {0.5, 1, 1, 2}, drop = {0.5, 1, 1, 1.5}, breakdown = {0.5, 1, 1, 2},
	melodic = {0.5, 1}, rebuild = {0.5, 1, 1, 2},
	buildUnit = 4, -- a build may be half a phrase
}

-- A track's sections, the ruler above its lanes, drawn from `rng`: an
-- intro, a way into the first drop, `cycles` drops joined in different
-- ways, and an outro. `cycle` is the material a section plays; a build
-- belongs to the drop it leads to, so a key change lands with its riser
-- rather than on the drop's first kick. A build carries its `kind`.
local function sections(A, FORM, cycles, rng)
	local list, start = {}, 0
	local function add(id, length, cycle, kind)
		table.insert(list, {id = id, start = start, length = length, cycle = cycle, kind = kind})
		start = start + length
	end
	local function scaled(bars, scales, unit)
		unit = unit or A.phraseBars
		return math.max(unit, math.floor(bars * rng.pick(scales)) // unit * unit)
	end
	local function build(bars, scales, cycle)
		add("build", scaled(bars, scales, FORM.buildUnit), cycle, rng.pick(FORM.builds))
	end
	local opening = rng.pick(FORM.openings)
	add("intro", scaled(A.introBars, FORM.intro), 0)
	if opening == "melodic" then add("breakdown", scaled(A.breakdownBars, FORM.melodic), 0) end
	if opening ~= "cold" then build(A.buildBars, FORM.build, 0) end
	for cycle = 0, cycles - 1 do
		add("drop", scaled(A.dropBars, FORM.drop), cycle)
		if cycle == cycles - 1 then
			add("outro", A.outroBars, cycle)
		else
			local link = rng.pick(FORM.links)
			if link:find("breakdown") then add("breakdown", scaled(A.breakdownBars, FORM.breakdown), cycle) end
			if link:find("build") then build(A.rebuildBars, FORM.rebuild, cycle + 1) end
		end
	end
	return list, start
end

local function merged(base, over)
	local result = {}
	for k, v in pairs(base or {}) do result[k] = v end
	for k, v in pairs(over or {}) do result[k] = v end
	return result
end

-- Checks a flavour's channels against the roles and the library: at most
-- eight, one to a role, playing material that exists.
local function checkFlavour(flavour, roles, library)
	local where = "flavour " .. tostring(flavour.id)
	assert(type(flavour.id) == "string" and type(flavour.name) == "string", "a flavour needs an id and a name")
	for _, name in ipairs(flavour.snares or {}) do
		local known = false
		for _, snare in ipairs(Drums.snares) do known = known or snare == name end
		assert(known, "unknown snare character " .. tostring(name))
	end
	local channels = assert(flavour.channels, where .. " needs channels")
	assert(#channels > 0 and #channels <= Model.channels,
		where .. " plays on at most " .. Model.channels .. " channels")
	local seen = {}
	for _, entry in ipairs(channels) do
		local role = entry.role
		assert(Model.family[role], where .. " has a channel of unknown role " .. tostring(role))
		assert(not seen[role], where .. " has two " .. role .. " channels")
		seen[role] = true
		local spec = merged(roles[role], entry)
		for _, id in ipairs(spec.patches or {}) do library:get("patches", id) end
		for _, id in ipairs(spec.beats or {}) do library:get("beats", id) end
		if spec.half then library:get("beats", spec.half) end
		for _, id in ipairs(spec.fills or {}) do
			if id:sub(1, 1) ~= "@" then library:get("beats", id) end
		end
		for _, id in ipairs(spec.lines or {}) do
			if id:sub(1, 1) == "@" then
				assert(Motif.lines[id:sub(2)], where .. " names unknown line writer " .. id)
			else
				library:get("lines", id)
			end
		end
		for _, id in ipairs(spec.hooks or {}) do
			if id ~= "@motif" then library:get("hooks", id) end
		end
		if Model.family[role] == "drums" then
			assert(#(spec.beats or {}) > 0, where .. " " .. role .. " channel needs beats")
		elseif role ~= "fx" or spec.patches then
			assert(#(spec.patches or {}) > 0, where .. " " .. role .. " channel needs patches")
		end
	end
	assert(seen.drums, where .. " needs a drums channel")
end

--- An endless DJ set: a sequence of tracks, each with a flavour, a mode, a
--- key harmonically mixed from the previous track, a tempo and a swing of
--- its own, a drum kit, its eight channels and their patches, and a form:
--- an intro, drops reached and joined in different ways, and an outro.
--- `spec.flavours` are the style's (see plugins/styles); `spec.roles` what
--- a channel of each role falls back on; `spec.library` the material they
--- name; `spec.modes` mode names; `spec.arrangement` overrides
--- DEFAULT_ARRANGEMENT fields and `spec.form` how forms are drawn (see
--- FORM); `spec.modulations` are the key changes a cycle may take;
--- `spec.salt` is an integer that tells this style's forms from another's
--- under the same seed.
function StyleKit.newSet(seed, spec)
	local arrangement = merged(DEFAULT_ARRANGEMENT, spec.arrangement)
	local form = merged(FORM)
	for k, v in pairs(spec.form or {}) do
		assert(FORM[k], "unknown form field " .. tostring(k))
		form[k] = v
	end
	local library = spec.library or Library.shared()
	local roles = spec.roles or {}
	for role in pairs(roles) do assert(Model.family[role], "unknown role " .. tostring(role)) end
	for _, flavour in ipairs(assert(spec.flavours, "a set needs flavours")) do
		checkFlavour(flavour, roles, library)
		for k in pairs(flavour.form or {}) do assert(FORM[k], "unknown form field " .. tostring(k)) end
	end
	local modes = {}
	for _, name in ipairs(spec.modes or {"minor"}) do table.insert(modes, (assert(StyleKit.modes[name], "unknown mode " .. tostring(name)))) end
	return setmetatable({seed = seed, flavours = spec.flavours, modes = modes, roles = roles, library = library,
		arrangement = arrangement, form = form, salt = spec.salt or 0, modulations = spec.modulations or {5, -2, 3, 2},
		tracks = {}, hint = 0}, Set)
end
StyleKit.Set = Set

-- One of `ids`, other than `avoid` where there is a choice.
local function another(rng, ids, avoid)
	local id = rng.pick(ids)
	if id == avoid and #ids > 1 then
		local rest = {}
		for _, other in ipairs(ids) do if other ~= avoid then table.insert(rest, other) end end
		id = rng.pick(rest)
	end
	return id
end

-- A track's channels, drawn from its flavour: a channel the flavour gives
-- a `chance` may sit the track out, and each takes a patch or a beat the
-- track before it did not play.
local function channelsOf(set, rng, flavour, previous)
	local channels, byRole = {}, {}
	local library = set.library
	for _, entry in ipairs(flavour.channels) do
		local spec = merged(set.roles[entry.role], entry)
		local plays = spec.chance == nil or rng.chance(spec.chance)
		local before = previous and previous.byRole[spec.role]
		local channel = {role = spec.role, spec = spec, name = Model.roles[Model.roleIndex[spec.role]].title}
		if spec.patches then
			channel.patch = library:get("patches", another(rng, spec.patches, before and before.patch and before.patch.id))
			channel.name = channel.patch.name
		end
		if spec.beats then
			channel.beat = library:get("beats", another(rng, spec.beats, before and before.beat and before.beat.id))
			-- The groove a later drop may turn to.
			channel.alt = library:get("beats", another(rng, spec.beats, channel.beat.id))
			channel.half = spec.half and library:get("beats", spec.half) or nil
			channel.name = channel.beat.name
		end
		if plays then
			table.insert(channels, channel)
			byRole[channel.role] = channel
		end
	end
	return channels, byRole
end

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
				shifts = {[0] = 0},
			}
			track.key = StyleKit.keyName(track.tonic, track.mode)
			-- Its own stream, so the form never shifts the composition.
			track.sections, track.length = sections(A, merged(self.form, flavour.form), cycles,
				StyleKit.random(self.seed, 7, index, self.salt))
			track.phraseBars, track.blendBars = A.phraseBars, A.blendBars
			-- What its arrangement and its material draw from.
			track.seed = hash(self.seed, 6, index, self.salt)
			-- Their own streams, so the kit and the channels never shift
			-- the composition.
			track.drums = StyleKit.drumDesign(StyleKit.random(self.seed, 5, index), flavour)
			local feel = StyleKit.random(self.seed, 8, index, self.salt)
			track.tempo = math.floor(feel.between(flavour.tempo or DEFAULT_FEEL.tempo) + 0.5)
			track.swing = feel.between(flavour.swing or DEFAULT_FEEL.swing)
			track.channels, track.byRole = channelsOf(self, StyleKit.random(self.seed, 9, index, self.salt), flavour,
				previous)
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

--- The tempo of set bar n: the track's own, reached through its first
--- `blendBars` from the tempo of the track before, as a DJ rides the pitch
--- fader through a mix.
function Set:tempoAt(n)
	local track = self:trackAt(n)
	local pos = n - track.start
	if track.index == 0 or pos >= track.blendBars then return track.tempo end
	local before = self:track(track.index - 1).tempo
	return before + (track.tempo - before) * pos / track.blendBars
end

-- The score --------------------------------------------------------------

local Bar = {}
Bar.__index = Bar

--- A bar of score for the Synth. `channels` are its track's and `drums` its
--- kit design; `tempo` is the bar's own (BPM) and `trackTempo` the tempo
--- its loops were made at; `swing` delays the off-16ths, in 16ths. Every
--- list is in 16th steps (fractions allowed for rolls), each entry naming
--- the `role` of the channel that plays it:
---   hits   {role, step, voice, gain, nudge, throw}      one-shots of the kit
---   slices {role, step, length, beat, variant, slice, gain, rate, reverse,
---           throw, energy, complexity}                  a loop, by slice
---   notes  {role, step, length, notes, patch, gain, glide, accent, rate,
---           throw, from, to, gap}                        a voice of a patch
--- `notes` holds one MIDI note or a chord; `rate` is a wobble's cycles per
--- beat; `from` and `to` how far through a rise the note starts and ends;
--- `gap` the share of a 16th it stops short by (0 for a held chord).
--- `kickSteps` and `snareSteps` are where the kit's accents fall, for the
--- sidechain and the visualizer. `automation[role]` is the ride a channel's
--- block takes through the bar: {level = {from, to}, kind, filter = {from,
--- to}}. `feel` humanizes one-shots: small reproducible timing and velocity
--- drift per hit; the kick and the backbeat stay tight, as a drummer's would.
function StyleKit.newBar(n, info, feel)
	local track = info.track
	local bar = setmetatable({
		index = n, section = info.section, sectionBar = info.sectionBar, sectionLength = info.sectionLength,
		track = track.index, trackBar = n - track.start, trackLength = track.length,
		style = track.flavour.name, key = StyleKit.keyName(info.tonic, track.mode), tonic = info.tonic,
		tempo = info.tempo, trackTempo = track.tempo, swing = track.swing,
		channels = track.channels, drums = track.drums,
		automation = {}, hits = {}, slices = {}, notes = {}, kickSteps = {}, snareSteps = {},
	}, Bar)
	bar._feel = feel
	return bar
end

--- Adds a drum hit to `role`'s channel. `humanize` (0…1) scales the
--- drift; `extra` fields (throw, …) are copied onto the hit.
function Bar:hit(role, step, voice, gain, humanize, extra)
	local feel = self._feel
	local anchor = voice == "kick" or ((voice == "snare" or voice == "clap") and step % 4 == 0)
	local drift = (humanize or 0) * (anchor and 0.25 or 1)
	local h = {role = role, step = step, voice = voice, gain = gain * (1 - 0.3 * drift * feel.float()),
		nudge = (feel.float() - 0.5) * 0.14 * drift}
	if extra then for k, v in pairs(extra) do h[k] = v end end
	table.insert(self.hits, h)
	if voice == "kick" then table.insert(self.kickSteps, step) end
	if (voice == "snare" or voice == "clap") and gain >= 0.8 then table.insert(self.snareSteps, step) end
	return h
end

--- The notes `role` plays in this bar.
function Bar:of(role)
	local notes = {}
	for _, note in ipairs(self.notes) do
		if note.role == role then table.insert(notes, note) end
	end
	return notes
end

--- The slices `role` plays in this bar.
function Bar:loop(role)
	local slices = {}
	for _, slice in ipairs(self.slices) do
		if slice.role == role then table.insert(slices, slice) end
	end
	return slices
end

--- The one-shots of `voice` in this bar, as sorted steps.
function Bar:steps(voice)
	local steps = {}
	for _, hit in ipairs(self.hits) do
		if hit.voice == voice then table.insert(steps, hit.step) end
	end
	table.sort(steps)
	return steps
end

-- Arranging ----------------------------------------------------------------

local Lanes = {}
Lanes.__index = Lanes

--- A builder for a track's lanes, one to a channel: `add` places blocks in
--- any order, `cut` and `automate` edit what is placed, and `done()` returns
--- the lanes as {part, blocks} (see host/Arrangement.lua). Blocks for a
--- role the track has no channel for are dropped, so a plan can name every
--- role and a track plays the eight it has.
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

-- An envelope's value `at` (0…1) of the way through it.
local function along(envelope, at)
	return envelope.from + (envelope.to - envelope.from) * at
end

-- The part of `block` over track bars [start, stop), as a block of its own.
-- Like a clip split in an arrange window, a piece keeps playing its pattern
-- from where the whole block would be (`offset` bars in, of `whole`), and
-- its envelopes are the stretch of the block's that it covers.
local function piece(block, start, stop)
	local from, to = (start - block.start) / block.length, (stop - block.start) / block.length
	local result = {start = start, length = stop - start, pattern = block.pattern, keep = block.keep,
		offset = (block.offset or 0) + start - block.start, whole = block.whole or block.length}
	if block.level then result.level = {from = along(block.level, from), to = along(block.level, to)} end
	if block.filter then
		result.filter = {kind = block.filter.kind, from = along(block.filter, from), to = along(block.filter, to)}
	end
	return result
end

--- Whether the track has a channel for `part`. A track given no channels
--- (a test's) has them all.
function Lanes:has(part)
	local byRole = self.track.byRole
	return byRole == nil or byRole[part] ~= nil
end

--- A block of `pattern` on `part`'s lane over bars [start, start + length)
--- of the track, clipped to the track. Blocks never overlap in a lane.
--- `automation` may give the block a `level` {from, to} (a fade, 0…1) and a
--- `filter` {kind = "lowpass" | "highpass", from, to} (a sweep: 1 is open,
--- 0 as closed as it goes); with `keep` the block is what its section is
--- about, and the producer's moves leave its entry alone.
function Lanes:add(part, start, length, pattern, automation)
	if not self:has(part) then return end
	local stop = math.min(start + length, self.track.length)
	start = math.max(0, start)
	if stop <= start then return end
	local blocks = laneOf(self, part).blocks
	local i = #blocks
	while i > 0 and blocks[i].start > start do i = i - 1 end
	local before, after = blocks[i], blocks[i + 1]
	assert((not before or before.start + before.length <= start) and not (after and after.start < stop),
		string.format("%s block %s at bar %d overlaps its lane", part, pattern, start))
	local block = {start = start, length = stop - start, pattern = pattern}
	if automation then block.level, block.filter, block.keep = automation.level, automation.filter, automation.keep end
	table.insert(blocks, i + 1, block)
end

--- Blocks of `pattern` over whatever of [start, start + length) the lane
--- leaves empty, so a background part can run around earlier blocks.
function Lanes:fill(part, start, length, pattern, automation)
	if not self:has(part) then return end
	local stop = math.min(start + length, self.track.length)
	local cursor = math.max(0, start)
	local blocks = {table.unpack(laneOf(self, part).blocks)}
	for _, block in ipairs(blocks) do
		if block.start >= stop then break end
		if block.start > cursor then self:add(part, cursor, block.start - cursor, pattern, automation) end
		cursor = math.max(cursor, block.start + block.length)
	end
	if cursor < stop then self:add(part, cursor, stop - cursor, pattern, automation) end
end

--- Bars [from, to) of a section; `to` defaults to the section's end.
function Lanes:within(part, section, from, to, pattern, automation)
	to = math.min(to or section.length, section.length)
	self:add(part, section.start + from, to - from, pattern, automation)
end

--- A one-bar block on the last bar of every `every` bars of a section.
function Lanes:phraseEnds(part, section, every, pattern)
	for bar = every - 1, section.length - 1, every do self:add(part, section.start + bar, 1, pattern) end
end

--- The block of `part` under track bar `pos`, or nil.
function Lanes:at(part, pos)
	local lane = self.byPart[part]
	for _, block in ipairs(lane and lane.blocks or {}) do
		if block.start <= pos and pos < block.start + block.length then return block end
	end
end

--- Whether `part` has a block anywhere in bars [start, start + length).
function Lanes:plays(part, start, length)
	local lane = self.byPart[part]
	for _, block in ipairs(lane and lane.blocks or {}) do
		if block.start < start + length and block.start + block.length > start then return true end
	end
	return false
end

-- Splits the lane's blocks at the edges of [start, stop) and calls
-- `edit(block)` for each one inside, in order; a block `edit` returns
-- false for is removed.
local function edit(self, part, start, stop, change)
	local lane = self.byPart[part]
	if not lane then return end
	local blocks = {}
	for _, block in ipairs(lane.blocks) do
		local first, last = block.start, block.start + block.length
		local from, to = math.max(first, start), math.min(last, stop)
		if from >= to then
			table.insert(blocks, block)
		else
			if first < from then table.insert(blocks, piece(block, first, from)) end
			local inside = (first < from or to < last) and piece(block, from, to) or block
			if change(inside) ~= false then table.insert(blocks, inside) end
			if to < last then table.insert(blocks, piece(block, to, last)) end
		end
	end
	lane.blocks = blocks
end

--- Silences bars [start, start + length) of a lane: the drop-out before a
--- phrase lands, or a part that enters late or leaves early.
function Lanes:cut(part, start, length)
	edit(self, part, start, start + length, function() return false end)
end

--- Rides a fade or a filter sweep over bars [start, start + length) of a
--- lane, across however many blocks lie there (see `add` for `automation`).
function Lanes:automate(part, start, length, automation)
	local stop = start + length
	edit(self, part, start, stop, function(block)
		local from, to = (block.start - start) / length, (block.start + block.length - start) / length
		local level, filter = automation.level, automation.filter
		if level then block.level = {from = along(level, from), to = along(level, to)} end
		if filter then block.filter = {kind = filter.kind, from = along(filter, from), to = along(filter, to)} end
	end)
end

--- Plays `pattern` over bars [start, start + length) of a lane in place of
--- whatever it held there.
function Lanes:replace(part, start, length, pattern, automation)
	self:cut(part, start, length)
	self:add(part, start, length, pattern, automation)
end

function Lanes:done()
	local lanes = {}
	for _, lane in ipairs(self.list) do
		if #lane.blocks > 0 then table.insert(lanes, lane) end
	end
	return lanes
end

-- The plan --------------------------------------------------------------------

--- What each role plays in each section, unless a style or a flavour says
--- otherwise: a pattern id, an entry {pattern, from, to, cycle, last,
--- every, level, filter, keep}, or a list of entries. `from` and `to` are bars
--- into the section (negative: from its end) or "half", "phrase" and
--- "blend" (the bars a new track mixes in over); `cycle` is the first
--- cycle the entry plays in and `last` the last one; `every` places a
--- one-bar block every so many bars; `keep` holds a part to its entry,
--- which the producer would otherwise be free to delay. A role the track
--- has no channel for
--- plays nothing. In a style's or a flavour's `plan`, `false` silences a
--- role in a section.
StyleKit.plan = {
	intro = {
		drums = "drums.light",
		pad = {"pad.chords", from = "blend"},
		keys = {"keys.comp", from = "blend"},
		texture = "texture.drone",
	},
	build = {
		drums = "drums.roll",
		pad = "pad.chords",
		arp = {"arp.run", from = "half"},
		texture = "texture.drone",
		fx = "fx.riser",
	},
	drop = {
		drums = "drums.groove",
		tops = "tops.loop",
		bass = "bass.line",
		pad = {"pad.chords", from = "phrase"},
		keys = {"keys.comp", from = "phrase"},
		stab = "stab.hits",
		arp = {"arp.run", from = "phrase"},
		lead = {"lead.hook", from = 16},
		counter = {"counter.answer", from = 16},
		texture = "texture.drone",
		fx = {"fx.impact", every = 16},
	},
	breakdown = {
		bass = "bass.hold",
		pad = "pad.chords",
		keys = "keys.comp",
		arp = "arp.run",
		lead = {"lead.soft", from = "half"},
		texture = "texture.drone",
		fx = {"fx.impact", to = 1},
	},
	outro = {
		drums = {{"drums.groove", to = "half"}, {"drums.light", from = "half"}},
		tops = "tops.loop",
		bass = {{"bass.line", to = "half"}, {"bass.hold", from = "half"}},
		keys = "keys.comp",
		texture = "texture.drone",
		fx = {"fx.impact", every = 16},
	},
}

--- A plan with `overrides` laid over it, section by section and role by
--- role.
function StyleKit.planWith(plan, overrides)
	local result = {}
	for section, roles in pairs(plan) do result[section] = merged(roles) end
	for section, roles in pairs(overrides or {}) do
		assert(StyleKit.plan[section], "a plan has no section " .. tostring(section))
		result[section] = result[section] or {}
		for role, entry in pairs(roles) do
			assert(Model.family[role], "a plan names unknown role " .. tostring(role))
			result[section][role] = entry
		end
	end
	return result
end

-- A bar count from an entry's `from` or `to`.
local function barsOf(value, section, track, default)
	if value == nil then return default end
	if value == "half" then return section.length // 2 end
	if value == "phrase" then return track.phraseBars end
	if value == "blend" then return track.index > 0 and track.blendBars or 0 end
	assert(math.type(value) == "integer", "a plan counts whole bars, not " .. tostring(value))
	return value < 0 and section.length + value or value
end

local function place(lanes, track, section, role, entry)
	if type(entry) == "string" then entry = {entry} end
	if type(entry[1]) == "table" then
		for _, each in ipairs(entry) do place(lanes, track, section, role, each) end
		return
	end
	if entry.cycle and section.cycle < entry.cycle then return end
	if entry.last and section.cycle > entry.last then return end
	local from = math.min(barsOf(entry.from, section, track, 0), section.length)
	local to = math.min(barsOf(entry.to, section, track, section.length), section.length)
	local automation = (entry.level or entry.filter or entry.keep)
		and {level = entry.level, filter = entry.filter, keep = entry.keep} or nil
	if entry.every then
		for bar = from, to - 1, entry.every do lanes:add(role, section.start + bar, 1, entry[1], automation) end
	elseif to > from then
		-- Around what the lane already holds: the blend into a new track.
		lanes:fill(role, section.start + from, to - from, entry[1], automation)
	end
end

-- The producer's moves ------------------------------------------------------

local PRODUCE = {
	drums = {"drums", "tops"},
	melodic = {"keys", "stab", "arp", "lead", "counter"},
	-- Parts that may join a section late or leave it early.
	layers = {"tops", "stab", "counter", "texture"},
	-- What a filter build borrows from the drop it leads to.
	groove = {"drums", "bass"},
	sweepFilter = 0.15,  -- where the whole mix opens a filter build from
	slamFilter = 0.3,    -- and closes to, when a breakdown runs into a drop
	slamBars = 4,
	introFilter = 0.3,   -- how far shut the drums open an intro
	buildFilter = 0.4,   -- how thin a build's tops get before the drop
	teaseFilter = {from = 0.12, to = 0.6},
	teaseLevel = {from = 0.4, to = 0.9},
	dipFilter = 0.3,     -- the bass closing into a drop's second half
	outroFilter = 0.35,
	fade = 0.3,          -- where a faded part starts from, or ends at
	pullBack = 0.7, smallPullBack = 0.35, dip = 0.5, tease = 0.6, leave = 0.3,
	fill = 0.85,         -- the share of phrases that end on a drum fill
}

local function each(lanes, parts, start, length, automation)
	for _, part in ipairs(parts) do lanes:automate(part, start, length, automation) end
end

-- Whether a layer's entry into a section may be delayed: it plays from the
-- section's first bar, and the plan does not hold it there.
local function mayDelay(lanes, part, start)
	local block = lanes:at(part, start)
	return block ~= nil and not block.keep
end

local ALL = {}
for _, role in ipairs(Model.roles) do table.insert(ALL, role.id) end

--- What turns a plan of whole sections into an arrangement, drawn from the
--- track's seed. Parts join a section a phrase or two late and leave early;
--- a phrase ends on a drum fill, or the bar before it lands pulls the drums,
--- the bass or both out; filters open the drums through an intro, thin the
--- tops through a build, tease the bass under it, close the bass into a
--- drop's second half and the pads open through a breakdown; an outro sheds
--- parts and closes down for the next track to mix over. A build winds up
--- as its `kind` says (see FORM.builds). Call it last, on lanes arranged
--- section by section.
function StyleKit.produce(lanes, track)
	local rng = StyleKit.random(track.seed, 1)
	local phrase, P = track.phraseBars, PRODUCE
	local drop = 0
	for i, section in ipairs(track.sections) do
		local id, start, length = section.id, section.start, section.length
		local half = length // 2
		local following = track.sections[i + 1]
		if id == "intro" then
			each(lanes, P.drums, start, length, {filter = {kind = "lowpass", from = P.introFilter, to = 1}})
			each(lanes, P.melodic, start, length, {level = {from = P.fade, to = 1}})
			for _, part in ipairs(P.layers) do
				local bars = rng.pick({0, length // 4, half})
				if mayDelay(lanes, part, start) then lanes:cut(part, start, bars) end
			end
		elseif id == "build" then
			local kind = section.kind
			if kind == "stomp" then
				lanes:replace("drums", start, length, "drums.stomp")
			elseif kind == "sweep" then
				-- The drop's groove, early, opening through a filter.
				for _, part in ipairs(P.groove) do
					local block = lanes:at(part, start + length)
					if block then lanes:replace(part, start, length, block.pattern) end
				end
				each(lanes, ALL, start, length, {filter = {kind = "lowpass", from = P.sweepFilter, to = 1}})
			elseif kind == "rise" then
				for _, part in ipairs(P.drums) do lanes:cut(part, start, length) end
			end
			if kind ~= "sweep" then
				lanes:automate("tops", start, length, {filter = {kind = "highpass", from = 1, to = P.buildFilter}})
				each(lanes, P.melodic, start, length, {level = {from = P.fade * 2, to = 1}})
				if not lanes:plays("bass", start, length) and (kind == "rise" or rng.chance(P.tease)) then
					lanes:add("bass", start + half, length - half, "bass.hold", {level = P.teaseLevel,
						filter = {kind = "lowpass", from = P.teaseFilter.from, to = P.teaseFilter.to}})
				end
			end
		elseif id == "drop" or id == "outro" then
			if id == "drop" then
				drop = drop + 1
				-- The first drop holds layers back; later ones arrive nearly whole.
				local entries = drop == 1 and {0, 0, 1, 2} or {0, 0, 0, 1}
				for _, part in ipairs(P.layers) do
					local bars = rng.pick(entries) * phrase
					if mayDelay(lanes, part, start) then lanes:cut(part, start, bars) end
					local phrases = length // phrase
					if phrases > 2 and rng.chance(P.leave) then
						lanes:cut(part, start + (rng.int(phrases - 2) + 1) * phrase, phrase)
					end
				end
			end
			-- How each phrase ends: on a fill, or with the drums, the bass
			-- or both pulled out of the bar before the next one lands.
			for last = phrase - 1, length - 1, phrase do
				local final = last == length - 1
				local big = (last + 1) % (2 * phrase) == 0
				local move = rng.chance(P.fill) and "fill" or "none"
				if id == "drop" and not final and rng.chance(big and P.pullBack or P.smallPullBack) then
					move = big and rng.pick({"bass", "drums", "both", "fill"}) or "tops"
				end
				if move == "fill" and lanes:at("drums", start + last) then
					lanes:replace("drums", start + last, 1, "drums.fill")
				end
				if move == "drums" or move == "both" then
					for _, part in ipairs(P.drums) do lanes:cut(part, start + last, 1) end
				end
				if move == "bass" or move == "both" then lanes:cut("bass", start + last, 1) end
				if move == "bass" and lanes:at("drums", start + last) then
					lanes:replace("drums", start + last, 1, "drums.fill")
				end
				if move == "tops" then lanes:cut("tops", start + last, 1) end
			end
			if id == "drop" and length >= 4 * phrase and rng.chance(P.dip) then
				lanes:automate("bass", start + half - phrase // 2, phrase // 2,
					{filter = {kind = "lowpass", from = 1, to = P.dipFilter}})
			end
			if id == "outro" then
				for _, part in ipairs(P.layers) do
					local from = (rng.int(math.max(1, length // phrase)) - 1) * phrase + rng.pick({0, phrase // 2})
					if from > 0 then lanes:cut(part, start + from, length - from) end
				end
				each(lanes, P.melodic, start, length, {level = {from = 1, to = P.fade}})
				lanes:automate("tops", start + half, length - half, {filter = {kind = "highpass", from = 1, to = P.buildFilter}})
				lanes:automate("bass", start, length, {filter = {kind = "lowpass", from = 1, to = P.outroFilter}})
			end
		elseif id == "breakdown" then
			lanes:automate("pad", start, length, {filter = {kind = "lowpass", from = P.introFilter, to = 1}})
			lanes:automate("keys", start, length, {filter = {kind = "lowpass", from = 0.5, to = 1}})
			lanes:automate("arp", start, length, {level = {from = P.fade, to = 1}})
			lanes:automate("tops", start, length, {level = {from = 1, to = P.fade}})
			if following and following.id == "drop" then
				-- No build: the mix closes down and the drop slams out of it.
				local bars = math.min(P.slamBars, length)
				each(lanes, ALL, start + length - bars, bars, {filter = {kind = "lowpass", from = 1, to = P.slamFilter}})
			end
		end
	end
end

--- The DJ blend: through the first `blendBars` of a new track's intro the
--- outgoing track's last chords keep sounding on the pad and, for the
--- first half, the bass, played on the outgoing track's patches.
function StyleKit.blendIn(lanes, track, previous)
	if track.index == 0 or not previous then return end
	if previous.byRole.pad then lanes:add("pad", 0, track.blendBars, "pad.blend") end
	if previous.byRole.bass then lanes:add("bass", 0, track.blendBars // 2, "bass.blend") end
end

--- A track's lanes from a plan (see StyleKit.plan): the blend into it, each
--- section's roles, then the producer's moves. `previous` is the track
--- before it in the set.
function StyleKit.arrange(track, plan, previous)
	local lanes = StyleKit.lanes(track)
	StyleKit.blendIn(lanes, track, previous)
	for _, section in ipairs(track.sections) do
		-- In the order the channels are listed, so a plan reads the same
		-- from one run to the next.
		for _, role in ipairs(Model.roles) do
			local entry = (plan[section.id] or {})[role.id]
			if entry then place(lanes, track, section, role.id, entry) end
		end
	end
	StyleKit.produce(lanes, track)
	return lanes:done()
end

-- Patterns every style shares. A pattern renders one bar of its role's
-- channel into the Bar; `ctx` is the bar's place and the track's material
-- (see host/Composer.lua). The drums render first and leave `ctx.fill` for
-- the parts that make room for one.

-- How far a fill, a chop or an edit reaches into a bar's last beat.
local EDIT = {from = 12, flam = 14, retrig = 0.5, tape = 0.5}

-- One bar of `beat` by slice. `options.variant` is the loop's (see
-- Drums.plays); `options.from` and `to` bound the steps played;
-- `options.edits[step]` replaces a step's slice with a list of {at, slice,
-- length, reverse, rate, gain} (`at` a fraction of the step in), or with
-- false for silence; `options.phase` is the bar of the loop to play.
local function playLoop(ctx, beat, options)
	options = options or {}
	local edits = options.edits or {}
	local phase = (options.phase or ctx.pos) % beat.bars
	local step = options.from or 0
	local stop = options.to or StyleKit.stepsPerBar
	while step < stop do
		local change = edits[step]
		local advance = 1
		if change == nil then
			ctx.slice({step = step, beat = beat, slice = phase * StyleKit.stepsPerBar + step,
				variant = options.variant, gain = options.gain, throw = options.throw and step == 12 or nil})
		elseif change then
			for _, each in ipairs(change) do
				ctx.slice({step = step + (each.at or 0), beat = beat, slice = each.slice % beat.slices,
					length = each.length, reverse = each.reverse, rate = each.rate, variant = options.variant,
					gain = (options.gain or 1) * (each.gain or 1)})
				advance = math.max(advance, math.ceil((each.at or 0) + (each.length or 1)))
			end
		end
		step = step + advance
	end
end

-- The cycle's chops for this bar of a phrase, as edits of `beat`: a
-- producer's break edits, let in as Complexity rises.
local function chopEdits(ctx, beat, chops)
	local edits = {}
	for _, chop in ipairs(chops or {}) do
		if chop.bar == ctx.phraseBar and chop.threshold < ctx.complexity * 0.9 then
			local source = chop.source % beat.slices
			if chop.kind == "stutter" then
				local snares = beat.snareSlices
				local snare = #snares > 0 and snares[chop.source % #snares + 1] or source
				for i = 0, chop.length - 1 do
					if chop.step + i < 16 then edits[chop.step + i] = {{slice = snare}} end
				end
			elseif chop.kind == "reverse" then
				if chop.step + chop.length <= 16 then
					edits[chop.step] = {{slice = source, length = chop.length, reverse = true}}
				end
			else
				for i = 0, chop.length - 1 do
					if chop.step + i < 16 then edits[chop.step + i] = {{slice = source + i}} end
				end
			end
		end
	end
	return edits
end

-- A roll tightening through a build: quarters, eighths, then 16ths.
local function roll(voice)
	return function(bar, ctx)
		local bars = ctx.blockLength
		local progress = ctx.barInBlock / bars
		local every = progress < 0.5 and 4 or (progress < 0.75 and 2 or 1)
		local played = type(voice) == "function" and voice(ctx) or voice
		for step = 0, 15, every do
			ctx.hit(step, played, 0.35 + 0.6 * (ctx.barInBlock * 16 + step) / (bars * 16))
		end
	end
end

-- The voice a channel rolls into a drop on: the style's, or the snare.
local function rollVoice(ctx) return ctx.channel.spec.roll or "snare" end

-- The bar's groove: the cycle's, or its half-time beat under a switch-up.
local function grooveOf(ctx)
	local channel = ctx.channel
	if ctx.halftime and channel.half then return channel.half end
	return ctx.cycle.grooves[channel.role] or channel.beat
end

local function loopPattern(variant)
	return function(_, ctx)
		local beat = grooveOf(ctx)
		local chops = ctx.channel.spec.chops and not ctx.halftime and ctx.cycle.chops or nil
		playLoop(ctx, beat, {variant = variant, gain = ctx.channel.spec.gain, throw = ctx.throw,
			edits = chopEdits(ctx, beat, chops)})
	end
end

-- The edits a fill makes of the groove itself, the tracker's effects: a
-- stuttered snare, the last beat backwards, a drop-out and a flam, a
-- retrigger in 32nds, or the tape slowing to half speed.
local function fillEdits(kind, beat, phase)
	local edits = {}
	local base = phase * StyleKit.stepsPerBar
	local snares = beat.snareSlices
	local snare = #snares > 0 and snares[#snares] or base + EDIT.from
	if kind == "stutter" then
		edits[12], edits[13] = {{slice = snare}}, {{slice = snare}}
		edits[14] = {{slice = snare, length = 0.5}, {at = 0.5, slice = snare, length = 0.5}}
		edits[15] = {{slice = snare, length = 0.5}, {at = 0.5, slice = snare, length = 0.5}}
	elseif kind == "reverse" then
		edits[12] = {{slice = base + 12, length = 4, reverse = true}}
	elseif kind == "cut" then
		for step = 8, 13 do edits[step] = false end
		edits[14] = {{slice = snare, length = 0.5, gain = 0.6}, {at = 0.5, slice = snare, length = 0.5, gain = 0.8}}
		edits[15] = {{slice = snare}}
	elseif kind == "retrig" then
		for step = 12, 15 do
			edits[step] = {{slice = base + 12, length = EDIT.retrig}, {at = 0.5, slice = base + 12, length = EDIT.retrig}}
		end
	elseif kind == "tape" then
		edits[12] = {{slice = base + 12, length = 4, rate = EDIT.tape}}
	else
		error("unknown fill " .. tostring(kind))
	end
	return edits
end
--- The fills that edit the groove ("@stutter" in a channel's `fills`).
StyleKit.fills = {"stutter", "reverse", "cut", "retrig", "tape"}

-- Notes of a line or a hook that fall in this bar, with their steps in it.
local function inBar(line, bar)
	local notes = {}
	local first = (bar % line.bars) * StyleKit.stepsPerBar
	for _, note in ipairs(line.notes) do
		if note.step >= first and note.step < first + StyleKit.stepsPerBar then
			table.insert(notes, {note = note, step = note.step - first})
		end
	end
	return notes
end

local function plays(note, ctx)
	return note.chance <= ctx.energy * 0.9 + 0.1 and note.detail <= ctx.complexity
end

-- The hook (or a voice answering it) at `gain`, in `register`.
local function melody(which, gain, register)
	return function(_, ctx)
		if ctx.halftime then return end
		local line = ctx.cycle[which]
		if not line then return end
		local played = inBar(line, ctx.phraseBar)
		local degree = line.follow == "key" and 1 or ctx.chord.degree
		for index, each in ipairs(played) do
			local note = each.note
			if plays(note, ctx) then
				ctx.note({step = each.step, length = math.min(note.length, 16 - each.step), glide = note.glide,
					gain = gain, throw = (ctx.throw and index == #played) or nil,
					notes = {ctx.kit.pitch(ctx.mode, ctx.tonic, degree, note.offset, register, note.bend)
						+ 12 * (ctx.channel.spec.octave or 0)}})
			end
		end
	end
end

-- The chord held for as many bars as it lasts; a block that starts inside a
-- chord sounds what is left of it.
local function chords(bar, ctx, chord, patch)
	local every = ctx.barsPerChord
	local into = ctx.n % every
	if into == 0 or ctx.barInBlock == 0 then
		local bars = math.min(every - into, ctx.block.length - (ctx.pos - ctx.block.start))
		ctx.note({step = 0, length = bars * StyleKit.stepsPerBar, gap = 0, notes = chord.notes, patch = patch})
	end
end

-- The outgoing track, named for the header while it mixes out.
local function blend(bar, ctx)
	local chord, key = ctx.outgoing()
	bar.blend = {key = key, style = ctx.previous.flavour.name}
	return chord
end

local function riser(from, to)
	return function(_, ctx)
		local length = ctx.blockLength
		local a, b = ctx.barInBlock / length, (ctx.barInBlock + 1) / length
		if from > to then a, b = 1 - a, 1 - b end
		ctx.note({step = 0, length = StyleKit.stepsPerBar, gap = 0, notes = {60}, from = a, to = b})
		ctx.bar.riser = {from = a, to = b}
	end
end

StyleKit.patterns = {
	-- Drums: a loop by slice, its light variant for intros and outros, its
	-- tops alone, a fill, and the rolls of a build.
	{id = "drums.groove", part = "drums", render = loopPattern("full")},
	{id = "drums.light", part = "drums", render = loopPattern("light")},
	{id = "drums.tops", part = "drums", render = loopPattern("tops")},
	{id = "drums.fill", part = "drums", render = function(_, ctx)
		local beat = grooveOf(ctx)
		local fills = ctx.cycle.fills
		local fill = fills[(ctx.sectionBar // ctx.track.phraseBars) % #fills + 1]
		ctx.fill = fill.id
		if ctx.halftime then
			playLoop(ctx, beat, {variant = "full", gain = ctx.channel.spec.gain})
		elseif fill.beat then
			-- The groove up to the fill, then the fill's own loop.
			local from = fill.beat.from or EDIT.from
			playLoop(ctx, beat, {variant = "full", gain = ctx.channel.spec.gain, to = from})
			playLoop(ctx, fill.beat, {variant = "full", gain = ctx.channel.spec.gain, from = from, phase = 0})
		else
			playLoop(ctx, beat, {variant = "full", gain = ctx.channel.spec.gain,
				edits = fillEdits(fill.edit, beat, ctx.pos % beat.bars)})
		end
	end},
	{id = "drums.roll", part = "drums", render = roll(rollVoice)},
	-- The kick winds up; the snare joins for the last two bars.
	{id = "drums.stomp", part = "drums", render = function(bar, ctx)
		roll("kick")(bar, ctx)
		if ctx.blockLength - ctx.barInBlock <= 2 then
			for step = 0, 15, ctx.blockLength - ctx.barInBlock == 1 and 1 or 2 do
				ctx.hit(step, rollVoice(ctx), 0.4 + 0.035 * step)
			end
		end
	end},
	-- The second loop: a break or a percussion loop over the programmed kit.
	{id = "tops.loop", part = "tops", render = loopPattern("full")},
	{id = "tops.light", part = "tops", render = loopPattern("tops")},

	-- Bass: the track's line, every fourth bar its busier variation; one
	-- long note; and the outgoing track's under a blend.
	{id = "bass.line", part = "bass", render = function(_, ctx)
		local line = ctx.cycle.line
		local notes = inBar(line, ctx.pos)
		if line.variation and ctx.phraseBar % 4 == 3 and ctx.complexity > 0.3 and not ctx.halftime then
			notes = {}
			for _, note in ipairs(line.variation) do table.insert(notes, {note = note, step = note.step}) end
		end
		local degree = ctx.chord.degree
		local octave = (line.octave or 0) + (ctx.channel.spec.octave or 0)
		for _, each in ipairs(notes) do
			local note, step = each.note, each.step
			local keep = plays(note, ctx) or (step == 0 and note.chance == 0)
			if ctx.halftime then keep = step % 4 == 0 and (step == 0 or note.chance < ctx.energy * 0.6) end
			if keep then
				local length = ctx.halftime and math.max(note.length, 4) or note.length
				ctx.note({step = step, length = math.min(length, 16.5 - step), gap = 0.15, glide = note.glide,
					accent = note.accent, rate = note.rate and note.rate * (0.5 + ctx.energy) or nil,
					notes = {ctx.kit.pitch(ctx.mode, ctx.tonic, degree, note.offset, ctx.kit.register.bass, note.bend)
						+ 12 * octave}})
			end
		end
	end},
	{id = "bass.hold", part = "bass", render = function(_, ctx)
		ctx.note({step = 0, length = 16, gap = 0.15, notes = {ctx.chord.root + 12 * (ctx.channel.spec.octave or 0)}})
	end},
	{id = "bass.blend", part = "bass", render = function(bar, ctx)
		local chord = blend(bar, ctx)
		local patch = ctx.previous.byRole.bass.patch
		ctx.note({step = 0, length = 16, gap = 0.15, notes = {chord.root}, patch = patch})
	end},

	-- Chords: held, comped on the track's rhythm, or struck.
	{id = "pad.chords", part = "pad", render = function(bar, ctx) chords(bar, ctx, ctx.chord) end},
	{id = "pad.blend", part = "pad", render = function(bar, ctx)
		chords(bar, ctx, blend(bar, ctx), ctx.previous.byRole.pad.patch)
	end},
	{id = "keys.comp", part = "keys", render = function(_, ctx)
		for index, hit in ipairs(ctx.cycle.comp) do
			if hit.threshold <= ctx.complexity * 0.7 + 0.2 then
				ctx.note({step = hit.step, length = hit.length, notes = ctx.chord.notes, gain = index == 1 and 1 or 0.75})
			end
		end
	end},
	{id = "stab.hits", part = "stab", render = function(_, ctx)
		if ctx.energy <= 0.25 or ctx.halftime then return end
		local last = ctx.cycle.stabs[#ctx.cycle.stabs]
		for _, hit in ipairs(ctx.cycle.stabs) do
			if hit.threshold <= ctx.complexity * 0.8 + 0.2 then
				ctx.note({step = hit.step, length = hit.length or 1, notes = ctx.chord.notes,
					throw = ctx.throw and hit == last or nil})
			end
		end
	end},

	-- Melody: the arpeggio, the hook, the hook held back, and its answer.
	{id = "arp.run", part = "arp", render = function(_, ctx)
		local arp, chord = ctx.cycle.arp, ctx.chord
		local order, rate = arp.order, arp.rate
		if not arp.always and ctx.section == "drop" and ctx.energy <= 0.3 then return end
		local i = 0
		for step = 0, 15, rate do
			if arp.mask[step] <= ctx.complexity * 0.9 + 0.1 or arp.always then
				local index = order[(ctx.n * 16 // rate + i) % #order + 1]
				ctx.note({step = step, length = rate * arp.gate, gap = 0,
					notes = {chord.notes[(index - 1) % #chord.notes + 1] + 12 * (arp.octave + (index - 1) // #chord.notes)},
					gain = step % 4 == 0 and 1 or 0.7})
			end
			i = i + 1
		end
	end},
	{id = "lead.hook", part = "lead", bars = 4, render = melody("hook", 1, REGISTER.lead)},
	{id = "lead.soft", part = "lead", bars = 4, render = melody("hook", 0.6, REGISTER.lead)},
	{id = "counter.answer", part = "counter", bars = 4, render = melody("answer", 0.8, REGISTER.counter)},

	-- A drone under the track: the key's root and fifth, held four bars.
	{id = "texture.drone", part = "texture", render = function(_, ctx)
		local every = 4
		if ctx.n % every == 0 or ctx.barInBlock == 0 then
			local bars = math.min(every - ctx.n % every, ctx.block.length - (ctx.pos - ctx.block.start))
			local root = ctx.kit.fold(ctx.tonic, 48)
			ctx.note({step = 0, length = bars * StyleKit.stepsPerBar, gap = 0, notes = {root, root + 7}})
		end
	end},

	-- Effects: the riser through a build, and the impact a section lands
	-- on, a crash over a downlifter.
	{id = "fx.riser", part = "fx", render = riser(0, 1)},
	{id = "fx.impact", part = "fx", render = function(bar, ctx)
		ctx.hit(0, "crash", 0.8)
		if ctx.sectionBar == 0 and ctx.channel.patch then riser(1, 0)(bar, ctx) end
	end},
}

return StyleKit
