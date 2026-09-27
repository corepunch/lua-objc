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
-- Rings are separated by a gap at least as wide as a sector gap would be at
-- 2pt; thinner separators render as dark hairlines on any backdrop.
-- A raised chart turns its first boundary to half past one, so under the
-- tilted camera the sectors start on a diagonal instead of a vertical seam
-- that the perspective foreshortens into a sliver. Its rings all stand the
-- same height: a taller inner ring's wall would run into the top of the ring
-- in front of it and the two would read as one.
local STYLE = { ringGap = 2, dimmedAlpha = 0.35, raisedStart = TOP + 45 }

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
			local sector = {id = mark.id, color = mark.color, label = mark.label, value = value,
				alpha = math.max(0, math.min(1, tonumber(mark.opacity) or 1)),
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
-- ring, parent}). `angularInset` is SwiftUI's point gap between neighbours,
-- converted to degrees at each ring's inner edge. Non-positive values occupy
-- no angle; a lone first-ring sector is a closed ring without a gap. Child
-- marks share their parent's angle by value; a remainder stays empty, and
-- children worth more than their parent are scaled down to fit its angle
-- rather than spilling into a neighbour's.
-- `start` is the first boundary in Arc degrees (12 o'clock by default).
function Sectors.layout(marks, diameter, innerRadius, angularInset, start)
	local rings, byRing = 1, {}
	for _, mark in ipairs(marks or {}) do
		local ring = math.max(1, math.floor(tonumber(mark.ring) or 1))
		rings = math.max(rings, ring)
		byRing[ring] = byRing[ring] or {}
		table.insert(byRing[ring], mark)
	end
	-- A stroked arc's gap is a wedge that narrows towards the center, so the
	-- inset is measured at the band's inner edge: like SwiftUI's inset shape,
	-- the separator is never thinner than `angularInset` anywhere. A pie
	-- (no hole) measures at mid-radius instead.
	local function gapFor(band)
		if (angularInset or 0) <= 0 or band.frame <= 0 then return 0 end
		local radius = band.inner > 0 and band.inner or band.frame / 2
		return math.deg(angularInset / radius)
	end
	local result, total = {}, 0
	for _, mark in ipairs(byRing[1] or {}) do
		if (tonumber(mark.value) or 0) > 0 then total = total + mark.value end
	end
	if total <= 0 then return result, total end
	local band = Sectors.band(diameter, innerRadius, 1, rings)
	local placed = {}
	for _, sector in ipairs(spread(byRing[1], start or TOP, 360, total, gapFor(band), 1, band)) do
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

-- Charts keep their marks, sectors and arcs so `Sectors.update` can move the
-- arcs to new values in place, as SwiftUI Charts does when its data changes,
-- instead of rebuilding the chart and replaying its entrance.
local charts = setmetatable({}, {__mode = "k"})

-- The arcs to draw: one per sector, or the empty ring in the quaternary
-- label color when no value is positive, so the chart keeps its shape.
local function arcSpecs(sectors, ring)
	if #sectors == 0 then
		return {{startAngle = TOP, endAngle = TOP, spanStart = TOP, spanEnd = TOP, inner = ring.inner, outer = ring.outer,
			lineWidth = ring.lineWidth, stroke = "quaternaryLabel", frame = ring.frame, alpha = 1, ring = 1}}
	end
	local specs = {}
	for _, sector in ipairs(sectors) do
		table.insert(specs, {startAngle = sector.startAngle, endAngle = sector.endAngle, lineWidth = sector.lineWidth,
			spanStart = sector.spanStart, spanEnd = sector.spanEnd, inner = sector.inner, outer = sector.outer,
			stroke = sector.color or "accent", frame = sector.frame, alpha = sector.alpha, ring = sector.ring})
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

-- A raised chart hands every sector to one SceneKit view as its whole share
-- (span) and band, plus one `gap` in points. Solids are not strokes, so the
-- view cuts parallel-sided gaps of that width between neighbours and between
-- rings alike, instead of the flat chart's wedges, which widen outwards. The
-- highlighted sector lifts out of the ring.
local function sceneSpecs(state, alphas, highlightedIndex)
	local result = {}
	local gap = math.max(STYLE.ringGap, state.angularInset or 0)
	for index, spec in ipairs(state.specs) do
		-- Only a band with a neighbour inside it gives up half a gap there;
		-- the hole keeps its radius.
		local inner = spec.ring > 1 and spec.inner + gap / 2 or spec.inner
		table.insert(result, {startAngle = spec.spanStart, endAngle = spec.spanEnd, color = spec.stroke,
			inner = inner, outer = math.max(inner, spec.outer - (spec.ring < state.rings and gap / 2 or 0)), gap = gap,
			height = state.depth,
			alpha = alphas and alphas[index] or spec.alpha, lift = index == highlightedIndex and 1 or 0})
	end
	return result
end

local function ringCount(sectors)
	local rings = 1
	for _, sector in ipairs(sectors) do rings = math.max(rings, sector.ring or 1) end
	return rings
end

-- The sector under a view point of a raised chart, seen through its tilted
-- camera, and the pointer on the flat chart: where the ray meets the top
-- face every sector shares.
local function sceneHit(state, x, y)
	local cx, cy = state.ns._sectorScenePoint(state.scene, x, y, state.depth)
	return cx and Sectors.hit(state.sectors, state.diameter, cx, cy), cx, cy
end

local function newArc(ns, spec)
	return ns.Arc {startAngle = spec.startAngle, endAngle = spec.endAngle, strokeAlpha = spec.alpha,
		lineWidth = spec.lineWidth, stroke = spec.stroke, width = spec.frame, height = spec.frame}
end

-- Builds the chart with the platform module `ns`. Array entries of `props` are
-- `SectorMark` records or overlay views centered on the chart, like SwiftUI's
-- `chartBackground` content in the hole. `onSelect(id, clickCount)`,
-- `onHover(id)` and `onCenter()` make it interactive; hovering dims the
-- other sectors. A positive `depth` draws raised sectors `depth`
-- points deep in a SceneKit view instead of flat arcs; the geometry, hit
-- testing and interaction are the same.
function Sectors.chart(ns, props)
	props = props or {}
	local diameter = math.min(props.fixedWidth or props.fixedHeight or 160,
		props.fixedHeight or props.fixedWidth or 160)
	local marks, overlays = splitChildren(props)
	local depth = math.max(0, tonumber(props.depth) or 0)
	local state = {ns = ns, diameter = diameter, innerRadius = props.innerRadius, angularInset = props.angularInset,
		marks = marks, arcs = {}, depth = depth}
	state.ring = Sectors.ring(diameter, props.innerRadius)
	state.start = depth > 0 and STYLE.raisedStart or TOP
	state.sectors = Sectors.layout(marks, diameter, props.innerRadius, props.angularInset, state.start)
	local stack = {alignment = "center", fixedWidth = diameter, fixedHeight = diameter}
	for key, value in pairs(props) do
		if type(key) == "string" and stack[key] == nil and key ~= "innerRadius" and key ~= "angularInset" and key ~= "depth"
			and key ~= "accessibilityLabel" and key ~= "onSelect" and key ~= "onHover" and key ~= "onCenter" and key ~= "dragItem" then
			stack[key] = value
		end
	end
	state.specs = arcSpecs(state.sectors, state.ring)
	state.rings = ringCount(state.sectors)
	if depth > 0 then
		assert(type(ns.SectorScene) == "function", "SectorChart depth needs a SectorScene view on this platform")
		state.scene = ns.SectorScene {width = diameter, height = diameter, sectors = sceneSpecs(state)}
		table.insert(stack, state.scene)
	else
		for index, spec in ipairs(state.specs) do
			state.arcs[index] = newArc(ns, spec)
			table.insert(stack, state.arcs[index])
		end
	end
	for _, overlay in ipairs(overlays) do table.insert(stack, overlay) end
	local interactive = props.onSelect or props.onHover or props.onCenter or props.dragItem
	if interactive and type(ns.PointerView) == "function" then
		local ChartKeys = require("ui.chartkeys")
		local highlighted
		-- Hovering or keyboard focus dims the other sectors; a typed filter
		-- dims sectors whose label does not match.
		local function restyle(animated)
			local alphas, highlightedIndex = {}, nil
			for index, sector in ipairs(state.sectors) do
				local alpha = sector.alpha
				if highlighted and sector ~= highlighted then alpha = alpha * STYLE.dimmedAlpha end
				if sector == highlighted then highlightedIndex = index end
				local mark = state.keys and state.keys:find(sector.id)
				if mark and not state.keys:matches(mark) then alpha = alpha * STYLE.dimmedAlpha end
				alphas[index] = alpha
				if state.arcs[index] then state.arcs[index].strokeAlpha = alpha end
			end
			if state.scene then
				ns._sectorSceneConfigure(state.scene, sceneSpecs(state, alphas, highlightedIndex), animated ~= false)
			end
		end
		state.restyle = restyle
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
			back = function() if props.onCenter then props.onCenter() end end,
			filtered = restyle,
		})
		state.unhighlight = function() highlighted = nil end
		-- The sector under a pointer, and the pointer in flat chart points.
		local function locate(x, y)
			if not (x and y) then return nil, x, y end
			if state.scene then return sceneHit(state, x, y) end
			return Sectors.hit(state.sectors, diameter, x, y), x, y
		end
		table.insert(stack, (ns.PointerView {width = diameter, height = diameter,
			onClick = function(_, x, y, count)
				local sector
				sector, x, y = locate(x, y)
				if sector then
					if props.onSelect then props.onSelect(sector.id, count) end
				elseif x and math.sqrt((x - diameter / 2) ^ 2 + (y - diameter / 2) ^ 2) < state.ring.inner then
					if props.onCenter then props.onCenter() end
				end
			end,
			onHover = function(_, x, y)
				local sector = locate(x, y)
				highlight(sector)
				if props.onHover then props.onHover(sector and sector.id or nil) end
			end,
			onDrag = props.dragItem and function(_, x, y)
				local sector = locate(x, y)
				return sector and props.dragItem(sector.id) or nil
			end,
			onKey = function(_, key) return state.keys:handle(key) end}))
	end
	local view = ns.ZStack(stack)
	if props.accessibilityLabel then view.accessibilityLabel = props.accessibilityLabel end
	charts[view] = state
	return view
end

-- Applies new `SectorMark` records to a chart built by `Sectors.chart`: arcs
-- keep their views and take the new angles, and arcs are added or removed at
-- the end of the ring, below the overlay. Inside an animation transaction
-- the changes animate. A raised chart reuses its SceneKit nodes the same
-- way. Returns false for a view this module did not build.
function Sectors.update(view, records)
	local state = charts[view]
	if not state then return false end
	local ns = state.ns
	local marks = splitChildren(records)
	state.marks = marks
	state.sectors = Sectors.layout(marks, state.diameter, state.innerRadius, state.angularInset, state.start)
	local specs = arcSpecs(state.sectors, state.ring)
	state.specs = specs
	state.rings = ringCount(state.sectors)
	if state.keys then
		state.keys.marks = marks
		state.unhighlight()
	end
	if state.scene then
		if state.restyle then state.restyle(false) else ns._sectorSceneConfigure(state.scene, sceneSpecs(state), false) end
		return true
	end
	for index, spec in ipairs(specs) do
		local arc = state.arcs[index]
		if arc then
			arc.fixedWidth, arc.fixedHeight = spec.frame, spec.frame
			arc.startAngle, arc.endAngle = spec.startAngle, spec.endAngle
			arc.lineWidth, arc.stroke, arc.strokeAlpha = spec.lineWidth, spec.stroke, spec.alpha
		else
			arc = newArc(ns, spec)
			state.arcs[index] = arc
			ns._motionInsert(view, arc, index)
		end
	end
	for index = #state.arcs, #specs + 1, -1 do
		ns._motionRemove(state.arcs[index])
		state.arcs[index] = nil
	end
	if state.restyle then state.restyle() end
	return true
end

return Sectors
