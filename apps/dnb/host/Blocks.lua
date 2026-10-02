-- Blocks: the authored material a track is arranged from. A block is a
-- short loop of one role (a two-bar bass line, a four-bar hook, a drum
-- loop, a chord rhythm) with the numbers and tags the arranger picks by.
-- Blocks are named "<genre>.<role>.<number>", as sample packs name their
-- loops ("trance.bass.024"), and live in plain data files: each style's
-- `blocks.lua` and the shared `library/blocks/common.lua`. See BLOCKS.md.
--
-- Every block has
--   id        "trance.bass.024": genre, role, a number unique to the pair
--   role      a channel role (Model.roles)
--   bars      how many bars it loops over
--   energy    0…1, how intense it sounds on its own: a kick alone is 0.2,
--             the full groove 0.9; the arranger takes the nearest to the
--             energy a moment of the track wants
--   density   0…1, how busy: notes per bar, layers of percussion
--   brightness 0…1 (optional, 0.5): sub is 0, hats and risers are 1
--   tags      what it is: "rolling", "halftime", "mixable", "dark" …
--   flavours  the genre's flavours it belongs to (optional: all of them)
--   excludes  tags it cannot share a phrase with (optional)
-- and the content of its role:
--   drums, tops   lanes of steps (Library.beat) and, for a record's break,
--                 `kit = "break"` and its `bpm`
--   bass, lead, counter
--                 `notes` in scale steps (Library.notes), `follow` ("chord"
--                 or "key") and `octave`
--   pad, keys, stab
--                 `comp`: chord hits as "step:length" (an optional "!" for
--                 an accent, "?" while Energy is up, "+" while Complexity
--                 is); a pad with `hold = true` sustains the chord instead
--   arp           `order` (chord tones, 1 the lowest), `rate` (steps to a
--                 note), `gate`, `mask` ("X" always, "x" while Complexity
--                 is up, "." rest, over 16 steps) and `octave`
--   texture       `voices`, semitones above the key's root held `every` bars
--   fx            `kind`: "riser", "downlifter", "impact" or "crash"
local Model = require("apps.dnb.Model")
local Library = require("apps.dnb.host.Library")

local Blocks = {}
Blocks.__index = Blocks

local STEPS = 16
local THRESHOLD = 0.55
Blocks.fxKinds = {riser = true, downlifter = true, impact = true, crash = true}

local function range(spec, field, where, default)
	local value = spec[field]
	if value == nil then return default end
	assert(type(value) == "number" and value >= 0 and value <= 1, where .. " " .. field .. " is a number from 0 to 1")
	return value
end

local function set(list, where, what)
	if list == nil then return nil end
	assert(type(list) == "table", where .. " " .. what .. " is a list")
	local result = {}
	for _, name in ipairs(list) do
		assert(type(name) == "string" and name:match("^[a-z][a-z0-9%-]*$"), where .. " has a bad " .. what .. " " .. tostring(name))
		result[name] = true
	end
	return result
end

-- Chord hits, "step:length" with bars split by "|": {bar, step, length,
-- accent, chance, detail}, and how many bars they cover.
local function comp(text, where)
	local hits, bar = {}, 0
	for segment in (text .. "|"):gmatch("([^|]*)|") do
		for token in segment:gmatch("%S+") do
			local step, length, flags = token:match("^([%d%.]+):([%d%.]+)([!?+]*)$")
			assert(step, where .. " has a chord hit it cannot read: " .. token)
			step, length = tonumber(step), tonumber(length)
			assert(step < STEPS and length > 0, where .. " hit " .. token .. " must start inside its bar")
			table.insert(hits, {bar = bar, step = step, length = length, accent = flags:find("!", 1, true) ~= nil,
				chance = flags:find("?", 1, true) and THRESHOLD or 0, detail = flags:find("+", 1, true) and THRESHOLD or 0})
		end
		bar = bar + 1
	end
	assert(#hits > 0, where .. " has no chord hits")
	return hits, bar
end

-- A mask over 16 steps; one that divides 16 repeats.
local function mask(text, where)
	local pattern = {}
	for c in text:gmatch("[^%s|]") do
		assert(c == "X" or c == "x" or c == ".", where .. " mask has unknown step " .. c)
		table.insert(pattern, c)
	end
	assert(#pattern > 0 and STEPS % #pattern == 0, where .. " mask divides 16 steps")
	local steps = {}
	for at = 0, STEPS - 1 do steps[at] = pattern[at % #pattern + 1] end
	return steps
end

local CONTENT = {
	drums = function(spec, block, where)
		assert(spec.lanes, where .. " needs lanes")
		block.beat = Library.beat({id = spec.id, name = spec.name, bars = block.bars, lanes = spec.lanes, kit = spec.kit,
			bpm = spec.bpm, send = spec.send})
		block.beat.when = nil
	end,
	line = function(spec, block, where)
		local parsed = Library.notes(assert(spec.notes, where .. " needs notes"), where)
		assert(block.bars >= parsed.bars, where .. " is written longer than its bars")
		parsed.follow, parsed.octave, parsed.bars = spec.follow or "chord", spec.octave, block.bars
		assert(parsed.follow == "chord" or parsed.follow == "key", where .. " follows the chord or the key")
		block.line = parsed
	end,
	chords = function(spec, block, where)
		block.hold = spec.hold == true
		if block.hold then
			assert(spec.comp == nil, where .. " holds the chord and has no rhythm")
		else
			local bars
			block.comp, bars = comp(assert(spec.comp, where .. " needs a chord rhythm in `comp`"), where)
			assert(block.bars >= bars, where .. " is written longer than its bars")
			block.compBars = bars
		end
	end,
	arp = function(spec, block, where)
		local order = assert(spec.order, where .. " needs an `order` of chord tones")
		assert(#order > 0, where .. " needs chord tones")
		for _, index in ipairs(order) do assert(math.type(index) == "integer" and index >= 1, where .. " chord tones count from 1") end
		block.arp = {order = order, rate = spec.rate or 1, gate = spec.gate or 0.7, octave = spec.octave or 1,
			mask = mask(spec.mask or "XXXXXXXXXXXXXXXX", where)}
		assert(block.arp.rate == 1 or block.arp.rate == 2 or block.arp.rate == 4, where .. " steps by 1, 2 or 4")
	end,
	texture = function(spec, block, where)
		block.voices = spec.voices or {0, 7}
		block.every = spec.every or 4
		for _, v in ipairs(block.voices) do assert(type(v) == "number", where .. " voices are semitones") end
	end,
	fx = function(spec, block, where)
		assert(Blocks.fxKinds[spec.kind], where .. " is an fx of unknown kind " .. tostring(spec.kind))
		block.kind = spec.kind
	end,
}
local FAMILY = {drums = "drums", tops = "drums", bass = "line", lead = "line", counter = "line", pad = "chords",
	keys = "chords", stab = "chords", arp = "arp", texture = "texture", fx = "fx"}

--- Parses and checks one block. Errors name the block.
function Blocks.parse(spec)
	assert(type(spec) == "table" and type(spec.id) == "string", "a block needs an id")
	local where = "block " .. spec.id
	local genre, role, number = spec.id:match("^([%l]+)%.([%l]+)%.(%d+)$")
	assert(genre, where .. " is named <genre>.<role>.<number>")
	assert(spec.role == role, where .. " is a " .. tostring(spec.role) .. " but its id says " .. role)
	assert(Model.family[role] and FAMILY[role], where .. " has unknown role " .. tostring(role))
	local bars = spec.bars or 1
	assert(math.type(bars) == "integer" and bars >= 1 and bars <= 8, where .. " loops over 1 to 8 bars")
	assert(spec.energy ~= nil and spec.density ~= nil, where .. " needs an energy and a density")
	local block = {id = spec.id, role = role, genre = genre, number = tonumber(number), bars = bars,
		name = spec.name or spec.id, energy = range(spec, "energy", where), density = range(spec, "density", where),
		brightness = range(spec, "brightness", where, 0.5), tags = set(spec.tags, where, "tag") or {},
		flavours = set(spec.flavours, where, "flavour"), excludes = set(spec.excludes, where, "exclusion") or {}}
	block.tagList = {}
	for _, tag in ipairs(spec.tags or {}) do table.insert(block.tagList, tag) end
	CONTENT[FAMILY[role]](spec, block, where)
	return block
end

--- A catalogue of `lists` of block specs: {byId, byRole, list}. Ids are
--- unique across the lists.
function Blocks.catalogue(lists)
	local self = setmetatable({byId = {}, byRole = {}, list = {}}, Blocks)
	for _, role in ipairs(Model.roles) do self.byRole[role.id] = {} end
	for _, specs in ipairs(lists) do
		for _, spec in ipairs(specs) do
			local block = Blocks.parse(spec)
			assert(not self.byId[block.id], "block " .. block.id .. " is defined twice")
			self.byId[block.id] = block
			table.insert(self.byRole[block.role], block)
			table.insert(self.list, block)
		end
	end
	return self
end

function Blocks:get(id)
	return self.byId[id] or error("unknown block " .. tostring(id), 0)
end

--- The blocks of `role` that `genre` and `flavour` may play: the genre's
--- own and the shared ones ("common"), those a flavour list leaves out
--- excluded, and any carrying a tag in `avoid`.
function Blocks:candidates(role, genre, flavour, avoid)
	local result = {}
	for _, block in ipairs(self.byRole[role] or {}) do
		local ok = block.genre == genre or block.genre == "common"
		if ok and block.flavours and not block.flavours[flavour] then ok = false end
		for tag in pairs(avoid or {}) do
			if block.tags[tag] then ok = false end
		end
		if ok then table.insert(result, block) end
	end
	return result
end

return Blocks
