_G.__headless = true

local t = require("TestKit")
local Model = require("apps.diskmap.Model")
local ns = require("AppKit")
local xml = require("ui.xml")

t.assertEqual(Model.humanKb(1024), "1.0 MB", "disk map formats megabytes")
t.assertEqual(Model.humanKb(1024 * 1024), "1.0 GB", "disk map formats gigabytes")
t.assertEqual(Model.humanKb(12), "12 KB", "disk map preserves small sizes")

local tree = {
	children = {
		{ children = { { children = {} }, { children = {} } } },
		{ children = {} },
	},
}
t.assertEqual(Model.countItems(tree), 4, "disk map counts nested items")

local cfg = xml.renderFile("apps/diskmap/views/Window.etlua", {}, ns)
local sidebar = xml.renderFile("apps/diskmap/views/Sidebar.etlua", { navItems = {} }, ns)
local content = xml.renderFile("apps/diskmap/views/ContentPane.etlua", {}, ns)
local detail = xml.renderFile("apps/diskmap/views/DetailPane.etlua", {}, ns)
cfg.sidebar = sidebar
cfg.content = content
cfg.detail = detail
t.expect(cfg.sidebar ~= nil, "disk map config installs native sidebar pane")
t.expect(cfg.content ~= nil, "disk map config installs main content pane")
t.expect(cfg.detail ~= nil, "disk map config installs native detail pane")
t.assertEqual(cfg.sidebarWidth, 228, "disk map preserves the concept sidebar width")
t.assertEqual(cfg.detailWidth, 330, "disk map preserves the inspector width")
t.assertEqual(#cfg.toolbar, 2, "disk map toolbar has sidebar and inspector controls")
t.assertEqual(cfg.toolbar[1].id, "toggleSidebar", "disk map toolbar starts with sidebar toggle")
t.assertEqual(cfg.toolbar[2].id, "toggleDetail", "disk map toolbar includes inspector toggle")

os.exit(t.summary() and 0 or 1)
