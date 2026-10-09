_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.Controller")
local app = Controller.new(Mock.new({showcase = true}))
local window = app:createWindow()
local function layout(width, height)
	local page = app.page.refs.page
	page.size = ns.Size(width, height)
	page:layout(width)
	return app.page.refs
end
for _, size in ipairs({{724, 580}, {1174, 900}, {1574, 650}, {724, 580}}) do
	app:show("overview")
	local refs = layout(size[1], size[2])
	local chart, column = refs.breakdownChart, refs.breakdownSummary
	local row = chart.superview
	local side = math.min(260, row.frame.size.width - 40 - 28 - 300)
	t.assertSize(chart, side, side, "Overview fits an ideal square beside a readable legend")
	t.assertEqual(refs.chartDetail, nil, "no redundant hover subtitle occupies chart height")
	t.assertEqual(refs.breakdownLegend.frame.size.width, column.frame.size.width, "the legend reaches its column's trailing edge")
	t.assertEqual(refs.hiddenSpace.frame.size.width, column.frame.size.width, "hidden-space values reach that edge too")
	t.assertEqual(column.frame.origin.x + column.frame.size.width, row.frame.size.width - 20,
		"the legend consumes the row up to its normal inset")
	app.page.actions.chartHover("photos")
	refs = layout(size[1], size[2])
	chart = refs.breakdownChart
	t.assertEqual(refs.breakdownTotal.text, "Photos", "hover is named once in the chart center")
	t.assertSize(chart, side, side, "hover preserves chart geometry")
	app.page.actions.chartHover(nil)
	t.assertEqual(refs.breakdownTotal.text, "640.0 GB", "leaving restores the used total")
end

-- All breakdown pages use the same compact chart metrics.
for _, page in ipairs({"map", "folder", "kinds"}) do
	app:show(page, page == "folder" and {path = "/Users/appleseed/Downloads"} or nil)
	for _, size in ipairs({{724, 580}, {1174, 900}}) do
		local refs = layout(size[1], size[2])
		local chart = refs.breakdownChart
		t.expect(chart ~= nil, page .. " has its loaded ring")
		t.expect(chart.frame.size.width >= 120 and chart.frame.size.width <= 260, page .. " uses the shared diameter")
		local width, height = chart.frame.size.width, chart.frame.size.height
		chart.toolTip = string.rep("A very long folder name ", 12)
		refs = layout(size[1], size[2])
		t.assertSize(chart, width, height, page .. " tooltip never reserves layout space")
	end
end
window:close()
os.exit(t.summary() and 0 or 1)
