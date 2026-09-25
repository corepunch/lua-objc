_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local xml = require("ui.xml")

for _, tag in ipairs({"List", "OutlineView"}) do
	local list = xml.render('<' .. tag .. ' header="false" rowHeight="44"><Column id="name" /></' .. tag .. '>', {}, ns)
	list:replaceRows({{id = "one", name = "First"}, {id = "two", name = "Second"}})
	list.hasVerticalScroller = false
	list.fixedHeight = 92
	local content = ns.VStack { spacing = 0, list, ns.Text { "Below", fixedHeight = 400 } }
	local page = ns.ScrollView { content = content }
	page.frameSize = ns.Size(400, 200)
	page:layout(400)
	for _, lines in ipairs({false, true}) do
		for _, delta in ipairs({-1, 1}) do
			t.assertEqual(bridge._testScrollWheel(list.documentView, delta, 0, lines), page,
				tag .. " forwards pixel and line wheel input in both directions")
		end
	end
	t.assertEqual(list.contentView.bounds.origin.y, 0, tag .. " keeps its rows stationary")
	list:selectRow(1)
	t.assertEqual(bridge._testScrollWheel(list.documentView, -1), page, tag .. " selected list forwards input")
	t.assertEqual(list.documentView.selectedRow, 1, tag .. " wheel input preserves selection")
	t.assertEqual(bridge._testScrollWheel(list.documentView, 0), page, tag .. " forwards phase-only events for fitted content")

	local rows = {}
	for i = 1, 20 do table.insert(rows, {id = tostring(i), name = "Row " .. i}) end
	list:replaceRows(rows)
	page:layout(400)
	t.expect(list.documentView.frame.size.height > list.contentView.bounds.size.height,
		tag .. " fixture now has scrollable rows despite hidden scroller")
	t.assertEqual(bridge._testScrollWheel(list.documentView, -1), list, tag .. " overflowing list keeps native scrolling")
	t.assertEqual(bridge._testScrollWheel(list.documentView, 1), list, tag .. " scrollable list keeps its native edge behavior")
	t.assertEqual(bridge._testScrollWheel(list.documentView, 0), list, tag .. " scrollable list keeps phase-only events")
	list.hasVerticalScroller = true
	t.assertEqual(bridge._testScrollWheel(list.documentView, -1), list, tag .. " visible scroller keeps native scrolling")
	list:replaceRows({})
	page:layout(400)
	t.assertEqual(bridge._testScrollWheel(list.documentView, -1), page, tag .. " empty list resumes forwarding")
	t.assertEqual(list.rowCount, 0, tag .. " wheel input does not mutate rows")
end

-- Forward through multiple nested containers, using the actual scrolling axis.
local inner = ns.ScrollView { content = ns.VStack { ns.Text { "Short", fixedHeight = 40 } }, fixedHeight = 80 }
local middle = ns.ScrollView { content = ns.VStack { inner }, fixedHeight = 80 }
local outer = ns.ScrollView { content = ns.VStack { middle, ns.Text { "Below", fixedHeight = 400 } } }
outer.frameSize = ns.Size(400, 200)
outer:layout(400)
t.assertEqual(bridge._testScrollWheel(inner.documentView, -1), outer, "short nested ScrollViews forward to the scrolling ancestor")
inner.documentView.frameSize = ns.Size(800, 40)
t.assertEqual(bridge._testScrollWheel(inner.documentView, 0, -1), inner, "horizontal overflow handles horizontal input locally")
t.assertEqual(bridge._testScrollWheel(inner.documentView, -1), outer, "horizontal overflow does not swallow vertical input")
t.assertEqual(bridge._testScrollWheel(inner.documentView, -1, -1), inner, "diagonal input with a scrollable axis stays native")

local standalone = ns.ScrollView { content = ns.Text { "Short" } }
standalone.frameSize = ns.Size(400, 200)
standalone:layout(400)
t.assertEqual(bridge._testScrollWheel(standalone.documentView, -1), standalone, "standalone scroll view keeps native handling")
standalone.frameSize = ns.Size(0, 0)
t.assertEqual(bridge._testScrollWheel(standalone.documentView, -1), standalone, "zero-size viewport is safe")
os.exit(t.summary() and 0 or 1)
