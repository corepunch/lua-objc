-- The composer every style shares, built from its manifest. The DJ set
-- (StyleKit.newSet) sequences tracks and gives each its channels; the
-- composer writes each track's material once, from its seed (a rhythm cell,
-- a motif and the hook made of it, a bass line, grooves and fills picked
-- from the library), arranges it as lanes of blocks before its first bar
-- plays (host/Arrangement.lua), and renders bar n from the pattern of every
-- block under it. The plan it arranges is the one the timeline draws and
-- tests read.
local Plugins = require("Plugins")
local Model = require("apps.dnb.Model")
local StyleKit = require("apps.dnb.host.StyleKit")
local Library = require("apps.dnb.host.Library")
local Motif = require("apps.dnb.host.Motif")
local Arrangement = require("apps.dnb.host.Arrangement")

local kit = Plugins.readonly(StyleKit)

-- What a style leaves out of its `harmony`.
local HARMONY = {progressions = {{1, 6, 3, 7}}, barsPerChord = 2,
	change = 0.35} -- the share of later cycles that take a progression of their own
-- A track's material: how many fills and break edits a cycle draws, the
-- share of later drops that turn to the other groove, and where in a drop
-- a half-time switch-up falls.
local MATERIAL = {fills = 6, chops = 10, turn = 0.4, halftime = {from = 16, to = 24},
	repitch = 0.5} -- the share of authored bass lines whose answers are moved
local CHOPS = {"stutter", "swap", "swap", "shuffle", "reverse"}
local HOOKS = {"same", "same", "third", "mirror"}
-- Bars a section keeps its throws to: every fourth, unless a style says.
local THROWS = 4

local Composer = {}
Composer.__index = Composer

--- The style's patterns over the shared ones, by id, checked.
local function patternsOf(style)
	local patterns = {}
	local function add(pattern, shared)
		local id = pattern.id
		assert(type(id) == "string", "a pattern needs an id")
		assert(Model.family[pattern.part], "pattern " .. id .. " plays unknown role " .. tostring(pattern.part))
		assert(type(pattern.render) == "function", "pattern " .. id .. " needs a render function")
		local bars = pattern.bars or 1
		assert(math.type(bars) == "integer" and bars > 0, "pattern " .. id .. " loops a whole number of bars")
		assert(shared or not patterns[id] or patterns[id].shared, "pattern " .. id .. " is defined twice")
		patterns[id] = {id = id, part = pattern.part, bars = bars, render = pattern.render, shared = shared}
	end
	for _, pattern in ipairs(StyleKit.patterns) do add(pattern, true) end
	for _, pattern in ipairs(style.patterns or {}) do add(pattern, false) end
	return patterns
end

-- A style's own number, from its title: two styles given one seed draw
-- different forms.
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
	local spec = {salt = salt(style), flavours = style.flavours, roles = style.roles, library = library}
	for k, v in pairs(style.set) do spec[k] = v end
	return setmetatable({
		style = style, seed = seed, kit = kit, library = library,
		set = StyleKit.newSet(seed, spec),
		patterns = patternsOf(style),
		plan = StyleKit.planWith(StyleKit.plan, style.plan),
		plans = {}, materials = {},
	}, Composer)
end

function Composer:trackAt(n) return self.set:trackAt(n) end
function Composer:trackStart(k) return self.set:trackStart(k) end

-- One of a channel's fills: a fill beat from the library, or an edit of
-- the groove ("@stutter").
local function fillOf(library, id)
	if id:sub(1, 1) == "@" then return {id = id:sub(2), edit = id:sub(2)} end
	return {id = id, beat = library:get("beats", id)}
end

-- The first bar of a hook, as a motif.
local function firstBar(hook)
	local notes = {}
	for _, note in ipairs(hook.notes) do
		if note.bar == 0 then table.insert(notes, note) end
	end
	return notes
end

--- A track's material, written once from its seed. What is the track's
--- own (its rhythm cell, motif, hook and bass line) is kept through every
--- cycle; a cycle brings its harmony, a way of playing the hook, its
--- grooves, fills and break edits:
---   {cell, motif, hook, line, cycles = {[0] = {progression, voicings,
---    barsPerChord, hook, answer, line, comp, stabs, arp, grooves, fills,
---    chops, halftime}, …}}
function Composer:material(track)
	local material = self.materials[track.index]
	if material then return material end
	local style, library, flavour = self.style, self.library, track.flavour
	local rng = StyleKit.random(track.seed, 2)
	local harmony = merged(merged(HARMONY, style.harmony), flavour.harmony)
	local cell = Motif.cell(rng, harmony.cells)
	local byRole = track.byRole
	local function spec(role) return byRole[role] and byRole[role].spec or merged(style.roles and style.roles[role]) end

	-- The hook: one from the library, or one made of a motif of the track's.
	local melodic = spec(byRole.lead and "lead" or "counter")
	local hookId = rng.pick(melodic.hooks or {"@motif"})
	local hook
	if hookId == "@motif" then
		hook = Motif.develop(rng, Motif.write(rng, cell, melodic.motif))
	else
		-- An authored hook is played as written, a third away or mirrored:
		-- two tracks that take the same hook do not play the same tune.
		hook = Motif.vary(rng, library:get("hooks", hookId), rng.pick(HOOKS))
		hook.motif = firstBar(hook)
	end
	local lineId = rng.pick(spec("bass").lines or {"@cell"})
	local line
	if lineId:sub(1, 1) == "@" then
		line = Motif.lines[lineId:sub(2)](rng, cell, spec("bass"))
	else
		line = library:get("lines", lineId)
		if rng.chance(MATERIAL.repitch) then line = Motif.repitch(rng, line) end
	end
	local comp = Motif.comp(rng, cell, spec("keys").comp)
	-- Stabs answer the rhythm: a pattern of the style's, or the cell's rests.
	local stabs = {}
	local stabSpec = spec("stab")
	local stabSteps = stabSpec.steps and kit.steps(rng.pick(stabSpec.steps)) or Motif.offbeats(cell, 2)
	for i, step in ipairs(stabSteps) do
		if i == 1 or #stabs < 4 then table.insert(stabs, {step = step, threshold = i == 1 and 0 or rng.float() * 0.9}) end
	end
	local arp = Motif.arp(rng, spec("arp").arp, hook.motif)

	material = {cell = cell, motif = hook.motif, hook = hook, line = line, cycles = {}}
	local progression = kit.stableProgression(track.mode, rng.pick(harmony.progressions))
	for index = 0, track.cycles - 1 do
		local own = StyleKit.random(track.seed, 3, index)
		if index > 0 and own.chance(harmony.change) then
			progression = kit.stableProgression(track.mode, own.pick(harmony.progressions))
		end
		local played = index == 0 and hook or Motif.vary(own, hook)
		local cycle = {
			progression = progression,
			voicings = kit.voicings(track.mode, progression, harmony.voicing),
			barsPerChord = harmony.barsPerChord,
			hook = played, answer = Motif.answer(own, played),
			line = line, comp = comp, stabs = stabs, arp = arp,
			grooves = {}, fills = {}, chops = {},
		}
		for _, channel in ipairs(track.channels) do
			if channel.beat then
				cycle.grooves[channel.role] = (index > 0 and own.chance(MATERIAL.turn)) and channel.alt or channel.beat
			end
		end
		local drums = spec("drums")
		for _ = 1, MATERIAL.fills do
			table.insert(cycle.fills, fillOf(library, own.pick(drums.fills or {"@stutter", "@cut", "@reverse"})))
		end
		-- Break edits, the jungle producer's craft: stutter a snare slice,
		-- swap a beat in from elsewhere, play one backwards, or drop a
		-- stray 16th somewhere new.
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
			table.insert(cycle.chops, chop)
		end
		if own.chance(flavour.halftime or 0) then cycle.halftime = MATERIAL.halftime end
		material.cycles[index] = cycle
	end
	self.materials[track.index] = material
	return material
end

--- Material for one cycle of a track.
function Composer:cycle(track, index)
	return self:material(track).cycles[index]
end

--- Track k's arrangement: built once, from the seed alone. Its lanes are
--- the track's channels, in their order.
function Composer:arrangement(k)
	local plan = self.plans[k]
	if plan then return plan end
	local track = self.set:track(k)
	local sections = {}
	for i, section in ipairs(track.sections) do
		sections[i] = {id = section.id, start = section.start, length = section.length, cycle = section.cycle,
			kind = section.kind}
	end
	local order, channels = {}, {}
	for i, channel in ipairs(track.channels) do
		order[i] = channel.role
		channels[i] = {role = channel.role, name = channel.name}
	end
	local previous = k > 0 and self.set:track(k - 1) or nil
	plan = Arrangement.new({track = k, start = track.start, length = track.length, sections = sections,
		channels = channels, tempo = track.tempo,
		lanes = StyleKit.arrange(track, StyleKit.planWith(self.plan, track.flavour.plan), previous)},
		self.patterns, order)
	self.plans[k] = plan
	return plan
end

--- The key a track plays a cycle in, after its modulations.
function Composer:tonic(track, cycle)
	return (track.tonic + self.set:shift(track, cycle)) % 12
end

--- The chord a track's cycle plays under set bar n.
function Composer:chord(track, cycle, n)
	local material = self:cycle(track, cycle)
	return kit.chordAt(track.mode, material.progression, material.voicings, self:tonic(track, cycle), n,
		material.barsPerChord)
end

--- Bar n of the set. `settings` provides plays(role) (which channels
--- sound) and value(control), as Model does; energy and complexity shape
--- every pattern bar by bar, on top of the fixed arrangement.
function Composer:bar(n, settings)
	local set = self.set
	local track = set:trackAt(n)
	local plan = self:arrangement(track.index)
	local pos = n - track.start
	local section = plan:sectionAt(pos)
	local cycleIndex = section.cycle
	local mode = track.mode
	local material = self:cycle(track, cycleIndex)
	local tonic = self:tonic(track, cycleIndex)
	local sectionBar = pos - section.start
	local bar = StyleKit.newBar(n, {section = section.id, sectionBar = sectionBar, sectionLength = section.length,
		track = track, tonic = tonic, tempo = set:tempoAt(n)}, StyleKit.random(self.seed, 2, n))
	local chord = self:chord(track, cycleIndex, n)
	bar.progression, bar.chord = kit.progressionName(mode, material.progression), chord
	-- The plan it came from, for the timeline: a bar can sound after a new
	-- style or set has replaced this composer.
	bar.composer = self
	local humanize = settings:value("humanize")
	local energy, complexity = settings:value("energy"), settings:value("complexity")
	local previous = track.index > 0 and set:track(track.index - 1) or nil
	local halftime = material.halftime
	local throws = self.style.throws == nil and THROWS or self.style.throws
	local ctx = {
		kit = kit, n = n, pos = pos, bar = bar, track = track, flavour = track.flavour, mode = mode, tonic = tonic,
		chord = chord, material = self:material(track), cycle = material, cycleIndex = cycleIndex,
		barsPerChord = material.barsPerChord,
		section = section.id, sectionBar = sectionBar, sectionLength = section.length,
		phraseBar = sectionBar % track.phraseBars,
		energy = energy, complexity = complexity, humanize = humanize,
		previous = previous,
		-- The switch-up inside a drop: the drums turn to half-time and the
		-- arrangement thins.
		halftime = halftime ~= nil and section.id == "drop" and section.length > halftime.from
			and sectionBar >= halftime.from and sectionBar < halftime.to,
		-- A dub echo: the parts that answer it throw their last hit of the
		-- phrase into the delay.
		throw = throws and section.id ~= "build" and sectionBar % throws == throws - 1 or false,
	}
	bar.halftime = ctx.halftime or nil
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
		local last = previous.cycles - 1
		return self:chord(previous, last, n), kit.keyName(self:tonic(previous, last), previous.mode)
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
			ctx.loopBar = ctx.barInBlock % pattern.bars
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
