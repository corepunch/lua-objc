_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Component = require("ui.component")
local Template = require("ui.template")

local function near(actual, expected, message)
	t.expect(math.abs((actual or math.huge) - expected) < 0.5,
		message .. " (expected " .. expected .. ", got " .. tostring(actual) .. ")")
end

local function layout(view, width, height)
	view.size = ns.Size(width, height)
	view:layout(width)
end

-- ActivityRings: geometry is plain data.
local ActivityRings = require("components.ActivityRings")
t.assertEqual(ActivityRings.fraction({ value = 30, goal = 60 }), 0.5, "a ring's fraction is value over goal")
t.assertEqual(ActivityRings.fraction({ value = 0.4 }), 0.4, "without a goal the value is the fraction")
t.assertEqual(ActivityRings.fraction({ value = -3, goal = 10 }), 0, "negative values draw nothing")
t.assertEqual(ActivityRings.fraction({ value = 5, goal = 0 }), 1, "a zero goal is met by any value")
local rings = ActivityRings.layout({ { value = 1, goal = 4 }, { value = 3, goal = 2 }, { value = 0, goal = 1 } }, 100, 10, 2)
t.assertEqual(rings[1].frame, 90, "the outer ring strokes its centre line inside the frame")
t.assertEqual(rings[2].frame, 66, "inner rings step in by a line width and the spacing")
t.assertEqual(rings[1].lap.endAngle, 0, "a quarter ends at 3 o'clock")
t.assertEqual(rings[2].lap.startAngle, rings[2].lap.endAngle, "a met goal closes the lap")
t.assertEqual(rings[2].overlap.endAngle, 90, "the second lap shows how far past the goal")
t.assertEqual(rings[1].overlap.alpha, 0, "no second lap below the goal")
t.assertEqual(rings[3].lap.alpha, 0, "an empty ring hides its progress, not its track")
t.expect(not ActivityRings.layout({ {}, {}, {}, {}, {}, {} }, 40, 10, 2)[6].visible, "rings that no longer fit are hidden")
t.assertEqual(#ActivityRings.layout({}, 100), 0, "no records draw no rings")

local ringView, ringRefs = xml.render([[
<ActivityRings id="rings" width="120" height="120" lineWidth="12" accessibilityLabel="Move 50%">
  <ActivityRing value="200" goal="400" color="systemRed" />
  <ActivityRing value="45" goal="30" color="systemGreen" />
  <Label id="centre" text="50%" />
</ActivityRings>]], {}, ns)
t.assertEqual(ringRefs.rings, ringView, "the component is addressable by id")
t.assertEqual(#ringView.subviews, 7, "each ring is three native arcs, then the centre content")
t.assertEqual(ringView.subviews[1].className, "LuaArcView", "rings are native Arc views")
t.assertEqual(ringView.subviews[2].endAngle, 90, "progress runs clockwise from 12 o'clock")
t.assertEqual(ringView.subviews[2].lineCap, "round", "progress has round caps")
t.assertEqual(ringView.subviews[6].endAngle, 90, "the second lap overlaps the first")
t.assertEqual(ringView.accessibilityLabel, "Move 50%", "VoiceOver reads the summary")
layout(ringView, 120, 120)
local centre = ringRefs.centre.frame
near(centre.origin.x + centre.size.width / 2, 60, "centre content is centred horizontally")
near(ringView.subviews[4].frame.size.width, 120 - 12 - 2 * (12 + 2), "the inner ring's frame follows the layout")

-- CapacityBar: segments share the bar by value.
local CapacityBar = require("components.CapacityBar")
local segments = CapacityBar.segments({ { value = 30 }, { value = 0 }, { value = 20 } }, 100)
t.assertEqual(#segments, 3, "zero segments are dropped and the remainder is added")
t.expect(segments[3].remainder and segments[3].fraction == 0.5, "the remainder is the unused capacity")
local full = CapacityBar.segments({ { value = 80 }, { value = 40 } }, 100)
t.assertEqual(#full, 2, "an overfull bar has no remainder")
t.assertEqual(full[1].fraction, 80 / 120, "an overfull bar scales to the sum")
t.assertEqual(#CapacityBar.segments({}, 0), 0, "an empty bar with no capacity draws nothing")

local bar = xml.render([[
<CapacityBar total="100" accessibilityLabel="50 of 100 used">
  <CapacitySegment value="30" color="systemBlue" />
  <CapacitySegment value="20" color="systemPurple" />
</CapacityBar>]], {}, ns)
t.assertEqual(#bar.subviews, 3, "two segments and the remaining track")
layout(bar, 301, 12)
local w1, w2, w3 = bar.subviews[1].frame.size.width, bar.subviews[2].frame.size.width, bar.subviews[3].frame.size.width
near(w1 + w2 + w3, 299, "segments fill the bar less the two hairline gaps")
near(w1 / w3, 30 / 50, "segments are proportional to their values")
near(bar.subviews[1].frame.size.height, 12, "segments fill the bar's height")
t.assertEqual(bar.cornerRadius, 6, "the bar is a capsule")

-- BarChart: bar heights scale to the largest value or maxValue.
local BarChart = require("components.BarChart")
local heights = BarChart.heights({ { value = 10 }, { value = 5 }, { value = -2 } }, 60)
t.assertEqual(heights[1], 60, "the largest bar fills the plot")
t.assertEqual(heights[2], 30, "bars are proportional")
t.assertEqual(heights[3], 1, "a zero or negative bar keeps a hairline")
t.assertEqual(BarChart.heights({ { value = 10 } }, 60, 20)[1], 30, "maxValue fixes the scale")
t.assertEqual(BarChart.heights({ { value = 30 } }, 60, 20)[1], 60, "values above maxValue are capped")
t.assertEqual(BarChart.heights({ { value = 0 } }, 60)[1], 1, "an all-zero chart draws hairlines")

local chart = xml.render([[
<BarChart height="60" spacing="4">
  <BarMark value="10" />
  <BarMark value="5" />
  <BarMark value="5" />
</BarChart>]], {}, ns)
layout(chart, 308, 60)
near(chart.subviews[1].frame.size.width, 100, "bars share the width equally")
near(chart.subviews[2].frame.size.height, 30, "bars take their heights")
near(chart.subviews[2].frame.origin.y, chart.subviews[1].frame.origin.y, "bars stand on one baseline")

-- HeatmapGrid: levels and columns.
local HeatmapGrid = require("components.HeatmapGrid")
local levels = HeatmapGrid.levels({ { value = 0 }, { value = 1 }, { value = 5 }, { value = 10 } }, 4)
t.assertEqual(levels[1], 0, "zero is empty")
t.assertEqual(levels[2], 1, "any activity is at least level one")
t.assertEqual(levels[3], 2, "levels are shares of the largest value")
t.assertEqual(levels[4], 4, "the largest value is the top level")
local color, opacity = HeatmapGrid.style(0, 4, "systemGreen")
t.expect(color == "quaternaryLabel" and opacity == 1, "empty cells use the quaternary fill")
color, opacity = HeatmapGrid.style(4, 4, "systemGreen")
t.expect(color == "systemGreen" and opacity == 1, "the top level is the opaque tint")
t.expect(select(2, HeatmapGrid.style(1, 4)) < 1, "lower levels are fainter")
t.assertEqual(HeatmapGrid.columns(15, 7), 3, "cells wrap into columns of rows")
local cells = {}
for index = 1, 10 do table.insert(cells, ('<HeatmapCell value="%d" label="Day %d" />'):format(index % 3, index)) end
local grid = xml.render('<HeatmapGrid rows="7" cellSize="10" spacing="2">' .. table.concat(cells) .. '</HeatmapGrid>', {}, ns)
t.assertEqual(#grid.subviews, 2, "ten cells make two week columns")
t.assertEqual(#grid.subviews[2].subviews, 3, "the last column holds the remainder")
t.assertEqual(grid.subviews[1].subviews[1].accessibilityLabel, "Day 1", "cells carry their labels")
layout(grid, 22, 82)
near(grid.subviews[2].frame.origin.x, 12, "columns step by cell size and spacing")

-- Retained templates patch components in place, inside the transaction.
local host = ns.VStack {}
local template = Template.new(host, "tests/fixtures/components.etlua", ns)
template:update({ rings = { 5 }, total = 10, used = 5 })
local mountedRings, mountedBar = template.refs.rings, template.refs.bar
local firstSegment = mountedBar.subviews[1]
template:update({ rings = { 10, 2 }, total = 20, used = 8 })
t.expect(template.refs.rings == mountedRings, "new ring values keep the component's view")
t.assertEqual(#mountedRings.subviews, 6, "an added ring inserts its arcs in place")
t.assertEqual(mountedRings.subviews[2].startAngle, mountedRings.subviews[2].endAngle, "the first ring's lap closes")
t.expect(template.refs.bar == mountedBar and mountedBar.subviews[1] == firstSegment, "the bar keeps its segments")
t.assertEqual(firstSegment.flexGrow, 8, "segments take their new weights")
t.assertEqual(mountedBar.subviews[2].flexGrow, 12, "the remaining track shrinks")
t.assertEqual(mountedBar.accessibilityLabel, "8 of 20", "the summary updates in place")
template:update({ rings = { 10 }, total = 5, used = 5 })
t.expect(template.refs.bar ~= mountedBar, "a change the component declines rebuilds it")
t.assertEqual(#template.refs.rings.subviews, 3, "a removed ring removes its arcs in place")

-- Tags resolve from the nearest components/ folder, then lua/components/.
local gallery = Template.new(ns.VStack {}, "demo/component-gallery/views/Gallery.etlua", ns)
local Model = require("demo.component-gallery.Model")
local model = Model.new()
gallery:update(model:snapshot())
local sleep = gallery.refs.sleep
t.assertEqual(Component.instance(sleep).tag, "SleepChart", "an app's components/ folder defines tags")
local steps = gallery.refs.steps
model:advance()
gallery:update(model:snapshot())
t.expect(gallery.refs.steps == steps, "a new day moves the existing bars")

local SleepChart = require("demo.component-gallery.components.SleepChart")
local rows, night = SleepChart.rows({
	{ stage = "rem", start = 10, ["end"] = 20 }, { stage = "rem", start = 15, ["end"] = 30 },
	{ stage = "deep", start = 40, ["end"] = 35 }, { stage = "core", start = 50, ["end"] = 90 },
}, 60)
t.assertEqual(night, 90, "the night lasts until the last interval ends")
t.assertEqual(rows[2].pieces[1].gap, 10, "a row starts with the gap before its first interval")
t.assertEqual(rows[2].pieces[3].interval, 10, "overlapping intervals are clipped")
t.assertEqual(#rows[4].pieces, 1, "an inverted interval draws nothing")

-- Definitions are checked.
t.assertThrows(function() Component.define("VStack", { build = function() end }) end, "built-in tags cannot be redefined")
t.assertThrows(function() Component.define("BarChart", { build = function() end }, "another.module") end,
	"a second module cannot claim a component's tag")
t.assertThrows(function() Component.define("Broken", {}) end, "a component needs build")
-- BarChart is the bundled chart by now. A nearer module of the same name
-- is refused loudly; the tag never silently means another component.
local shadowed, shadowError = pcall(xml.renderFile, "tests/fixtures/shadowed.etlua", {}, ns)
t.expect(not shadowed and tostring(shadowError):find("<BarChart> is already defined by components.BarChart", 1, true),
	"a nearer module cannot take over a defined tag")
t.expect(Component.instance(xml.render('<BarChart><BarMark value="1" /></BarChart>', {}, ns)).bars ~= nil,
	"and the tag keeps its component")
local ok, err = pcall(xml.render, "<NoSuchComponent />", {}, ns)
t.expect(not ok and tostring(err):find("unknown tag <NoSuchComponent>", 1, true), "unknown tags still fail clearly")

os.exit(t.summary() and 0 or 1)
