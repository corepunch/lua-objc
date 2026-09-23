_G.__headless = true
package.path = "./?.lua;./lua/?.lua;" .. package.path

local t = require("TestKit")
local Controller = require("demo.motion-feedback.Controller")
local controller = Controller.new()
local ok, err = pcall(function() controller:createWindow() end)
t.expect(ok, "motion feedback example renders in headless mode")
if not ok then io.stderr:write(tostring(err) .. "\n") end
if ok then
	controller:addItem()
	t.assertEqual(controller.refs.items.rowCount, 1, "native List inserts a row")
	t.assertEqual(controller.model.items[1].title, "Item 1", "model state stays in sync")
	controller:addItem()
	t.assertEqual(controller.refs.items.rowCount, 2, "second insertion preserves existing rows")
	t.assertEqual(controller.model.items[1].id, "1", "unrelated row identity remains unchanged")
end
os.exit(t.summary() and 0 or 1)
