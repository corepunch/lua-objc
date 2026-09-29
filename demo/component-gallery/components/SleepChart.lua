-- An app-local component: the stage chart from Health's sleep view. Each
-- `SleepStage` record is an interval in minutes after going to bed; stages
-- sit on their own row (awake at the top, deep at the bottom) and every
-- interval is a colored native view whose flex weight is its length, with
-- clear spacers of the gaps' lengths in between, so the rows line up at any
-- width.
--
-- The gallery's templates use it as `<SleepChart>`: the XML renderer finds
-- SleepChart.etlua in this app's components/ folder, beside views/.

local STYLE = { rowHeight = 18, rowSpacing = 4, labelWidth = 52, labelSize = 11, cornerRadius = 3 }

local STAGES = {
	{ id = "awake", label = "Awake", color = "systemOrange" },
	{ id = "rem", label = "REM", color = "systemCyan" },
	{ id = "core", label = "Core", color = "systemBlue" },
	{ id = "deep", label = "Deep", color = "systemIndigo" },
}

local SleepChart = {
	props = { duration = "num" },
	records = { SleepStage = { stage = "str", start = "num", ["end"] = "num" } },
}

-- Per stage, the pieces of its row in order: `{gap = minutes}` spacers and
-- `{interval = minutes}` bars. Intervals are clamped to the night and sorted
-- by start; the night lasts `duration` or until the last interval ends.
function SleepChart.rows(records, duration)
	local night = tonumber(duration) or 0
	for _, record in ipairs(records or {}) do night = math.max(night, tonumber(record["end"]) or 0) end
	local rows = {}
	for _, stage in ipairs(STAGES) do
		local intervals = {}
		for _, record in ipairs(records or {}) do
			local start = math.max(0, tonumber(record.start) or 0)
			local finish = math.min(night, tonumber(record["end"]) or 0)
			if record.stage == stage.id and finish > start then table.insert(intervals, { start = start, finish = finish }) end
		end
		table.sort(intervals, function(a, b) return a.start < b.start end)
		local pieces, cursor = {}, 0
		for _, interval in ipairs(intervals) do
			local start = math.max(cursor, interval.start)
			if start > cursor then table.insert(pieces, { gap = start - cursor }) end
			if interval.finish > start then table.insert(pieces, { interval = interval.finish - start }) end
			cursor = math.max(cursor, interval.finish)
		end
		if night > cursor then table.insert(pieces, { gap = night - cursor }) end
		table.insert(rows, { stage = stage, pieces = pieces })
	end
	return rows, night
end

function SleepChart.data(props, records)
	return { rows = SleepChart.rows(records, props.duration), style = STYLE }
end

return SleepChart
