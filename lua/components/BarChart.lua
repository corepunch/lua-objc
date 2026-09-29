-- A compact column chart after Swift Charts' `BarMark`: one bar per
-- `BarMark` record, equal widths, heights scaled to the largest value (or
-- `maxValue`). Bars are native views bottom-aligned in an HStack, so the
-- chart fills the width it is offered; its height is the plot height.
--
--   <BarChart height="64" accessibilityLabel="Steps this week">
--     <BarMark value="6200" label="Mon" />
--     <BarMark value="8400" label="Tue" color="systemOrange" />
--   </BarChart>

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

function BarChart.data(props, records, attrs)
	local height = tonumber(attrs.height) or STYLE.height
	local bars = {}
	for index, barHeight in ipairs(BarChart.heights(records, height, props.maxValue)) do
		table.insert(bars, { height = barHeight, color = records[index].color or props.tint or "accent" })
	end
	return { bars = bars, height = height, spacing = props.spacing or STYLE.spacing, radius = STYLE.cornerRadius }
end

return BarChart
