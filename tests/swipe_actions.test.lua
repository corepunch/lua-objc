_G.__headless = true

local ns = require("AppKit")
local t = require("TestKit")
local xml = require("ui.xml")
local Controller = require("demo.swipe-actions.Controller")

local controller = Controller.new()
controller:createWindow()
local first = controller.model.items[1]
local second = controller.model.items[2]
local third = controller.model.items[3]
t.assertEqual(controller.refs.items.rowCount, 3, "native list starts with three rows")
t.expect(ns._testRowSwipe(controller.refs.items, 2, "trailing"),
	"trailing action dispatches through the native table delegate")
t.assertEqual(controller.refs.items.rowCount, 2, "swipe removes only the target row")
t.expect(controller.model.items[1] == first and controller.model.items[2] == third,
	"unrelated model rows retain identity and order")
t.expect(controller.model.items[1] ~= second, "target row was removed")
t.expect(ns._testRowSwipe(controller.refs.items, 1, "leading"),
	"leading action dispatches through the native table delegate")
t.assertEqual(controller.refs.items.rowCount, 1, "leading swipe updates the native list")
t.expect(controller.model.items[1] == third, "remaining row is unchanged")
t.expect(not ns._testRowSwipe(controller.refs.items, 4, "trailing"),
	"missing rows do not dispatch a swipe")

local otherStackRow = controller.model.stackItems[2]
t.expect(ns._testRowSwipe(controller.refs.stack_a, 1, "leading"),
	"VStack SwipeRow dispatches its leading action")
t.assertEqual(controller.model.stackItems[1].status, "Archived",
	"stack swipe mutates its model item")
t.expect(controller.model.stackItems[2] == otherStackRow
	and otherStackRow.status == "", "unrelated stack row is unchanged")
t.assertEqual(controller.refs.stack_a.rowCount, 1,
	"the native stack row remains visible after its status update")
t.expect(ns._testRowSwipe(controller.refs.stack_a, 1, "trailing"),
	"VStack SwipeRow dispatches its trailing action")
t.assertEqual(controller.model.stackItems[1].status, "Complete",
	"trailing stack action updates the same item")

local ok = pcall(function()
	xml.render('<List swipeTrailing="missing"><Column id="title" /></List>',
		{ actions = {} }, ns)
end)
t.expect(not ok, "a swipe action must resolve to a controller callback")

os.exit(t.summary() and 0 or 1)
