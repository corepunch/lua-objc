-- The composer every style shares, built from its manifest. The DJ set
-- (StyleKit.newSet) sequences tracks; the style's `arrange` lays each track
-- out as lanes of blocks before its first bar plays (host/Arrangement.lua);
-- and bar n renders the pattern of every block under it. A style supplies
-- the "what" (patterns) and the "when" (arrange) separately, and the plan it
-- arranges is the one the timeline draws and tests read.
local Plugins = require("Plugins")
local Model = require("apps.dnb.Model")
local StyleKit = require("apps.dnb.host.StyleKit")
local Arrangement = require("apps.dnb.host.Arrangement")

local kit = Plugins.readonly(StyleKit)

-- Structure lanes render first: they leave the flags (a fill, a throw,
-- half-time, chops) the instruments read. Then the instruments, in lane order.
local RENDER_ORDER = {}
for _, id in ipairs(Model.parts) do
	if Model.family[id] == "structure" then table.insert(RENDER_ORDER, id) end
end
for _, id in ipairs(Model.parts) do
	if Model.family[id] ~= "structure" then table.insert(RENDER_ORDER, id) end
end

local Composer = {}
Composer.__index = Composer

--- The style's patterns over the shared ones, by id, checked.
local function library(style)
	local patterns = {}
	local function add(pattern, shared)
		local id = pattern.id
		assert(type(id) == "string", "a pattern needs an id")
		assert(Model.family[pattern.part], "pattern " .. id .. " plays unknown part " .. tostring(pattern.part))
		assert(type(pattern.render) == "function", "pattern " .. id .. " needs a render function")
		local bars = pattern.bars or 1
		assert(math.type(bars) == "integer" and bars > 0, "pattern " .. id .. " loops a whole number of bars")
		assert(shared or not patterns[id] or patterns[id].shared, "pattern " .. id .. " is defined twice")
		patterns[id] = {id = id, part = pattern.part, bars = bars, render = pattern.render, shared = shared}
	end
	for _, pattern in ipairs(StyleKit.patterns) do add(pattern, true) end
	for _, pattern in ipairs(style.patterns) do add(pattern, false) end
	return patterns
end

function Composer.new(style, seed)
	return setmetatable({
		style = style, seed = seed, kit = kit,
		set = StyleKit.newSet(seed, style.set),
		patterns = library(style),
		barsPerChord = style.barsPerChord or 2,
		plans = {},
	}, Composer)
end

function Composer:trackAt(n) return self.set:trackAt(n) end
function Composer:trackStart(k) return self.set:trackStart(k) end

--- Material for one cycle of a track: the style's `material(kit, rng,
--- track, first)`, where `first` is the track's first cycle (nil while it is
--- being built), so later cycles can keep its melody or harmony.
function Composer:cycle(track, index)
	local style = self.style
	local first = index > 0 and self:cycle(track, 0) or nil
	return self.set:cycle(track, index, function(rng) return style.material(kit, rng, track, first) end)
end

--- Track k's arrangement: built once, from the seed alone.
function Composer:arrangement(k)
	local plan = self.plans[k]
	if plan then return plan end
	local track = self.set:track(k)
	local cycles = {}
	for i = 0, track.cycles - 1 do cycles[i] = self:cycle(track, i) end
	local sections = {}
	for i, section in ipairs(track.sections) do
		sections[i] = {id = section.id, start = section.start, length = section.length, cycle = section.cycle}
	end
	plan = Arrangement.new({track = k, start = track.start, length = track.length, sections = sections,
		lanes = self.style.arrange(kit, track, cycles)}, self.patterns, Model.parts)
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
		self.barsPerChord)
end

--- Bar n of the set. `settings` provides plays(part) (which lanes sound)
--- and value(control), as Model does; energy and complexity shape every
--- pattern bar by bar, on top of the fixed arrangement.
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
		track = track, tonic = tonic}, StyleKit.random(self.seed, 2, n))
	local chord = self:chord(track, cycleIndex, n)
	bar.progression, bar.chord = kit.progressionName(mode, material.progression), chord
	-- The plan it came from, for the timeline: a bar can sound after a new
	-- style or set has replaced this composer.
	bar.composer = self
	local humanize = settings:value("humanize")
	local previous = track.index > 0 and set:track(track.index - 1) or nil
	local ctx = {
		kit = kit, n = n, pos = pos, track = track, flavour = track.flavour, mode = mode, tonic = tonic, chord = chord,
		cycle = material, cycleIndex = cycleIndex,
		section = section.id, sectionBar = sectionBar, sectionLength = section.length,
		phraseBar = sectionBar % track.phraseBars,
		energy = settings:value("energy"), complexity = settings:value("complexity"), humanize = humanize,
		previous = previous,
	}
	function ctx.hit(step, voice, gain, extra) return bar:hit(step, voice, gain, humanize, extra) end
	-- The outgoing track's chord under this bar and its key, for the blend.
	function ctx.outgoing()
		local last = previous.cycles - 1
		return self:chord(previous, last, n), kit.keyName(self:tonic(previous, last), previous.mode)
	end
	local blocks = plan:blocksAt(pos)
	for _, part in ipairs(RENDER_ORDER) do
		local block = blocks[part]
		if block and settings:plays(part) then
			local pattern = self.patterns[block.pattern]
			ctx.block, ctx.variant = block, block.variant
			ctx.barInBlock = pos - block.start
			ctx.loopBar = ctx.barInBlock % pattern.bars
			pattern.render(bar, ctx)
		end
	end
	return bar
end

return Composer
