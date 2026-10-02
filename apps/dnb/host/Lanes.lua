-- A track's lanes under construction: one lane to a channel, each a row of
-- blocks over the track's bars, as an arrange window holds clips. The
-- arranger (host/Canvas.lua) places blocks, cuts and automates them, and
-- `done()` hands the lanes to host/Arrangement.lua.
local Lanes = {}
Lanes.__index = Lanes

--- A builder for a track's lanes, one to a channel: `add` places blocks in
--- any order, `cut` and `automate` edit what is placed, and `done()` returns
--- the lanes as {part, blocks} (see host/Arrangement.lua). Blocks for a
--- role the track has no channel for are dropped, so the arranger can name
--- every role and a track plays the eight it has.
function Lanes.new(track)
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
		variant = block.variant, under = block.under, phase = block.phase,
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
--- 0 as closed as it goes); a drum block may play its `variant` ("light":
--- the groove without its extra layers, for the first and last bars).
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
	if automation then
		block.level, block.filter, block.keep = automation.level, automation.filter, automation.keep
		block.variant, block.under, block.phase = automation.variant, automation.under, automation.phase
	end
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

return Lanes
