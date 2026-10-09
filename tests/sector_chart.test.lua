_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Sectors = require("ui.sectors")
local bridge = require("AppKitNative")

-- Geometry: a donut is one Arc per sector, stroked at the ring's mid-radius.
local ring = Sectors.ring(180, 0.6)
t.assertEqual(ring.lineWidth, 36, "stroke width spans outer to inner radius")
t.assertEqual(ring.frame, 144, "arc frame is the mid-radius diameter")
t.assertEqual(Sectors.ring(100, 0).frame, 50, "a pie strokes from the center")
t.assertEqual(Sectors.ring(100, 2).lineWidth, 0.5, "the hole never swallows the ring")

-- SwiftUI starts at 12 o'clock and runs clockwise in data order.
local sectors, total = Sectors.layout({{value = 1, color = "systemBlue"}, {value = 3, color = "systemGreen"}}, 180, 0.6, 0)
t.assertEqual(total, 4, "values sum to the chart total")
t.assertEqual(sectors[1].startAngle, -90, "the first sector starts at 12 o'clock")
t.assertEqual(sectors[1].endAngle, 0, "a quarter ends at 3 o'clock")
t.assertEqual(sectors[2].startAngle, 0, "the next sector continues clockwise")
t.assertEqual(sectors[2].endAngle, 270, "sectors close the circle")
t.assertEqual(sectors[2].fraction, 0.75, "fractions are shares of the total")

-- As in SwiftUI, each sector gives up the angular inset at each side, so
-- neighbours are twice it apart.
local inset = Sectors.layout({{value = 1}, {value = 1}}, 180, 0.6, 1)
local gap = inset[2].startAngle - inset[1].endAngle
t.expect(math.abs(math.rad(gap) * 54 - 2) < 1e-9, "an inset of 1 is a 2pt gap at the inner edge, so no separator is thinner")
local pie = Sectors.layout({{value = 1}, {value = 1}}, 180, 0, 1)
t.expect(math.abs(math.rad(pie[2].startAngle - pie[1].endAngle) * 45 - 2) < 1e-9, "a pie measures its gap at mid-radius")
local band = Sectors.band(200, 0.5, 1, 3)
t.expect(math.abs(band.lineWidth - (band.outer - band.inner)) < 1e-9, "a band spans its ring; the arcs' inset separates rings")
local twoRings = ns.SectorChart {fixedWidth = 200, fixedHeight = 200, innerRadius = 0.4,
	{__sectorMark = true, id = "a", value = 1}, {__sectorMark = true, id = "a1", parent = "a", ring = 2, value = 1}}
t.assertEqual(twoRings.subviews[1].inset, 2, "rings are separated by a 2pt gap, not a hairline")
local oneRing = ns.SectorChart {fixedWidth = 200, fixedHeight = 200, innerRadius = 0.4, angularInset = 1.5,
	{__sectorMark = true, id = "a", value = 1, cornerRadius = 4}, {__sectorMark = true, id = "b", value = 1}}
t.assertEqual(oneRing.subviews[1].inset, 3, "SwiftUI's 1.5 inset leaves 3pt between neighbours")
t.assertEqual(oneRing.subviews[1].cornerRadius, 4, "a mark rounds its own corners")
t.assertEqual(oneRing.subviews[2].cornerRadius, 0, "and only its own")
-- A sector is filled: its ink is the band of its share less half the inset
-- at each parallel edge, so the gap does not widen outwards. Every arc
-- covers the chart, whose center is at 100.
local right = oneRing.subviews[1]:arcBounds()
t.expect(math.abs(right.origin.x - (100 + 1.5)) < 0.5, "the gap beside a half is the inset's half, in points: " .. right.origin.x)
t.expect(math.abs(right.size.height - (200 - 3)) < 0.5, "and the rim gives up the same half: " .. right.size.height)
t.expect(math.abs((inset[1].startAngle + inset[1].endAngle) / 2 - 0) < 1e-9, "insets keep each sector centred on its share")

local lone = Sectors.layout({{value = 0}, {value = 5}, {value = -2}}, 100, 0.5, 4)
t.assertEqual(#lone, 1, "zero and negative values occupy no angle")
t.assertEqual(lone[1].startAngle, lone[1].endAngle, "a lone sector is a closed ring without a gap")
local tiny = Sectors.layout({{value = 1000}, {value = 0.001}}, 100, 0.5, 4)
t.assertEqual(#tiny, 1, "a sector consumed by its inset draws nothing")
t.assertEqual(#Sectors.layout({}, 100, 0.5, 0), 0, "no data draws no sectors")

-- XML renders native arcs with the overlay centered over the hole.
local chart, refs = xml.render([[
<SectorChart id="chart" width="120" height="120" innerRadius="0.7" angularInset="1" accessibilityLabel="Storage">
  <SectorMark value="30" color="systemBlue" />
  <SectorMark value="10" color="systemPurple" />
  <SectorMark value="60" color="quaternaryLabel" />
  <Label id="total" text="40 GB" size="17" monospacedDigit="true" />
</SectorChart>]], {}, ns)
t.assertEqual(refs.chart, chart, "the chart is addressable by id")
t.assertEqual(#chart.subviews, 4, "three arcs and one overlay")
t.assertEqual(chart.subviews[1].stroke, "systemBlue", "sectors keep their colors in data order")
t.assertEqual(chart.subviews[3].stroke, "quaternaryLabel", "semantic colors pass through to the stroke")
t.assertEqual(chart.subviews[1].lineWidth, 18, "stroke width follows the inner radius")
t.assertEqual(chart.accessibilityLabel, "Storage", "VoiceOver reads the chart summary")
chart.size = ns.Size(120, 120); chart:layout(120)
t.assertEqual(chart.frame.size.width, 120, "the chart keeps its requested diameter")
local label = refs.total
t.expect(math.abs(label.frame.origin.x + label.frame.size.width / 2 - 60) < 1, "overlay is centered horizontally")
t.expect(math.abs(label.frame.origin.y + label.frame.size.height / 2 - 60) < 1, "overlay is centered vertically")
local arcFrame = chart.subviews[1].frame
t.expect(math.abs(arcFrame.origin.x + arcFrame.size.width / 2 - 60) < 1, "arcs are concentric with the chart")

local empty = xml.render([[<SectorChart width="80" height="80" innerRadius="0.5" />]], {}, ns)
t.assertEqual(#empty.subviews, 1, "an empty chart keeps its track ring")
t.assertEqual(empty.subviews[1].stroke, "quaternaryLabel", "the empty ring uses the quaternary label color")

-- Sunburst rings: children share their parent's angle by value.
local rings = Sectors.layout({
	{id = "a", value = 3}, {id = "b", value = 1},
	{id = "a1", parent = "a", ring = 2, value = 2, opacity = 0.7}, {id = "a2", parent = "a", ring = 2, value = 1},
	{id = "orphan", parent = "missing", ring = 2, value = 5},
}, 200, 0.5, 0)
local byId = {}
for _, sector in ipairs(rings) do byId[sector.id] = sector end
t.assertEqual(byId.a.endAngle, 180, "the first ring spans the whole circle")
t.assertEqual(byId.a1.startAngle, -90, "a child starts where its parent starts")
t.assertEqual(byId.a2.endAngle, 180, "children fill their parent's angle")
t.expect(byId.a1.inner >= byId.a.outer, "the second ring sits outside the first")
t.assertEqual(byId.a1.alpha, 0.7, "marks carry their opacity")
t.assertEqual(byId.orphan, nil, "a child without a drawn parent is not drawn")
t.assertEqual(Sectors.hit(rings, 200, 100, 40).id, "a", "a point in the first ring hits its sector")
t.assertEqual(Sectors.hit(rings, 200, 190, 100).id, "a1", "a point in the second ring hits the child")
t.assertEqual(Sectors.hit(rings, 200, 100, 100), nil, "the hole hits nothing")

-- A parent's only child still gives up half a gap at each end, so the gap to
-- a cousin under the next parent is as wide as between siblings.
local lone = Sectors.layout({
	{id = "a", value = 1}, {id = "b", value = 1},
	{id = "a1", parent = "a", ring = 2, value = 1}, {id = "b1", parent = "b", ring = 2, value = 1}, {id = "b2", parent = "b", ring = 2, value = 1},
}, 200, 0.5, 2)
local lonely = {}
for _, sector in ipairs(lone) do lonely[sector.id] = sector end
local siblingGap = lonely.b2.startAngle - lonely.b1.endAngle
t.expect(lonely.a1.startAngle > lonely.a1.spanStart, "a lone child is inset from its parent's boundary")
t.expect(math.abs((lonely.b1.startAngle - lonely.a1.endAngle) - siblingGap) < 1e-9, "cousins are as far apart as siblings")
-- A closed first ring keeps the chart's start, and its children follow it.
local closed = Sectors.layout({{id = "a", value = 1}, {id = "a1", parent = "a", ring = 2, value = 1}, {id = "a2", parent = "a", ring = 2, value = 1}},
	200, 0.5, 0)
t.assertEqual(closed[1].spanStart, -90, "a lone ring starts where the chart starts")
t.assertEqual(closed[2].startAngle, -90, "its children start there too")
-- Children worth more than their parent are scaled into its angle.
local overflow = Sectors.layout({{id = "a", value = 1}, {id = "b", value = 1},
	{id = "a1", parent = "a", ring = 2, value = 2}, {id = "a2", parent = "a", ring = 2, value = 2}}, 200, 0.5, 0)
local over = {}
for _, sector in ipairs(overflow) do over[sector.id] = sector end
t.expect(math.abs(over.a2.endAngle - over.a.endAngle) < 1e-9, "overflowing children end at their parent's edge")

-- Interactive charts keep the hovered sector, fade the others, and report
-- selection.
local chosen, hoveredId, centered
local interactive = ns.SectorChart {fixedWidth = 200, fixedHeight = 200, innerRadius = 0.5,
	{__sectorMark = true, id = "a", value = 3, color = "systemBlue"},
	{__sectorMark = true, id = "b", value = 1, color = "systemGreen"},
	onSelect = function(id, count) chosen = {id, count} end,
	onHover = function(id) hoveredId = id end,
	onCenter = function() centered = true end}
local pointer = interactive.subviews[#interactive.subviews]
t.assertEqual(pointer.className, "LuaPointerView", "an interactive chart places a pointer view on top")
bridge._pointerSend(pointer, "hover", 100, 40)
t.assertEqual(hoveredId, "a", "hover names the sector under the pointer")
t.assertEqual(interactive.subviews[1].strokeAlpha, 1, "an opaque hovered sector keeps its opacity")
t.expect(interactive.subviews[2].strokeAlpha < 1, "so hover shows by fading the other sectors")
bridge._pointerSend(pointer, "hover")
t.assertEqual(interactive.subviews[1].strokeAlpha, 1, "leaving restores every sector")
t.assertEqual(interactive.subviews[2].strokeAlpha, 1, "including the faded ones")
local faded = ns.SectorChart {fixedWidth = 200, fixedHeight = 200, innerRadius = 0.5,
	{__sectorMark = true, id = "a", value = 3, color = "systemBlue", opacity = 0.5},
	{__sectorMark = true, id = "b", value = 1, color = "systemGreen", opacity = 0.5},
	onHover = function() end}
bridge._pointerSend(faded.subviews[#faded.subviews], "hover", 100, 40)
t.assertEqual(faded.subviews[1].strokeAlpha, 0.5, "a translucent hovered sector keeps its own opacity")
t.expect(faded.subviews[2].strokeAlpha < 0.5, "and the others recede below theirs")
-- In a sunburst the hovered sector keeps its lineage: the parent it sits in
-- and the children inside it. Siblings and cousins recede.
local burstHovered
local burst = ns.SectorChart {fixedWidth = 200, fixedHeight = 200, innerRadius = 0.3,
	{__sectorMark = true, id = "a", value = 1, color = "systemBlue"},
	{__sectorMark = true, id = "b", value = 1, color = "systemGreen"},
	{__sectorMark = true, id = "a1", parent = "a", ring = 2, value = 1, color = "systemBlue"},
	{__sectorMark = true, id = "a2", parent = "a", ring = 2, value = 1, color = "systemBlue"},
	{__sectorMark = true, id = "b1", parent = "b", ring = 2, value = 1, color = "systemGreen"},
	{__sectorMark = true, id = "a1x", parent = "a1", ring = 3, value = 1, color = "systemBlue"},
	onHover = function(id) burstHovered = id end}
local burstArcs = {}
for index, id in ipairs({"a", "b", "a1", "a2", "b1", "a1x"}) do burstArcs[id] = burst.subviews[index] end
local burstPointer = burst.subviews[#burst.subviews]
-- Moves the pointer across the chart until it rests on sector `id`.
local function hoverOn(id)
	for y = 0, 200, 2 do
		for x = 0, 200, 2 do
			bridge._pointerSend(burstPointer, "hover", x, y)
			if burstHovered == id then return end
		end
	end
	error("no point of the chart hovers " .. id)
end
hoverOn("a1")
t.assertEqual(burstArcs.a1.strokeAlpha, 1, "the hovered sector keeps its opacity")
t.assertEqual(burstArcs.a.strokeAlpha, 1, "its parent stays")
t.assertEqual(burstArcs.a1x.strokeAlpha, 1, "its child stays")
t.expect(burstArcs.a2.strokeAlpha < 1, "its sibling recedes")
t.expect(burstArcs.b.strokeAlpha < 1 and burstArcs.b1.strokeAlpha < 1, "another branch recedes")
hoverOn("a")
t.assertEqual(burstArcs.a2.strokeAlpha, 1, "hovering a first-ring sector keeps all its children")
t.expect(burstArcs.b1.strokeAlpha < 1, "but not another sector's")
bridge._pointerSend(burstPointer, "hover")
t.assertEqual(burstArcs.b1.strokeAlpha, 1, "leaving restores the whole chart")
bridge._pointerSend(pointer, "click", 100, 40, 1)
t.expect(chosen and chosen[1] == "a" and chosen[2] == 1, "clicking selects a sector")
bridge._pointerSend(pointer, "click", 100, 100, 1)
t.expect(centered, "clicking the hole calls onCenter")

-- Changed chart records replace the complete chart with final geometry.
local Template = require("ui.template")
local chartHost = ns.VStack {}
local chartTemplate = Template.new(chartHost, "tests/fixtures/sector_chart.etlua", ns)
local data = {label = "Used 1 GB", total = "1 GB", marks = {{id = "a", value = 1, color = "systemBlue"}, {id = "b", value = 2, color = "systemGreen"}}}
chartTemplate:update(data)
local mountedChart, oldArc = chartTemplate.refs.chart, chartTemplate.refs.chart.subviews[1]
chartTemplate:update(data)
t.assertEqual(chartTemplate.refs.chart, mountedChart, "unchanged data does not rebuild a chart")
data.total = "Current total"
chartTemplate:update(data)
t.assertEqual(chartTemplate.refs.chart, mountedChart, "unchanged marks keep the chart when its nested overlay changes")
t.assertEqual(chartTemplate.refs.total.text, "Current total", "mixed record and view children retain live native targets")
data.total = "Updated total"
chartTemplate:update(data)
t.assertEqual(chartTemplate.refs.total.text, "Updated total", "a second overlay update keeps its native refs intact")
chartTemplate:update({label = "Used 4 GB", total = "4 GB", marks = {{id = "a", value = 2, color = "systemBlue"}, {id = "b", value = 2, color = "systemGreen"}, {id = "c", value = 1, color = "systemRed"}}})
local changed = chartTemplate.refs.chart
t.expect(changed ~= mountedChart, "changed records create a fresh chart")
t.expect(changed.subviews[1] ~= oldArc, "a matching mark id does not carry an old arc into the new chart")
t.assertEqual(mountedChart.superview, nil, "the old chart is detached")
t.assertEqual(chartTemplate.refs.total.stringValue, "4 GB", "the new overlay shows its total immediately")
t.assertEqual(#changed.subviews, 4, "three arcs and the overlay")
t.assertEqual(changed.accessibilityLabel, "Used 4 GB", "the fresh chart has the current VoiceOver summary")
t.assertEqual(changed.subviews[1].layer.animationKeys, nil, "new arcs have no layer animations")
chartTemplate:update({label = "Empty", total = "0 GB", marks = {}})
t.assertEqual(chartTemplate.refs.chart.subviews[1].stroke, "quaternaryLabel", "empty data draws its own empty ring")
t.assertEqual(#chartTemplate.refs.chart.subviews, 2, "empty data removes previous sectors")

-- A scalable chart fills the room it is given and keeps its sectors in fixed
-- units: every arc fills the chart and draws its circle in those units, so
-- the rings grow with the view about one center, and pointer positions are
-- mapped back into the same geometry.
local function mark(id, value, ring, parent)
	return {__sectorMark = true, id = id, value = value, ring = ring, parent = parent, color = "systemBlue"}
end
local scalableHovered, scalableCentered
local scalable = ns.SectorChart {scalable = true, diameter = 360, innerRadius = 0.4,
	mark("a", 3), mark("b", 1), mark("a1", 1, 2, "a"), ns.Text {text = "Total"},
	onHover = function(id) scalableHovered = id end, onCenter = function() scalableCentered = true end}
local host = ns.VStack {alignment = "center", flexGrow = 1, scalable}
host.size = ns.Size(800, 500)
host:layout(800)
local first = scalable.subviews[1]
t.assertEqual(first.className, "LuaArcView", "a scalable chart draws flat arcs")
local arcWidth, arcHeight = first.frame.size.width, first.frame.size.height
t.expect(arcWidth > 360 and arcHeight > 360, "a scalable chart is not held to its geometry units: " .. arcWidth .. " x " .. arcHeight)
t.assertEqual(first.fitDiameter, 360, "its arcs draw in the chart's units")
local smallBounds = first:arcBounds()
t.expect(math.abs(smallBounds.size.width - smallBounds.size.height) < 1, "the rings keep their aspect in a wide view")
t.expect(math.abs(smallBounds.origin.x + smallBounds.size.width / 2 - arcWidth / 2) < 1, "and stay centered")
local smallScale = math.min(arcWidth, arcHeight) / 360
t.expect(math.abs(smallBounds.size.height - ((first.diameter + first.lineWidth) * smallScale - first.inset)) < 1,
	"the ring scales with the view, its gaps stay in points")
host.size = ns.Size(1200, 900)
host:layout(1200)
local largerWidth, largerHeight = first.frame.size.width, first.frame.size.height
t.expect(largerWidth > arcWidth and largerHeight > arcHeight, "a larger view gives a larger chart")
t.expect(first:arcBounds().size.width > smallBounds.size.width, "and larger rings")
local scalablePointer = scalable.subviews[#scalable.subviews]
t.assertEqual(scalablePointer.className, "LuaPointerView", "the pointer view stays on top")
local scale = math.min(largerWidth, largerHeight) / 360
-- a1 is the outer ring's first third of a, from 12 o'clock to 3 o'clock.
local outerMid = (Sectors.band(360, 0.4, 2, 2).inner + Sectors.band(360, 0.4, 2, 2).outer) / 2
bridge._pointerSend(scalablePointer, "hover", largerWidth / 2 + outerMid * scale * math.cos(math.rad(-45)),
	largerHeight / 2 + outerMid * scale * math.sin(math.rad(-45)))
t.assertEqual(scalableHovered, "a1", "the pointer lands in chart units")
bridge._pointerSend(scalablePointer, "click", largerWidth / 2, largerHeight / 2, 1)
t.expect(scalableCentered, "the view's center is the chart's hole")
-- Direct geometry changes and hover styling apply without layer motion.
first.startAngle, first.endAngle = 0, 90
t.assertEqual(first.endAngle, 90, "angle changes apply immediately")
t.assertEqual(first.layer.animationKeys, nil, "shape changes start no implicit or explicit animation")
bridge._pointerSend(scalablePointer, "hover")
t.assertEqual(first.layer.animationKeys, nil, "hover styling starts no animation")

-- UIKit composes the same chart from its own Arc and ZStack.
local file = assert(io.open("lua/embedded/UIKit.lua")); local uikit = file:read("*a"); file:close()
t.expect(uikit:find('require("ui.sectors").chart(UIKit, props)', 1, true) ~= nil, "UIKit shares the sector geometry")

-- A different level and hole are independent charts with fresh native views.
local top = {mark("a", 3), mark("b", 1), mark("a1", 2, 2, "a"), mark("a2", 1, 2, "a"), mark("b1", 1, 2, "b"), mark("a1x", 1, 3, "a1")}
local inside = {mark("a1", 2), mark("a2", 1), mark("a1x", 1, 2, "a1"), mark("a1y", 1, 2, "a1")}
local function sunburstOf(marks, props)
	local chart = {fixedWidth = 200, fixedHeight = 200, innerRadius = 0.3}
	for key, value in pairs(props or {}) do chart[key] = value end
	for _, record in ipairs(marks) do table.insert(chart, record) end
	return ns.SectorChart(chart)
end
local holeTemplate = Template.new(ns.VStack {}, "tests/fixtures/sector_sunburst.etlua", ns)
holeTemplate:update({hole = 0.3, level = "top", marks = top})
local holeChart = holeTemplate.refs.chart
holeTemplate:update({hole = 0.5, level = "a", marks = inside})
local insideChart = holeTemplate.refs.chart
t.expect(insideChart ~= holeChart, "a new level and radius create a fresh chart")
t.assertEqual(#insideChart.subviews, 4, "the new chart contains only the current level's arcs")
t.assertEqual(holeChart.superview, nil, "the previous level leaves the host")
t.assertEqual(insideChart.subviews[1].layer.animationKeys, nil, "the drilled level appears immediately")
holeTemplate:update({hole = 0.3, level = "top", marks = top})
t.expect(holeTemplate.refs.chart ~= holeChart and holeTemplate.refs.chart ~= insideChart, "going back builds another fresh chart")
t.assertEqual(#holeTemplate.refs.chart.subviews, 6, "going back restores the parent level's sectors")

-- The keyboard reaches an interactive chart: focus reports through onHover,
-- Return activates, and Delete goes back, which is not a click in the hole.
local keyed = {}
local keyChart = sunburstOf(top, {onSelect = function(id, count) keyed.selected = {id, count} end,
	onHover = function(id) keyed.focused = id end, onCenter = function() keyed.centered = true end,
	onBack = function() keyed.back = true end})
local keyPointer = keyChart.subviews[#keyChart.subviews]
t.expect(bridge._pointerSend(keyPointer, "key", "tab") and keyed.focused == "a", "tab focuses the largest sector")
bridge._pointerSend(keyPointer, "key", "right")
t.assertEqual(keyed.focused, "b", "arrows move between neighbours")
bridge._pointerSend(keyPointer, "key", "return")
t.expect(keyed.selected[1] == "b" and keyed.selected[2] == 2, "return activates the focused sector")
bridge._pointerSend(keyPointer, "key", "delete")
t.expect(keyed.back and not keyed.centered, "delete goes back without clicking the hole")
local holeOnly = sunburstOf(top, {onCenter = function() keyed.holeOnly = true end})
bridge._pointerSend(holeOnly.subviews[#holeOnly.subviews], "key", "delete")
t.expect(not keyed.holeOnly, "a chart with nowhere to go back to ignores delete")


-- A scalable chart's center content is in the chart's units: the total in the
-- hole grows with the rings, and a label that no longer fits shrinks.
local function centered(width, height)
	local chart, refs = xml.render([[<SectorChart scalable="true" diameter="360" innerRadius="0.7" flexGrow="1" maxWidth="infinity" maxHeight="infinity">
	<SectorMark value="1" color="systemBlue" />
	<Label id="total" text="640 GB" size="40" minimumScaleFactor="0.2" lines="1" />
</SectorChart>]], {}, ns)
	local host = ns.VStack {alignment = "center", flexGrow = 1, chart}
	host.size = ns.Size(width, height)
	host:layout(width)
	return refs.total.font.pointSize, refs.total.frame.size.width
end
local smallSize = centered(180, 180)
local largeSize, largeWidth = centered(360, 360)
t.expect(largeSize > smallSize * 1.5, "a larger chart sets its total larger: " .. smallSize .. " -> " .. largeSize)
t.expect(largeWidth <= 360 * 0.3 / math.sqrt(2) * 2 + 1, "and the total stays inside the hole")

os.exit(t.summary() and 0 or 1)
