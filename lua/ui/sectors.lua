-- SwiftUI Charts `SectorMark` for both platforms, composed from native Arc
-- strokes in a ZStack. A ring of outer radius R and inner radius r is one Arc
-- per sector, stroked at the ring's mid-radius with a line width of R - r, so
-- the chart needs no custom drawing class. Angles follow SwiftUI: the first
-- sector starts at 12 o'clock and sectors advance clockwise in data order.
--
-- Marks may sit on several rings (a sunburst): a mark with `ring = 2` and a
-- `parent` id is drawn inside its parent's angle, sized by its share of the
-- parent's value. Points map back to marks in Lua, so hover and selection use
-- the same geometry that drew the chart.
local Sectors = {}

-- Arc angles are clockwise from east in a y-down view; 12 o'clock is -90.
local TOP = -90
-- Sectors thinner than this after the angular inset draw nothing, matching
-- SwiftUI, which drops a mark once its inset consumes it.
local MINIMUM_SWEEP = 0.1
local STYLE = { ringGap = 1, dimmedAlpha = 0.35 }

-- Returns the stroke geometry for a chart `diameter` points wide whose hole is
-- `innerRadius` (0...1) of the outer radius. A pie (0) strokes from the center.
function Sectors.ring(diameter, innerRadius)
	local outer = math.max(0, diameter or 0) / 2
	local ratio = math.max(0, math.min(innerRadius or 0, 0.99))
	local inner = outer * ratio
	return {outer = outer, inner = inner, lineWidth = outer - inner, frame = outer + inner}
end

-- The band for `ring` (1 is innermost) when `rings` rings share the donut.
function Sectors.band(diameter, innerRadius, ring, rings)
	local whole = Sectors.ring(diameter, innerRadius)
	rings = math.max(1, rings or 1)
	local width = (whole.outer - whole.inner) / rings
	local inner = whole.inner + (ring - 1) * width
	local outer = inner + width
	local gap = rings > 1 and STYLE.ringGap or 0
	return {inner = inner, outer = outer, lineWidth = math.max(0, width - gap), frame = inner + outer}
end

local function spread(marks, from, span, total, gapDegrees, ring, band)
	local result, visible = {}, 0
	for _, mark in ipairs(marks) do if (tonumber(mark.value) or 0) > 0 then visible = visible + 1 end end
	local cursor = from
	for _, mark in ipairs(marks) do
		local value = tonumber(mark.value) or 0
		if value > 0 then
			local sweep = value / total * span
			local gap = visible > 1 and gapDegrees or 0
			local drawn = sweep - gap
			local sector = {id = mark.id, color = mark.color, label = mark.label, value = value,
				alpha = math.max(0, math.min(1, tonumber(mark.opacity) or 1)),
				fraction = value / total, ring = ring, inner = band.inner, outer = band.outer,
				lineWidth = band.lineWidth, frame = band.frame}
			if visible == 1 and span >= 360 then
				sector.startAngle, sector.endAngle = TOP, TOP
				sector.spanStart, sector.spanEnd = TOP, TOP + 360
				table.insert(result, sector)
			elseif drawn > MINIMUM_SWEEP then
				sector.startAngle, sector.endAngle = cursor + gap / 2, cursor + gap / 2 + drawn
				sector.spanStart, sector.spanEnd = cursor, cursor + sweep
				table.insert(result, sector)
			end
			cursor = cursor + sweep
		end
	end
	return result
end

-- Computes sector angles and radii for `marks` ({id, value, color, label,
-- ring, parent}). `angularInset` is SwiftUI's point gap between neighbours,
-- converted to degrees at each ring's mid-radius. Non-positive values occupy
-- no angle; a lone first-ring sector is a closed ring without a gap. Child
-- marks share their parent's angle by value; a remainder stays empty.
function Sectors.layout(marks, diameter, innerRadius, angularInset)
	local rings, byRing = 1, {}
	for _, mark in ipairs(marks or {}) do
		local ring = math.max(1, math.floor(tonumber(mark.ring) or 1))
		rings = math.max(rings, ring)
		byRing[ring] = byRing[ring] or {}
		table.insert(byRing[ring], mark)
	end
	local function gapFor(band)
		if (angularInset or 0) <= 0 or band.frame <= 0 then return 0 end
		return math.deg(angularInset / (band.frame / 2))
	end
	local result, total = {}, 0
	for _, mark in ipairs(byRing[1] or {}) do
		if (tonumber(mark.value) or 0) > 0 then total = total + mark.value end
	end
	if total <= 0 then return result, total end
	local band = Sectors.band(diameter, innerRadius, 1, rings)
	local placed = {}
	for _, sector in ipairs(spread(byRing[1], TOP, 360, total, gapFor(band), 1, band)) do
		table.insert(result, sector)
		if sector.id then placed[sector.id] = sector end
	end
	for ring = 2, rings do
		band = Sectors.band(diameter, innerRadius, ring, rings)
		local groups, order = {}, {}
		for _, mark in ipairs(byRing[ring] or {}) do
			if mark.parent and placed[mark.parent] then
				if not groups[mark.parent] then groups[mark.parent] = {}; table.insert(order, mark.parent) end
				table.insert(groups[mark.parent], mark)
			end
		end
		local next = {}
		for _, parentId in ipairs(order) do
			local parent = placed[parentId]
			local span = parent.spanEnd - parent.spanStart
			for _, sector in ipairs(spread(groups[parentId], parent.spanStart, span, parent.value, gapFor(band), ring, band)) do
				table.insert(result, sector)
				if sector.id then next[sector.id] = sector end
			end
		end
		for id, sector in pairs(next) do placed[id] = sector end
	end
	return result, total
end

-- The sector under a point in the chart's top-left, y-down coordinates.
-- Returns nil for the hole, the outside and gaps between sectors.
function Sectors.hit(sectors, diameter, x, y)
	if x == nil or y == nil then return nil end
	local dx, dy = x - diameter / 2, y - diameter / 2
	local radius = math.sqrt(dx * dx + dy * dy)
	local angle = math.deg(math.atan(dy, dx))
	for _, sector in ipairs(sectors) do
		if radius >= sector.inner and radius <= sector.outer then
			if sector.startAngle == sector.endAngle then return sector end
			local relative = (angle - sector.startAngle) % 360
			if relative <= sector.endAngle - sector.startAngle then return sector end
		end
	end
end

-- Builds the chart with the platform module `ns`. Array entries of `props` are
-- `SectorMark` records or overlay views centered on the chart, like SwiftUI's
-- `chartBackground` content in the hole. With no positive values, the empty
-- ring is drawn in the quaternary label color so the chart keeps its shape.
-- `onSelect(id, clickCount)`, `onHover(id)` and `onCenter()` make it
-- interactive; hovering dims the other sectors.
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
		if type(key) == "string" and stack[key] == nil and key ~= "innerRadius" and key ~= "angularInset"
			and key ~= "accessibilityLabel" and key ~= "onSelect" and key ~= "onHover" and key ~= "onCenter" and key ~= "dragItem" then
			stack[key] = value
		end
	end
	if #sectors == 0 then
		table.insert(stack, (ns.Arc {startAngle = TOP, endAngle = TOP, lineWidth = ring.lineWidth,
			stroke = "quaternaryLabel", width = ring.frame, height = ring.frame}))
	end
	local arcs = {}
	for index, sector in ipairs(sectors) do
		arcs[index] = ns.Arc {startAngle = sector.startAngle, endAngle = sector.endAngle, strokeAlpha = sector.alpha,
			lineWidth = sector.lineWidth, stroke = sector.color or "accent", width = sector.frame, height = sector.frame}
		table.insert(stack, arcs[index])
	end
	for _, overlay in ipairs(overlays) do table.insert(stack, overlay) end
	local interactive = props.onSelect or props.onHover or props.onCenter or props.dragItem
	if interactive and type(ns.PointerView) == "function" then
		local ChartKeys = require("ui.chartkeys")
		local highlighted, keys
		-- Hovering or keyboard focus dims the other sectors; a typed filter
		-- dims sectors whose label does not match.
		local function restyle()
			for index, arc in ipairs(arcs) do
				local sector, alpha = sectors[index], sectors[index].alpha
				if highlighted and sector ~= highlighted then alpha = alpha * STYLE.dimmedAlpha end
				local mark = keys and keys:find(sector.id)
				if mark and not keys:matches(mark) then alpha = alpha * STYLE.dimmedAlpha end
				arc.strokeAlpha = alpha
			end
		end
		local function highlight(sector)
			if sector == highlighted then return end
			highlighted = sector
			restyle()
		end
		local function sectorFor(id)
			for _, sector in ipairs(sectors) do if sector.id == id then return sector end end
		end
		keys = ChartKeys.new(marks, {
			focus = function(id)
				highlight(id and sectorFor(id))
				if props.onHover then props.onHover(id) end
			end,
			activate = function(id) if props.onSelect then props.onSelect(id, 2) end end,
			back = function() if props.onCenter then props.onCenter() end end,
			filtered = restyle,
		})
		table.insert(stack, (ns.PointerView {width = diameter, height = diameter,
			onClick = function(_, x, y, count)
				local sector = Sectors.hit(sectors, diameter, x, y)
				if sector then
					if props.onSelect then props.onSelect(sector.id, count) end
				elseif x and math.sqrt((x - diameter / 2) ^ 2 + (y - diameter / 2) ^ 2) < ring.inner then
					if props.onCenter then props.onCenter() end
				end
			end,
			onHover = function(_, x, y)
				local sector = Sectors.hit(sectors, diameter, x, y)
				highlight(sector)
				if props.onHover then props.onHover(sector and sector.id or nil) end
			end,
			onDrag = props.dragItem and function(_, x, y)
				local sector = Sectors.hit(sectors, diameter, x, y)
				return sector and props.dragItem(sector.id) or nil
			end,
			onKey = function(_, key) return keys:handle(key) end}))
	end
	local view = ns.ZStack(stack)
	if props.accessibilityLabel then view.accessibilityLabel = props.accessibilityLabel end
	return view
end

return Sectors
