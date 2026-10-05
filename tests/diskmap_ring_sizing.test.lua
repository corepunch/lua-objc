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
	local chart, column = refs.chart, refs.heroLegendColumn
	local row = chart.superview
	local side = math.min(260, row.frame.size.width - 40 - 28 - 300)
	t.assertSize(chart, side, side, "Overview fits an ideal square beside a readable legend")
	t.assertEqual(refs.chartDetail, nil, "no redundant hover subtitle occupies chart height")
	t.assertEqual(refs.legend.frame.size.width, column.frame.size.width, "the legend reaches its column's trailing edge")
	t.assertEqual(refs.hiddenSpace.frame.size.width, column.frame.size.width, "hidden-space values reach that edge too")
	t.assertEqual(column.frame.origin.x + column.frame.size.width, row.frame.size.width - 20,
		"the legend consumes the row up to its normal inset")
	app.page.actions.chartHover("photos")
	refs = layout(size[1], size[2])
	chart = refs.chart
	t.assertEqual(refs.usedTotal.text, "Photos", "hover is named once in the chart center")
	t.assertSize(chart, side, side, "hover preserves chart geometry")
	app.page.actions.chartHover(nil)
	t.assertEqual(refs.usedTotal.text, "640.0 GB", "leaving restores the used total")
end

-- The two exploration maps still fill their bounded panes. File Types has
-- a smaller contextual chart; its declared maximum, not a collapsed natural
-- height, controls its size.
for _, page in ipairs({"map", "folder", "kinds"}) do
	app:show(page, page == "folder" and {path = "/Users/appleseed/Downloads"} or nil)
	for _, size in ipairs({{724, 580}, {1174, 900}}) do
		local refs = layout(size[1], size[2])
		local chart = refs.sunburst or refs.folderSunburst or refs.kindsChart
		t.expect(chart ~= nil, page .. " has its loaded ring")
		t.expect(math.min(chart.frame.size.width, chart.frame.size.height) >= (page == "kinds" and 112 or 160),
			page .. " keeps a usable ring diameter")
		if page == "kinds" then
			t.assertSize(chart, 240, 240, "File Types draws its ring at its one diameter beside the legend")
		else
			local parent = chart.superview
			t.assertSize(chart, parent.frame.size.width, parent.frame.size.height, page .. " fills its chart host")
		end
	end
end
window:close()
os.exit(t.summary() and 0 or 1)
