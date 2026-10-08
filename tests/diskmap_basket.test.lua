_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.Controller")
local Treemap = require("apps.diskmap.helpers.Treemap")

-- The treemap is as tall as its cells need, within limits.
local function cells(count)
	local nodes = {{id = "group"}}
	for index = 1, count do table.insert(nodes, {id = "cell" .. index, parent = "group"}) end
	return nodes
end
t.assertEqual(Treemap.leaves(cells(5)), 5, "a group is not a cell")
t.assertEqual(Treemap.height(cells(3)), 320, "a few cells keep the minimum height")
t.assertEqual(Treemap.height(cells(400)), 720, "many cells stop at the maximum height")
t.expect(Treemap.height(cells(60)) < Treemap.height(cells(100)), "more cells make a taller map")
t.assertEqual(Treemap.height(cells(100), 480), 720, "a narrower map needs more height for the same cells")

-- The basket is a page: the toolbar's Marked button counts it, and Back and
-- Forward reach it.
local app = Controller.new(Mock.new())
app:createWindow()
local home = app.env.model.home
t.assertEqual(app.marked, 0, "nothing is marked at first")
app.env.basket:toggle({path = home .. "/Downloads/a.zip", name = "a.zip", bytes = 10})
app.env.basket:toggle({path = home .. "/Downloads/b.zip", name = "b.zip", bytes = 20})
t.assertEqual(app.marked, 2, "the toolbar's badge follows the number of marked items")
app:show("overview")
app:openReview(home .. "/Downloads/b.zip")
t.assertEqual(app.destination, "basket", "Review opens the basket page")
t.assertEqual(app.env:page("basket").selected.path, home .. "/Downloads/b.zip", "on the item asked for")
t.expect(app.collector.collectorArea.hidden, "the staging bar gives way to the page that lists the same items")
t.expect(app.navigation:back(), "Back leaves the basket page")
t.assertEqual(app.destination, "overview", "for the page before it")
t.expect(not app.collector.collectorArea.hidden, "and the staging bar returns")
t.expect(app.navigation:forward(), "Forward returns to the basket")
t.assertEqual(app.destination, "basket", "the page again")
app.env.basket:toggle({path = home .. "/Downloads/a.zip"})
t.assertEqual(app.marked, 1, "unmarking lowers the badge")
os.exit(t.summary() and 0 or 1)
