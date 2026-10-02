-- The library: the sounds and notation tracks are made of, as a tracker
-- module carries its samples. Patches (the instruments) and fills live in
-- apps/dnb/library/ and in each style plugin's own `library`; this module
-- reads their notation, checks them and looks them up by id. The loops a
-- track is arranged from are blocks (host/Blocks.lua), which use the
-- notations read here.
--
-- Beats are lanes of steps, 16 to a bar:
--   {id = "twostep", bars = 1, lanes = {
--     {"kick",  "X.........x....."},
--     {"snare", "....X.......X..."},
--     {"hat",   "x.x.x.x.x.x.x.x.", gain = 0.5, when = "energy"}}}
-- "X" is an accent, "x" a hit, "o" a soft hit, "g" a ghost; spaces and bar
-- lines are for the eye. A lane shorter than the beat repeats. `when` lets
-- a lane in only while Energy or Complexity is up, `light = false` keeps it
-- out of the beat's light variant (intros and outros), `div = 32` writes it
-- in 32nds. A beat with `kit = "break"` is a record's break: played on the
-- break kit, at the record's `bpm`, through a room.
--
-- Notes, "step:pitch:length" with bars split by "|":
--   "0:0:6 8:7:2~ 12:4:3! | 0:0:8 10:2b:2?"
-- Pitch is in scale steps (0 the root, 2 the third, 7 the octave; "b" and
-- "#" bend it a semitone), so a line stays in its track's key and mode.
-- "~" slides into the note, "!" accents it, "?" plays it while Energy is
-- up and "+" while Complexity is, "w3" sets a wobble rate.
local Instrument = require("apps.dnb.models.Instrument")
local Drums = require("apps.dnb.models.Drums")

local Library = {}
Library.__index = Library

local STEPS = 16
local VELOCITY = {X = 1, x = 0.8, o = 0.55, g = 0.3}
local REST = {["."] = true, ["-"] = true}
-- How far up Energy or Complexity must be for a "?" or "+" note to play:
-- just above the middle, so that Complexity at rest leaves the detail out.
local THRESHOLD = 0.55
local KICKS = {kick = true, breakKick = true}
local SNARES = {snare = true, clap = true, breakSnare = true}

--- Parses a beat into {id, bars, slices, hits, kit, bpm, send, from}: its
--- hits as {step, voice, gain, when, light, pan}, in step order.
function Library.beat(spec)
	local where = "beat " .. tostring(spec.id)
	assert(type(spec.id) == "string", "a beat needs an id")
	local bars = spec.bars or 1
	assert(math.type(bars) == "integer" and bars > 0, where .. " lasts a whole number of bars")
	assert(spec.kit == nil or spec.kit == "break", where .. " has unknown kit " .. tostring(spec.kit))
	assert(spec.kit ~= "break" or type(spec.bpm) == "number", where .. " is a record's break and needs its bpm")
	local beat = {id = spec.id, name = spec.name or spec.id, bars = bars, slices = bars * STEPS, kit = spec.kit,
		bpm = spec.bpm, send = spec.send, from = spec.from, hits = {}}
	for index, lane in ipairs(assert(spec.lanes, where .. " needs lanes")) do
		local voice, pattern = lane[1], lane[2]
		assert(Drums.place[voice], where .. " lane " .. index .. " plays unknown voice " .. tostring(voice))
		assert(lane.when == nil or lane.when == "energy" or lane.when == "complexity",
			where .. " lane " .. index .. " waits for energy or complexity")
		local div = lane.div or STEPS
		local steps = {}
		for c in pattern:gmatch("[^%s|]") do
			assert(VELOCITY[c] or REST[c], where .. " lane " .. index .. " has unknown step " .. c)
			table.insert(steps, c)
		end
		assert(#steps > 0 and #steps % div == 0, where .. " lane " .. index .. " is written in whole bars")
		for at = 0, bars * div - 1 do
			local velocity = VELOCITY[steps[at % #steps + 1]]
			if velocity then
				local step = at * STEPS / div
				table.insert(beat.hits, {step = math.tointeger(step) or step, voice = voice, gain = velocity * (lane.gain or 1),
					when = lane.when, light = lane.light, pan = lane.pan, full = velocity >= VELOCITY.x})
			end
		end
	end
	table.sort(beat.hits, function(a, b)
		if a.step ~= b.step then return a.step < b.step end
		return a.voice < b.voice
	end)
	-- Slices that open on a full snare hit, for stutters.
	beat.snareSlices = {}
	for _, hit in ipairs(beat.hits) do
		if SNARES[hit.voice] and hit.full and hit.when == nil and math.type(hit.step) == "integer" then
			table.insert(beat.snareSlices, hit.step)
		end
	end
	return beat
end

--- The kicks and snares of `beat` inside steps [from, from + length), as
--- steps from `from`, for the hits a loop `variant` plays.
function Library.accents(beat, from, length, variant, energy, complexity)
	local kicks, snares = {}, {}
	for _, hit in ipairs(beat.hits) do
		if hit.step >= from and hit.step < from + length and hit.full
			and Drums.plays(hit, variant, energy, complexity) then
			if KICKS[hit.voice] then table.insert(kicks, hit.step - from) end
			if SNARES[hit.voice] then table.insert(snares, hit.step - from) end
		end
	end
	return kicks, snares
end

--- Parses notes into {bars, notes}: each note {step (from the first bar),
--- bar, offset, bend, length, glide, accent, chance, detail, rate}.
function Library.notes(text, where)
	where = where or "notes"
	local notes, bar = {}, 0
	for segment in (text .. "|"):gmatch("([^|]*)|") do
		for token in segment:gmatch("%S+") do
			local step, pitch, bend, length, flags = token:match("^([%d%.]+):(%-?%d+)([b#]?):([%d%.]+)(.*)$")
			assert(step, where .. " has a note it cannot read: " .. token)
			step, length = tonumber(step), tonumber(length)
			assert(step < STEPS and length > 0, where .. " note " .. token .. " must start inside its bar")
			local note = {step = bar * STEPS + step, bar = bar, offset = math.tointeger(tonumber(pitch)),
				bend = bend == "b" and -1 or (bend == "#" and 1 or 0), length = length, chance = 0, detail = 0}
			local rate = flags:match("w([%d%.]+)")
			if rate then note.rate = tonumber(rate) end
			flags = flags:gsub("w[%d%.]+", "")
			for flag in flags:gmatch(".") do
				if flag == "~" then note.glide = true
				elseif flag == "!" then note.accent = true
				elseif flag == "?" then note.chance = THRESHOLD
				elseif flag == "+" then note.detail = THRESHOLD
				else error(where .. " note " .. token .. " has unknown flag " .. flag, 0) end
			end
			table.insert(notes, note)
		end
		bar = bar + 1
	end
	assert(#notes > 0, where .. " has no notes")
	table.sort(notes, function(a, b) return a.step < b.step end)
	return {bars = bar, notes = notes}
end

local KINDS = {
	patches = function(spec) return Instrument.patch(spec) end,
	fills = Library.beat,
}
Library.kinds = {"patches", "fills"}

local function add(self, kind, specs, source)
	for _, spec in ipairs(specs or {}) do
		local entry = KINDS[kind](spec)
		assert(not self[kind][entry.id] or self.shared[kind][entry.id],
			kind .. " " .. entry.id .. " is defined twice in " .. source)
		self[kind][entry.id] = entry
	end
end

local shared

--- The material every style shares (apps/dnb/library/).
function Library.shared()
	if not shared then
		shared = setmetatable({patches = {}, fills = {}, shared = {patches = {}, fills = {}}}, Library)
		add(shared, "patches", require("apps.dnb.library.Patches"), "the library")
		add(shared, "fills", require("apps.dnb.library.Fills"), "the library")
	end
	return shared
end

--- The library a style plays from: its own material (`style.library`, a
--- table of lists by kind) over the shared one.
function Library.of(style)
	local base = Library.shared()
	local self = setmetatable({patches = {}, fills = {}, shared = base}, Library)
	for _, kind in ipairs(Library.kinds) do
		for id, entry in pairs(base[kind]) do self[kind][id] = entry end
	end
	for kind, specs in pairs(style.library or {}) do
		assert(KINDS[kind], style.title .. " library has unknown kind " .. tostring(kind))
		add(self, kind, specs, style.title)
	end
	return self
end

--- The entry of `kind` called `id`; an unknown id is an error naming it.
function Library:get(kind, id)
	local entry = self[kind][id]
	if not entry then error("unknown " .. kind:sub(1, -2) .. " " .. tostring(id), 0) end
	return entry
end

return Library
