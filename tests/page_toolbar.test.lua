_G.__headless = true

-- <Page> declares a navigation destination's title and toolbar. On AppKit the
-- items and a navigational back item join the window toolbar, as SwiftUI does
-- on macOS; UIKit maps the same placements onto the navigation bar.

local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local xml = require("ui.xml")

local events = {}
local actions = {
	settings = function() table.insert(events, "settings") end,
	disappear = function() table.insert(events, "disappear") end,
}
local PAGE = [[
<Page title="Session" onDisappear="disappear">
  <Toolbar>
    <ToolbarItem id="heading" placement="principal" label="Session">
      <VStack><Label id="headingTitle" text="Session" /><Label text="Score 0" /></VStack>
    </ToolbarItem>
    <ToolbarItem id="settings" placement="primaryAction" icon="textformat.size" label="Reading settings" action="settings" />
  </Toolbar>
  <VStack id="content"><Label text="Transcript" /></VStack>
</Page>]]

local function identifiers(window)
	local ids = {}
	for _, item in ipairs(window.toolbar and window.toolbar.items or {}) do table.insert(ids, item.itemIdentifier) end
	return table.concat(ids, ",")
end

-- A window without its own toolbar gains one only while a page needs it.
local _, rootRefs = xml.render('<NavigationStack id="nav" title="Library"><Label text="Root" /></NavigationStack>', {}, ns)
local window = ns.Window { visible = false, width = 600, height = 400, content = rootRefs.nav }
local nav = rootRefs.nav
t.expect(window.toolbar == nil, "a root page without items adds no toolbar")

local page, refs = xml.render(PAGE, { actions = actions }, ns)
t.assertEqual(page.title, "Session", "Page carries its navigation title")
nav:push(page)
t.assertEqual(nav.depth, 2, "a Page pushes like any hosting controller")
local ids = identifiers(window)
t.expect(ids:find("lua-objc.navigation.back", 1, true) == 1, "the back item leads the toolbar")
t.expect(ids:find("heading", 1, true) and ids:find("settings", 1, true), "page items join the window toolbar")
local items = {}
for _, item in ipairs(window.toolbar.items) do items[item.itemIdentifier] = item end
t.expect(items["lua-objc.navigation.back"].navigational, "the back item is a navigational toolbar item")
-- With one centered item, AppKit reports it through the singular accessor.
t.assertEqual(window.toolbar.centeredItemIdentifier, "heading", "principal placement is centered")
t.expect(refs.headingTitle.superview ~= nil, "the principal item hosts the declared view")
bridge._invokeAction(items.settings.view or items.settings)
t.assertEqual(events[1], "settings", "a toolbar item runs its controller action")

bridge._invokeAction(items["lua-objc.navigation.back"])
t.assertEqual(nav.depth, 1, "the back item pops the page")
t.assertEqual(events[#events], "disappear", "popping runs the page's onDisappear once")
t.expect(window.toolbar == nil, "leaving the page removes the toolbar it added")

-- A window toolbar keeps its own items and gains page items beside them.
local _, workspaceRefs = xml.render('<NavigationStack id="nav"><Label text="Root" /></NavigationStack>', {}, ns)
local withToolbar = ns.Window { visible = false, width = 600, height = 400, content = workspaceRefs.nav,
	toolbar = { { id = "refresh", label = "Refresh", icon = "arrow.clockwise", action = function() end } } }
t.assertEqual(identifiers(withToolbar), "refresh", "window items stand alone at the root")
workspaceRefs.nav:push((xml.render(PAGE, { actions = actions }, ns)))
t.expect(identifiers(withToolbar):find("refresh", 1, true) ~= nil, "window items stay while a page is shown")
workspaceRefs.nav:pop()
t.assertEqual(identifiers(withToolbar), "refresh", "popping restores exactly the window's items")

t.assertThrows(function() xml.render('<Page><Toolbar /></Page>', {}, ns) end, "Page requires content")
t.assertThrows(function()
	xml.render('<Page><Toolbar><ToolbarItem id="x" action="missing" /></Toolbar><Label text="x" /></Page>', { actions = {} }, ns)
end, "a misspelt toolbar action fails at render time")

-- The UIKit bridge maps the same placements; no app-specific chrome remains.
local function source(path)
	local file = assert(io.open(path)); local text = file:read("*a"); file:close(); return text
end
local uikit = source("src/uikit/navigation.m")
t.expect(uikit:find("bridge_UIKitNavigation_page_toolbar", 1, true) ~= nil, "UIKit installs page toolbars")
for _, path in ipairs({ "src/uikit/navigation.m", "src/appkit/navigation.m", "src/appkit/toolbar.m", "lua/embedded/UIKit.lua" }) do
	local text = source(path)
	t.expect(not text:find("textformat.size", 1, true) and not text:find("Reading settings", 1, true),
		path .. " contains no application-specific toolbar items")
end

withToolbar:close()
window:close()
os.exit(t.summary() and 0 or 1)
