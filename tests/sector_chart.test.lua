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

local inset = Sectors.layout({{value = 1}, {value = 1}}, 180, 0.6, 2)
local gap = inset[2].startAngle - inset[1].endAngle
t.expect(math.abs(math.rad(gap) * 54 - 2) < 1e-9, "angular inset is a point gap at the inner edge, so no separator is thinner")
local pie = Sectors.layout({{value = 1}, {value = 1}}, 180, 0, 2)
t.expect(math.abs(math.rad(pie[2].startAngle - pie[1].endAngle) * 45 - 2) < 1e-9, "a pie measures its inset at mid-radius")
local band = Sectors.band(200, 0.5, 1, 3)
t.expect(math.abs(band.lineWidth - (band.outer - band.inner)) < 1e-9, "a band spans its ring; the arcs' inset separates rings")
local twoRings = ns.SectorChart {fixedWidth = 200, fixedHeight = 200, innerRadius = 0.4,
	{__sectorMark = true, id = "a", value = 1}, {__sectorMark = true, id = "a1", parent = "a", ring = 2, value = 1}}
t.assertEqual(twoRings.subviews[1].inset, 2, "rings are separated by a 2pt gap, not a hairline")
local oneRing = ns.SectorChart {fixedWidth = 200, fixedHeight = 200, innerRadius = 0.4, angularInset = 3,
	{__sectorMark = true, id = "a", value = 1, cornerRadius = 4}, {__sectorMark = true, id = "b", value = 1}}
t.assertEqual(oneRing.subviews[1].inset, 3, "the angular inset separates neighbours")
t.assertEqual(oneRing.subviews[1].cornerRadius, 4, "a mark rounds its own corners")
t.assertEqual(oneRing.subviews[2].cornerRadius, 0, "and only its own")
-- A sector is filled: its ink is the band of its share less half the inset
-- at each parallel edge, so the gap does not widen outwards. The arc is its
-- mid-radius circle, 140pt wide, so the chart's center is at 70.
local right = oneRing.subviews[1]:arcBounds()
t.expect(math.abs(right.origin.x - (70 + 1.5)) < 0.5, "the gap beside a half is the inset's half, in points: " .. right.origin.x)
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

-- Interactive charts raise the hovered sector, leave the others alone, and
-- report selection.
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
t.assertEqual(interactive.subviews[1].strokeAlpha, 1, "the hovered sector is opaque")
t.assertEqual(interactive.subviews[2].strokeAlpha, 1, "other sectors do not dim")
bridge._pointerSend(pointer, "hover")
t.assertEqual(interactive.subviews[1].strokeAlpha, 1, "leaving restores every sector")
local faded = ns.SectorChart {fixedWidth = 200, fixedHeight = 200, innerRadius = 0.5,
	{__sectorMark = true, id = "a", value = 3, color = "systemBlue", opacity = 0.5},
	{__sectorMark = true, id = "b", value = 1, color = "systemGreen", opacity = 0.5},
	onHover = function() end}
bridge._pointerSend(faded.subviews[#faded.subviews], "hover", 100, 40)
t.assertEqual(faded.subviews[1].strokeAlpha, 0.75, "a flat chart moves the hovered sector halfway to opaque")
t.assertEqual(faded.subviews[2].strokeAlpha, 0.5, "and keeps the others at their own opacity")
bridge._pointerSend(pointer, "click", 100, 40, 1)
t.expect(chosen and chosen[1] == "a" and chosen[2] == 1, "clicking selects a sector")
bridge._pointerSend(pointer, "click", 100, 100, 1)
t.expect(centered, "clicking the hole calls onCenter")

-- New data moves the existing arcs, as SwiftUI Charts does, instead of
-- rebuilding the chart and replaying its entrance.
local Sectors = require("ui.sectors")
local live = ns.SectorChart {fixedWidth = 200, fixedHeight = 200, innerRadius = 0.5,
	{__sectorMark = true, id = "a", value = 1, color = "systemBlue"},
	{__sectorMark = true, id = "b", value = 1, color = "systemGreen"},
	onHover = function() end}
local firstArc, secondArc = live.subviews[1], live.subviews[2]
t.expect(Sectors.update(live, {{__sectorMark = true, id = "a", value = 3, color = "systemBlue"}, {__sectorMark = true, id = "b", value = 1, color = "systemGreen"}}),
	"a chart built here takes new marks")
t.expect(live.subviews[1] == firstArc and live.subviews[2] == secondArc, "arcs keep their views")
t.expect(firstArc.endAngle - firstArc.startAngle > secondArc.endAngle - secondArc.startAngle, "arcs take the new angles")
Sectors.update(live, {{__sectorMark = true, id = "a", value = 3, color = "systemBlue"}, {__sectorMark = true, id = "b", value = 1, color = "systemGreen"},
	{__sectorMark = true, id = "c", value = 1, color = "systemRed"}})
t.assertEqual(live.subviews[3].className, "LuaArcView", "a new mark adds an arc below the overlay")
t.assertEqual(live.subviews[#live.subviews].className, "LuaPointerView", "the pointer view stays on top")
Sectors.update(live, {})
t.assertEqual(live.subviews[1].stroke, "quaternaryLabel", "no data draws the empty ring")
t.assertEqual(live.subviews[2].className, "LuaPointerView", "extra arcs are removed")
t.expect(not Sectors.update(ns.ZStack {}, {}), "a view the chart module did not build is refused")

-- A retained template reconciles changed marks into the same chart.
local Template = require("ui.template")
local chartHost = ns.VStack {}
local chartTemplate = Template.new(chartHost, "tests/fixtures/sector_chart.etlua", ns)
chartTemplate:update({label = "Used 1 GB", total = "1 GB", marks = {{id = "a", value = 1, color = "systemBlue"}, {id = "b", value = 2, color = "systemGreen"}}})
local mountedChart = chartTemplate.refs.chart
chartTemplate:update({label = "Used 4 GB", total = "4 GB", marks = {{id = "a", value = 2, color = "systemBlue"}, {id = "b", value = 2, color = "systemGreen"}, {id = "c", value = 1, color = "systemRed"}}})
t.expect(chartTemplate.refs.chart == mountedChart, "changed marks keep the chart view")
t.assertEqual(chartTemplate.refs.total.stringValue, "4 GB", "the overlay updates in place")
t.assertEqual(#mountedChart.subviews, 4, "three arcs and the overlay")
t.assertEqual(mountedChart.accessibilityLabel, "Used 4 GB", "the VoiceOver summary updates in place")

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
t.expect(Sectors.update(scalable, {mark("a", 1), mark("b", 1)}), "a scalable chart takes new marks")
t.assertEqual(scalable.subviews[1], first, "keeping its arcs")
t.assertEqual(first.fitDiameter, 360, "which still draw in the chart's units")

-- Marks that arrive inside an animated transaction (a scan's new sizes)
-- appear where they belong: the arc is not grown from the size it was built
-- with, even though the hover restyle writes to it before layout places it.
local growing = ns.SectorChart {scalable = true, diameter = 360, innerRadius = 0.4, angularInset = 3,
	mark("a", 3), mark("b", 1), onHover = function() end}
local growingHost = ns.VStack {alignment = "center", flexGrow = 1, growing}
growingHost.size = ns.Size(600, 400)
growingHost:layout(600)
ns.withAnimation(function() Sectors.update(growing, {mark("a", 3), mark("b", 1), mark("c", 1)}) end)
growingHost:layout(600)
local arrived = bridge._motionAnimations(growing.subviews[3])
t.expect(arrived.bounds == nil and arrived.position == nil, "a new sector does not fly in from its construction frame")
bridge._motionSettle()

-- UIKit composes the same chart from its own Arc and ZStack.
local file = assert(io.open("lua/embedded/UIKit.lua")); local uikit = file:read("*a"); file:close()
t.expect(uikit:find('require("ui.sectors").chart(UIKit, props)', 1, true) ~= nil, "UIKit shares the sector geometry")

-- New marks take the chart's arcs in place: a drill into a sector and back
-- out keeps the chart and its view, and a new hole applies with the marks.
local top = {mark("a", 3), mark("b", 1), mark("a1", 2, 2, "a"), mark("a2", 1, 2, "a"), mark("b1", 1, 2, "b"), mark("a1x", 1, 3, "a1")}
local inside = {mark("a1", 2), mark("a2", 1), mark("a1x", 1, 2, "a1"), mark("a1y", 1, 2, "a1")}
local function sunburstOf(marks, props)
	local chart = {fixedWidth = 200, fixedHeight = 200, innerRadius = 0.3}
	for key, value in pairs(props or {}) do chart[key] = value end
	for _, record in ipairs(marks) do table.insert(chart, record) end
	return ns.SectorChart(chart)
end
local hit
local drilled = sunburstOf(inside, {onCenter = function() hit = true end})
t.expect(Sectors.configure(drilled, {innerRadius = 0.5}), "a chart takes a new hole for its next marks")
Sectors.update(drilled, top)
t.assertEqual(#drilled.subviews, 7, "six arcs and the pointer view")
bridge._pointerSend(drilled.subviews[#drilled.subviews], "click", 100, 60)
t.expect(hit, "the center follows the new hole")

-- A retained template takes a new hole with its marks, keeping the chart.
local holeTemplate = Template.new(ns.VStack {}, "tests/fixtures/sector_sunburst.etlua", ns)
holeTemplate:update({hole = 0.3, level = "top", marks = top})
local holeChart = holeTemplate.refs.chart
holeTemplate:update({hole = 0.5, level = "a", marks = inside})
t.expect(holeTemplate.refs.chart == holeChart, "a new inner radius keeps the chart view")
t.assertEqual(#holeChart.subviews, 4, "with one arc per new mark")
bridge._motionSettle()

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

os.exit(t.summary() and 0 or 1)
