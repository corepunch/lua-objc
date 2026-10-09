_G.__headless = true
local t = require("TestKit")
local Controller = require("apps.diskmap.Controller")
local Mock = require("apps.diskmap.services.Mock")
local Files = require("apps.diskmap.models.Files")
local Locations = require("apps.diskmap.models.Locations")
local Search = require("apps.diskmap.helpers.Search")

-- The matcher: case-insensitive, literal, trimmed, and nothing for a blank query.
t.assertEqual(Search.needle("  Xcode "), "xcode", "the needle is trimmed and lowered")
t.assertEqual(Search.needle("   "), nil, "a blank query looks for nothing")
t.expect(Search.matches("deriv", nil, "Xcode DerivedData"), "any field may match, nil fields are skipped")
t.expect(Search.matches("[", "a [b") and not Search.matches("%a", "abc"), "patterns are literal")
t.assertEqual(#Search.filter({{name = "a", path = "/x"}, {name = "b", path = "/a"}}, "a", {"name", "path"}), 2, "rows match by any named field")
t.assertEqual(#Search.filter(nil, "a", {"name"}), 0, "no rows find nothing")

local service = Mock.new()
local revealed
service.reveal = function(path) revealed = path end
local app = Controller.new(service)
app:createWindow()
local function refs() return app.page.refs end

-- Typing opens Search over the current page; the other pages never filter.
app:show("largest")
local largest = refs().largest.rowCount
app:search("DerivedData")
t.assertEqual(app.destination, "search", "typing opens the Search page")
t.assertEqual(app.searchField.stringValue, "DerivedData", "the field shows the query")
t.expect(refs().results_locations ~= nil, "matching locations are listed")
t.expect(refs().results_locations.rowCount >= 1, "DerivedData is found")
t.expect(app.window.subtitle:find("for “DerivedData”", 1, true) ~= nil, "the summary names the query")

-- Results come from every model: a file found by name, an app, a topic.
local file = Files:rows()[1]
app:search(file.name)
t.expect(refs().results_files ~= nil and refs().results_files.rowCount >= 1, "large files are searched")
app.page.actions.open(nil, nil, app.page.request.presented.lists.results_files[1])
t.assertEqual(revealed, app.env:page("search").presented.lists.results_files[1].path, "a file result opens in Finder")

app:search("swap")
t.expect(refs().results_guide ~= nil, "Storage Guide topics are searched")
local topic = app.page.request.presented.lists.results_guide[1]
app.page.actions.open(nil, nil, topic)
t.assertEqual(app.destination, "guide", "a topic opens its book")
t.assertEqual(app.env:page("guide").opened, topic.id, "with that topic open")
t.assertEqual(app.searchField.stringValue, "", "pages other than Search show the field empty")
app.navigation:back()
t.assertEqual(app.destination, "search", "Back returns to the results")
t.assertEqual(app.searchField.stringValue, "swap", "with the query")

-- A location result opens where its location sends it.
app:search("DerivedData")
local location = app.page.request.presented.lists.results_locations[1]
app.page.actions.open(nil, nil, location)
local destination = Locations:find(location.id):destination()
if destination.page then t.assertEqual(app.destination, destination.page, "a location opens its page")
end

-- Pages are found by name, and each result has a menu.
app:search("simul")
t.expect(refs().results_pages ~= nil, "pages are searched by title")
for id, rows in pairs(app.page.request.presented.lists) do
	local menu = app.page.request:rowMenu(nil, nil, rows[1])
	t.expect(type(menu) == "table" and #menu > 0, id .. " rows have a menu")
end

-- Nothing found says so, and clearing returns to the page Search left.
app:show("largest")
app:search("no such thing anywhere")
t.expect(refs().searchNoResults ~= nil, "no results is a stated result")
t.assertEqual(next(app.page.request.presented.lists), nil, "no lists without results")
app:search("")
t.assertEqual(app.destination, "largest", "clearing returns to the page Search opened over")
t.assertEqual(refs().largest.rowCount, largest, "that page lists all it lists")

-- A long group lists its largest results and says so.
app:search(".")
for id, rows in pairs(app.page.request.presented.lists) do
	t.expect(#rows <= 25, id .. " is capped")
end

-- The Search page is not in the sidebar or the Go menu.
t.assertEqual(app.navigation:index("search"), nil, "Search has no sidebar row")
app:search("xcode")
t.assertEqual(app.navigation.refs.sidebar.documentView.selectedRow, -1, "and no row is selected while it shows")
app:search("")
t.expect(app.navigation.refs.sidebar.documentView.selectedRow >= 0, "the page it returns to is selected again")
t.assertEqual(app.env.manifest.pages.search.listed, false, "Search is an unlisted page")

-- The Help menu opens a topic instead of searching for it.
app:search("")
app.commandActions.shortcuts()
t.assertEqual(app.destination, "help", "Keyboard Shortcuts opens Help")
t.assertEqual(app.env:page("help").opened, "shortcuts", "on its topic")
t.assertEqual(app.query, "", "without a search")

app:dispose()
os.exit(t.summary() and 0 or 1)
