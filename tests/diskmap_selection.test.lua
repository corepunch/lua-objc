_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local Model = require("apps.diskmap.Model")
local Overview = require("apps.diskmap.models.Overview")
local Files = require("apps.diskmap.models.Files")
local Selection = require("apps.diskmap.models.Selection")
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.Controller")

-- The token's rules.
t.expect(Selection.isResource("applications"), "a category id is a resource")
t.expect(not Selection.isResource("free"), "free space is volume geometry")
t.expect(not Selection.isResource("unreconciled"), "the residual is not selectable")
t.expect(Selection.isResource("other"), "\"other\" is a file kind; only a page without that row ignores it")
t.expect(not Selection.isResource("developer#other"), "a folded remainder is not a row")
t.expect(not Selection.isResource(""), "empty is not a resource")
t.expect(not Selection.isResource(nil), "nothing is not a resource")

local rows = {{id = "video", kindId = "video"}, {id = "mp4", kindId = "video"}, {id = "zip", kindId = "archives"}}
t.assertEqual(Selection.index(rows, "video"), 0, "rows are counted from zero, as the list counts them")
t.assertEqual(Selection.index(rows, "zip"), 2, "a row owns its own id")
t.assertEqual(Selection.index(rows, "missing"), nil, "an id without a row selects nothing")
t.assertEqual(Selection.index(rows, "free"), nil, "volume geometry selects nothing")
t.assertEqual(Selection.index(nil, "video"), nil, "no rows select nothing")

local filtered = Selection.extensions(rows, "archives")
t.assertEqual(#filtered, 1, "extensions narrow to the selected kind")
t.assertEqual(filtered[1].id, "zip", "the matching extension remains")
t.assertEqual(#Selection.extensions(rows, "missing"), 3, "an unknown token leaves the ranking")
t.assertEqual(#Selection.extensions(rows, nil), 3, "no token leaves the ranking")
t.assertEqual(#rows, 3, "filtering leaves the ranking itself alone")

local model = Model.new("/Users/test")
model.measurements["apps-system-other"] = {bytes = 58e9, status = "complete"}
local disk = {totalKb = 494e9 / 1024, freeKb = 157e9 / 1024}
local chart = Overview.chart(model, disk)
t.assertEqual(chart.marks[1].id, "applications", "overview sectors carry the category id")
t.assertEqual(chart.marks[#chart.marks].id, "free", "the empty track is tagged free")

model.files = {
	large = {},
	old = {},
	extensions = {
		{extension = "mp4", bytes = 8e9, count = 4, oldBytes = 1e9},
		{extension = "mov", bytes = 2e9, count = 1, oldBytes = 0},
		{extension = "zip", bytes = 1e9, count = 2, oldBytes = 0},
	},
}
local kinds, extensions = Files.kinds(model)
t.expect(#kinds >= 2, "kinds group extensions")
local videos = Selection.extensions(extensions, "video")
t.expect(#videos >= 1 and #videos < #extensions, "a kind narrows the top extensions")
for _, row in ipairs(videos) do t.assertEqual(row.kindId, "video", "to its own extensions") end

-- A selection that follows the pointer selects in place.
local list = ns.List { columns = {{id = "name", title = "Name"}} }
list:replaceRows({{id = "a", name = "A"}, {id = "b", name = "B"}, {id = "c", name = "C"}})
local picked
list:onRowSelect(function(_, index) picked = index end)
Selection.show(list, {{id = "a"}, {id = "b"}, {id = "c"}}, "b")
t.assertEqual(picked, 1, "the token selects its row")
t.assertEqual(list.documentView.selectedRow, 1, "natively")
Selection.show(list, {{id = "a"}, {id = "b"}, {id = "c"}}, "free")
t.assertEqual(list.documentView.selectedRow, -1, "a token without a row clears the selection")

-- The pages.
local app = Controller.new(Mock.new())
app:createWindow()

app:show("overview")
local overview = app.pages.overview
local results = overview.refs.results
local category = overview.categoryRows[2].id
overview.hero.actions.chartHover(category)
t.assertEqual(overview.selectedId, category, "the Overview's sector and rows share one token")
t.assertEqual(results.documentView.selectedRow, 1, "hovering a sector selects its category row")
app.scan:notify()
t.assertEqual(overview.refs.results.documentView.selectedRow, Selection.index(overview.categoryRows, category),
	"new measurements keep the selected row")
overview.hero.actions.chartHover("other")
t.assertEqual(overview.selectedId, nil, "the folded categories have no row")
overview.hero.actions.chartHover("free")
t.assertEqual(overview.selectedId, nil, "free space is no resource")
t.assertEqual(overview.refs.results.documentView.selectedRow, -1, "and selects no row")
overview.hero.actions.chartHover(category)
overview.hero.actions.chartHover(nil)
t.assertEqual(overview.refs.results.documentView.selectedRow, -1, "leaving the chart clears the selection")

app:show("map")
local map = app.pages.map
map.template.actions.chartHover("developer")
t.assertEqual(map.selectedId, "developer", "the Map's wedge and rows share one token")
t.assertEqual(map.refs.mapList.documentView.selectedRow, Selection.index(map.rows, "developer"),
	"hovering a wedge selects its row")
t.assertEqual(map.focus, "", "without looking inside it")
map.template.actions.chartHover("developer#other")
t.assertEqual(map.selectedId, nil, "a folded remainder is no resource")
t.assertEqual(map.refs.mapList.documentView.selectedRow, -1, "and selects no row")

app:show("kinds")
local page = app.pages.kinds
local opened
local showFiles = page.showFiles
page.showFiles = function(id) opened = id end
local first, second = page.kinds[1].id, page.kinds[2].id
local allExtensions = page.refs.extensions.rowCount
page.template.actions.chartHover(second)
t.assertEqual(page.refs.kinds.documentView.selectedRow, 1, "hovering a kind's sector points at its row")
t.assertEqual(page.selectedId, nil, "pointing keeps no kind")
t.assertEqual(page.refs.extensions.rowCount, allExtensions, "and leaves the top extensions whole")
page.template.actions.chartSelect(second)
t.assertEqual(page.selectedId, second, "clicking a sector keeps its kind")
t.assertEqual(page.refs.kinds.documentView.selectedRow, 1, "its row stays selected")
t.expect(page.refs.extensions.rowCount <= allExtensions, "the top extensions follow the kind")
t.assertEqual(opened, nil, "the first click opens nothing")
page.template.actions.chartHover(first)
page.template.actions.chartHover(nil)
t.assertEqual(page.refs.kinds.documentView.selectedRow, 1, "leaving the chart returns to the kept kind")
page.template.actions.chartSelect(second)
t.assertEqual(opened, second, "a second click opens the kind's largest files")
page.refs.kinds:selectRow(0)
t.assertEqual(page.selectedId, first, "selecting a row keeps its kind too")
page.showFiles = showFiles

os.exit(t.summary() and 0 or 1)
