_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local config, refs = xml.render([[
<Window title="Intrinsic toolbar" width="1000" height="640">
  <Toolbar>
    <ToolbarItem id="summary" bordered="false">
      <HStack ref="summary" spacing="10" alignment="center">
        <SystemImage name="internaldrive" size="22" />
        <VStack spacing="2" alignment="leading">
          <Label ref="title" text="Diskmap" size="15" />
          <Label ref="capacity" text="245.1 GB total · 191.3 GB used · 53.8 GB available" size="11" lines="1" />
        </VStack>
      </HStack>
    </ToolbarItem>
    <ToolbarItem id="search"><SearchField ref="search" placeholder="Filter results…" /></ToolbarItem>
  </Toolbar>
  <Label text="Body" />
</Window>
]], {}, ns)
local window = ns.Window(config)
t.assertEqual(ns.ToolbarItem(window, "search").className, "NSSearchToolbarItem", "search uses the native toolbar item")
t.expect(refs.search.bezeled, "native search bezel remains enabled")
local initial = refs.summary.size
t.expect(refs.title.size.width >= refs.title.fittingSize.width, "title preserves native cell insets for the final glyph")
local labelHeight = refs.title.size.height + refs.capacity.size.height + 2
t.expect(initial.height >= labelHeight, "toolbar measures both text lines")
t.expect(initial.width >= refs.capacity.fittingSize.width + 32, "toolbar measures full subtitle and icon")
t.expect(refs.capacity.size.width >= refs.capacity.fittingSize.width, "subtitle is not compressed")
refs.capacity.text = "1000.0 GB total · 123.4 GB used · 876.6 GB available — additional information"
refs.summary:layout()
t.expect(refs.summary.size.width > initial.width, "toolbar grows when subtitle grows")
t.expect(refs.capacity.size.width >= refs.capacity.fittingSize.width, "updated subtitle remains readable")
refs.capacity.text = "Capacity unavailable"
refs.summary:layout()
t.expect(refs.summary.size.width < initial.width, "toolbar shrinks when subtitle shrinks")
t.assertEqual(refs.title.text, "Diskmap", "remeasurement preserves the title")
window:close()
os.exit(t.summary() and 0 or 1)
