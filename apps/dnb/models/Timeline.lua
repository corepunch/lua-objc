-- The timeline: the arrangement as the arrange window draws it. Clips
-- slide right to left past a fixed playhead, one row per track; a clip
-- shows the fade or filter sweep riding it, and the headline names the
-- section to come. This model turns arrangements into plain data:
-- the rows, the instances the Metal program draws, the values it animates,
-- and the headline naming the next section change. It never touches views.
local Model = require("apps.dnb.Model")
local Arrangement = require("apps.dnb.host.Arrangement")

local Timeline = {}

-- The window: bars in view and how many of them lie behind the playhead,
-- so the next section change shows well before it lands.
Timeline.window = {bars = 16, behind = 4}

local SECTION_TITLES = {intro = "Intro", build = "Build-up", drop = "Drop", breakdown = "Breakdown", outro = "Outro"}

-- Floats per instance: row, first bar, length in bars, colour (the
-- track's place in Model.tracks, from 0), its envelope at its first and
-- last bar (0…1, 1 full and open) and whether it thins from below, as a
-- high-pass does.
Timeline.stride = 7

local trackOf, trackIndex = {}, {}
for i, track in ipairs(Model.tracks) do
	trackIndex[track.id] = i
	for _, part in ipairs(track.parts) do trackOf[part] = track end
end

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

--- The tracks with a lane in any of `plans`, in the timeline's order.
function Timeline.rows(plans)
	local present = {}
	for _, plan in ipairs(plans) do
		for _, lane in ipairs(plan.lanes) do
			local track = trackOf[lane.part]
			if track then present[track.id] = true end
		end
	end
	local rows = {}
	for _, track in ipairs(Model.tracks) do
		if present[track.id] then table.insert(rows, {track = track.id, parts = track.parts}) end
	end
	return rows
end

-- A block's envelope `at` (0…1) of the way through it: its level times its
-- filter's opening.
local function envelope(block, at)
	local level, _, opening = Arrangement.automation(block, at)
	return level * (opening or 1)
end

--- The clips of a track in `plan`: the blocks of its first part, and of
--- each further part where no earlier one already has a clip, as
--- {start, length, from, to, thins}, in track bars.
function Timeline.clips(plan, parts)
	local clips, covered = {}, {}
	for _, part in ipairs(parts) do
		local lane = plan:lane(part)
		local placed = {}
		for _, block in ipairs(lane and lane.blocks or {}) do
			local cursor, stop = block.start, block.start + block.length
			local function place(from, to)
				if to <= from then return end
				table.insert(placed, {start = from, length = to - from,
					from = envelope(block, (from - block.start) / block.length),
					to = envelope(block, (to - block.start) / block.length),
					thins = block.filter ~= nil and block.filter.kind == "highpass"})
			end
			for _, clip in ipairs(covered) do
				if clip.start >= stop then break end
				place(cursor, math.min(clip.start, stop))
				cursor = math.max(cursor, clip.start + clip.length)
			end
			place(cursor, stop)
		end
		for _, clip in ipairs(placed) do
			table.insert(clips, clip)
			table.insert(covered, clip)
		end
		table.sort(covered, function(a, b) return a.start < b.start end)
	end
	table.sort(clips, function(a, b) return a.start < b.start end)
	return clips
end

local function add(data, row, start, length, colour, from, to, thins)
	table.insert(data, row)
	table.insert(data, start)
	table.insert(data, length)
	table.insert(data, colour)
	table.insert(data, from)
	table.insert(data, to)
	table.insert(data, thins)
end

local function colourOf(part) return trackIndex[trackOf[part].id] - 1 end

--- The arrangement's instances: every clip on its row, at set bars,
--- `Timeline.stride` floats each.
function Timeline.instances(plans, rows)
	local data = {}
	for _, plan in ipairs(plans) do
		for i, row in ipairs(rows) do
			for _, clip in ipairs(Timeline.clips(plan, row.parts)) do
				add(data, i - 1, plan.start + clip.start, clip.length, colourOf(row.parts[1]),
					clip.from, clip.to, clip.thins and 1 or 0)
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
