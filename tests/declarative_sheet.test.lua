_G.__headless = true

-- Sheet lifecycle, default action/focus, and XML event bindings: the
-- framework owns what controllers previously wired by hand.

local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Template = require("ui.template")

local SHEET = [[
<Sheet width="420" height="300">
  <VStack maxWidth="infinity" maxHeight="infinity" padding="20" spacing="12">
    <SearchField id="search" placeholder="Search" onChange="search" defaultFocus="true" maxWidth="infinity" />
    <TextField id="name" accessibilityLabel="Name" />
    <VStack id="mount" />
    <TabView id="tabs" onChange="tabChanged" maxWidth="infinity" maxHeight="infinity">
      <Tab title="One">
        <List id="rows" onSelect="select" onActivate="open" onSort="sort" maxWidth="infinity" maxHeight="infinity">
          <Column id="name" title="Name" sortable="true" />
        </List>
      </Tab>
      <Tab title="Two"><Label text="Second" /></Tab>
    </TabView>
    <HStack>
      <Button id="cancel" title="Cancel" action="done" keyboardShortcut="cancelAction" />
      <Button id="done" title="Done" action="done" keyboardShortcut="defaultAction" />
    </HStack>
  </VStack>
</Sheet>]]

local events = {}
local actions = {
	search = function() end,
	done = function() end,
	tabChanged = function() table.insert(events, "tab") end,
	select = function(_, _, row) table.insert(events, "select:" .. tostring(row and row.name)) end,
	open = function() table.insert(events, "open") end,
	sort = function(_, column) table.insert(events, "sort:" .. tostring(column)) end,
}

local parent = ns.Window { visible = false, width = 800, height = 600 }
local mounted
local sheet, refs = ns.presentSheet(function()
	local view, viewRefs = xml.render(SHEET, { actions = actions }, ns)
	mounted = Template.new(viewRefs.mount, "apps/adventure-arena/views/MetadataChip.etlua", ns)
	mounted:update({ text = "mounted", systemImage = "tag" })
	return view, viewRefs
end, { parent = parent })

t.assertEqual(sheet.className, "LuaPanel", "presentSheet returns the builder's sheet")
t.expect(refs and refs.search ~= nil, "presentSheet returns the builder's refs")
t.expect(ns.isFirstResponder(sheet, refs.search), "defaultFocus field receives focus on presentation")
t.assertEqual(refs.done.keyEquivalent, "\r", "defaultAction maps to Return")
t.assertEqual(refs.cancel.keyEquivalent, "\27", "cancelAction maps to Escape")
t.assertEqual(refs.name.accessibilityLabel, "Name", "TextField accessibilityLabel is declarative")

refs.rows:replaceRows({ { name = "Alpha" }, { name = "Beta" } })
refs.rows:selectRow(1)
t.expect(table.concat(events, ","):find("select:Beta", 1, true) ~= nil, "List onSelect binds a controller action")
refs.tabs:selectTab(1)
t.expect(table.concat(events, ","):find("tab", 1, true) ~= nil, "TabView onChange binds a controller action")

t.expect(not mounted:isDisposed(), "templates built for a sheet live while it is presented")
ns.dismiss(sheet)
t.expect(mounted:isDisposed(), "dismiss releases everything the sheet builder created")

t.assertThrows(function()
	ns.presentSheet(function() error("builder failed") end, { parent = parent })
end, "a failing builder propagates its error")
t.assertThrows(function()
	ns.presentSheet(sheet)
end, "AppKit sheets require a parent window")
t.assertThrows(function()
	xml.render('<List onSelect="missing"><Column id="a" /></List>', { actions = {} }, ns)
end, "a misspelt event action fails at render time")
t.assertThrows(function()
	xml.render('<Button title="x" keyboardShortcut="enter" />', {}, ns)
end, "unknown keyboard shortcuts are rejected")
local static = xml.render('<List onSelect="select"><Column id="a" /></List>', {}, ns)
t.expect(static ~= nil, "static renders without actions leave events unbound")

-- A retained child template belongs to its parent's scope.
local host = ns.VStack {}
local page = Template.new(host, "apps/adventure-arena/views/MetadataChip.etlua", ns)
local _, pageRefs = page:update({ text = "page", systemImage = "tag" })
t.expect(pageRefs ~= nil, "parent template mounts")
local wrapper = ns.VStack {}
host:add(wrapper)
page.refs.slot = wrapper
local child = page:child("slot", "apps/adventure-arena/views/MetadataChip.etlua")
child:update({ text = "child", systemImage = "tag" })
page:dispose()
t.expect(child:isDisposed(), "disposing a template disposes its children")
t.assertThrows(function() page:child("missing", "x.etlua") end, "child requires a mounted ref")

-- Semantic values shared with UIKit.
local slider = ns.Slider { min = 14, max = 24, value = 17 }
t.assertEqual(slider.value, 17, "Slider exposes UIKit's `value`")
slider.value = 20
t.assertEqual(slider.doubleValue, 20, "Slider `value` writes the native position")
local font = ns.Font { size = 19, weight = "bold", design = "serif" }
t.assertEqual(font.pointSize, 19, "Font resolves a native font of the requested size")
t.expect(ns.Color("primary") ~= nil and ns.Color("#F5E8D1") ~= nil, "Color resolves semantic and hex names")
t.assertThrows(function() ns.Font {} end, "Font requires a size")

-- Hosts instantiate app classes without passing the class as an argument.
local function source(path)
	local file = assert(io.open(path)); local text = file:read("*a"); file:close(); return text
end
for _, path in ipairs({ "src/main.m", "ios/LuaRuntime/LRTApplicationController.m" }) do
	local text = source(path)
	local call = text:match('lua_getfield%([^,]+, %-1, "new"%);(.-)createWindow')
	t.expect(call and call:find("lua_pcall%([^,]+, 0, 1, 0%)"), path .. " calls class.new() with no arguments")
end

parent:close()
os.exit(t.summary() and 0 or 1)
