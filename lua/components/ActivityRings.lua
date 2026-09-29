-- Concentric progress rings in the style of Apple's Activity rings: one ring
-- per `ActivityRing` record, outermost first. Each ring is three native Arc
-- strokes (a dimmed track, the progress and, past the goal, a second lap
-- over the first), so no custom drawing is involved. Progress starts at 12
-- o'clock and runs clockwise with round caps. ActivityRings.etlua draws
-- what `ActivityRings.layout` measures; view children sit in the middle.
--
--   <ActivityRings width="120" height="120" accessibilityLabel="Move 80%">
--     <ActivityRing value="320" goal="400" color="systemRed" />
--     <ActivityRing value="24" goal="30" color="systemGreen" />
--   </ActivityRings>

-- Arc angles are clockwise from east in a y-down view; 12 o'clock is -90.
-- Rings are this fraction of the diameter wide unless `lineWidth` is given,
-- and the track shows the ring's color at `trackAlpha`, like Activity.
local STYLE = { top = -90, lineWidthRatio = 0.12, spacing = 2, trackAlpha = 0.25, diameter = 120 }

local ActivityRings = {
	props = { lineWidth = "num", spacing = "num" },
	records = { ActivityRing = { value = "num", goal = "num", color = "str", label = "str" } },
}

-- The fraction of its goal a ring has reached; a missing goal means the
-- value is already a fraction. Never negative.
function ActivityRings.fraction(record)
	local value = math.max(0, tonumber(record.value) or 0)
	local goal = tonumber(record.goal)
	if goal == nil then return value end
	if goal <= 0 then return value > 0 and 1 or 0 end
	return value / goal
end

-- Stroke geometry for each record in a chart `diameter` points wide:
-- `frame` is the diameter of the ring's centre line, `lap` the progress arc
-- and `overlap` the second lap drawn once the goal is passed.
function ActivityRings.layout(records, diameter, lineWidth, spacing)
	diameter = math.max(0, diameter or 0)
	lineWidth = lineWidth or diameter * STYLE.lineWidthRatio
	spacing = spacing or STYLE.spacing
	local rings = {}
	for index, record in ipairs(records or {}) do
		local frame = diameter - lineWidth - 2 * (index - 1) * (lineWidth + spacing)
		local fraction = ActivityRings.fraction(record)
		local laps = math.floor(fraction)
		local remainder = fraction - laps
		local ring = { color = record.color or "accent", frame = math.max(0, frame), lineWidth = lineWidth,
			fraction = fraction, visible = frame > 0 }
		-- Equal angles close an Arc, so a whole lap is drawn closed and an
		-- empty ring hides its progress.
		ring.lap = { startAngle = STYLE.top, endAngle = fraction >= 1 and STYLE.top or STYLE.top + 360 * fraction,
			alpha = fraction > 0 and 1 or 0 }
		ring.overlap = { startAngle = STYLE.top, endAngle = STYLE.top + 360 * remainder,
			alpha = (laps >= 1 and remainder > 0) and 1 or 0 }
		table.insert(rings, ring)
	end
	return rings
end

-- The rings fill the smaller side of the frame the tag was given.
function ActivityRings.data(props, records, attrs)
	local width, height = tonumber(attrs.width), tonumber(attrs.height)
	local diameter = math.min(width or height or STYLE.diameter, height or width or STYLE.diameter)
	local rings = ActivityRings.layout(records, diameter, props.lineWidth, props.spacing)
	for _, ring in ipairs(rings) do
		ring.track = { startAngle = STYLE.top, endAngle = STYLE.top, alpha = STYLE.trackAlpha }
		for _, arc in ipairs({ ring.track, ring.lap, ring.overlap }) do
			if not ring.visible then arc.alpha = 0 end
		end
	end
	return { diameter = diameter, rings = rings }
end

return ActivityRings
