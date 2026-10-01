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

-- A scalable chart fills the room it is given and keeps its sectors in fixed
-- units: the camera frames the narrower side, so the wheel grows with its view
-- and pointer positions still land in the same geometry.
local scalableHovered
local scalable = ns.SectorChart {scalable = true, diameter = 360, innerRadius = 0.4, depth = 10,
	raisedMarks[1], raisedMarks[2], raisedMarks[3],
	onHover = function(id) scalableHovered = id end}
local host = ns.VStack {alignment = "center", flexGrow = 1, scalable}
host.size = ns.Size(800, 500)
host:layout(800)
local scalableScene = scalable.subviews[1]
local sceneWidth, sceneHeight = scalableScene.frame.size.width, scalableScene.frame.size.height
t.expect(sceneWidth > 360 and sceneHeight > 360, "a scalable chart is not held to its geometry units: " .. sceneWidth .. " x " .. sceneHeight)
t.assertEqual(scalableScene.fitRadius, 180, "the camera frames the chart's own radius, not the view's")
host.size = ns.Size(1200, 900)
host:layout(1200)
local largerWidth, largerHeight = scalableScene.frame.size.width, scalableScene.frame.size.height
t.expect(largerWidth > sceneWidth and largerHeight > sceneHeight, "a larger view gives a larger wheel")
local px, py = ns._sectorScenePoint(scalableScene, largerWidth / 2, largerHeight / 2, 0)
t.expect(px and math.abs(px - 180) < 1 and math.abs(py - 180) < 1, "the view center is the chart center on the floor, in sector units: " .. tostring(px) .. ", " .. tostring(py))
local _, flatFails = pcall(ns.SectorChart, {scalable = true, raisedMarks[1]})
t.expect(not _, "a scalable chart must be raised")

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
bridge._pointerSend(raisedPointer, "hover")
local resting = ns._sectorSceneNodes(scene)
bridge._pointerSend(raisedPointer, "hover", 185, 100)
nodes = ns._sectorSceneNodes(scene)
t.assertEqual(nodes[3].z, 5, "the hovered sector stays on the floor")
t.assertEqual(nodes[3].x, 0, "and does not slide out of its ring")
t.assertEqual(nodes[3].y, 0, "in either direction")
t.assertEqual(nodes[1].alpha, resting[1].alpha, "the other sectors keep their opacity")
-- It steps away from the backdrop: lighter in dark mode, deeper in light.
t.expect(nodes[3].luminance ~= resting[3].luminance, "the hovered sector stands out")
t.assertEqual(nodes[1].luminance, resting[1].luminance, "the others keep their color")
bridge._pointerSend(raisedPointer, "hover")
t.expect(Sectors.highlight(raised, "a"), "code can highlight a sector")
nodes = ns._sectorSceneNodes(scene)
t.expect(nodes[1].luminance ~= resting[1].luminance, "the named sector stands out")
t.assertEqual(nodes[3].luminance, resting[3].luminance, "and the pointer's sector rests")
t.assertEqual(nodes[1].z, 5, "without moving")
Sectors.highlight(raised)
t.assertEqual(ns._sectorSceneNodes(scene)[1].luminance, resting[1].luminance, "highlighting nothing rests every sector")
t.expect(not Sectors.highlight(ns.SectorChart {fixedWidth = 50, fixedHeight = 50, raisedMarks[1]}, "a"), "a chart without input highlights nothing")
t.expect(Sectors.update(raised, {raisedMarks[1], raisedMarks[2]}), "a raised chart takes new marks")
t.assertEqual(#ns._sectorSceneNodes(scene), 2, "removed marks remove their solids")
t.assertEqual(raised.subviews[1], scene, "the scene view is kept")
t.expect(scene.castsShadow, "a raised chart casts a shadow by default")
local unshadowed = ns.SectorChart {fixedWidth = 100, fixedHeight = 100, depth = 8, shadow = false, raisedMarks[1]}
t.expect(not unshadowed.subviews[1].castsShadow, "shadow = false drops the contact shadow")

-- UIKit composes the same chart from its own Arc and ZStack.
local file = assert(io.open("lua/embedded/UIKit.lua")); local uikit = file:read("*a"); file:close()
t.expect(uikit:find('require("ui.sectors").chart(UIKit, props)', 1, true) ~= nil, "UIKit shares the sector geometry")


-- A raised chart is its own animator: inside an animated transaction new
-- marks move its solids with the transaction's animation. Showing the inside
-- of one of its sectors, or going back out, opens that sector to the whole
-- circle; outside a transaction every change applies at once.
local function mark(id, value, ring, parent)
	return {__sectorMark = true, id = id, value = value, ring = ring, parent = parent, color = "systemBlue"}
end
local top = {mark("a", 3), mark("b", 1), mark("a1", 2, 2, "a"), mark("a2", 1, 2, "a"), mark("b1", 1, 2, "b"), mark("a1x", 1, 3, "a1")}
local inside = {mark("a1", 2), mark("a2", 1), mark("a1x", 1, 2, "a1"), mark("a1y", 1, 2, "a1")}
local function sunburstOf(marks, props)
	local chart = {fixedWidth = 200, fixedHeight = 200, innerRadius = 0.3, depth = 10}
	for key, value in pairs(props or {}) do chart[key] = value end
	for _, record in ipairs(marks) do table.insert(chart, record) end
	return ns.SectorChart(chart)
end
local sunburst = sunburstOf(top, {onSelect = function() end})
local burst = sunburst.subviews[1]
Sectors.update(sunburst, inside)
t.assertEqual(ns._sectorSceneTransitionState(burst), 0, "outside a transaction new marks show at once")
t.assertEqual(#ns._sectorSceneNodes(burst), 4, "as the new level's solids")
Sectors.update(sunburst, top)

local finished = false
ns.withAnimation(ns.Animation.easeInOut(0.3), function()
	t.expect(Sectors.configure(sunburst, {innerRadius = 0.5}), "a chart takes a new hole for its next marks")
	Sectors.update(sunburst, inside)
end, function() finished = true end)
-- a1, a2 and a1x move; a1y enters; a, b and b1 leave.
t.assertEqual(ns._sectorSceneTransitionState(burst), 7, "drilling in a transaction tweens the solids of both levels")
t.assertEqual(#ns._sectorSceneNodes(burst), 7, "one solid per pair while it runs")
Sectors.highlight(sunburst, "a1")
t.assertEqual(ns._sectorSceneTransitionState(burst), 7, "a highlight does not cut the transition short")
t.expect(not finished, "the transaction's completion waits for the chart")
bridge._motionSettle()
t.assertEqual(ns._sectorSceneTransitionState(burst), 0, "settling the transaction ends the transition")
t.expect(finished, "and runs its completion")
local settled = ns._sectorSceneNodes(burst)
t.assertEqual(#settled, 4, "leaving the new level's solids")
Sectors.highlight(sunburst)
t.expect(settled[1].luminance ~= ns._sectorSceneNodes(burst)[1].luminance, "with the restyle made while it ran")

local hit
local drilled = sunburstOf(inside, {onCenter = function() hit = true end})
ns.withAnimation(function()
	Sectors.configure(drilled, {innerRadius = 0.5})
	Sectors.update(drilled, top)
end)
t.assertEqual(ns._sectorSceneTransitionState(drilled.subviews[1]), 7, "going back out runs the same pairs in reverse")
bridge._motionSettle()
t.assertEqual(#ns._sectorSceneNodes(drilled.subviews[1]), 6, "and ends on the outer level")
bridge._pointerSend(drilled.subviews[#drilled.subviews], "click", 100, 60)
t.expect(hit, "the center follows the new hole")

-- Any other change moves each sector to its new shape; marks that come or go
-- open from, or close to, nothing.
ns.withAnimation(function() Sectors.update(drilled, {mark("a", 5), mark("b", 1), mark("c", 2)}) end)
t.assertEqual(ns._sectorSceneTransitionState(drilled.subviews[1]), 7, "new values move the sectors: a, b and c, and the four that leave")
bridge._motionSettle()
t.assertEqual(#ns._sectorSceneNodes(drilled.subviews[1]), 3, "ending on the new marks")
ns.withAnimation(nil, function() Sectors.update(drilled, top) end)
t.assertEqual(ns._sectorSceneTransitionState(drilled.subviews[1]), 0, "a transaction without animation applies at once")
bridge._motionOverrideReduceMotion(true)
ns.withAnimation(function() Sectors.update(drilled, inside) end)
t.assertEqual(ns._sectorSceneTransitionState(drilled.subviews[1]), 0, "so does Reduce Motion")
bridge._motionOverrideReduceMotion(nil)
bridge._motionSettle()

-- A retained template takes a new hole with its marks, keeping the chart,
-- and animates when its animation value changes.
local holeTemplate = Template.new(ns.VStack {}, "tests/fixtures/sector_sunburst.etlua", ns)
holeTemplate:update({hole = 0.3, level = "top", marks = top})
local holeChart = holeTemplate.refs.chart
holeTemplate:update({hole = 0.5, level = "a", marks = inside})
t.expect(holeTemplate.refs.chart == holeChart, "a new inner radius keeps the chart view")
t.assertEqual(ns._sectorSceneTransitionState(holeChart.subviews[1]), 7, "and the template's animation drills it in place")
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
