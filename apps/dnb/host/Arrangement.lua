-- One track of the set, fully arranged before its first bar plays, after the
-- arrange window of Cubase or MTV Music Generator: a ruler of sections and
-- one lane per part, each lane a row of blocks that point at patterns.
--
--   {track = 3, start = 1040, length = 176,        -- set bar of its first bar; bars
--    sections = {{id = "intro", start = 0, length = 16, cycle = 0}, ...},
--    lanes = {{part = "kick", blocks = {{start = 8, length = 16, pattern = "kick.intro"}, ...}}, ...}}
--
-- Section and block starts count bars from the track's first bar. Blocks are
-- pure data (numbers and strings), so the composer, the timeline, tests and a
-- future editor all read the same plan; patterns hold the only code. Within
-- a lane blocks never overlap, and silence is the absence of a block.
local Arrangement = {}
Arrangement.__index = Arrangement

local function isData(value)
	local kind = type(value)
	if kind == "number" or kind == "string" or kind == "boolean" then return true end
	if kind ~= "table" or getmetatable(value) ~= nil then return false end
	for k, v in pairs(value) do
		if not (type(k) == "number" or type(k) == "string") or not isData(v) then return false end
	end
	return true
end

--- Checks the plan and returns it as an Arrangement. `patterns` maps
--- pattern ids to patterns; every block's pattern must exist and belong to
--- its lane's part. `order` lists the parts lanes are sorted by.
function Arrangement.new(fields, patterns, order)
	local self = setmetatable(fields, Arrangement)
	local where = "track " .. tostring(self.track)
	assert(math.type(self.length) == "integer" and self.length > 0, where .. " needs a whole number of bars")
	local cursor = 0
	for _, section in ipairs(self.sections) do
		assert(section.start == cursor and section.length > 0, where .. " sections must tile the track")
		cursor = section.start + section.length
	end
	assert(cursor == self.length, where .. " sections must cover every bar")
	local rank = {}
	for i, part in ipairs(order) do rank[part] = i end
	local seen = {}
	for _, lane in ipairs(self.lanes) do
		local part = lane.part
		assert(rank[part], where .. " has a lane for unknown part " .. tostring(part))
		assert(not seen[part], where .. " has two " .. part .. " lanes")
		seen[part] = true
		local stop = 0
		for _, block in ipairs(lane.blocks) do
			local name = string.format("%s %s block at bar %s", where, part, tostring(block.start))
			assert(isData(block), name .. " must be plain data")
			assert(math.type(block.start) == "integer" and math.type(block.length) == "integer" and block.length > 0,
				name .. " needs whole bars")
			assert(block.start >= stop, name .. " overlaps the block before it")
			assert(block.start + block.length <= self.length, name .. " runs past the track")
			local pattern = patterns[block.pattern]
			assert(pattern, name .. " plays unknown pattern " .. tostring(block.pattern))
			assert(pattern.part == part, name .. " plays " .. block.pattern .. ", a " .. pattern.part .. " pattern")
			stop = block.start + block.length
		end
	end
	table.sort(self.lanes, function(a, b) return rank[a.part] < rank[b.part] end)
	return self
end

--- The section holding track bar `pos`, and its index.
function Arrangement:sectionAt(pos)
	local sections = self.sections
	local lo, hi = 1, #sections
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if sections[mid].start <= pos then lo = mid else hi = mid - 1 end
	end
	return sections[lo], lo
end

--- The block of `lane` under track bar `pos`, or nil for silence.
function Arrangement.blockAt(lane, pos)
	local blocks = lane.blocks
	local lo, hi = 1, #blocks
	while lo <= hi do
		local mid = (lo + hi) // 2
		local block = blocks[mid]
		if pos < block.start then hi = mid - 1
		elseif pos >= block.start + block.length then lo = mid + 1
		else return block end
	end
end

function Arrangement:lane(part)
	for _, lane in ipairs(self.lanes) do
		if lane.part == part then return lane end
	end
end

--- Every block under track bar `pos`, by part.
function Arrangement:blocksAt(pos)
	local blocks = {}
	for _, lane in ipairs(self.lanes) do blocks[lane.part] = Arrangement.blockAt(lane, pos) end
	return blocks
end

--- Whether `part` plays anything in the section at index `i`.
function Arrangement:plays(part, i)
	local lane, section = self:lane(part), self.sections[i]
	if not lane then return false end
	for _, block in ipairs(lane.blocks) do
		if block.start < section.start + section.length and block.start + block.length > section.start then return true end
	end
	return false
end

return Arrangement
