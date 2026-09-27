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
t.expect(math.abs(math.rad(gap) * 72 - 2) < 1e-9, "angular inset is a point gap at the mid-radius")
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

-- UIKit composes the same chart from its own Arc and ZStack.
local file = assert(io.open("lua/embedded/UIKit.lua")); local uikit = file:read("*a"); file:close()
t.expect(uikit:find('require("ui.sectors").chart(UIKit, props)', 1, true) ~= nil, "UIKit shares the sector geometry")

os.exit(t.summary() and 0 or 1)
