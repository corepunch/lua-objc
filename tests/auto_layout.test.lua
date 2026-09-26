_G.__headless = true

-- Writes that change measured size schedule layout automatically; apps never
-- call layout(). One pass per run-loop turn; geometry reads flush first.

local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local xml = require("ui.xml")

local window = ns.Window { visible = false, width = 400, height = 300 }
local root, refs = xml.render([[
<VStack spacing="8" alignment="leading" maxWidth="infinity" maxHeight="infinity">
  <Label id="title" text="Short" />
  <Label id="banner" text="Banner" />
  <Label id="below" text="Below" />
  <HStack id="row" spacing="4">
    <Label id="left" text="A" />
    <Label id="right" text="B" />
  </HStack>
</VStack>]], {}, ns)
window:add(root)
window:layout()

local rightX = refs.right.frame.origin.x
refs.left.text = "A much longer leading label"
t.expect(bridge._pendingLayoutCount() > 0, "a text write marks its view for layout")
t.expect(refs.right.frame.origin.x > rightX, "a geometry read observes the relayout without layout()")
t.assertEqual(bridge._pendingLayoutCount(), 0, "reading geometry flushes pending layout")

refs.left.text = "A"
-- A run loop with no sources returns without sleeping; a timer keeps it
-- running long enough to reach the before-waiting observer, as in an app.
local fired = false
bridge._timerAfter(0.02, function() fired = true end)
for _ = 1, 20 do if fired then break end bridge._runLoopTick(0.01) end
t.assertEqual(bridge._pendingLayoutCount(), 0, "the run loop flushes pending layout before sleeping")

local belowY = refs.below.frame.origin.y
refs.banner.hidden = true
t.expect(refs.below.frame.origin.y ~= belowY, "hiding a view closes its gap")
refs.banner.hidden = false
t.assertEqual(refs.below.frame.origin.y, belowY, "showing it restores the gap")

refs.title.alphaValue = 0.5
refs.title.offsetX = 3
t.assertEqual(bridge._pendingLayoutCount(), 0, "paint-only writes never schedule layout")

refs.row:clearContainer()
t.expect(bridge._pendingLayoutCount() > 0, "removing children schedules layout")
refs.row:add((xml.render('<Label text="C" />', {}, ns)))
t.assertEqual(refs.row.frame.size.width > 0 and #refs.row.subviews, 1, "adding children lays out the container")

refs.title.text = "pending"
window:layout()
t.assertEqual(bridge._pendingLayoutCount(), 0, "an explicit layout satisfies pending work inside it")

-- A list that does not scroll is as tall as its rows.
local page, pageRefs = xml.render([[
<ScrollView id="page" maxWidth="infinity" maxHeight="infinity">
  <VStack maxWidth="infinity">
    <List id="short" scrollDisabled="true" header="false" rowHeight="30" maxWidth="infinity"><Column id="name" /></List>
    <List id="scrolling" header="false" rowHeight="30" height="90" maxWidth="infinity"><Column id="name" /></List>
  </VStack>
</ScrollView>]], {}, ns)
local sheet = ns.Window { visible = false, width = 400, height = 300 }
sheet:add(page)
sheet:layout()
local list, scrolling = pageRefs.short, pageRefs.scrolling
t.expect(list.scrollDisabled and not list.hasVerticalScroller, "scrollDisabled lists have no scroller")
local function rows(count)
	local data = {}
	for index = 1, count do table.insert(data, { name = "Row " .. index }) end
	return data
end
list:replaceRows(rows(5))
local fiveRows = list.frame.size.height
t.expect(fiveRows >= 150, "five rows set the list height")
list:replaceRows(rows(12))
t.expect(list.frame.size.height > fiveRows * 2, "more rows grow the list and the page scrolls instead")
t.expect(page.documentView.frame.size.height > page.contentSize.height, "the page overflows its viewport")
list:clearRows()
t.expect(list.frame.size.height < 5, "an empty list collapses")
list:addRow({ name = "One" })
t.expect(list.frame.size.height > 0 and list.frame.size.height < fiveRows, "one row is shorter than five")
scrolling:replaceRows(rows(20))
t.assertEqual(scrolling.frame.size.height, 90, "a scrolling list keeps its own height")
t.assertEqual(bridge._pendingLayoutCount(), 0, "row changes in a scrolling list never schedule layout")

-- Controllers no longer call layout(); source guards keep them from returning.
local function source(path)
	local file = assert(io.open(path)); local text = file:read("*a"); file:close(); return text
end
for _, path in ipairs({
	"apps/diskmap/Controller.lua", "apps/diskmap/controllers/ManagementController.lua",
	"apps/adventure-arena/controllers/SessionController.lua", "apps/studio/Controller.lua",
}) do
	t.expect(not source(path):find(":layout%(") and not source(path):find("_layout%("),
		path .. " relies on automatic layout")
end
t.expect(source("src/uikit/metatable.m"):find("uikit_invalidate_layout", 1, true) ~= nil,
	"UIKit property writes invalidate layout")

sheet:close()
window:close()
os.exit(t.summary() and 0 or 1)
