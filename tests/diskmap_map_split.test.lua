_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.Controller")

local app = Controller.new(Mock.new({showcase = true}))
local window = app:createWindow()
app:show("map", {focus = "xcode"})
bridge._flushLayout()

local function layout(width, height)
	local refs = app.page.refs
	refs.page.size = ns.Size(width, height)
	refs.page:layout(width)
	return refs
end

-- Content widths exclude the native sidebar. Both panes share available
-- space; a fixed list cap used to send every extra point to the ring pane.
local narrowList
for _, size in ipairs({{724, 580}, {1174, 900}, {1374, 650}, {724, 580}}) do
	local refs = layout(size[1], size[2])
	local list, chart = refs.mapListPane.frame, refs.mapChartPane.frame
	t.expect(math.abs(list.size.width - chart.size.width) < 0.01, "map panes share width at " .. size[1])
	t.expect(list.size.width >= 300 and chart.size.width >= 300, "both panes retain their minimum width")
	t.expect(math.abs(chart.origin.x + chart.size.width - refs.mapBody.frame.size.width) < 0.01,
		"the panes consume the available row width")
	t.expect(refs.mapList.frame.size.width >= list.size.width - 20, "the native list uses its wider pane")
	t.expect(math.min(refs.sunburst.frame.size.width, refs.sunburst.frame.size.height) >= 200,
		"the ring retains a usable diameter")
	if size[1] == 724 then
		narrowList = narrowList or list.size.width
		t.assertEqual(list.size.width, narrowList, "shrinking back restores the same split")
	else
		t.expect(list.size.width > narrowList, "extra width gives location names more room")
		t.expect(list.size.width > 330, "the list no longer stops at its old cap")
	end
end

app.page.actions.pickStyle(1)
local refs = layout(1174, 900)
t.assertEqual(refs.mapListPane, nil, "rectangles have no duplicate list pane")
t.assertEqual(refs.mapChartPane.frame.size.width, refs.mapBody.frame.size.width,
	"rectangles take the full content width")
app.page.actions.pickStyle(0)
refs = layout(1174, 900)
t.assertEqual(refs.mapListPane.frame.size.width, refs.mapChartPane.frame.size.width,
	"returning to rings restores the balanced split")
t.assertEqual(app.env:page("map").focusId, "xcode", "layout and style changes retain exploration focus")

window:close()
os.exit(t.summary() and 0 or 1)
