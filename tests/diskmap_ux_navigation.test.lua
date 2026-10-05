_G.__headless = true
local t = require("TestKit")
local Controller = require("apps.diskmap.Controller")
local Mock = require("apps.diskmap.services.Mock")
local Locations = require("apps.diskmap.models.Locations")
local Projects = require("apps.diskmap.models.Projects")
local Files = require("apps.diskmap.models.Files")
local Format = require("apps.diskmap.helpers.Format")
local service = Mock.new()
local revealed, previewed
service.reveal = function(path) revealed = path end
service.quickLook = function(paths, index) previewed = paths[index]; return true end
local app = Controller.new(service)
app:createWindow()
local function refs() return app.page.refs end
local function mapLeaf(id)
	app:show("map", {focus = Locations:find(id):parent().id})
	app.page.actions.chartSelect(id, 1)
	t.expect(refs().mapOpen.enabled, id .. " has an explicit action")
	local title = refs().mapOpen.title
	app.page.actions.chartHover(nil)
	t.assertEqual(refs().mapOpen.title, title, "hover exit preserves the selected action")
	app.page.actions.openSelection()
end

-- The same originating leaf takes the same destination from either entry.
for _, id in ipairs({"projects", "derived", "devices", "downloads"}) do
	local location = Locations:find(id)
	if not location then error("missing fixture location " .. id) end
	local destination = location:destination()
	mapLeaf(id)
	if destination.page then t.assertEqual(app.destination, destination.page, id .. " reaches its dedicated page")
	else
		t.assertEqual(app.env.management.selectedId, id, id .. " arrives selected in its sheet")
		t.assertEqual(app.env.management.rootId, destination.category, "the category matches its destination")
	end
	app.env.management:close()
	app:show("largest")
	app.page.actions.open(nil, nil, {id = id})
	if destination.page then t.assertEqual(app.destination, destination.page, "Largest Locations agrees")
	else t.assertEqual(app.env.management.selectedId, id, "Largest Locations preserves the same selection") end
	app.env.management:close()
end

-- Page-local search clears on arrival, including history, and stays on refresh.
app:search("largest", "DerivedData")
t.assertEqual(app.query, "DerivedData", "an explicit search is applied after arrival")
t.assertEqual(refs().largest.rowCount, 1, "the query filters this population")
t.assertEqual(app.searchField.placeholderString, "Search Largest Locations", "search names its scope")
app:updateRows()
t.assertEqual(app.query, "DerivedData", "refresh preserves the query")
app:show("files")
t.assertEqual(app.query, "", "changing pages clears search")
t.assertEqual(app.searchField.stringValue, "", "the native search field clears too")
t.assertEqual(refs().files.rowCount, #Files:rows("All"), "All measured files are discoverable immediately")
t.expect(refs().files.rowCount > #Files:rows("Yours"), "the default includes owner-managed files")
local file = app.env:page("files").visible[1]
app.page.actions.select(nil, nil, file)
t.assertEqual(refs().openSelection.title, "Show in Finder", "a selected file names its destination")
app.page.actions.openSelection()
t.assertEqual(revealed, file.path, "the explicit file action reveals the selected file")
app:search("files", "absent query")
t.expect(refs().filesNoResults.subviews[4].subviews[2].text:find("absent query", 1, true) ~= nil, "empty results name the active query")
t.expect(refs().filesNoResults.subviews[4].subviews[2].text:find("All", 1, true) ~= nil, "and the active filter")
app.navigation:back()
t.assertEqual(app.destination, "largest", "Back visits the previous page")
t.assertEqual(app.query, "", "Back follows the clear-on-arrival policy")
app.navigation:forward()
t.assertEqual(app.destination, "files", "Forward visits the next page")

-- Folder contents and build artifacts have separately named actions and amounts.
local projects = Locations:find("projects")
app:show("map", {focus = projects:parent().id})
app.page.actions.chartSelect("projects", 1)
t.assertEqual(refs().mapOpen.title, "Review Build Data", "the narrower destination names its scope")
t.expect(refs().mapSelection.text:find(Format.size(Projects:bytesWithin(projects.path)) .. " generated build data", 1, true) ~= nil, "build bytes are separate from the full location")
local historyCount = #app.navigation.history
app.page.actions.up()
t.assertEqual(#app.navigation.history, historyCount, "Up changes map levels without recording a page visit")
app.page.actions.chartSelect("developer", 1)
app.page.actions.chartSelect("projects", 1)
app.page.actions.inspectSelection()
t.assertEqual(app.destination, "folder", "Inspect goes to Folder Map")
t.assertEqual(app.env:page("folder").path, projects.path, "the full location's path survives")
t.expect(not app.searchField.enabled, "Folder Map does not advertise an ineffective filter")
local menu = app.env.rowActions:resource("projects")
local inspect, review
for _, item in ipairs(menu) do
	if item.title == "Inspect Folder Contents" then inspect = item end
	if item.title == "Review Build Data…" then review = item end
end
t.expect(inspect and review, "the resource menu separates folder inspection and build review")
review.action()
t.assertEqual(app.destination, "projects", "build review keeps its dedicated destination")
inspect.action()
t.assertEqual(app.env:page("folder").path, projects.path, "menu inspection keeps the exact path")
t.expect(Locations:folderBytes(projects.path) >= Projects:bytesWithin(projects.path), "full folder contents include separately catalogued build folders")
t.expect(refs().folderSummary.text:find(Format.size(Locations:folderBytes(projects.path)), 1, true) ~= nil, "folder scan and combined catalog bytes agree")
t.assertEqual(Projects:bytesWithin("/no-artifacts"), nil, "missing measurements are not shown as zero build bytes")

app:openFolder(service.home .. "/Downloads")
local folder = app.env:page("folder")
local selected
for _, row in ipairs(folder:data().rows) do if row.directory == false and not row.other then selected = row; break end end
t.expect(selected ~= nil, "the fixture has a file to preview")
app.page.actions.selectRow(nil, nil, selected)
t.assertEqual(refs().folderOpen.title, "Preview File", "folder file selection names Quick Look")
app.page.actions.openSelection()
t.assertEqual(previewed, selected.path, "the explicit preview keeps the path")
app:show("overview")
t.expect(refs().findLargest ~= nil and refs().inspectFolder ~= nil, "Overview exposes both discovery paths")
app.page.actions.showLargest()
t.assertEqual(app.destination, "largest", "Find Largest Locations reaches the ranking")
app:show("overview")
app.page.actions.inspectFolder()
t.assertEqual(app.destination, "folder", "Inspect a Folder reaches Folder Map")
app:dispose()
os.exit(t.summary() and 0 or 1)
