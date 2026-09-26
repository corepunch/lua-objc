-- SwiftUI Charts `SectorMark` for both platforms, composed from native Arc
-- strokes in a ZStack. A ring of outer radius R and inner radius r is one Arc
-- per sector, stroked at the ring's mid-radius with a line width of R - r, so
-- the chart needs no custom drawing class. Angles follow SwiftUI: the first
-- sector starts at 12 o'clock and sectors advance clockwise in data order.
local Sectors = {}

-- Arc angles are clockwise from east in a y-down view; 12 o'clock is -90.
local TOP = -90
-- Sectors thinner than this after the angular inset draw nothing, matching
-- SwiftUI, which drops a mark once its inset consumes it.
local MINIMUM_SWEEP = 0.1

-- Returns the stroke geometry for a chart `diameter` points wide whose hole is
-- `innerRadius` (0...1) of the outer radius. A pie (0) strokes from the center.
function Sectors.ring(diameter, innerRadius)
	local outer = math.max(0, diameter or 0) / 2
	local ratio = math.max(0, math.min(innerRadius or 0, 0.99))
	local inner = outer * ratio
	return {outer = outer, inner = inner, lineWidth = outer - inner, frame = outer + inner}
end

-- Computes sector angles for `marks` ({value, color, label}). `angularInset`
-- is SwiftUI's point gap between neighbours, converted to degrees at the ring's
-- mid-radius. Non-positive values occupy no angle; a lone sector is a closed
-- ring without a gap.
function Sectors.layout(marks, diameter, innerRadius, angularInset)
	local total = 0
	for _, mark in ipairs(marks or {}) do
		if (tonumber(mark.value) or 0) > 0 then total = total + mark.value end
	end
	local result = {}
	if total <= 0 then return result, total end
	local ring = Sectors.ring(diameter, innerRadius)
	local visible = 0
	for _, mark in ipairs(marks) do if (tonumber(mark.value) or 0) > 0 then visible = visible + 1 end end
	local gap = 0
	if visible > 1 and (angularInset or 0) > 0 and ring.frame > 0 then
		gap = math.deg((angularInset or 0) / (ring.frame / 2))
	end
	local cursor = TOP
	for _, mark in ipairs(marks) do
		local value = tonumber(mark.value) or 0
		if value > 0 then
			local sweep = value / total * 360
			local drawn = sweep - gap
			if visible == 1 then
				table.insert(result, {startAngle = TOP, endAngle = TOP, color = mark.color,
					label = mark.label, value = value, fraction = 1})
			elseif drawn > MINIMUM_SWEEP then
				table.insert(result, {startAngle = cursor + gap / 2, endAngle = cursor + gap / 2 + drawn,
					color = mark.color, label = mark.label, value = value, fraction = value / total})
			end
			cursor = cursor + sweep
		end
	end
	return result, total
end

-- Builds the chart with the platform module `ns`. Array entries of `props` are
-- `SectorMark` records or overlay views centered on the chart, like SwiftUI's
-- `chartBackground` content in the hole. With no positive values, the empty
-- ring is drawn in the quaternary label color so the chart keeps its shape.
function Sectors.chart(ns, props)
	props = props or {}
	local diameter = math.min(props.fixedWidth or props.fixedHeight or 160,
		props.fixedHeight or props.fixedWidth or 160)
	local marks, overlays = {}, {}
	for _, child in ipairs(props) do
		if type(child) == "table" and child.__sectorMark then
			table.insert(marks, child)
		else
			table.insert(overlays, child)
		end
	end
	local ring = Sectors.ring(diameter, props.innerRadius)
	local sectors = Sectors.layout(marks, diameter, props.innerRadius, props.angularInset)
	local stack = {alignment = "center", fixedWidth = diameter, fixedHeight = diameter}
	for key, value in pairs(props) do
		if type(key) == "string" and stack[key] == nil and key ~= "innerRadius"
			and key ~= "angularInset" and key ~= "accessibilityLabel" then
			stack[key] = value
		end
	end
	if #sectors == 0 then
		table.insert(stack, (ns.Arc {startAngle = TOP, endAngle = TOP, lineWidth = ring.lineWidth,
			stroke = "quaternaryLabel", width = ring.frame, height = ring.frame}))
	end
	for _, sector in ipairs(sectors) do
		table.insert(stack, (ns.Arc {startAngle = sector.startAngle, endAngle = sector.endAngle,
			lineWidth = ring.lineWidth, stroke = sector.color or "accent", width = ring.frame, height = ring.frame}))
	end
	for _, overlay in ipairs(overlays) do table.insert(stack, overlay) end
	local view = ns.ZStack(stack)
	if props.accessibilityLabel then view.accessibilityLabel = props.accessibilityLabel end
	return view
end

return Sectors
