_G.__headless = true

local t = require("TestKit")
local Sidebar = require("apps.studio.controllers.SidebarController")
local metrics = {
	iconSize = 20, iconSlotWidth = 32, rowPadding = 8,
	expandedPadding = 12, collapsedPadding = 8,
	expandedWidth = 208, compactWidth = 184, collapsedWidth = 64,
}
local sidebar = Sidebar.new(metrics):presentation()
t.assertEqual(sidebar.metrics, metrics, "sidebar receives platform metrics")
t.assertEqual(sidebar.collapsed, false, "sidebar starts expanded")
t.expect(#sidebar.projects > 0, "sidebar presents recent projects")
t.expect(#sidebar.links > 0, "sidebar presents navigation links")

local source = require("ui.xml").describeFile("apps/studio/views/Sidebar.etlua", sidebar).source
t.expect(source:find('name="hammer.fill"', 1, true) ~= nil,
	"Lua Studio hammer icon renders in the fixed icon slot")
t.expect(source:find('action="toggleChat"', 1, true) ~= nil,
	"sidebar retains its preview focus action")
t.expect(source:find('action="toggleSidebarWidth"', 1, true) ~= nil,
	"sidebar retains its width customization action")
t.expect(source:find('fixedWidth="208"', 1, true) ~= nil,
	"expanded sidebar applies its configured width")
os.exit(t.summary() and 0 or 1)
