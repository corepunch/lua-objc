-- The timeline: the arrangement as the arrange window draws it. Blocks
-- slide right to left past a fixed playhead, one row per lane, under a ruler
-- of sections. This model turns arrangements into plain data: the rows, the
-- block instances the Metal program draws, the values it animates, and the
-- headline naming the next section change. It never touches views.
local Model = require("apps.dnb.Model")

local Timeline = {}

-- The window: bars in view and how many of them lie behind the playhead,
-- so the next section change shows well before it lands.
Timeline.window = {bars = 16, behind = 4}

-- Colour indices the shader tints by: a lane's family, or a section.
local COLOURS = {drums = 0, bass = 1, chords = 2, melody = 3, structure = 4,
	intro = 5, build = 6, drop = 7, breakdown = 8, outro = 9}
local RULER = -1 -- the row index of the section ruler
local SECTION_TITLES = {intro = "Intro", build = "Build-up", drop = "Drop", breakdown = "Breakdown", outro = "Outro"}

-- Floats per instance: row, first bar, length in bars, colour.
Timeline.stride = 4

--- The plans in view around set bar `n`: the playing track's and, once its
--- end is inside the window, the next one's.
function Timeline.plans(composer, n)
	local plan = composer:arrangement(composer:trackAt(n).index)
	local plans = {plan}
	if plan.start + plan.length - n <= Timeline.window.bars then
		table.insert(plans, composer:arrangement(plan.track + 1))
	end
	return plans
end

--- The parts with a lane in any of `plans`, in the timeline's part order.
function Timeline.rows(plans)
	local present = {}
	for _, plan in ipairs(plans) do
		for _, lane in ipairs(plan.lanes) do present[lane.part] = true end
	end
	local rows = {}
	for _, part in ipairs(Model.parts) do
		if present[part] then table.insert(rows, {part = part, family = Model.family[part]}) end
	end
	return rows
end

--- The draw's instance data: every section on the ruler and every block on
--- its row, at set bars, `Timeline.stride` floats each.
function Timeline.instances(plans, rows)
	local index = {}
	for i, row in ipairs(rows) do index[row.part] = i - 1 end
	local data = {}
	local function add(row, start, length, colour)
		table.insert(data, row)
		table.insert(data, start)
		table.insert(data, length)
		table.insert(data, colour)
	end
	for _, plan in ipairs(plans) do
		for _, section in ipairs(plan.sections) do
			add(RULER, plan.start + section.start, section.length, COLOURS[section.id])
		end
		for _, lane in ipairs(plan.lanes) do
			for _, block in ipairs(lane.blocks) do
				add(index[lane.part], plan.start + block.start, block.length, COLOURS[Model.family[lane.part]])
			end
		end
	end
	return data
end

--- The next section change after set bar `n` in `plans`: "Breakdown in 8
--- bars", or the next track's intro once the outro plays.
function Timeline.headline(plans, n)
	for p, plan in ipairs(plans) do
		for _, section in ipairs(plan.sections) do
			local start = plan.start + section.start
			if start > n then
				local bars = start - n
				local title = p > 1 and "Next track" or SECTION_TITLES[section.id]
				return string.format("%s in %d bar%s", title, bars, bars == 1 and "" or "s")
			end
		end
	end
	local plan = plans[#plans]
	local bars = plan.start + plan.length - n
	return string.format("Next track in %d bar%s", bars, bars == 1 and "" or "s")
end

--- The values the shader reads: the playhead (a set bar and its fraction),
--- its speed in bars per second to extrapolate between updates, the row
--- count, and the window.
function Timeline.values(playhead, barsPerSecond, rows)
	return {playhead, barsPerSecond, rows, Timeline.window.bars, Timeline.window.behind}
end

return Timeline
