-- A segmented capacity bar like the storage bar in System Settings: one
-- colored segment per `CapacitySegment`, sized by its share of `total`, and
-- the unused remainder as a quaternary track. Segments are native views in
-- an HStack whose flex weights are the values, so the layout engine splits
-- whatever width the bar is offered and the bar expands like SwiftUI's
-- linear ProgressView.
--
--   <CapacityBar total="500" accessibilityLabel="320 GB of 500 GB used">
--     <CapacitySegment value="180" color="systemBlue" label="Apps" />
--     <CapacitySegment value="140" color="systemPurple" label="Documents" />
--   </CapacityBar>

-- The bar is a capsule `height` points tall with hairline gaps between
-- segments; the remainder uses the same quaternary fill as an empty chart.
local STYLE = { height = 12, spacing = 1, track = "quaternaryLabel" }

local CapacityBar = {
	props = { total = "num", spacing = "num" },
	records = { CapacitySegment = { value = "num", color = "str", label = "str" } },
}

-- The segments to draw, in order: records with a positive value, then the
-- remainder of `total` when the records do not fill it. Records worth more
-- than `total` are drawn at their share of the sum instead of overflowing.
-- Each entry carries its `weight` (flex share) and `fraction` of the bar.
function CapacityBar.segments(records, total)
	local sum, result = 0, {}
	for _, record in ipairs(records or {}) do
		local value = tonumber(record.value) or 0
		if value > 0 then
			sum = sum + value
			table.insert(result, { value = value, color = record.color or "accent", label = record.label })
		end
	end
	local capacity = math.max(sum, tonumber(total) or 0)
	if capacity > sum then
		table.insert(result, { value = capacity - sum, color = STYLE.track, remainder = true })
	end
	for _, segment in ipairs(result) do
		segment.weight = segment.value
		segment.fraction = capacity > 0 and segment.value / capacity or 0
	end
	return result
end

function CapacityBar.data(props, records, attrs)
	local height = tonumber(attrs.height) or STYLE.height
	return { segments = CapacityBar.segments(records, props.total), height = height, radius = height / 2,
		spacing = props.spacing or STYLE.spacing }
end

return CapacityBar
