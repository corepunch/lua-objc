-- The host API every style plugin receives (read-only): seeded randomness,
-- music theory, the DJ set that sequences tracks and gives each its tempo,
-- kit, eight channels, length, energy curve and palette of blocks, and the
-- bar score the Synth plays. Styles are data on top of it: flavours and the
-- blocks they play (host/Blocks.lua); the sound belongs to the patches and
-- the Synth. How a track is arranged is host/Canvas.lua.
local Model = require("apps.dnb.Model")
local Drums = require("apps.dnb.models.Drums")
local Canvas = require("apps.dnb.host.Canvas")

local StyleKit = {}

StyleKit.stepsPerBar = 16
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

-- What a flavour leaves out: a tempo and a swing of no range.
local DEFAULT_FEEL = {tempo = {120, 120}, swing = {0, 0}}

local Set = {}
Set.__index = Set

local function merged(base, over)
	local result = {}
	for k, v in pairs(base or {}) do result[k] = v end
	for k, v in pairs(over or {}) do result[k] = v end
	return result
end

-- Checks a flavour's channels against the roles and the blocks: at most
-- eight, one to a role, each playing a patch that exists and blocks that
-- suit it.
local function checkFlavour(flavour, roles, library, catalogue, genre)
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
		for _, id in ipairs(spec.fills or {}) do
			if id:sub(1, 1) ~= "@" then library:get("fills", id) end
		end
		if Model.family[role] == "drums" or role ~= "fx" or spec.patches then
			if role ~= "drums" and role ~= "tops" and role ~= "fx" then
				assert(#(spec.patches or {}) > 0, where .. " " .. role .. " channel needs patches")
			end
		end
		if role ~= "fx" then
			local avoid = {}
			for _, tag in ipairs(spec.avoid or {}) do avoid[tag] = true end
			assert(#catalogue:candidates(role, genre, flavour.id, avoid) > 0,
				where .. " has no " .. role .. " blocks to play")
		end
		for _, field in ipairs({"wants", "avoid"}) do
			for _, tag in ipairs(spec[field] or {}) do
				assert(type(tag) == "string", where .. " " .. role .. " " .. field .. " are tags")
			end
		end
	end
	assert(seen.drums, where .. " needs a drums channel")
end

--- An endless DJ set: a sequence of tracks, each with a flavour, a mode, a
--- key harmonically mixed from the previous track, a tempo and a swing of
--- its own, a drum kit, its eight channels and their patches, a length and
--- an energy curve, and the palette of blocks it plays. `spec.flavours`
--- are the style's (see plugins/styles); `spec.roles` what a channel of
--- each role falls back on; `spec.library` its patches and fills;
--- `spec.catalogue` its blocks and `spec.genre` their id prefix; `spec.modes`
--- mode names; `spec.arc` overrides Canvas.defaults; `spec.modulations` are
--- the key lifts a track may take; `spec.salt` is an integer that tells
--- this style's tracks from another's under the same seed.
function StyleKit.newSet(seed, spec)
	local arc = Canvas.arc(spec.arc)
	local library = assert(spec.library, "a set needs a library")
	local catalogue = assert(spec.catalogue, "a set needs a catalogue of blocks")
	local roles = spec.roles or {}
	for role in pairs(roles) do assert(Model.family[role], "unknown role " .. tostring(role)) end
	for _, flavour in ipairs(assert(spec.flavours, "a set needs flavours")) do
		checkFlavour(flavour, roles, library, catalogue, spec.genre)
		Canvas.arc(spec.arc, flavour.arc)
	end
	local modes = {}
	for _, name in ipairs(spec.modes or {"minor"}) do table.insert(modes, (assert(StyleKit.modes[name], "unknown mode " .. tostring(name)))) end
	return setmetatable({seed = seed, flavours = spec.flavours, modes = modes, roles = roles, library = library,
		catalogue = catalogue, genre = spec.genre, arc = spec.arc, salt = spec.salt or 0,
		modulations = spec.modulations or {2, 5, -2, 3}, tracks = {}, hint = 0}, Set)
end
StyleKit.Set = Set

-- One of `ids`, other than `avoid` where there is a choice.
-- A track's channels, drawn from its flavour: a channel the flavour gives
-- a `chance` may sit the track out, and each takes a patch the track
-- before it did not play.
local function channelsOf(set, rng, flavour, previous)
	local channels, byRole = {}, {}
	for _, entry in ipairs(flavour.channels) do
		local spec = merged(set.roles[entry.role], entry)
		local plays = spec.chance == nil or rng.chance(spec.chance)
		local before = previous and previous.byRole[spec.role]
		local channel = {role = spec.role, spec = spec, name = Model.roles[Model.roleIndex[spec.role]].title}
		if spec.patches then
			local avoid = before and before.patch and before.patch.id
			local ids = spec.patches
			if #ids > 1 and avoid then
				local rest = {}
				for _, id in ipairs(ids) do if id ~= avoid then table.insert(rest, id) end end
				ids = rest
			end
			channel.patch = set.library:get("patches", rng.pick(ids))
			channel.name = channel.patch.name
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
			local arc = Canvas.arc(self.arc, flavour.arc)
			local track = {
				index = index, flavour = flavour, mode = rng.pick(self.modes), arc = arc,
				tonic = previous and (previous.tonic + rng.pick(MIXES)) % 12 or rng.int(12) - 1,
				start = previous and previous.start + previous.length or 0,
			}
			track.key = StyleKit.keyName(track.tonic, track.mode)
			track.phraseBars, track.blendBars = arc.phrase, arc.blend
			-- What its arrangement and its material draw from.
			track.seed = hash(self.seed, 6, index, self.salt)
			-- Their own streams, so the kit and the channels never shift
			-- the composition.
			track.drums = StyleKit.drumDesign(StyleKit.random(self.seed, 5, index), flavour)
			local feel = StyleKit.random(self.seed, 8, index, self.salt)
			track.tempo = math.floor(feel.between(flavour.tempo or DEFAULT_FEEL.tempo) + 0.5)
			track.swing = feel.between(flavour.swing or DEFAULT_FEEL.swing)
			track.length, track.phrases, track.lift = Canvas.layout(arc, track.tempo, self.modulations,
				StyleKit.random(self.seed, 7, index, self.salt))
			track.channels, track.byRole = channelsOf(self, StyleKit.random(self.seed, 9, index, self.salt), flavour,
				previous)
			track.palette = Canvas.palette(track, self.catalogue, self.genre,
				StyleKit.random(self.seed, 10, index, self.salt), previous and previous.palette)
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
		index = n, arc = info.arc, label = info.label, phrase = info.phrase, phraseBar = info.phraseBar,
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

return StyleKit
