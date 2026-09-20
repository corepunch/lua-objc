_G.__headless = true

local t = require("TestKit")
local Model = require("apps.diskmap.Model")

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

os.exit(t.summary() and 0 or 1)
