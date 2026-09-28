-- A compact column chart after Swift Charts' `BarMark`: one bar per
-- `BarMark` record, equal widths, heights scaled to the largest value (or
-- `maxValue`). Bars are native views bottom-aligned in an HStack, so the
-- chart fills the width it is offered; its height is the plot height.
--
--   <BarChart height="64" accessibilityLabel="Steps this week">
--     <BarMark value="6200" label="Mon" />
--     <BarMark value="8400" label="Tue" color="systemOrange" />
--   </BarChart>
local Component = require("ui.component")

-- Bars keep a small corner radius like Swift Charts' default rounded bars;
-- a zero value still shows a hairline so the day reads as recorded.
local STYLE = { height = 64, spacing = 2, cornerRadius = 2, minimumHeight = 1 }

local BarChart = {
	props = { maxValue = "num", spacing = "num", tint = "str" },
	records = { BarMark = { value = "num", color = "str", label = "str" } },
}

-- Bar heights in points for a plot `height` tall. Negative values draw as
-- zero; `maxValue` fixes the scale so charts side by side compare.
function BarChart.heights(records, height, maxValue)
	local largest = tonumber(maxValue) or 0
	if largest <= 0 then
		for _, record in ipairs(records or {}) do largest = math.max(largest, tonumber(record.value) or 0) end
	end
	local result = {}
	for index, record in ipairs(records or {}) do
		local value = math.max(0, tonumber(record.value) or 0)
		local share = largest > 0 and math.min(1, value / largest) or 0
		result[index] = math.max(STYLE.minimumHeight, height * share)
	end
	return result
end

local function barView(ns, height, color)
	return ns.VStack { background = color, fixedHeight = height, flexGrow = 1, flexBasis = 0,
		cornerRadius = STYLE.cornerRadius }
end

local function colorOf(self, record)
	return record.color or self.props.tint or "accent"
end

function BarChart.build(self, ns)
	local height = self.layout.fixedHeight or STYLE.height
	self.height = height
	local chart = Component.frame(self, { spacing = self.props.spacing or STYLE.spacing, alignment = "bottom",
		fixedHeight = height, fillWidth = true })
	self.bars = {}
	for index, barHeight in ipairs(BarChart.heights(self.records, height, self.props.maxValue)) do
		self.bars[index] = barView(ns, barHeight, colorOf(self, self.records[index]))
		table.insert(chart, self.bars[index])
	end
	return ns.HStack(chart)
end

-- New values resize the existing bars; bars are added or removed at the end,
-- like a chart whose series grows by a day.
function BarChart.update(self, ns)
	self.view.spacing = self.props.spacing or STYLE.spacing
	local heights = BarChart.heights(self.records, self.height, self.props.maxValue)
	for index, barHeight in ipairs(heights) do
		local color = colorOf(self, self.records[index])
		local bar = self.bars[index]
		if bar then
			bar.fixedHeight = barHeight
			bar.backgroundColor = ns.Color(color)
		else
			self.bars[index] = barView(ns, barHeight, color)
			ns._motionInsert(self.view, self.bars[index], index)
		end
	end
	for index = #self.bars, #heights + 1, -1 do
		ns._motionRemove(self.bars[index])
		self.bars[index] = nil
	end
end

return BarChart
