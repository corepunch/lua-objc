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

local xml = require("ui.xml")
local source = xml.describeFile("apps/studio/views/Window.etlua", {
	sidebar = sidebar,
	preview = { device = "iPhone 16", zoom = "100%", runLabel = "Run" },
	chat = { status = "Ready", prompt = "Prompt", response = "Response", files = {}, suggestions = {} },
}).source
t.expect(source:find('name="hammer.fill"', 1, true) ~= nil,
	"Lua Studio identity remains visible in the toolbar")
local toolbar = assert(source:match('(<HStack ref="toolbar".-</HStack>)'))
t.expect(toolbar:find('action="toggleChat"', 1, true) ~= nil,
	"preview focus action is in the top toolbar")
t.expect(toolbar:find('action="toggleSidebarWidth"', 1, true) ~= nil,
	"sidebar width action is in the same top toolbar")
t.expect(toolbar:find('action="reloadPreview"', 1, true) ~= nil,
	"Run reloads the preview from the top toolbar")
t.expect(toolbar:find('accessibilityLabel="Focus Preview"', 1, true) ~= nil,
	"icon-only preview action retains an accessible name")
t.expect(source:find('fixedWidth="208"', 1, true) ~= nil,
	"expanded sidebar applies its configured width")

local Root = require("apps.studio.Controller")
local child = {}
local root = setmetatable({
	model = { files = {} },
	preview = { render = function() return child end },
	refs = { preview = {}, previewStatus = {} },
}, Root)
t.expect(root:reloadPreview(), "Run reloads the embedded controller")
t.assertEqual(root.refs.preview.content, child, "successful reload replaces preview content")
t.assertEqual(root.refs.previewStatus.text, "Ready", "successful reload clears the prior status")
root.preview.render = function() return nil, "bad project" end
t.expect(not root:reloadPreview(), "failed reload is reported")
t.assertEqual(root.refs.preview.content, child, "failed reload preserves the prior preview")
t.expect(root.refs.previewStatus.text:find("bad project", 1, true) ~= nil,
	"failed reload displays its error")
os.exit(t.summary() and 0 or 1)
