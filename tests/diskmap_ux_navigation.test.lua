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
	app.page.actions.chartSelect(id, 2)
end

-- The same originating leaf takes the same destination from either entry.
for _, id in ipairs({"projects", "derived", "devices", "downloads"}) do
	local location = Locations:find(id)
	if not location then error("missing fixture location " .. id) end
	local destination = location:destination()
	mapLeaf(id)
	t.assertEqual(app.destination, destination.page, id .. " reaches its destination")
	app:show("largest")
	app.page.actions.open(nil, nil, {id = id})
	t.assertEqual(app.destination, destination.page, "Largest Locations agrees")
end

-- Search is one page over the whole store; a refresh keeps its results.
app:show("largest")
app:search("DerivedData")
t.assertEqual(app.destination, "search", "a search opens Search")
t.expect(refs().results_locations.rowCount >= 1, "the query finds its locations")
app:updateRows()
t.assertEqual(app.query, "DerivedData", "refresh preserves the query")
app:show("files")
t.assertEqual(app.searchField.stringValue, "", "another page shows the field empty")
t.assertEqual(refs().files.rowCount, #Files:rows("All"), "All measured files are discoverable immediately")
t.expect(refs().files.rowCount > #Files:rows("Yours"), "the default includes owner-managed files")
local file = app.env:page("files").visible[1]
t.expect(refs().openSelection == nil, "Large Files has no selection panel")
app.page.actions.reveal(nil, nil, file)
t.assertEqual(revealed, file.path, "activating a file reveals it")
app:search("absent query")
t.expect(refs().searchNoResults ~= nil, "a search without results says so")
app.navigation:back()
t.assertEqual(app.destination, "files", "Back visits the previous page")
t.assertEqual(app.searchField.stringValue, "", "and shows the field empty")
app.navigation:forward()
t.assertEqual(app.destination, "search", "Forward returns to the results")
t.assertEqual(app.searchField.stringValue, "absent query", "with their query")
app:search("")
t.assertEqual(app.destination, "files", "clearing the field returns to the page")

-- Folder contents and build artifacts have separately named actions and amounts.
local projects = Locations:find("projects")
app:show("map", {focus = projects:parent().id})
app.page.actions.chartSelect("projects", 1)
t.assertEqual(app.env.rowActions:locationAction("projects").title, "Review Build Data", "the narrower destination names its scope")
t.expect(refs().mapSelection == nil, "the redundant selection caption is removed")
-- Map levels are locations, as a browser's pages are: Up is a visit and
-- Back returns down to the group that was open.
local inside = app:location()
app.page.actions.up()
t.expect(app:location() ~= inside, "Up moves the map's location")
app.navigation:back()
t.assertEqual(app:location(), inside, "Back returns to the level Up left")
app.page.actions.chartSelect("developer", 1)
app.page.actions.chartSelect("projects", 1)
app:show("folder", {path = projects.path})
t.assertEqual(app.destination, "folder", "Inspect goes to Folder Map")
t.assertEqual(app.env:page("folder").path, projects.path, "the full location's path survives")
t.expect(app.searchField.enabled, "Search is available from Folder Map too")
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
t.expect(app.window.subtitle:find(Format.size(Locations:folderBytes(projects.path)), 1, true) ~= nil, "folder scan and combined catalog bytes agree")
t.assertEqual(Projects:bytesWithin("/no-artifacts"), nil, "missing measurements are not shown as zero build bytes")

app:openFolder(service.home .. "/Downloads")
local folder = app.env:page("folder")
local selected
for _, row in ipairs(folder:data().lists.folderList) do if row.directory == false and not row.other then selected = row; break end end
t.expect(selected ~= nil, "the fixture has a file to preview")
app.page.actions.selectRow(nil, nil, selected)
t.assertEqual(folder:selection().title, "Preview File", "folder file selection names Quick Look")
app.page.actions.drillRow(nil, nil, selected)
t.assertEqual(previewed, selected.path, "the explicit preview keeps the path")
app:show("overview")
t.expect(refs().findLargest == nil and refs().inspectFolder == nil, "Overview does not duplicate the sidebar's discovery navigation")
app.page.actions.showLargest()
t.assertEqual(app.destination, "largest", "the existing Largest items section's Show All reaches the ranking")
app:show("overview")
app.navigation.refs.sidebar:selectRow(app.navigation:index("folder"))
t.assertEqual(app.destination, "folder", "the sidebar opens Folder Map")
app:dispose()
os.exit(t.summary() and 0 or 1)
