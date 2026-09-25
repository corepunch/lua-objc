_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local xml = require("ui.xml")
local config, refs = xml.render([[
<Window title="Intrinsic toolbar" width="1000" height="640">
  <Toolbar>
    <ToolbarItem id="summary" bordered="false">
      <HStack id="summary" spacing="10" alignment="center">
        <SystemImage name="internaldrive" size="22" />
        <VStack spacing="2" alignment="leading">
          <Label id="title" text="Diskmap" size="15" />
          <Label id="capacity" text="245.1 GB total · 191.3 GB used · 53.8 GB available" size="11" lines="1" />
        </VStack>
      </HStack>
    </ToolbarItem>
    <ToolbarSpacer />
    <ToolbarItem id="settings" label="Settings" icon="gearshape" action="settings" />
    <ToolbarItem id="search"><SearchField id="search" placeholder="Filter results…" width="160" /></ToolbarItem>
  </Toolbar>
  <Label text="Body" />
</Window>
]], {actions = {settings = function() end}}, ns)
-- Inspect the native constructor directly: a later Lua property assignment is
-- too late for AppKit's first glass grouping (search expansion used to repair it).
local invoked = 0
config.toolbar[1].action = function() invoked = invoked + 1 end
local initialWindow = bridge._window("Initial toolbar", 1000, 640, false, true, config.toolbar, false)
local initialTitle = ns.ToolbarItem(initialWindow, "summary")
t.assertEqual(initialTitle.view, refs.summary, "custom title is installed before toolbar insertion")
t.assertEqual(initialTitle.bordered, false, "title opts out of glass before toolbar insertion")
bridge._invokeAction(initialTitle)
t.assertEqual(invoked, 1, "inline content preserves the toolbar item's action")
local initialSearch = ns.ToolbarItem(initialWindow, "search")
t.assertEqual(initialSearch.className, "NSSearchToolbarItem", "constructor recognizes inline search control")
t.assertEqual(initialSearch.searchField, refs.search, "search content is installed before toolbar insertion")
t.assertEqual(initialSearch.preferredWidthForSearchField, 160, "initial search uses the declared expansion width")
initialWindow:close()
config.toolbar[1].action = nil
local window = ns.Window(config)
window:layout()
local function assertActionsVisible()
	t.assertEqual(ns.ToolbarItem(window, "summary").bordered, false, "title keeps its native borderless policy")
	for _, identifier in ipairs({"settings", "search"}) do
		local item = ns.ToolbarItem(window, identifier)
		local view = identifier == "search" and item.searchField or item.view
		t.expect(view.superview ~= nil, identifier .. " is attached to its native toolbar host")
		t.expect(not view.hiddenOrHasHiddenAncestor, identifier .. " is not hidden by title styling")
	end
end
assertActionsVisible()
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
assertActionsVisible()
t.expect(refs.summary.size.width > initial.width, "toolbar grows when subtitle grows")
t.expect(refs.capacity.size.width >= refs.capacity.fittingSize.width, "updated subtitle remains readable")
refs.capacity.text = "Capacity unavailable"
refs.summary:layout()
assertActionsVisible()
t.expect(refs.summary.size.width < initial.width, "toolbar shrinks when subtitle shrinks")
t.assertEqual(refs.title.text, "Diskmap", "remeasurement preserves the title")
window:close()
os.exit(t.summary() and 0 or 1)
