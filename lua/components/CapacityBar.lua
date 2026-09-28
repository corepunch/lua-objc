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
local Component = require("ui.component")

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

local function segmentView(ns, segment)
	return ns.VStack { background = segment.color, flexGrow = segment.weight, flexBasis = 0, fillHeight = true }
end

function CapacityBar.build(self, ns)
	local height = self.layout.fixedHeight or STYLE.height
	local bar = Component.frame(self, { spacing = self.props.spacing or STYLE.spacing, fixedHeight = height,
		fillWidth = true, cornerRadius = height / 2, clipsToBounds = true })
	self.segments = {}
	for index, segment in ipairs(CapacityBar.segments(self.records, self.props.total)) do
		self.segments[index] = segmentView(ns, segment)
		table.insert(bar, self.segments[index])
	end
	return ns.HStack(bar)
end

-- A change keeps the segments and moves their weights, so the bar animates
-- inside a transaction; a different number of visible segments rebuilds.
function CapacityBar.accepts(self, props, records)
	return #CapacityBar.segments(records, props.total) == #self.segments
end

function CapacityBar.update(self, ns)
	self.view.spacing = self.props.spacing or STYLE.spacing
	for index, segment in ipairs(CapacityBar.segments(self.records, self.props.total)) do
		local view = self.segments[index]
		view.flexGrow = segment.weight
		view.backgroundColor = ns.Color(segment.color)
	end
end

return CapacityBar
