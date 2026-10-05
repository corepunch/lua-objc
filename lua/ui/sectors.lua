-- SwiftUI Charts `SectorMark` for both platforms, composed from native Arcs
-- in a ZStack. A ring of outer radius R and inner radius r is one Arc per
-- sector, centered on the ring's mid-radius with a line width of R - r. With
-- an `angularInset`, or a mark's `cornerRadius`, each Arc fills its sector as
-- SwiftUI's does: parallel-sided gaps of that many points between neighbours
-- and between rings, and rounded corners, both in points at any chart size.
-- Angles follow SwiftUI: the first sector starts at 12 o'clock and sectors
-- advance clockwise in data order.
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
-- Rings are separated by a gap of at least 2pt; thinner separators render
-- as dark hairlines on any backdrop.
-- Content in a donut's hole is offered the side of the square inscribed in
-- the hole, so a label with a minimum scale factor sizes itself to the hole.
-- Hovering fades every sector outside the hovered one's lineage to
-- `unfocusedAlpha` of its own opacity, the 0.3 of Apple's SectorMark
-- selection sample: emphasis by receding the rest works whatever opacity a
-- sector has, where brightening cannot raise a sector that is already
-- opaque. As in that sample on macOS, the change is not animated.
--   WWDC23 "Explore pie charts and interactivity in Swift Charts":
--     https://developer.apple.com/videos/play/wwdc2023/10037/
--   Its sample, "Visualizing your app's data" (StylesDetails.swift):
--     https://developer.apple.com/documentation/charts/visualizing-your-app-s-data
local STYLE = { ringGap = 2, dimmedAlpha = 0.35, unfocusedAlpha = 0.3, holeContent = 1 / math.sqrt(2) }

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
	return {inner = inner, outer = outer, lineWidth = width, frame = inner + outer}
end

-- Lays `marks` out clockwise over `span` degrees from `from`, each taking
-- its share of `total`. Only a lone mark spanning the whole circle is a
-- closed ring; every other sector, including a parent's only child, gives up
-- half a gap at each end, so the gap between cousins under different parents
-- is as wide as between siblings.
local function spread(marks, from, span, total, gapDegrees, ring, band)
	local result, visible = {}, 0
	for _, mark in ipairs(marks) do if (tonumber(mark.value) or 0) > 0 then visible = visible + 1 end end
	local closed = visible == 1 and span >= 360
	local cursor = from
	for _, mark in ipairs(marks) do
		local value = tonumber(mark.value) or 0
		if value > 0 then
			local sweep = value / total * span
			local drawn = sweep - gapDegrees
			local sector = {id = mark.id, parent = mark.parent, color = mark.color, label = mark.label, value = value,
				alpha = math.max(0, math.min(1, tonumber(mark.opacity) or 1)),
				cornerRadius = math.max(0, tonumber(mark.cornerRadius) or 0),
				fraction = value / total, ring = ring, inner = band.inner, outer = band.outer,
				lineWidth = band.lineWidth, frame = band.frame}
			if closed then
				sector.startAngle, sector.endAngle = from, from
				sector.spanStart, sector.spanEnd = from, from + 360
				table.insert(result, sector)
			elseif drawn > MINIMUM_SWEEP then
				sector.startAngle, sector.endAngle = cursor + gapDegrees / 2, cursor + gapDegrees / 2 + drawn
				sector.spanStart, sector.spanEnd = cursor, cursor + sweep
				table.insert(result, sector)
			end
			cursor = cursor + sweep
		end
	end
	return result
end

-- Computes sector angles and radii for `marks` ({id, value, color, label,
-- ring, parent}). `angularInset` is SwiftUI's: each sector gives up that
-- many points at each side, so neighbours are twice it apart (WWDC23 10037:
-- an inset of 1.5 makes a 3pt gap); the gap is converted to degrees at each
-- ring's inner edge. https://developer.apple.com/documentation/charts/sectormark Non-positive values occupy
-- no angle; a lone first-ring sector is a closed ring without a gap. Child
-- marks share their parent's angle by value; a remainder stays empty, and
-- children worth more than their parent are scaled down to fit its angle
-- rather than spilling into a neighbour's.
function Sectors.layout(marks, diameter, innerRadius, angularInset)
	local rings, byRing = 1, {}
	for _, mark in ipairs(marks or {}) do
		local ring = math.max(1, math.floor(tonumber(mark.ring) or 1))
		rings = math.max(rings, ring)
		byRing[ring] = byRing[ring] or {}
		table.insert(byRing[ring], mark)
	end
	-- A stroked arc's gap is a wedge that narrows towards the center, so the
	-- inset is measured at the band's inner edge: like SwiftUI's inset shape,
	-- the separator is never thinner than its points anywhere. A pie
	-- (no hole) measures at mid-radius instead.
	local function gapFor(band)
		if (angularInset or 0) <= 0 or band.frame <= 0 then return 0 end
		local radius = band.inner > 0 and band.inner or band.frame / 2
		return math.deg(2 * angularInset / radius)
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
			local children = 0
			for _, mark in ipairs(groups[parentId]) do children = children + math.max(0, tonumber(mark.value) or 0) end
			local share = math.max(parent.value, children)
			for _, sector in ipairs(spread(groups[parentId], parent.spanStart, span, share, gapFor(band), ring, band)) do
				table.insert(result, sector)
				if sector.id then next[sector.id] = sector end
			end
		end
		for id, sector in pairs(next) do placed[id] = sector end
	end
	return result, total
end

-- The sector under a point in the chart's top-left, y-down coordinates: the
-- one whose share of its ring holds it, so the pointer never falls into a
-- gap between neighbours. Returns nil for the hole and the outside.
function Sectors.hit(sectors, diameter, x, y)
	if x == nil or y == nil then return nil end
	local dx, dy = x - diameter / 2, y - diameter / 2
	local radius = math.sqrt(dx * dx + dy * dy)
	local angle = math.deg(math.atan(dy, dx))
	for _, sector in ipairs(sectors) do
		if radius >= sector.inner and radius <= sector.outer then
			if sector.spanEnd - sector.spanStart >= 360 then return sector end
			local relative = (angle - sector.spanStart) % 360
			if relative <= sector.spanEnd - sector.spanStart then return sector end
		end
	end
end

-- Chart state serves hit testing and hover emphasis for this chart only.
local charts = setmetatable({}, {__mode = "k"})

-- The arcs to draw: one per sector over its whole share, which the Arc's
-- inset separates from its neighbours, or the empty ring in the quaternary
-- label color when no value is positive, so the chart keeps its shape. Each
-- appears directly in its final geometry.
local function arcSpecs(sectors, ring)
	if #sectors == 0 then
		return {{startAngle = TOP, endAngle = TOP, lineWidth = ring.lineWidth, stroke = "quaternaryLabel",
			frame = ring.frame, alpha = 1, cornerRadius = 0}}
	end
	local specs = {}
	for _, sector in ipairs(sectors) do
		table.insert(specs, {startAngle = sector.spanStart, endAngle = sector.spanEnd, lineWidth = sector.lineWidth,
			stroke = sector.color or "accent", frame = sector.frame, alpha = sector.alpha, cornerRadius = sector.cornerRadius})
	end
	return specs
end

local function splitChildren(children)
	local marks, overlays = {}, {}
	for _, child in ipairs(children) do
		if type(child) == "table" and child.__sectorMark then
			table.insert(marks, child)
		else
			table.insert(overlays, child)
		end
	end
	return marks, overlays
end

-- Every arc fills the chart and draws its circle in the chart's units, so
-- the rings share one center and scale with the chart's view.
local function newArc(state, spec)
	local props = {startAngle = spec.startAngle, endAngle = spec.endAngle, lineWidth = spec.lineWidth, diameter = spec.frame,
		inset = state.inset, cornerRadius = spec.cornerRadius, stroke = spec.stroke, strokeAlpha = spec.alpha}
	props.fitDiameter = state.diameter
	for key, value in pairs(state.layerSize) do props[key] = value end
	return state.ns.Arc(props)
end

-- The points between neighbours: the chart's angular inset, and at least
-- the ring gap once a second ring needs separating from the first.
local function insetFor(state)
	local rings = 1
	for _, sector in ipairs(state.sectors) do rings = math.max(rings, sector.ring or 1) end
	-- An Arc's inset is the whole gap; SwiftUI's angular inset is each side's.
	local inset = 2 * math.max(0, tonumber(state.angularInset) or 0)
	return rings > 1 and math.max(inset, STYLE.ringGap) or inset
end

-- A point of the chart's view in chart units: the view's shorter side
-- spans the chart's diameter, centered.
local function toUnits(state, view, x, y)
	local size = view.frame.size
	local scale = math.min(size.width, size.height) / state.diameter
	if scale <= 0 then return nil, nil end
	return (x - size.width / 2) / scale + state.diameter / 2, (y - size.height / 2) / scale + state.diameter / 2
end

-- Builds the chart with the platform module `ns`. Array entries of `props` are
-- `SectorMark` records or overlay views centered on the chart, like SwiftUI's
-- `chartBackground` content in the hole. `onSelect(id, clickCount)`,
-- `onHover(id)`, `onCenter()` (a click in the hole) and `onBack()` (Delete,
-- up a level) make it interactive; the hovered sector, its parents and its
-- children keep their opacity while every other sector recedes, and
-- `Sectors.highlight` does the same from code.
-- `scalable = true` lays the sectors out in a fixed geometry of `diameter`
-- units (default 360) and lets the view take whatever room it is given: the
-- rings fill the view's narrower side, so the chart stays centered, keeps
-- its aspect and grows with the view. Pointer positions are mapped back into
-- those units.
function Sectors.chart(ns, props)
	props = props or {}
	local scalable = props.scalable == true
	local diameter = scalable and (tonumber(props.diameter) or 360)
		or math.min(props.fixedWidth or props.fixedHeight or 160, props.fixedHeight or props.fixedWidth or 160)
	local marks, overlays = splitChildren(props)
	local state = {ns = ns, diameter = diameter,
		-- Arcs and the pointer view cover the whole chart.
		layerSize = scalable and {fillWidth = true, fillHeight = true} or {width = diameter, height = diameter},
		angularInset = props.angularInset, arcs = {}}
	state.ring = Sectors.ring(diameter, props.innerRadius)
	state.sectors = Sectors.layout(marks, diameter, props.innerRadius, props.angularInset)
	state.inset = insetFor(state)
	local stack = {alignment = "center", fixedWidth = diameter, fixedHeight = diameter}
	-- A scalable chart's center content is in the chart's units too, so a
	-- total in the hole grows with the rings.
	if scalable then stack = {alignment = "center", fillWidth = true, fillHeight = true, fitDiameter = diameter} end
	for key, value in pairs(props) do
		if type(key) == "string" and stack[key] == nil and key ~= "scalable" and key ~= "diameter" and key ~= "innerRadius" and key ~= "angularInset"
			and key ~= "accessibilityLabel" and key ~= "onSelect" and key ~= "onHover" and key ~= "onCenter" and key ~= "onBack" and key ~= "dragItem" then
			stack[key] = value
		end
	end
	for index, spec in ipairs(arcSpecs(state.sectors, state.ring)) do
		state.arcs[index] = newArc(state, spec)
		table.insert(stack, state.arcs[index])
	end
	local hole = state.ring.inner * 2
	for _, overlay in ipairs(overlays) do
		if hole > 0 and overlay.maxWidth == nil then
			overlay.maxWidth = hole * STYLE.holeContent
		end
		table.insert(stack, overlay)
	end
	local interactive = props.onSelect or props.onHover or props.onCenter or props.onBack or props.dragItem
	if interactive and type(ns.PointerView) == "function" then
		local ChartKeys = require("ui.chartkeys")
		local highlighted
		-- Hovering or keyboard focus marks one sector: it and its lineage, the
		-- parents it sits in and the children inside it, keep their opacity
		-- and the rest recede. A typed filter also dims, marking sectors
		-- whose label does not match.
		local function lineage()
			if not highlighted then return nil end
			local byId, kept = {}, {[highlighted] = true}
			for _, sector in ipairs(state.sectors) do if sector.id then byId[sector.id] = sector end end
			local parent = highlighted.parent and byId[highlighted.parent]
			while parent and not kept[parent] do
				kept[parent] = true
				parent = parent.parent and byId[parent.parent]
			end
			-- Sectors are laid out ring by ring, so a parent is decided before its children.
			for _, sector in ipairs(state.sectors) do
				local parentSector = sector.parent and byId[sector.parent]
				if parentSector and parentSector.ring < sector.ring and kept[parentSector] and parentSector.ring >= highlighted.ring then
					kept[sector] = true
				end
			end
			return kept
		end
		local function restyle()
			local kept = lineage()
			for index, sector in ipairs(state.sectors) do
				local alpha = sector.alpha
				if kept and not kept[sector] then alpha = alpha * STYLE.unfocusedAlpha end
				local mark = state.keys and state.keys:find(sector.id)
				if mark and not state.keys:matches(mark) then alpha = alpha * STYLE.dimmedAlpha end
				if state.arcs[index] then state.arcs[index].strokeAlpha = alpha end
			end
		end
		local function highlight(sector)
			if sector == highlighted then return end
			highlighted = sector
			restyle()
		end
		local function sectorFor(id)
			for _, sector in ipairs(state.sectors) do if sector.id == id then return sector end end
		end
		state.keys = ChartKeys.new(marks, {
			focus = function(id)
				highlight(id and sectorFor(id))
				if props.onHover then props.onHover(id) end
			end,
			activate = function(id) if props.onSelect then props.onSelect(id, 2) end end,
			back = function() if props.onBack then props.onBack() end end,
			filtered = restyle,
		})
		state.highlight = function(id) highlight(id and sectorFor(id) or nil) end
		-- The sector under a pointer, and the pointer in chart units.
		local function locate(view, x, y)
			if not (x and y) then return nil, x, y end
			x, y = toUnits(state, view, x, y)
			return Sectors.hit(state.sectors, diameter, x, y), x, y
		end
		local pointer = {
			onClick = function(pointer, x, y, count)
				local sector
				sector, x, y = locate(pointer, x, y)
				if sector then
					if props.onSelect then props.onSelect(sector.id, count) end
				elseif x and math.sqrt((x - diameter / 2) ^ 2 + (y - diameter / 2) ^ 2) < state.ring.inner then
					if props.onCenter then props.onCenter() end
				end
			end,
			onHover = function(pointer, x, y)
				local sector = locate(pointer, x, y)
				highlight(sector)
				if props.onHover then props.onHover(sector and sector.id or nil) end
			end,
			onDrag = props.dragItem and function(pointer, x, y)
				local sector = locate(pointer, x, y)
				return sector and props.dragItem(sector.id) or nil
			end,
			onKey = function(_, key) return state.keys:handle(key) end}
		for key, value in pairs(state.layerSize) do pointer[key] = value end
		table.insert(stack, (ns.PointerView(pointer)))
	end
	local view = ns.ZStack(stack)
	if props.accessibilityLabel then view.accessibilityLabel = props.accessibilityLabel end
	charts[view] = state
	return view
end

-- Highlights the sector for mark `id` of an interactive chart as hovering it
-- would, or none for nil, so a list beside the chart can point at its sector.
-- Returns false for a view this module did not build or that takes no input.
function Sectors.highlight(view, id)
	local state = charts[view]
	if not (state and state.highlight) then return false end
	state.highlight(id)
	return true
end

return Sectors
