_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local Controller = require("apps.diskmap.Controller")
local Mock = require("apps.diskmap.services.Mock")

-- Mount the real overview page and controller without creating a window or scanning.
local app = Controller.new(Mock.new())
app.content = ns.VStack {}
app:show("overview")
local page, list = app.page.refs.page, app.page.refs.results
t.assertEqual(list.documentView.gridStyleMask, 2, "categories use native horizontal separators without vertical grid lines")
-- 724x580 is the narrowest window (isolated, no sidebar). Narrower than its
-- columns' minimums, a table scrolls sideways instead of breaking them.
for _, size in ipairs({{700, 720}, {724, 580}, {1000, 900}}) do
	app.content.frameSize = ns.Size(size[1], size[2])
	app.content:layout(size[1])
	t.expect(page.documentView.frame.size.height > page.contentSize.height, "overview overflows at test size")
	t.expect(list.documentView.frame.size.height <= list.contentView.bounds.size.height, "category list fits all its rows")
	t.assertEqual(bridge._testScrollWheel(list.documentView, -1), page,
		"wheel over a Diskmap category reaches the page")
end
app:updateRows()
app.content:layout(1000)
t.expect(list.rowCount > 0, "a refresh keeps the categories")
t.assertEqual(bridge._testScrollWheel(list.documentView, -1), page, "a redrawn list does not trap wheel input")
t.assertEqual(list.documentView.gridStyleMask, 2, "search updates preserve native row separators")
t.assertEqual(bridge._testScrollWheel(list.documentView, -1), page, "restored categories keep forwarding")
app.page:dispose()
t.assertEqual(app.page.refs, nil, "disposing the page releases its refs")
os.exit(t.summary() and 0 or 1)
