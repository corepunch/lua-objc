-- The composer every style shares, built from its manifest. The DJ set
-- (StyleKit.newSet) sequences tracks and gives each its channels, length,
-- energy curve and palette of blocks; the composer writes each track's
-- remaining material once, from its seed (harmony, fills and break edits),
-- has the canvas arrange it as lanes of blocks before its first bar plays
-- (host/Canvas.lua, host/Arrangement.lua), and renders bar n from the
-- pattern of every block under it. The plan it arranges is the one the
-- timeline draws and tests read.
local Plugins = require("Plugins")
local Model = require("apps.dnb.Model")
local StyleKit = require("apps.dnb.host.StyleKit")
local Library = require("apps.dnb.host.Library")
local Blocks = require("apps.dnb.host.Blocks")
local Canvas = require("apps.dnb.host.Canvas")
local Patterns = require("apps.dnb.host.Patterns")
local Arrangement = require("apps.dnb.host.Arrangement")

local kit = Plugins.readonly(StyleKit)

-- What a style leaves out of its `harmony`: the progressions it may use,
-- how many bars a chord lasts, how many bars a progression holds before it
-- may change, and the share of those changes that take another.
local HARMONY = {progressions = {{1, 6, 3, 7}}, barsPerChord = 2, segmentBars = 16, change = 0.35}
-- A track's material: how many fills and break edits it draws.
local MATERIAL = {fills = 6, chops = 10}
local CHOPS = {"stutter", "swap", "swap", "shuffle", "reverse"}
-- Bars a phrase keeps its throws to: every fourth, unless a style says.
local THROWS = 4

local Composer = {}
Composer.__index = Composer

-- The blocks a style plays: the shared ones and its own, parsed once.
local catalogues = {}
local function catalogueOf(style)
	local id = style.id or style.title
	if not catalogues[id] then
		catalogues[id] = Blocks.catalogue({require("apps.dnb.library.blocks.common"), style.blocks or {}})
	end
	return catalogues[id]
end

-- The patterns that play them, and the few that belong to no block.
local function patternsOf(catalogue)
	local patterns = {}
	for _, pattern in ipairs(Patterns.system) do
		patterns[pattern.id] = {id = pattern.id, part = pattern.part, bars = pattern.bars or 1, render = pattern.render}
	end
	for _, block in ipairs(catalogue.list) do patterns[block.id] = Patterns.of(block) end
	return patterns
end

-- A style's own number, from its title: two styles given one seed draw
-- different tracks.
local function salt(style)
	local sum = 0
	for i = 1, #style.title do sum = sum * 31 + style.title:byte(i) end
	return sum
end

local function merged(base, over)
	local result = {}
	for k, v in pairs(base or {}) do result[k] = v end
	for k, v in pairs(over or {}) do result[k] = v end
	return result
end

function Composer.new(style, seed)
	local library = Library.of(style)
	local catalogue = catalogueOf(style)
	local set = style.set or {}
	local spec = {salt = salt(style), flavours = style.flavours, roles = style.roles, library = library,
		catalogue = catalogue, genre = style.id, arc = style.arc, modes = set.modes, modulations = set.modulations}
	return setmetatable({
		style = style, seed = seed, kit = kit, library = library, catalogue = catalogue,
		set = StyleKit.newSet(seed, spec), patterns = patternsOf(catalogue),
		plans = {}, materials = {},
	}, Composer)
end

function Composer:trackAt(n) return self.set:trackAt(n) end
function Composer:trackStart(k) return self.set:trackStart(k) end

-- One of a channel's fills: a fill beat from the library, or an edit of
-- the groove ("@stutter").
local function fillOf(library, id)
	if id:sub(1, 1) == "@" then return {id = id:sub(2), edit = id:sub(2)} end
	return {id = id, beat = library:get("fills", id)}
end

--- A track's material, written once from its seed:
---   {segments = {{start, length, progression, voicings}, …}, barsPerChord,
---    fills, chops}
--- The harmony runs in segments of `segmentBars`, each keeping a
--- progression or taking another; fills and break edits are the producer's
--- craft, the jungle edits of a break: stutter a snare slice, swap a beat in
--- from elsewhere, play one backwards, or drop a stray 16th somewhere new.
function Composer:material(track)
	local material = self.materials[track.index]
	if material then return material end
	local style, library, flavour = self.style, self.library, track.flavour
	local rng = StyleKit.random(track.seed, 2)
	local harmony = merged(merged(HARMONY, style.harmony), flavour.harmony)
	material = {segments = {}, barsPerChord = harmony.barsPerChord, fills = {}, chops = {}}
	local progression
	local index = 0
	for start = 0, track.length - 1, harmony.segmentBars do
		local own = StyleKit.random(track.seed, 3, index)
		if not progression or own.chance(harmony.change) then
			progression = kit.stableProgression(track.mode, own.pick(harmony.progressions))
		end
		table.insert(material.segments, {start = start, length = math.min(harmony.segmentBars, track.length - start),
			progression = progression, voicings = kit.voicings(track.mode, progression, harmony.voicing)})
		index = index + 1
	end
	local own = StyleKit.random(track.seed, 3, 1000)
	local drums = merged(style.roles and style.roles.drums, track.byRole.drums and track.byRole.drums.spec)
	for _ = 1, MATERIAL.fills do
		table.insert(material.fills, fillOf(library, own.pick(drums.fills or {"@stutter", "@cut", "@reverse"})))
	end
	for _ = 1, MATERIAL.chops do
		local kind = own.pick(CHOPS)
		local chop = {kind = kind, bar = own.int(track.phraseBars) - 1, threshold = own.float(), source = own.int(64) - 1}
		if kind == "stutter" then
			chop.step, chop.length = own.pick({12, 14, 8}), own.pick({2, 4})
		elseif kind == "swap" or kind == "reverse" then
			chop.step, chop.length, chop.source = (own.int(4) - 1) * 4, 4, (own.int(16) - 1) * 4
		else
			chop.step, chop.length = own.int(16) - 1, 1
		end
		table.insert(material.chops, chop)
	end
	self.materials[track.index] = material
	return material
end

--- Track k's arrangement: built once, from the seed alone. Its lanes are
--- the track's channels, in their order.
function Composer:arrangement(k)
	local plan = self.plans[k]
	if plan then return plan end
	local track = self.set:track(k)
	local phrases = {}
	for i, phrase in ipairs(track.phrases) do
		phrases[i] = {start = phrase.start, length = phrase.length, energy = phrase.energy, label = phrase.label,
			valley = phrase.valley or false, edge = phrase.edge}
	end
	local order, channels = {}, {}
	for i, channel in ipairs(track.channels) do
		order[i] = channel.role
		channels[i] = {role = channel.role, name = channel.name}
	end
	local previous = k > 0 and self.set:track(k - 1) or nil
	local lanes, events = Canvas.arrange(track, StyleKit.random(track.seed, 1), previous)
	plan = Arrangement.new({track = k, start = track.start, length = track.length, phrases = phrases,
		events = events, channels = channels, tempo = track.tempo, lanes = lanes}, self.patterns, order)
	self.plans[k] = plan
	return plan
end

--- The key a track plays bar `pos` in, after its lift.
function Composer:tonic(track, pos)
	local lift = track.lift
	return (track.tonic + (lift and pos >= lift.bar and lift.semis or 0)) % 12
end

-- The segment of harmony holding track bar `pos`, and the bars it has run.
local function segmentAt(material, pos)
	local last = material.segments[#material.segments]
	for i = #material.segments, 1, -1 do
		local segment = material.segments[i]
		if pos >= segment.start then return segment, pos - segment.start end
	end
	return last, 0
end

--- The chord a track plays under track bar `pos`, and how many bars it has
--- sounded.
function Composer:chord(track, pos)
	local material = self:material(track)
	local segment, into = segmentAt(material, pos)
	return kit.chordAt(track.mode, segment.progression, segment.voicings, self:tonic(track, pos), into,
		material.barsPerChord), into % material.barsPerChord, segment
end

--- Bar n of the set. `settings` provides plays(role) (which channels
--- sound) and value(control), as Model does; energy and complexity shape
--- every pattern bar by bar, on top of the fixed arrangement.
function Composer:bar(n, settings)
	local set = self.set
	local track = set:trackAt(n)
	local plan = self:arrangement(track.index)
	local pos = n - track.start
	local phrase, phraseIndex = plan:phraseAt(pos)
	local mode = track.mode
	local material = self:material(track)
	local tonic = self:tonic(track, pos)
	local phraseBar = pos % track.phraseBars
	local bar = StyleKit.newBar(n, {arc = phrase.energy, label = phrase.label, phrase = phraseIndex,
		phraseBar = phraseBar, track = track, tonic = tonic, tempo = set:tempoAt(n)}, StyleKit.random(self.seed, 2, n))
	local chord, chordBar, segment = self:chord(track, pos)
	bar.progression, bar.chord = kit.progressionName(mode, segment.progression), chord
	-- The plan it came from, for the timeline: a bar can sound after a new
	-- style or set has replaced this composer.
	bar.composer = self
	local humanize = settings:value("humanize")
	local energy, complexity = settings:value("energy"), settings:value("complexity")
	local previous = track.index > 0 and set:track(track.index - 1) or nil
	local throws = self.style.throws == nil and THROWS or self.style.throws
	local ctx = {
		kit = kit, n = n, pos = pos, bar = bar, track = track, flavour = track.flavour, mode = mode, tonic = tonic,
		chord = chord, chordBar = chordBar, material = material, barsPerChord = material.barsPerChord,
		arc = phrase.energy, phrase = pos // track.phraseBars, phraseBar = phraseBar,
		energy = energy, complexity = complexity, humanize = humanize,
		previous = previous,
		-- A dub echo: the parts that answer it throw their last hit of the
		-- phrase into the delay.
		throw = throws and pos % throws == throws - 1 or false,
	}
	local role
	function ctx.hit(step, voice, gain, extra) return bar:hit(role, step, voice, gain, humanize, extra) end
	function ctx.note(fields)
		fields.patch = fields.patch or ctx.channel.patch
		if not fields.patch then return end
		fields.role = role
		table.insert(bar.notes, fields)
		return fields
	end
	function ctx.slice(fields)
		fields.role, fields.gain = role, fields.gain or 1
		fields.energy, fields.complexity = energy > 0.5, complexity > 0.5
		table.insert(bar.slices, fields)
		-- The kit's accents under the slice, for the pump and the flashes.
		if role == "drums" and not fields.reverse and (fields.rate or 1) == 1 then
			local kicks, snares = Library.accents(fields.beat, fields.slice, fields.length or 1, fields.variant,
				fields.energy, fields.complexity)
			for _, at in ipairs(kicks) do table.insert(bar.kickSteps, fields.step + at) end
			for _, at in ipairs(snares) do table.insert(bar.snareSteps, fields.step + at) end
		end
		return fields
	end
	-- The outgoing track's chord under this bar and its key, for the blend.
	function ctx.outgoing()
		local last = previous.length - 1
		return (self:chord(previous, last)), kit.keyName(self:tonic(previous, last), previous.mode)
	end
	local blocks = plan:blocksAt(pos)
	for _, channel in ipairs(track.channels) do
		role = channel.role
		local block = blocks[role]
		if block and settings:plays(role) then
			local pattern = self.patterns[block.pattern]
			local inBlock = pos - block.start
			ctx.channel = channel
			ctx.block, ctx.blockLength = block, block.whole or block.length
			ctx.barInBlock = inBlock + (block.offset or 0)
			if block.under then
				ctx.groove, ctx.grooveBar = self.patterns[block.under].block.beat, block.phase or 0
			end
			if pattern.block and pattern.block.tags.halftime then bar.halftime = true end
			pattern.render(bar, ctx)
			-- The channel rides its block's fade and sweep through the bar.
			if block.level or block.filter then
				local level, kind, from = Arrangement.automation(block, inBlock / block.length)
				local levelTo, kindTo, to = Arrangement.automation(block, (inBlock + 1) / block.length)
				bar.automation[role] = {level = {from = level, to = levelTo}, kind = kind or kindTo,
					filter = {from = from or 1, to = to or 1}}
			end
		end
	end
	return bar
end

return Composer
