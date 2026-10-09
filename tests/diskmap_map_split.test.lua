_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local Controller = require("apps.diskmap.Controller")
local app = Controller.new(require("apps.diskmap.services.Mock").new({showcase = true}))
local window = app:createWindow()
for _, id in ipairs({"map", "folder", "kinds", "overview"}) do
	app:show(id, id == "folder" and {path = "/Users/appleseed/Downloads"} or nil)
	for _, size in ipairs({{950,580},{1280,800},{1900,1000}}) do
		window.size = ns.Size(size[1], size[2]); bridge._flushLayout()
		local refs = app.page.refs
		local chart, summary = refs.breakdownChart.frameInWindow, refs.breakdownSummary.frameInWindow
		t.expect(chart.origin.x + chart.size.width <= summary.origin.x, id .. " keeps chart left of summary")
		t.expect(chart.size.height <= 260 and chart.size.width >= 120, id .. " has one compact chart size")
		local list = refs.mapList or refs.folderList or refs.kinds or refs.results
		t.expect(list ~= nil, id .. " has a complete list below the breakdown")
		t.expect(list.frameInWindow.origin.y + list.frameInWindow.size.height <= refs.breakdown.frameInWindow.origin.y, id .. " full list is below the card")
	end
	local count = (app.page.refs.mapList or app.page.refs.folderList or app.page.refs.kinds or app.page.refs.results).rowCount
	app:toggleChartStyle()
	t.expect(app.page.refs.breakdownRectangles ~= nil and app.page.refs.breakdownChart == nil, id .. " toggles to rectangles")
	bridge._flushLayout()
	local rectangle = app.page.refs.breakdownRectangles.frame
	t.expect(rectangle.size.width > 500, id .. " rectangles fill the entire widget width")
	t.assertEqual(app.page.refs.breakdownSummary, nil, id .. " rectangles have no summary list on the right")
	t.assertEqual((app.page.refs.mapList or app.page.refs.folderList or app.page.refs.kinds or app.page.refs.results).rowCount, count, id .. " switching preserves the full list")
	app:toggleChartStyle()
	t.expect(app.page.refs.breakdownChart ~= nil, id .. " toggles back to rings")
end
window:close()
os.exit(t.summary() and 0 or 1)
