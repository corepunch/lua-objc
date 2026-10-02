-- What renders a block into a bar. A pattern is {id, part, bars, render}:
-- `render(bar, ctx)` adds one bar of its role's channel to the Bar, where
-- `ctx` is the bar's place and the track's material (host/Composer.lua).
-- Every block of the library becomes a pattern (`Patterns.of`); the few
-- that belong to no block, the fill, the roll and the blend into a new
-- track, are `Patterns.system`. The drums render first and leave
-- `ctx.fill` for the parts that make room for one.
local Patterns = {}

local STEPS = 16
local REGISTER = {bass = 28, lead = 64, counter = 69}

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
	local phase = (options.phase or ctx.barInBlock) % beat.bars
	local step = options.from or 0
	local stop = options.to or STEPS
	while step < stop do
		local change = edits[step]
		local advance = 1
		if change == nil then
			ctx.slice({step = step, beat = beat, slice = phase * STEPS + step,
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

-- The track's chops for this bar of a phrase, as edits of `beat`: a
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

-- The edits a fill makes of the groove itself, the tracker's effects: a
-- stuttered snare, the last beat backwards, a drop-out and a flam, a
-- retrigger in 32nds, or the tape slowing to half speed.
local function fillEdits(kind, beat, phase)
	local edits = {}
	local base = phase * STEPS
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
Patterns.fills = {"stutter", "reverse", "cut", "retrig", "tape"}

-- Notes of a line that fall in this bar of it, with their steps in it.
local function inBar(line, bar)
	local notes = {}
	local first = (bar % line.bars) * STEPS
	for _, note in ipairs(line.notes) do
		if note.step >= first and note.step < first + STEPS then
			table.insert(notes, {note = note, step = note.step - first})
		end
	end
	return notes
end

local function plays(note, ctx)
	return note.chance <= ctx.energy * 0.9 + 0.1 and note.detail <= ctx.complexity
end

-- The chord held for as many bars as it lasts; a block that starts inside a
-- chord sounds what is left of it.
local function chords(ctx, chord, patch)
	local into = ctx.chordBar
	if into == 0 or ctx.barInBlock == 0 then
		local bars = math.min(ctx.barsPerChord - into, ctx.block.length - (ctx.pos - ctx.block.start))
		ctx.note({step = 0, length = bars * STEPS, gap = 0, notes = chord.notes, patch = patch})
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
		ctx.note({step = 0, length = STEPS, gap = 0, notes = {60}, from = a, to = b})
		ctx.bar.riser = {from = a, to = b}
	end
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

-- The voice a channel rolls into a phrase on: the style's, or the snare.
local function rollVoice(ctx) return ctx.channel.spec.roll or "snare" end

--- Patterns that belong to no block: the one-bar fill that ends a phrase
--- (a fill beat of the library, or an edit of the groove it interrupts,
--- named in the block's `under`), the roll that winds up before a rise,
--- and the outgoing track's bass and chord under a blend.
Patterns.system = {
	{id = "drums.fill", part = "drums", render = function(_, ctx)
		local beat = ctx.groove
		local fills = ctx.material.fills
		local fill = fills[ctx.phrase % #fills + 1]
		ctx.fill = fill.id
		if fill.beat then
			-- The groove up to the fill, then the fill's own loop.
			local from = fill.beat.from or EDIT.from
			playLoop(ctx, beat, {variant = "full", gain = ctx.channel.spec.gain, to = from, phase = ctx.grooveBar})
			playLoop(ctx, fill.beat, {variant = "full", gain = ctx.channel.spec.gain, from = from, phase = 0})
		else
			playLoop(ctx, beat, {variant = "full", gain = ctx.channel.spec.gain, phase = ctx.grooveBar,
				edits = fillEdits(fill.edit, beat, ctx.grooveBar % beat.bars)})
		end
	end},
	{id = "drums.roll", part = "drums", render = roll(rollVoice)},
	{id = "bass.blend", part = "bass", render = function(bar, ctx)
		local chord = blend(bar, ctx)
		local patch = ctx.previous.byRole.bass.patch
		ctx.note({step = 0, length = 16, gap = 0.15, notes = {chord.root}, patch = patch})
	end},
	{id = "pad.blend", part = "pad", render = function(bar, ctx)
		chords(ctx, blend(bar, ctx), ctx.previous.byRole.pad.patch)
	end},
}

-- Renderers by what a block holds ------------------------------------------------

local function drums(block)
	return function(_, ctx)
		local chops = ctx.channel.spec.chops and ctx.material.chops or nil
		playLoop(ctx, block.beat, {variant = ctx.block.variant or "full", gain = ctx.channel.spec.gain,
			throw = ctx.throw, edits = chopEdits(ctx, block.beat, chops)})
	end
end

local function bass(block)
	local line = block.line
	return function(_, ctx)
		local degree = line.follow == "key" and 1 or ctx.chord.degree
		local octave = (line.octave or 0) + (ctx.channel.spec.octave or 0)
		for _, each in ipairs(inBar(line, ctx.barInBlock)) do
			local note, step = each.note, each.step
			if plays(note, ctx) then
				ctx.note({step = step, length = math.min(note.length, 16.5 - step), gap = 0.15, glide = note.glide,
					accent = note.accent, rate = note.rate and note.rate * (0.5 + ctx.energy) or nil,
					notes = {ctx.kit.pitch(ctx.mode, ctx.tonic, degree, note.offset, REGISTER.bass, note.bend)
						+ 12 * octave}})
			end
		end
	end
end

local function melody(block, gain, register)
	local line = block.line
	return function(_, ctx)
		local played = inBar(line, ctx.barInBlock)
		local degree = line.follow == "key" and 1 or ctx.chord.degree
		local octave = (line.octave or 0) + (ctx.channel.spec.octave or 0)
		for index, each in ipairs(played) do
			local note = each.note
			if plays(note, ctx) then
				ctx.note({step = each.step, length = math.min(note.length, 16 - each.step), glide = note.glide,
					gain = gain, throw = (ctx.throw and index == #played) or nil,
					notes = {ctx.kit.pitch(ctx.mode, ctx.tonic, degree, note.offset, register, note.bend) + 12 * octave}})
			end
		end
	end
end

local function chordal(block, gain)
	if block.hold then
		return function(_, ctx) chords(ctx, ctx.chord) end
	end
	return function(_, ctx)
		local bar = ctx.barInBlock % block.compBars
		local last
		for _, hit in ipairs(block.comp) do
			if hit.bar == bar then last = hit end
		end
		for _, hit in ipairs(block.comp) do
			if hit.bar == bar and hit.chance <= ctx.energy * 0.9 + 0.1 and hit.detail <= ctx.complexity then
				ctx.note({step = hit.step, length = hit.length, notes = ctx.chord.notes,
					gain = (hit.accent and 1 or 0.75) * gain, throw = ctx.throw and hit == last or nil})
			end
		end
	end
end

local function arp(block)
	local spec = block.arp
	return function(_, ctx)
		local chord = ctx.chord
		local order, rate = spec.order, spec.rate
		local i = 0
		for step = 0, 15, rate do
			local mark = spec.mask[step]
			if mark == "X" or (mark == "x" and ctx.complexity >= 0.35) then
				local index = order[(ctx.pos * 16 // rate + i) % #order + 1]
				ctx.note({step = step, length = rate * spec.gate, gap = 0,
					notes = {chord.notes[(index - 1) % #chord.notes + 1] + 12 * (spec.octave + (index - 1) // #chord.notes)},
					gain = step % 4 == 0 and 1 or 0.7})
			end
			i = i + 1
		end
	end
end

-- A drone under the track: the key's root and what the block stacks on it,
-- held for `every` bars.
local function texture(block)
	return function(_, ctx)
		local every = block.every
		if ctx.pos % every == 0 or ctx.barInBlock == 0 then
			local bars = math.min(every - ctx.pos % every, ctx.block.length - (ctx.pos - ctx.block.start))
			local root = ctx.kit.fold(ctx.tonic, 48)
			local notes = {}
			for _, voice in ipairs(block.voices) do table.insert(notes, root + voice) end
			ctx.note({step = 0, length = bars * STEPS, gap = 0, notes = notes})
		end
	end
end

local function effect(block)
	local kind = block.kind
	if kind == "riser" then return riser(0, 1) end
	if kind == "downlifter" then return riser(1, 0) end
	return function(bar, ctx)
		ctx.hit(0, "crash", 0.8)
		if kind == "impact" and ctx.barInBlock == 0 and ctx.channel.patch then riser(1, 0)(bar, ctx) end
	end
end

local RENDER = {
	drums = drums, tops = drums, bass = bass,
	lead = function(block) return melody(block, 1, REGISTER.lead) end,
	counter = function(block) return melody(block, 0.8, REGISTER.counter) end,
	pad = function(block) return chordal(block, 1) end,
	keys = function(block) return chordal(block, 1) end,
	stab = function(block) return chordal(block, 1) end,
	arp = arp, texture = texture, fx = effect,
}

--- The pattern that plays `block`.
function Patterns.of(block)
	return {id = block.id, part = block.role, bars = block.bars, render = RENDER[block.role](block), block = block}
end

return Patterns
