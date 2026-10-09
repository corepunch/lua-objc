_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local Controller = require("apps.diskmap.Controller")
local app = Controller.new(require("apps.diskmap.services.Mock").new({showcase = true}))
local window = app:createWindow()
local search = app.searchField
local function item(id)
	for _, installed in ipairs(window.toolbar.items) do if installed.itemIdentifier == "operation_" .. id then return installed end end
end
-- Breakdown pages act on their rows in place; the toolbar holds no
-- selection, folder or measuring operations for them.
for _, id in ipairs({"overview", "map", "kinds", "folder"}) do
	app:show(id, id == "folder" and {path = "/Users/appleseed/Downloads"} or nil)
	for _, name in ipairs({"openSelection", "markSelection", "openFolder", "rescan", "stop"}) do
		t.assertEqual(item(name), nil, id .. " has no " .. name .. " toolbar operation")
	end
	t.expect(app.searchField == search, id .. " keeps the native search field")
end
app:show("worktrees")
t.expect(item("openOwner") ~= nil and not item("openOwner").enabled, "owner actions wait for selection")
app.page.refs.reviewList:selectRow(0)
t.expect(item("openOwner").enabled, "native list selection enables owner actions")
app:show("overview")
t.assertEqual(item("openOwner"), nil, "ordinary navigation clears previous selection operations")
t.assertEqual(item("access"), nil, "mock storage has no useless access operation")
window:close()
os.exit(t.summary() and 0 or 1)
