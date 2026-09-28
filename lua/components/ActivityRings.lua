-- Concentric progress rings in the style of Apple's Activity rings: one ring
-- per `ActivityRing` record, outermost first. Each ring is three native Arc
-- strokes (a dimmed track, the progress and, past the goal, a second lap
-- over the first), so no custom drawing is involved. Progress starts at 12
-- o'clock and runs clockwise with round caps.
--
--   <ActivityRings width="120" height="120" accessibilityLabel="Move 80%">
--     <ActivityRing value="320" goal="400" color="systemRed" />
--     <ActivityRing value="24" goal="30" color="systemGreen" />
--   </ActivityRings>
local Component = require("ui.component")

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

local function diameterOf(self)
	local width, height = self.layout.fixedWidth, self.layout.fixedHeight
	return math.min(width or height or STYLE.diameter, height or width or STYLE.diameter)
end

local function arcs(ns, ring)
	local function arc(startAngle, endAngle, alpha)
		return ns.Arc { width = ring.frame, height = ring.frame, lineWidth = ring.lineWidth, stroke = ring.color,
			lineCap = "round", startAngle = startAngle, endAngle = endAngle, strokeAlpha = ring.visible and alpha or 0 }
	end
	return {
		arc(STYLE.top, STYLE.top, STYLE.trackAlpha),
		arc(ring.lap.startAngle, ring.lap.endAngle, ring.lap.alpha),
		arc(ring.overlap.startAngle, ring.overlap.endAngle, ring.overlap.alpha),
	}
end

local function restyle(views, ring)
	for _, arc in ipairs(views) do
		arc.fixedWidth, arc.fixedHeight = ring.frame, ring.frame
		arc.lineWidth, arc.stroke = ring.lineWidth, ring.color
	end
	views[1].strokeAlpha = ring.visible and STYLE.trackAlpha or 0
	views[2].startAngle, views[2].endAngle = ring.lap.startAngle, ring.lap.endAngle
	views[2].strokeAlpha = ring.visible and ring.lap.alpha or 0
	views[3].startAngle, views[3].endAngle = ring.overlap.startAngle, ring.overlap.endAngle
	views[3].strokeAlpha = ring.visible and ring.overlap.alpha or 0
end

function ActivityRings.build(self, ns)
	local diameter = diameterOf(self)
	self.diameter = diameter
	self.rings = {}
	local stack = Component.frame(self, { alignment = "center", fixedWidth = diameter, fixedHeight = diameter })
	for index, ring in ipairs(ActivityRings.layout(self.records, diameter, self.props.lineWidth, self.props.spacing)) do
		self.rings[index] = arcs(ns, ring)
		for _, arc in ipairs(self.rings[index]) do table.insert(stack, arc) end
	end
	-- View children (a total, a symbol) sit in the middle, like SwiftUI
	-- content layered over rings in a ZStack.
	for _, view in ipairs(self.content) do table.insert(stack, view) end
	return ns.ZStack(stack)
end

-- New values move the existing arcs, so a change animates like SwiftUI's
-- trim animation; added rings insert below the centre content.
function ActivityRings.update(self, ns)
	local layout = ActivityRings.layout(self.records, self.diameter, self.props.lineWidth, self.props.spacing)
	for index, ring in ipairs(layout) do
		if self.rings[index] then
			restyle(self.rings[index], ring)
		else
			self.rings[index] = arcs(ns, ring)
			for offset, arc in ipairs(self.rings[index]) do
				ns._motionInsert(self.view, arc, (index - 1) * 3 + offset)
			end
		end
	end
	for index = #self.rings, #layout + 1, -1 do
		for _, arc in ipairs(self.rings[index]) do ns._motionRemove(arc) end
		self.rings[index] = nil
	end
end

return ActivityRings
