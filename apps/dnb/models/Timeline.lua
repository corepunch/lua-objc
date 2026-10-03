-- The timeline: the arrangement as a tracker's song or an arrange window
-- draws it. Eight rows, one to a channel, named after what the playing
-- track has on them; clips slide right to left past a fixed playhead, a
-- clip shows the fade or filter sweep riding it, a meter beside the
-- playhead shows each channel's level, and the headline names the section
-- to come. This model turns arrangements into plain data: the rows, the
-- instances the Metal program draws, the values it animates, and the
-- headline. It never touches views.
local Model = require("apps.dnb.Model")
local Arrangement = require("apps.dnb.host.Arrangement")

local Timeline = {}

-- The window: bars in view and how many of them lie behind the playhead,
-- so the next section change shows well before it lands.
Timeline.window = {bars = 32, behind = 8}
Timeline.rowCount = Model.channels

-- A meter spans this many decibels below full level.
local METER = {range = 48}

local EVENT_TITLES = {valley = "Breakdown", ["return"] = "Full band", lift = "Key lift", riser = "Riser",
	drumsOut = "Drums out", halftime = "Half-time"}

-- Floats per instance: row, first bar, length in bars, colour (its role's
-- place in Model.roles, from 0), its envelope at its first and last bar
-- (0…1, 1 full and open) and whether it thins from below, as a high-pass
-- does.
Timeline.stride = 7

--- The first set bar in view with the playhead at set bar `n` and the view
--- scrolled `offset` bars ahead of it (behind it when negative).
function Timeline.left(n, offset)
	return n - Timeline.window.behind + (offset or 0)
end

--- The plans in view around set bar `n`, scrolled by `offset`: the playing
--- track's first, then every other track the window reaches, in order.
function Timeline.plans(composer, n, offset)
	local playing = composer:trackAt(n).index
	local left = Timeline.left(n, offset)
	local first = composer:trackAt(math.max(0, left)).index
	local last = composer:trackAt(math.max(0, left + Timeline.window.bars - 1)).index
	local plans = {composer:arrangement(playing)}
	for k = first, last do
		if k ~= playing then table.insert(plans, composer:arrangement(k)) end
	end
	return plans
end

--- How far the view may scroll from the playhead at set bar `n`: back to
--- the set's first bar (or no further than the playhead's own view, which
--- near the start shows a little before it), ahead to the end of the track
--- after the playing one. Returns the least and the greatest offset.
function Timeline.offsetRange(composer, n)
	local window = Timeline.window
	local playing = composer:trackAt(n).index
	local stop = composer:trackStart(playing + 2)
	local least = math.min(0, window.behind - n)
	return least, math.max(least, stop - window.bars + window.behind - n)
end

--- The offset after a scroll of `dx`, `dy` points over a strip `width`
--- points wide, kept within the range around set bar `n`. Content follows
--- the fingers: moving them left (or a wheel down) brings later bars in.
function Timeline.scroll(composer, n, offset, dx, dy, width)
	if width <= 0 then return offset end
	local least, greatest = Timeline.offsetRange(composer, n)
	local moved = offset - (dx + dy) / width * Timeline.window.bars
	return math.max(least, math.min(greatest, moved))
end

--- The set bar under point `x` of a strip `width` points wide, with the
--- playhead at `playhead` (a set bar and its fraction) and the view
--- scrolled by `offset`: the bar a click asks to play from.
function Timeline.barAt(playhead, offset, x, width)
	local bar = Timeline.left(playhead, offset) + math.max(0, math.min(1, x / width)) * Timeline.window.bars
	return math.max(0, math.floor(bar))
end

--- The eight rows, named after the channels of the playing track (the
--- first of `plans`): {index, role, name}. A track with fewer channels
--- leaves its last rows empty, with no role and no name.
function Timeline.rows(plans)
	local rows = {}
	local channels = plans[1].channels
	for index = 1, Timeline.rowCount do
		local channel = channels[index]
		rows[index] = {index = index, role = channel and channel.role or nil, name = channel and channel.name or ""}
	end
	return rows
end

-- A block's envelope `at` (0…1) of the way through it: its level times its
-- filter's opening.
local function envelope(block, at)
	local level, _, opening = Arrangement.automation(block, at)
	return level * (opening or 1)
end

--- The clips of a channel in `plan`, one to a block of its lane, as
--- {start, length, from, to, thins}, in track bars.
function Timeline.clips(plan, role)
	local clips = {}
	local lane = plan:lane(role)
	for _, block in ipairs(lane and lane.blocks or {}) do
		table.insert(clips, {start = block.start, length = block.length,
			from = envelope(block, 0), to = envelope(block, 1),
			thins = block.filter ~= nil and block.filter.kind == "highpass"})
	end
	return clips
end

--- The arrangement's instances: every clip on its channel's row, at set
--- bars, `Timeline.stride` floats each. A track's clips sit on its own
--- rows, so the next track's arrive on the rows it will rename.
function Timeline.instances(plans)
	local data = {}
	for _, plan in ipairs(plans) do
		for row, channel in ipairs(plan.channels) do
			for _, clip in ipairs(Timeline.clips(plan, channel.role)) do
				table.insert(data, row - 1)
				table.insert(data, plan.start + clip.start)
				table.insert(data, clip.length)
				table.insert(data, Model.roleIndex[channel.role] - 1)
				table.insert(data, clip.from)
				table.insert(data, clip.to)
				table.insert(data, clip.thins and 1 or 0)
			end
		end
	end
	return data
end

--- The next event of the playing track after set bar `n`: "Breakdown in 8
--- bars", or the next track once the last has passed.
function Timeline.headline(plans, n)
	local plan = plans[1]
	for _, event in ipairs(plan.events) do
		local bars = plan.start + event.bar - n
		if bars > 0 then
			return string.format("%s in %d bar%s", EVENT_TITLES[event.kind], bars, bars == 1 and "" or "s")
		end
	end
	local bars = plan.start + plan.length - n
	return string.format("Next track in %d bar%s", bars, bars == 1 and "" or "s")
end

--- A channel's peak (0…1 of full level) as a meter's length (0…1), over
--- the decibels a meter spans.
function Timeline.meter(peak)
	if not peak or peak <= 0 then return 0 end
	return math.max(0, math.min(1, 1 + 20 * math.log(peak, 10) / METER.range))
end

--- The values the shader reads: the playhead (a set bar and its fraction),
--- its speed in bars per second to extrapolate between updates, the row
--- count, the window, the display scale, how far the view is scrolled from
--- the playhead in bars, then for each row its meter (0…1) and its colour.
--- `rows` are Timeline.rows'; `levels` maps a role to its channel's peak.
function Timeline.values(playhead, barsPerSecond, rows, scale, levels, offset)
	local values = {playhead, barsPerSecond, #rows, Timeline.window.bars, Timeline.window.behind, scale or 1,
		offset or 0}
	for _, row in ipairs(rows) do
		table.insert(values, row.role and Timeline.meter(levels and levels[row.role]) or 0)
	end
	for _, row in ipairs(rows) do
		table.insert(values, row.role and Model.roleIndex[row.role] - 1 or 0)
	end
	return values
end

return Timeline
