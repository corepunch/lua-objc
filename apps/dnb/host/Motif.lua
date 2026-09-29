-- What the generator writes itself, beside the authored library: a track's
-- rhythm cell, its motif and the hook developed from it, bass lines, comping
-- and arpeggios. A tune is remembered by one idea heard many times, so a
-- track has one rhythm cell and one motif, and everything melodic is made
-- from them: the hook repeats, answers and resolves the motif, the bass and
-- the chords lean on the cell's accents, the arpeggio follows the motif's
-- contour. Nothing here is random per bar: a track's material is written
-- once, from its seed.
--
-- Notes are the library's: {step, bar, offset, bend, length, glide, accent,
-- chance, detail, rate}, `offset` in scale steps above the chord's root (or
-- the key's, for a hook that follows the key).
local Motif = {}

local STEPS = 16

-- One-bar rhythm cells, the syncopations dance music is written in: the
-- tresillo and its rotations, dotted-eighth runs, off-beat pushes, and
-- call-and-gap cells that leave half a bar to breathe.
Motif.cells = {
	"x..x..x.........", "x..x..x...x.....", "x..x..x...x.x...", "x..x..x..x..x...",
	"x.....x...x.....", "x...x..x..x.....", "x.x..x....x.....", "..x...x...x...x.",
	"x..x....x..x....", "x.x...x.x.......", "x......x..x..x..", "x...x.....x.x...",
	"..x..x..x.......", "x..x.x..x.......", "x.x.x..x..x.....", "x....x..x.x.....",
	"x..x..x.x..x..x.", "x...x...x.x.x...", "..x.x...x.x.....", "x.xx..x...x.....",
}

-- Contours, as the pitch (0…1 of the motif's range) of each note from the
-- first to the last.
local CONTOURS = {
	arch = function(t) return 1 - math.abs(2 * t - 1) end,
	descent = function(t) return 1 - t end,
	ascent = function(t) return t end,
	valley = function(t) return math.abs(2 * t - 1) end,
	wave = function(t) return 0.5 + 0.5 * math.sin(t * 2 * math.pi) end,
	plateau = function(t) return t < 0.3 and t / 0.3 or 1 end,
}
local CONTOUR_NAMES = {"arch", "descent", "ascent", "valley", "wave", "plateau"}

-- The ways a four-bar hook is made of a one-bar motif: each bar names what
-- it plays. "a" is the motif, "a'" the motif with a new last note, "s" the
-- motif a step or two away (a sequence), "i" its mirror image, "h" its
-- first half left to ring, "b" an answer in the motif's rhythm, "e" the
-- ending: half the motif, then a long note home.
Motif.forms = {
	{"a", "a'", "a", "e"}, {"a", "s", "a", "e"}, {"a", "b", "a", "e"}, {"a", "a", "s", "e"},
	{"a", "h", "a'", "e"}, {"a", "i", "a", "e"}, {"a", "b", "a'", "b"}, {"a", "a'", "s", "h"},
}

local RANGE = {low = -2, high = 9}
-- Chord tones, as scale steps above the root folded into one octave.
local CHORD_TONE = {[0] = true, [2] = true, [4] = true}

local function copy(note, changes)
	local result = {}
	for k, v in pairs(note) do result[k] = v end
	for k, v in pairs(changes or {}) do result[k] = v end
	return result
end

local function clamp(offset)
	return math.max(RANGE.low, math.min(RANGE.high, offset))
end

-- The chord tone nearest `offset`, preferring the one below on a tie.
local function chordTone(offset)
	for distance = 0, 3 do
		if CHORD_TONE[(offset - distance) % 7] then return offset - distance end
		if CHORD_TONE[(offset + distance) % 7] then return offset + distance end
	end
	return offset
end
Motif.chordTone = chordTone

local function onsets(text)
	local steps = {}
	local at = 0
	for c in text:gmatch("[^%s|]") do
		if c ~= "." and c ~= "-" then table.insert(steps, at) end
		at = at + 1
	end
	return steps
end

--- A track's rhythm cell: {text, steps}, drawn from `cells` (or the
--- shared ones).
function Motif.cell(rng, cells)
	local text = rng.pick(cells or Motif.cells)
	return {text = text, steps = onsets(text)}
end

--- A one-bar motif on a rhythm cell: a contour over a few scale steps,
--- strong beats on chord tones, the rest moving by step where they can.
--- `options.span` is how many scale steps it ranges over (4…7 by
--- default), `options.base` where it starts from, `options.legato` the
--- share of notes held until the next.
function Motif.write(rng, cell, options)
	options = options or {}
	local steps = cell.steps
	local contour = CONTOURS[rng.pick(CONTOUR_NAMES)]
	local span = options.span or (3 + rng.int(4))
	local base = options.base or rng.pick({0, 0, 2, 4})
	local legato = options.legato or 0.5
	local notes = {}
	local previous
	for i, step in ipairs(steps) do
		local t = #steps > 1 and (i - 1) / (#steps - 1) or 0
		local offset = base + math.floor(contour(t) * span + 0.5)
		if step % 4 == 0 or i == 1 then
			offset = chordTone(offset)
		elseif previous and math.abs(offset - previous) > 2 and rng.chance(0.6) then
			-- A leap is taken on a strong beat; elsewhere the line steps.
			offset = previous + (offset > previous and 1 or -1)
		end
		offset = clamp(offset)
		local untilNext = (steps[i + 1] or STEPS) - step
		local length = rng.chance(legato) and math.min(untilNext, 4) or math.min(untilNext, rng.int(2))
		table.insert(notes, {step = step, bar = 0, offset = offset, bend = 0, length = length,
			glide = previous ~= nil and step % 4 ~= 0 and math.abs(offset - previous) == 1 and rng.chance(0.4) or nil,
			chance = 0, detail = (step % 2 == 1 and i > 1) and 0.5 or 0})
		previous = offset
	end
	return notes
end

local function shifted(notes, by)
	local result = {}
	for _, note in ipairs(notes) do table.insert(result, copy(note, {offset = clamp(note.offset + by)})) end
	return result
end

local function mirrored(notes)
	local axis = notes[1].offset
	local result = {}
	for _, note in ipairs(notes) do table.insert(result, copy(note, {offset = clamp(2 * axis - note.offset)})) end
	return result
end

-- The motif with a new last note: up or down a third, held a little longer.
local function retailed(notes, rng)
	local result = shifted(notes, 0)
	local last = result[#result]
	last.offset = clamp(chordTone(last.offset + rng.pick({-2, 2, 3, -3})))
	last.length = math.min(STEPS - last.step, math.max(last.length, 3))
	return result
end

-- The first notes of the motif, the last of them left to ring.
local function halved(notes)
	local result = {}
	for _, note in ipairs(notes) do
		if note.step < 8 then table.insert(result, copy(note)) end
	end
	if #result == 0 then result = {copy(notes[1])} end
	local last = result[#result]
	last.length = math.min(STEPS - last.step, 8)
	last.glide = nil
	return result
end

-- The motif's rhythm with a contour of its own, ending where it began.
local function answered(notes, rng)
	local result = {}
	local offset = notes[#notes].offset
	for i, note in ipairs(notes) do
		if i == #notes then
			offset = chordTone(notes[1].offset)
		elseif note.step % 4 == 0 then
			offset = chordTone(offset + rng.pick({-2, 0, 2}))
		else
			offset = offset + rng.pick({-1, -1, 1})
		end
		offset = clamp(offset)
		table.insert(result, copy(note, {offset = offset}))
	end
	return result
end

-- Half the motif, then a long note home.
local function ended(notes)
	local result = {}
	for _, note in ipairs(notes) do
		if note.step < 8 then
			table.insert(result, copy(note, {length = math.min(note.length, 8 - note.step)}))
		end
	end
	table.insert(result, {step = 8, bar = 0, offset = 0, bend = 0, length = 8, glide = true, chance = 0, detail = 0})
	return result
end

--- A hook of `#form` bars developed from a one-bar motif: {bars, notes}
--- with `motif` and `form` kept for whoever varies it later.
function Motif.develop(rng, motif, form)
	form = form or rng.pick(Motif.forms)
	local turn = rng.pick({-2, -1, 1, 2})
	local notes = {}
	for bar, kind in ipairs(form) do
		local played
		if kind == "a" then played = shifted(motif, 0)
		elseif kind == "a'" then played = retailed(motif, rng)
		elseif kind == "s" then played = shifted(motif, turn)
		elseif kind == "i" then played = mirrored(motif)
		elseif kind == "h" then played = halved(motif)
		elseif kind == "b" then played = answered(motif, rng)
		elseif kind == "e" then played = ended(motif)
		else error("unknown hook form " .. tostring(kind)) end
		for _, note in ipairs(played) do
			note.bar = bar - 1
			note.step = (bar - 1) * STEPS + note.step % STEPS
			table.insert(notes, note)
		end
	end
	return {bars = #form, notes = notes, motif = motif, form = form, follow = "chord"}
end

--- The ways a later drop plays the hook: as it was, an octave up, mirrored,
--- a third away, or with the rests between its notes filled in.
Motif.variations = {"same", "octave", "third", "mirror", "busy"}

--- `hook` varied for a later cycle. The rhythm stays: it is the same tune.
function Motif.vary(rng, hook, kind)
	kind = kind or rng.pick(Motif.variations)
	local notes = {}
	if kind == "octave" then
		for _, note in ipairs(hook.notes) do table.insert(notes, copy(note, {offset = note.offset + 7})) end
	elseif kind == "third" then
		for _, note in ipairs(hook.notes) do table.insert(notes, copy(note, {offset = note.offset + 2})) end
	elseif kind == "mirror" then
		local axis = hook.notes[1].offset
		for _, note in ipairs(hook.notes) do
			table.insert(notes, copy(note, {offset = clamp(chordTone(2 * axis - note.offset))}))
		end
	elseif kind == "busy" then
		-- A passing note into every leap, while Complexity is up.
		for i, note in ipairs(hook.notes) do
			table.insert(notes, copy(note))
			local after = hook.notes[i + 1]
			local gap = after and after.step - (note.step + note.length) or 0
			if after and after.bar == note.bar and gap >= 1 and math.abs(after.offset - note.offset) >= 2 then
				table.insert(notes, {step = after.step - 1, bar = note.bar, bend = 0, length = 1, chance = 0, detail = 0.5,
					offset = after.offset + (after.offset > note.offset and -1 or 1)})
			end
		end
	else
		for _, note in ipairs(hook.notes) do table.insert(notes, copy(note)) end
	end
	return {bars = hook.bars, notes = notes, motif = hook.motif, form = hook.form, follow = hook.follow, id = hook.id,
		name = hook.name, variation = kind}
end

--- The answer a second voice gives the hook: it plays in the bars the hook
--- ends (every other one), the hook's phrase an octave up and thinned, and
--- rests while the hook speaks.
function Motif.answer(rng, hook)
	local notes = {}
	for _, note in ipairs(hook.notes) do
		if note.bar % 2 == 1 and note.detail == 0 then
			table.insert(notes, copy(note, {offset = note.offset + rng.pick({7, 7, 4}), glide = nil,
				step = note.step, length = math.min(note.length, 2)}))
		end
	end
	if #notes == 0 then
		table.insert(notes, {step = STEPS + 8, bar = 1, offset = 7, bend = 0, length = 4, chance = 0, detail = 0})
	end
	return {bars = hook.bars, notes = notes, follow = hook.follow}
end

-- Bass ------------------------------------------------------------------------

-- Where a bass answers its root: scale steps, the root and the octave most.
local BASS_STEPS = {0, 0, 0, 7, 4, 6, 2, 3, 7, 4}
-- The 303's notes: the root and octave, the fifth, and a semitone either
-- side of the root for the squelch.
local ACID_STEPS = {{0, 0}, {0, 0}, {0, 0}, {7, 0}, {7, 0}, {4, 0}, {2, 0}, {6, 0}, {6, -12}, {3, 0}, {1, -1}}

local function bass(step, offset, length, fields)
	local note = {step = step, bar = step // STEPS, offset = offset, bend = 0, length = length, chance = 0, detail = 0}
	for k, v in pairs(fields or {}) do note[k] = v end
	return note
end

--- The writers of bass lines, by name ("@roll" in a channel's `lines`).
--- Each takes (rng, cell, channel) and returns a line {bars, notes,
--- variation, octave}: `variation` is the busier bar a line plays every
--- fourth bar, `octave` how far above the sub register it sits.
Motif.lines = {}

-- Drum & bass: a long root on each bar's downbeat, then short syncopated
-- answers whose count grows with energy.
function Motif.lines.roll(rng)
	local function write(first, last, busy)
		local notes = {}
		local step = first
		while step < last do
			local downbeat = step % STEPS == 0
			local length = downbeat and (4 + rng.int(3) - 1) or (busy and rng.int(2) or 1 + rng.int(3))
			length = math.min(length, last - step, STEPS - step % STEPS)
			table.insert(notes, bass(step, downbeat and 0 or rng.pick(BASS_STEPS), length, {
				glide = not downbeat and rng.chance(0.35) or nil,
				chance = downbeat and 0 or rng.float(), detail = length > 1 and 0 or rng.float()}))
			step = step + length + (rng.chance(0.4) and 1 or 0)
		end
		return notes
	end
	local notes = write(0, 2 * STEPS)
	return {bars = 2, notes = notes, variation = write(0, STEPS, true)}
end

-- The 303: sixteen steps, each of which may sound, slide into the next or
-- accent, an octave above the sub.
function Motif.lines.acid(rng)
	local notes = {}
	for step = 0, STEPS - 1 do
		if step == 0 or rng.chance(0.62) then
			local pick = step == 0 and ACID_STEPS[1] or rng.pick(ACID_STEPS)
			table.insert(notes, bass(step, pick[1], 1, {bend = pick[2] == -1 and -1 or 0,
				drop = pick[2] == -12 or nil, slide = rng.chance(0.25),
				accent = (step % 4 == 0 and rng.chance(0.6) or rng.chance(0.2)) or nil,
				chance = step % 4 == 0 and 0 or rng.float() * 0.9}))
		end
	end
	-- A slide holds its note into the next one, which then glides.
	for i, note in ipairs(notes) do
		local after = notes[i + 1]
		if note.slide then
			note.length = (after and after.step or STEPS) - note.step + 0.5
			if after then after.glide = true end
		end
		if note.drop then note.offset = note.offset - 7 end
		note.slide, note.drop = nil, nil
	end
	return {bars = 1, notes = notes, octave = 1}
end

-- Techno's rumble, rolling on the two 16ths after each kick.
function Motif.lines.rumble()
	local notes = {}
	for beat = 0, 3 do
		table.insert(notes, bass(beat * 4 + 2, 0, 1))
		table.insert(notes, bass(beat * 4 + 3, 0, 1, {chance = 0.5}))
	end
	return {bars = 1, notes = notes}
end

-- Trance's off-beat bass, an octave up.
function Motif.lines.offbeat()
	local notes = {}
	for step = 2, 14, 4 do table.insert(notes, bass(step, 0, 1.6)) end
	return {bars = 1, notes = notes, octave = 1}
end

-- Psytrance's gallop: every 16th but the kick's.
function Motif.lines.gallop()
	local notes = {}
	for step = 0, STEPS - 1 do
		if step % 4 ~= 0 then
			table.insert(notes, bass(step, 0, 0.8, {accent = step % 4 == 2 or nil, chance = step % 4 == 2 and 0 or 0.3}))
		end
	end
	return {bars = 1, notes = notes, octave = 1}
end

-- The track's own rhythm in the bass: the root on the cell's accents, an
-- octave or a fifth where it answers.
function Motif.lines.cell(rng, cell)
	local notes = {}
	for i, step in ipairs(cell.steps) do
		local after = cell.steps[i + 1] or STEPS
		local offset = (i == 1 or step % 4 == 0) and 0 or rng.pick(BASS_STEPS)
		table.insert(notes, bass(step, offset, math.min(after - step, 1 + rng.int(3)),
			{chance = i == 1 and 0 or (step % 4 == 0 and 0.2 or rng.float()), glide = offset ~= 0 and rng.chance(0.3) or nil}))
	end
	if notes[1].step ~= 0 then table.insert(notes, 1, bass(0, 0, math.min(notes[1].step, 3))) end
	return {bars = 1, notes = notes}
end

-- Dubstep: long notes, each wobbling at a rate of its own.
function Motif.lines.wobble(rng, _, channel)
	local phrases = {
		{{0, 6, 0}, {6, 2, 0}, {8, 4, 7}, {12, 4, 2}},
		{{0, 4, 0}, {4, 4, 0}, {8, 8, 4}},
		{{0, 3, 0}, {3, 3, 0}, {6, 2, 7}, {10, 6, 0}},
		{{0, 8, 0}, {8, 2, 3}, {10, 2, 2}, {12, 4, 0}},
		{{0, 2, 0}, {2, 2, 0}, {6, 2, 0}, {8, 4, 1}, {12, 4, 0}},
	}
	local rates = channel and channel.rates or {1, 2, 3, 4}
	local notes = {}
	for bar = 0, 3 do
		for _, note in ipairs(rng.pick(phrases)) do
			table.insert(notes, bass(bar * STEPS + note[1], note[3], note[2], {rate = rng.pick(rates),
				bend = note[3] == 1 and -1 or 0, chance = note[1] == 0 and 0 or 0.3}))
		end
	end
	return {bars = 4, notes = notes}
end

--- An authored line with some of its answers moved: the rhythm and the
--- roots stay, so it is the same line, played by another hand.
function Motif.repitch(rng, line)
	local notes = {}
	for _, note in ipairs(line.notes) do
		local moved = note.offset ~= 0 and note.bend == 0 and rng.chance(0.4)
		table.insert(notes, copy(note, moved and {offset = rng.pick({7, 4, 6, 2, 3})} or nil))
	end
	return {id = line.id, name = line.name, bars = line.bars, notes = notes, octave = line.octave,
		variation = line.variation, follow = line.follow}
end

-- Chords and arpeggios --------------------------------------------------------

--- Where the chords are struck through a bar: the cell's accents, the
--- first always and the rest as Complexity allows. {step, length,
--- threshold}.
function Motif.comp(rng, cell, options)
	options = options or {}
	local comp = {}
	for i, step in ipairs(cell.steps) do
		local after = cell.steps[i + 1] or STEPS
		table.insert(comp, {step = step, length = math.min(after - step, options.length or (1 + rng.int(3))),
			threshold = i == 1 and 0 or rng.float() * 0.8})
	end
	return comp
end

--- The cell's complement: where it rests, for a part that answers it.
function Motif.offbeats(cell, every)
	local taken, steps = {}, {}
	for _, step in ipairs(cell.steps) do taken[step] = true end
	for step = 0, STEPS - 1, every or 2 do
		if not taken[step] then table.insert(steps, step) end
	end
	return steps
end

-- Arpeggio orders over the four chord tones (5–8 are an octave up).
Motif.arpOrders = {
	{1, 2, 3, 4}, {4, 3, 2, 1}, {1, 2, 3, 4, 3, 2}, {1, 3, 2, 4},
	{1, 2, 3, 4, 5, 6, 7, 8}, {1, 4, 2, 5, 3, 6}, {1, 1, 3, 2, 4, 3},
	{1, 2, 3, 4, 5, 4, 3, 2}, {1, 3, 2, 4, 3, 5, 4, 6}, {1, 2, 3, 5, 1, 2, 4, 5}, {1, 4, 3, 5, 2, 4, 3, 6},
}

--- An arpeggio: the order it takes the chord's notes in, how many 16ths
--- a note lasts and which steps sound as Complexity rises. `spec` (a
--- channel's `arp`) may fix `rates`, `orders`, `gate` and `octave`; with
--- `contour` the order follows the track's motif instead.
function Motif.arp(rng, spec, motif)
	spec = spec or {}
	local order = rng.pick(spec.orders or Motif.arpOrders)
	if spec.contour ~= false and motif and #motif >= 3 and rng.chance(0.5) then
		-- The motif's contour, as chord tones: its lowest note is the
		-- chord's first.
		local low = math.huge
		for _, note in ipairs(motif) do low = math.min(low, note.offset) end
		order = {}
		for _, note in ipairs(motif) do table.insert(order, math.min(8, (note.offset - low) // 2 + 1)) end
	end
	local rate = rng.pick(spec.rates or {1, 1, 2})
	local mask = {}
	for step = 0, STEPS - 1 do
		-- Downbeats always sound; the rest open up with complexity.
		mask[step] = step % 4 == 0 and 0 or rng.float()
	end
	return {order = order, rate = rate, mask = mask, gate = spec.gate or 0.8, octave = spec.octave or 1,
		always = spec.always == true}
end

return Motif
