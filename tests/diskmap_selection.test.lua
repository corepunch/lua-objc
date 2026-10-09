_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local Store = require("apps.diskmap.Store")
local Overview = require("apps.diskmap.helpers.Overview")
local Files = require("apps.diskmap.models.Files")
local Selection = require("apps.diskmap.helpers.Selection")
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.Controller")
local Categories = require("apps.diskmap.models.Categories")

-- The token's rules.
t.expect(Selection.isResource("applications"), "a category id is a resource")
t.expect(not Selection.isResource("free"), "free space is volume geometry")
t.expect(not Selection.isResource("unreconciled"), "the residual is not selectable")
t.expect(Selection.isResource("other"), "\"other\" is a category and a file kind of its own")
t.expect(not Selection.isResource(Categories.folded), "the Overview's folded categories are not one resource")
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

local model = Store.new("/Users/test")
model.measurements["apps-system-other"] = {bytes = 58e9, status = "complete"}
local disk = {totalKb = 494e9 / 1024, freeKb = 157e9 / 1024}
local chart = Categories:chart(disk)
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
local kinds, extensions = Files:kinds()
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
local overview = app.page
local model = overview.request
local results = overview.refs.results
local category = model.categoryRows[2].id
-- Hovering the ring names the sector in its center; no category row follows
-- the pointer and there is no redundant line below it.
overview.actions.chartHover(category)
t.assertEqual(model.selectedId, nil, "hovering a sector selects no category row")
t.assertEqual(results.documentView.selectedRow, -1, "natively")
t.assertEqual(overview.refs.breakdownTotal.text, model.categoryRows[2].name, "the center names the sector")
overview.actions.chartHover(Categories.folded)
t.assertEqual(overview.refs.breakdownTotal.text, "Other categories", "the folded categories name themselves")
overview.actions.chartHover("free")
t.assertEqual(overview.refs.breakdownTotal.text, "Free", "the center names free space")
overview.actions.chartHover(nil)
t.assertEqual(overview.refs.chartDetail, nil, "there is no subtitle taking space below the chart")
-- "other" is a category too: its sector and legend row are its own, never
-- the folded categories'.
local mapped = {}
local map = app.env:page("map")
map.setFocus = function(self, id) table.insert(mapped, id) end
overview.actions.chartSelect("other")
t.assertEqual(mapped[1], "other", "the Other category's sector opens the Map inside it")
app:show("overview")
overview.actions.chartSelect(Categories.folded)
t.assertEqual(mapped[2], "", "the folded sector opens the whole map")
map.setFocus = nil
app:show("overview")
t.assertEqual(overview.actions["category_" .. Categories.folded], nil, "the folded legend row opens nothing")

app:show("map")
local mapPage = app.page
mapPage.actions.chartHover("developer")
t.assertEqual(map.selectedId, nil, "hovering points at a row without changing the kept selection")
t.assertEqual(mapPage.refs.mapList.documentView.selectedRow, Selection.index(map.rows, "developer"),
	"hovering a wedge selects its row")
t.assertEqual(map.focusId, "", "without looking inside it")
mapPage.actions.chartHover("developer#other")
t.assertEqual(map.selectedId, nil, "a folded remainder is no resource")
t.assertEqual(mapPage.refs.mapList.documentView.selectedRow, -1, "and selects no row")

app:show("kinds")
local page = app.page
local model = page.request
local opened
local showFiles = model.showFiles
model.showFiles = function(_, id) opened = id end
local first, second = model.kinds[1].id, model.kinds[2].id
local allExtensions = page.refs.extensions.rowCount
page.actions.chartHover(second)
t.assertEqual(page.refs.kinds.documentView.selectedRow, 1, "hovering a kind's sector points at its row")
t.assertEqual(model.selectedId, nil, "pointing keeps no kind")
t.assertEqual(page.refs.extensions.rowCount, allExtensions, "and leaves the top extensions whole")
page.actions.chartSelect(second)
t.assertEqual(model.selectedId, second, "clicking a sector keeps its kind")
t.assertEqual(page.refs.kinds.documentView.selectedRow, 1, "its row stays selected")
t.expect(page.refs.extensions.rowCount <= allExtensions, "the top extensions follow the kind")
t.assertEqual(opened, nil, "the first click opens nothing")
page.actions.chartHover(first)
page.actions.chartHover(nil)
t.assertEqual(page.refs.kinds.documentView.selectedRow, 1, "leaving the chart returns to the kept kind")
page.actions.chartSelect(second)
t.assertEqual(opened, second, "a second click opens the kind's largest files")
page.refs.kinds:selectRow(0)
t.assertEqual(model.selectedId, first, "selecting a row keeps its kind too")
model.showFiles = showFiles

os.exit(t.summary() and 0 or 1)
