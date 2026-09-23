_G.__headless = true

local t = require("TestKit")
local Model = require("demo.list-reorder.Model")
local reorder = require("ui.reorder")

local model = Model.new({
	{ _id = "a", title = "First", done = false },
	{ _id = "b", title = "Second", done = true },
	{ _id = "c", title = "Third", done = false },
})
local originalSecond = model.tasks[2]
local diff = reorder.Difference.new():move(2, 1)

t.expect(model:applyReorder(diff), "model accepts a reorder difference")
t.assertEqual(model.tasks[1]._id, "b", "move applies to the first row")
t.assertEqual(model.tasks[2]._id, "a", "move shifts the preceding row")
t.expect(model.tasks[1] == originalSecond, "move preserves row identity")
t.assertEqual(model.tasks[3]._id, "c", "unrelated row order stays unchanged")
t.expect(not model:applyReorder({}), "model rejects values outside the Difference API")

local Controller = require("demo.list-reorder.Controller")
local controller = Controller.new()
local ok, err = pcall(function() controller:createWindow() end)
t.expect(ok, "example renders its native list in headless mode")
if not ok then io.stderr:write(tostring(err) .. "\n") end
if ok then
	t.assertEqual(controller.refs.tasks.rowCount, #controller.model.tasks,
		"template binds model rows to the native list")
	controller:handleReorder(reorder.Difference.new():move(1, 2))
	t.assertEqual(controller.model.tasks[2]._id, "1",
		"controller applies native reorder updates to the model")
end

os.exit(t.summary() and 0 or 1)
