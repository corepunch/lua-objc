_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local Model = require("apps.diskmap.Model")
local Watchlist = require("apps.diskmap.models.Watchlist")
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.Controller")

-- Application Support comes from NSFileManager, one folder per app.
local support = ns.applicationSupportDirectory("lua-objc")
t.expect(support and support:sub(-#"/Library/Application Support/lua-objc") == "/Library/Application Support/lua-objc", "the app's folder is inside Application Support")
t.expect(not pcall(ns.applicationSupportDirectory, "../escape"), "a folder name cannot leave Application Support")
t.expect(not pcall(ns.applicationSupportDirectory, ""), "an empty folder name is refused")

-- Model: stored entries are validated, deduplicated and keep their baseline.
local model = Model.new("/Users/test")
local day = os.time({year = 2026, month = 9, day = 20, hour = 12})
local list = Watchlist.new(model, {
	{kind = "resource", id = "developer", bytes = 5e9, measuredAt = day},
	{kind = "resource", id = "developer"},
	{kind = "resource", id = "retired-resource"},
	{kind = "folder", path = "relative/path"},
	{kind = "folder", path = "/Users/test/Projects", bytes = 2e9, measuredAt = day},
	"not an entry",
})
t.assertEqual(list:count(), 2, "invalid, duplicate and retired entries are dropped")
t.assertEqual(list:find("resource:developer").name, "Developer", "a resource takes its catalog name")
t.assertEqual(list:find("folder:/Users/test/Projects").name, "Projects", "a folder is named after its last component")
local rows = list:rows()
t.assertEqual(rows[1].id, "watched:resource:developer", "rows carry their sidebar id")
t.assertEqual(rows[1].size, "5.0 GB", "before a scan the stored size is shown")
t.assertEqual(rows[1].changeText, "Waiting for a measurement", "no change is claimed before measuring")
t.assertEqual(rows[2].icon, "folder.fill", "folders use the folder symbol")

-- A folder's measurement this session is compared with the baseline.
list:record("folder:/Users/test/Projects", 3.5e9, true, day + 86400 * 7)
local delta, text = list:change("folder:/Users/test/Projects")
t.assertEqual(delta, 1.5e9, "the change is signed bytes since the baseline")
t.assertEqual(text, "1.5 GB more since Sep 20", "growth names the previous session's day")
list:record("folder:/Users/test/Projects", 2e9 - 5e5, true, day + 86400 * 7)
t.assertEqual(select(2, list:change("folder:/Users/test/Projects")), "No change since Sep 20", "block-level noise reads as unchanged")
list:record("folder:/Users/test/Projects", 1e9, true, day + 86400 * 7)
t.assertEqual(select(2, list:change("folder:/Users/test/Projects")), "1.0 GB less since Sep 20", "shrinkage is worded as less")
list:record("folder:/Users/test/Projects", nil, false)
local missing = list:rows()[2]
t.expect(missing.missing and missing.size == "Missing", "a folder that disappeared is listed as missing")
t.expect(list:find("folder:/Users/test/Projects") ~= nil, "a missing folder stays watched")
list:record("folder:/Users/test/Nowhere", 1, true)
t.assertEqual(list:count(), 2, "recording an unwatched key changes nothing")

-- Only complete resource measurements count: a partial scan is not shrinkage.
model.measurements["derived"] = {status = "calculating"}
list:sync(day + 86400)
t.expect(list:change("resource:developer") == nil, "an incomplete category is not compared")
for _, leaf in ipairs(model.resources:find("developer"):getChildren()) do
	local function complete(node)
		if node:isLeaf() then model.measurements[node.id] = {status = "complete", bytes = 1e9}
		else for _, child in ipairs(node:getChildren()) do complete(child) end end
	end
	complete(leaf)
end
list:sync(day + 86400)
t.expect(list:change("resource:developer") ~= nil, "a complete category is compared")

-- Encoding rolls this session's sizes into the next session's baseline;
-- a missing folder keeps its last known size.
local encoded = list:encode()
t.assertEqual(encoded[1].measuredAt, day + 86400, "the stored time is this session's measurement")
t.expect(encoded[1].bytes ~= 5e9, "the stored size is this session's measurement")
t.assertEqual(encoded[2].bytes, 2e9, "a missing folder keeps its previous size")
local reloaded = Watchlist.new(model, encoded)
t.assertEqual(reloaded:find("resource:developer").bytes, encoded[1].bytes, "the next session starts from the stored size")

-- Toggling validates and removes cleanly.
local ok, err = list:toggle({kind = "resource", id = "nope"})
t.expect(not ok and err.code == "unknown_resource", "an unknown resource cannot be watched")
t.expect(select(2, list:toggle({kind = "resource", id = "developer"})) == false, "toggling a watched entry removes it")
t.expect(not list:has("resource:developer") and list:change("resource:developer") == nil, "removal forgets the session measurement too")
t.expect(select(2, list:toggle({kind = "resource", id = "developer"})) == true, "toggling again adds it back")
t.assertEqual(list:count(), 2, "the list holds each entry once")

-- End to end against the Mock HDD: watch from a row menu, open from the
-- sidebar, watch a subfolder, persist, stop watching.
local service = Mock.new()
local errors = {}
service.showError = function(title, message) table.insert(errors, title .. ": " .. tostring(message)) end
local app = Controller.new(service)
app:createWindow()
local sidebar = app.navigation.refs.sidebar
local plainRows = sidebar.rowCount
t.assertEqual(bridge._tableCell(sidebar, 0, 0).textField.stringValue, "Overview", "nothing watched: the sidebar starts with Overview")

local function perform(items, title)
	for _, item in ipairs(items) do
		if item.title == title then item.action(); return true end
	end
	return false
end
t.expect(perform(app.actions:resource("xcode"), "Watch"), "a category's menu offers Watch")
t.assertEqual(sidebar.rowCount, plainRows + 2, "the Watched section and its row lead the sidebar")
t.assertEqual(bridge._tableCell(sidebar, 0, 0).textField.stringValue, "Watched", "the section is a native group header")
t.assertEqual(bridge._tableCell(sidebar, 0, 1).textField.stringValue, "Xcode", "the watched category is listed by name")
t.expect(bridge._tableCell(sidebar, 0, 1).badgeField.stringValue:find("B$") ~= nil, "its badge is its measured size")
t.assertEqual(app.destination, "overview", "watching does not navigate away")
t.assertEqual(sidebar.documentView.selectedRow, app.navigation:index("overview"), "the selection follows the overview down")
local menu = app.actions:resource("xcode")
t.assertEqual(menu[#menu].title, "Stop Watching", "a watched resource offers Stop Watching after Keep")
t.assertEqual(#service.watchlist, 1, "the watch is saved at once")
t.expect(service.watchlist[1].bytes ~= nil, "the saved entry carries its size")

sidebar:selectRow(1)
t.assertEqual(app.destination, "watched:resource:xcode", "the sidebar row opens the watched page")
local refs = app.page.refs
t.expect(refs.watchedSummary.text:find("Measured for the first time", 1, true) ~= nil, "a new watch has nothing to compare with yet")
t.expect(refs.contents.rowCount >= 2, "a watched category lists its locations")
t.expect(refs.openCategory ~= nil and refs.unwatch ~= nil, "the page opens the category and stops watching")

-- A plain folder: measured on demand, one level down.
local home = service.home
t.expect(perform(app.actions:folder({path = home .. "/Library/Developer", name = "Developer"}), "Watch"), "a folder's menu offers Watch")
t.expect(not perform(app.actions:folder({path = home .. "/notes.txt", name = "notes.txt", directory = false}), "Watch"), "files are not watched")
app:show("watched:folder:" .. home .. "/Library/Developer")
refs = app.page.refs
t.expect(refs.contents.rowCount >= 1, "a watched folder lists its immediate children")
t.expect(refs.contentsDetail.text:find("at the top level", 1, true) ~= nil, "the contents are summarized once measured")
t.expect(refs.reveal ~= nil and refs.openCategory == nil, "a folder offers Finder but no category")
t.assertEqual(sidebar.documentView.selectedRow, 2, "the folder's sidebar row is selected")
local folderMenu = app.pages.watched:contentsMenu({path = home .. "/Library/Developer/Xcode", name = "Xcode", directory = true})
t.expect(perform(folderMenu, "Watch"), "a subfolder can be watched from the contents list")
t.assertEqual(#service.watchlist, 3, "three locations are saved")

-- The next launch compares with how this one ended.
service.watchlist[2].bytes = service.watchlist[2].bytes - 3e9
service.watchlist[2].measuredAt = day
local second = Controller.new(service)
second:createWindow()
second.watchlist:scanFinished()
local changed
for _, row in ipairs(second.watchlist:rows()) do if row.kind == "folder" and row.name == "Developer" then changed = row end end
t.expect(changed and changed.changeText:find("more since Sep 20", 1, true) ~= nil, "growth since the previous session is reported")
t.assertEqual(second.navigation.refs.sidebar.rowCount, plainRows + 4, "all three watches return on the next launch")

-- Stop Watching from the page returns to the overview.
second:show("watched:resource:xcode")
second.page.template.actions.unwatch()
t.assertEqual(second.destination, "overview", "stopping a watch leaves its page")
t.assertEqual(#service.watchlist, 2, "the removal is saved")
second:show("watched:resource:xcode")
t.assertEqual(second.destination, "overview", "an unwatched location cannot be opened")
t.assertEqual(#errors, 0, "no errors were shown")
