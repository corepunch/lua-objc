_G.__headless = true

-- A toolbar's content follows state as in SwiftUI: the window template says
-- which button an item is, and `window:updateToolbar` applies the template
-- described again. The item keeps its place and its native button; only the
-- label, tooltip, symbol and action change. Its search field is never remade.

local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local xml = require("ui.xml")

local path = os.getenv("TMPDIR") .. "/toolbar_update_window.etlua"
local file = assert(io.open(path, "w"))
file:write([[
<Window title="Work" width="600" height="400" visible="false">
  <Toolbar>
    <ToolbarItem id="back" label="Back" icon="chevron.left" action="back" />
    <% if running then %>
    <ToolbarItem id="work" label="Stop" icon="stop.circle" tooltip="Stop working" action="stop" />
    <% else %>
    <ToolbarItem id="work" label="Start" icon="arrow.clockwise" tooltip="Start working" action="start" />
    <% end %>
    <ToolbarSpacer />
    <ToolbarItem id="search" label="Search">
      <SearchField id="search" placeholder="Search" />
    </ToolbarItem>
  </Toolbar>
  <Label text="Content" />
</Window>]])
file:close()

local events = {}
local actions = {
	back = function() table.insert(events, "back") end,
	start = function() table.insert(events, "start") end,
	stop = function() table.insert(events, "stop") end,
}
local cfg, refs = xml.renderFile(path, {running = false, actions = actions}, ns)
local window = ns.Window(cfg)
local function item(id)
	for _, entry in ipairs(window.toolbar.items) do if entry.itemIdentifier == id then return entry end end
end
local function order()
	local ids = {}
	for _, entry in ipairs(window.toolbar.items) do table.insert(ids, entry.itemIdentifier) end
	return table.concat(ids, ",")
end
local before = order()
local button = item("work").view
t.assertEqual(item("work").label, "Start", "the item starts as the template's idle button")
bridge._invokeAction(button)
t.assertEqual(events[#events], "start", "the idle button runs its action")

-- Describing the template makes no view: the search item has none.
local described = xml.toolbarFile(path, {running = true, actions = actions})
t.assertEqual(#described, 4, "every toolbar item is described")
t.expect(described[4].view == nil, "a described item leaves its view child out")
t.assertEqual(type(described[2].action), "function", "a described action is bound")

window:updateToolbar(described)
t.assertEqual(order(), before, "the toolbar keeps its items in their places")
t.expect(item("work").view == button, "the item keeps its native button")
t.assertEqual(item("work").label, "Stop", "the label follows state")
t.assertEqual(item("work").toolTip, "Stop working", "the tooltip follows state")
t.assertEqual(button.toolTip, "Stop working", "the button's tooltip follows state")
t.assertEqual(button.image.accessibilityDescription, "Stop", "the symbol follows state")
bridge._invokeAction(button)
t.assertEqual(events[#events], "stop", "the button runs the new action")
t.expect(item("search").searchField == refs.search, "the search field is the one the window was made with")
t.assertEqual(item("back").label, "Back", "unchanged items stay as they were")

window:updateToolbar(xml.toolbarFile(path, {running = false, actions = actions}))
t.assertEqual(item("work").label, "Start", "the item returns to its idle button")
bridge._invokeAction(button)
t.assertEqual(events[#events], "start", "and runs the idle action again")

-- Page changes insert/remove native items, preserving the search view and
-- every unchanged item. Selection changes also update validation in place.
local search = item("search")
refs.search.stringValue = "unsaved query"
local expanded = xml.toolbarFile(path, {running = false, actions = actions})
table.insert(expanded, 3, {id = "inspect", label = "Inspect", icon = "folder", action = actions.start, validate = function() return false end})
window:updateToolbar(expanded)
t.expect(item("inspect") ~= nil and not item("inspect").enabled, "a page operation appears disabled until selection")
t.expect(item("search") == search and item("search").searchField == refs.search, "insertion preserves the search item and view")
t.assertEqual(refs.search.stringValue, "unsaved query", "insertion preserves search editing state")
expanded[3].validate = function() return true end
window:updateToolbar(expanded)
t.expect(item("inspect").enabled, "selection enables the operation")
window:updateToolbar(xml.toolbarFile(path, {running = false, actions = actions}))
t.assertEqual(item("inspect"), nil, "leaving removes the page operation")
t.expect(item("search") == search, "removal preserves the search item")
t.assertEqual(order(), before, "leaving restores the window toolbar order")
t.assertThrows(function() window:updateToolbar({{id = "duplicate"}, {id = "duplicate"}}) end, "duplicate item identity is invalid")
t.assertThrows(function() xml.toolbarFile(path, {running = true, actions = {back = actions.back, start = actions.start}}) end,
	"a misspelt action fails when the toolbar is described")

window:close()
os.remove(path)
os.exit(t.summary() and 0 or 1)
