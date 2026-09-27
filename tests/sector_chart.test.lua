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
t.expect(math.abs((band.outer - band.inner) - band.lineWidth - 2) < 1e-9, "rings are separated by a 2pt gap, not a hairline")
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
	200, 0.5, 0, -45)
t.assertEqual(closed[1].spanStart, -45, "a lone ring starts where the chart starts")
t.assertEqual(closed[2].startAngle, -45, "its children start there too")
-- Children worth more than their parent are scaled into its angle.
local overflow = Sectors.layout({{id = "a", value = 1}, {id = "b", value = 1},
	{id = "a1", parent = "a", ring = 2, value = 2}, {id = "a2", parent = "a", ring = 2, value = 2}}, 200, 0.5, 0)
local over = {}
for _, sector in ipairs(overflow) do over[sector.id] = sector end
t.expect(math.abs(over.a2.endAngle - over.a.endAngle) < 1e-9, "overflowing children end at their parent's edge")

-- Interactive charts dim other sectors on hover and report selection.
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
t.assertEqual(interactive.subviews[1].strokeAlpha, 1, "the hovered sector stays opaque")
t.expect(interactive.subviews[2].strokeAlpha < 1, "other sectors dim")
bridge._pointerSend(pointer, "hover")
t.assertEqual(interactive.subviews[2].strokeAlpha, 1, "leaving restores every sector")
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

-- A positive depth draws raised sectors in SceneKit, all one height, starting at
-- half past one; the flat arcs are not built.
local raisedMarks = {
	{__sectorMark = true, id = "a", value = 3, color = "systemBlue"},
	{__sectorMark = true, id = "b", value = 1, color = "systemGreen"},
	{__sectorMark = true, id = "a1", parent = "a", ring = 2, value = 1, color = "systemBlue", opacity = 0.5},
}
local raisedHovered
local raised = ns.SectorChart {fixedWidth = 200, fixedHeight = 200, innerRadius = 0.4, depth = 10,
	raisedMarks[1], raisedMarks[2], raisedMarks[3], ns.Text {text = "Total"},
	onHover = function(id) raisedHovered = id end}
local scene = raised.subviews[1]
t.assertEqual(scene.className, "LuaSectorSceneView", "depth renders sectors in one SceneKit view")
t.assertEqual(raised.subviews[#raised.subviews].className, "LuaPointerView", "the pointer view stays on top")
local nodes = ns._sectorSceneNodes(scene)
t.assertEqual(#nodes, 3, "one solid per sector")
t.assertEqual(nodes[1].height, 10, "the inner ring is the chart's depth")
t.assertEqual(nodes[3].height, 10, "every ring stands the same height, so rings never run into each other")
t.assertEqual(nodes[1].z, 5, "solids stand on the floor")
t.assertEqual(nodes[1].chamfer, 0, "sectors have square edges")
t.assertEqual(nodes[3].alpha, 0.5, "mark opacity carries into the scene")
local raisedLayout = Sectors.layout({{value = 1}, {value = 1}}, 200, 0.4, 0, -45)
t.assertEqual(raisedLayout[1].startAngle, -45, "layout can start at another angle")
-- The tilted camera maps a pointer back onto the flat chart: the view's
-- center is over the hole, and a point low in the view hits the front of
-- the chart.
local cx, cy = ns._sectorScenePoint(scene, 100, 100, 10)
t.expect(cx and math.abs(cx - 100) < 1 and math.abs(cy - 100) < 20, "the view center unprojects near the chart center")
local _, frontY = ns._sectorScenePoint(scene, 100, 160, 10)
t.expect(frontY > 150, "a point below the center lands on the front of the chart")
local raisedPointer = raised.subviews[#raised.subviews]
bridge._pointerSend(raisedPointer, "hover", 100, 100)
t.assertEqual(raisedHovered, nil, "the hole hovers nothing")
-- a1 spans the first third of a, from half past one to half past four.
bridge._pointerSend(raisedPointer, "hover", 185, 100)
t.assertEqual(raisedHovered, "a1", "the outer ring hovers through the camera")
nodes = ns._sectorSceneNodes(scene)
t.expect(nodes[3].z > 5 and nodes[1].alpha < 1, "the hovered sector lifts and the others dim")
t.expect(Sectors.update(raised, {raisedMarks[1], raisedMarks[2]}), "a raised chart takes new marks")
t.assertEqual(#ns._sectorSceneNodes(scene), 2, "removed marks remove their solids")
t.assertEqual(raised.subviews[1], scene, "the scene view is kept")

-- UIKit composes the same chart from its own Arc and ZStack.
local file = assert(io.open("lua/embedded/UIKit.lua")); local uikit = file:read("*a"); file:close()
t.expect(uikit:find('require("ui.sectors").chart(UIKit, props)', 1, true) ~= nil, "UIKit shares the sector geometry")

os.exit(t.summary() and 0 or 1)
