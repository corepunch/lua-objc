_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local Controller = require("apps.diskmap.Controller")
local Mock = require("apps.diskmap.services.Mock")

-- Mount the real dashboard and controller without creating a window or scanning.
local app = Controller.new(Mock.new())
app.content = ns.VStack {}
app:mountDashboard()
local page, list = app.refs.page, app.refs.results
t.assertEqual(list.documentView.gridStyleMask, 2, "categories use native horizontal separators without vertical grid lines")
for _, size in ipairs({{700, 720}, {540, 400}, {1000, 900}}) do
	page.frameSize = ns.Size(size[1], size[2])
	page:layout(size[1])
	t.expect(page.documentView.frame.size.height > page.contentSize.height, "dashboard overflows at test size")
	t.expect(list.documentView.frame.size.height <= list.contentView.bounds.size.height, "category list fits all its rows")
	t.assertEqual(bridge._testScrollWheel(list.documentView, -1), page,
		"wheel over a Diskmap category reaches the page")
end
app.query = "no category can match this query"
app:updateRows()
page:layout(1000)
t.assertEqual(list.rowCount, 0, "search empties the list")
t.assertEqual(bridge._testScrollWheel(list.documentView, -1), page, "empty search does not trap wheel input")
app.query = ""
app:updateRows()
page:layout(1000)
t.expect(list.rowCount > 0, "clearing search restores categories")
t.assertEqual(list.documentView.gridStyleMask, 2, "search updates preserve native row separators")
t.assertEqual(bridge._testScrollWheel(list.documentView, -1), page, "restored categories keep forwarding")
app.page:dispose()
os.exit(t.summary() and 0 or 1)
