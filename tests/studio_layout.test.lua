_G.__headless = true
local t = require("TestKit")
local xml = require("ui.xml")
local sidebar = require("apps.studio.models.Sidebar").presentation()
sidebar.metrics = {
	iconSize = 20,
	iconSlotWidth = 32,
	rowPadding = 8,
	expandedPadding = 12,
	collapsedPadding = 8,
	expandedWidth = 208,
	compactWidth = 184,
	collapsedWidth = 64,
}
sidebar.collapsed = false

local description = xml.describeFile("apps/studio/views/Window.etlua", {
	sidebar = sidebar,
	preview = { device = "iPhone 16", zoom = "100%", runLabel = "Run" },
	chat = {
		tabs = { "Preview", "Logs" },
		status = "Ready",
		prompt = "Prompt",
		response = "Response",
		files = { "App.lua" },
		suggestions = {},
	},
})

t.expect(not description.source:find("nil", 1, true), "sidebar partials render instead of inserting nil")
for _, title in ipairs({
	"HabitPal", "PixelPaint", "StoryWorld", "Calc+",
	"Projects", "Templates", "Examples", "Plugins", "Settings",
}) do
	t.expect(description.source:find(title, 1, true) ~= nil, "sidebar includes " .. title)
end
local _, verticalDividerCount = description.source:gsub('<Divider orientation="vertical"', "")
t.assertEqual(verticalDividerCount, 2, "workspace keeps one divider between each pane")
t.expect(description.source:find('minWidth="300"', 1, true) ~= nil, "preview pane can share the available width")
t.expect(description.source:find('minWidth="330"', 1, true) ~= nil, "chat pane can share the available width")
os.exit(t.summary() and 0 or 1)
