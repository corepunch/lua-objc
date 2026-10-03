_G.__headless = true
local Locations = require("apps.diskmap.models.Locations")
local t = require("TestKit")
local Model = require("data.model")
local bridge = require("AppKitNative")
local Store = require("apps.diskmap.Store")
local Catalog = require("apps.diskmap.Catalog")
local Projects = require("apps.diskmap.models.Projects")
local Overview = require("apps.diskmap.helpers.Overview")
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.Controller")

-- Opening a resource goes to one place, decided by the catalog, whichever
-- list, menu or link opened it.
local model = Store.new("/Users/test")
local function resolve(id) return Locations:destination(id) end
t.assertEqual(resolve("projects").page, "projects", "Developer projects open the Projects page")
t.assertEqual(resolve("simulators").page, "simulators", "Simulator devices open the Simulators page")
for _, id in ipairs({"derived", "devices", "watch-devices", "archives"}) do
	t.assertEqual(resolve(id).page, "xcode", id .. " opens the Xcode page, which lists it item by item")
end
t.assertEqual(resolve("xcode-app").sheet, "sdks", "an Xcode installation opens its SDKs")
t.assertEqual(resolve("clt").sheet, "sdks", "the Command Line Tools open their SDKs")
t.assertEqual(resolve("applications").page, "applications", "the Applications category opens its page")
t.assertEqual(resolve("apps-system-other").page, "applications", "and so does everything under it")
local npm = resolve("npm")
t.expect(npm.category == "packages" and npm.select == "npm", "any other location opens its group with its row selected")
local developer = resolve("developer")
t.expect(developer.category == "developer" and developer.select == nil, "a category opens its own list")
t.expect(resolve("xcode").category == "xcode", "a group opens its own list, not its parent's")
t.assertEqual(resolve("no-such-resource"), nil, "an unknown id has no destination")
t.expect(Locations:opensElsewhere("simulators") and Locations:opensElsewhere("xcode-app"), "pages and sheets are elsewhere")
t.expect(not Locations:opensElsewhere("npm"), "a location listed in its category is not")
-- Build folders discovered beside projects belong to the Projects page.
local group = Catalog.buildGroup("Node modules")
t.expect(Locations:add("developer", group) ~= nil, "a build group registers")
Locations:add(group.id, {id = "nm-site", name = "site", subtitle = "node_modules", path = "/Users/test/Developer/site/node_modules", artifact = "Node modules"})
t.assertEqual(resolve(group.id).page, "projects", "an ecosystem's build folders open Projects")
t.assertEqual(resolve("nm-site").page, "projects", "and so does one project's folder")
-- Every declared page exists.
local app = Controller.new(Mock.new())
local window = app:createWindow()
for _, row in ipairs(Locations:leaves()) do
	local destination = Locations:destination(row.id)
	t.expect(destination ~= nil, row.id .. " has a destination")
	if destination.page then t.expect(app.env.manifest.pages[destination.page] ~= nil, row.id .. " opens an existing page: " .. destination.page) end
	if destination.category then t.expect(Locations:find(destination.category) ~= nil, row.id .. " opens an existing category") end
end

-- Largest Items: a row opens where its resource lives, not its whole category.
app:show("largest")
local rows = Locations:largest(app.env.scan.disk, 100, "")
local function rowOf(id)
	for index, row in ipairs(rows) do if row.id == id then return index - 1 end end
end
t.expect(rowOf("projects") ~= nil and rowOf("simulators") ~= nil, "the fixture ranks projects and simulators")
app.page.refs.largest:activateRow(rowOf("projects"))
t.assertEqual(app.destination, "projects", "Developer projects open the Projects page")
t.expect(app.env.management.sheet == nil, "and no category sheet")
local sizes = {}
Model.db.projectInfo = {}
for _, project in ipairs(Projects:groups(nil, nil, nil)) do table.insert(sizes, project.bytes) end
for index = 2, #sizes do t.expect(sizes[index - 1] >= sizes[index], "projects are listed largest first") end
app:show("largest")
app.page.refs.largest:activateRow(rowOf("simulators"))
t.assertEqual(app.destination, "simulators", "Simulator devices open the Simulators page")
app:show("largest")
local leaf
for _, row in ipairs(rows) do
	local destination = Locations:destination(row.id)
	if destination.select then leaf = row; break end
end
t.expect(leaf ~= nil, "the fixture ranks a location that lives in a category list")
app.page.refs.largest:activateRow(rowOf(leaf.id))
local parent = Locations:find(leaf.id):parent()
t.assertEqual(app.env.management.rootId, parent.id, "a location opens its own group")
t.assertEqual(app.env.management.selectedId, leaf.id, "with its row selected")
local list = app.env.management.refs.rows1
local selected = list.documentView.selectedRow
t.expect(selected >= 0, "the list shows the selection")
t.assertEqual(bridge._tableCell(list, 0, selected).textField.stringValue, leaf.name, "on the row that was opened")
local previous
for index = 0, list.rowCount - 1 do
	local text = bridge._tableCell(list, 2, index).textField.stringValue
	local value, unit = text:match("([%d%.]+) (%a+)")
	local bytes = value and tonumber(value) * (({KB = 1e3, MB = 1e6, GB = 1e9, TB = 1e12})[unit] or 1)
	if bytes and previous then t.expect(previous >= bytes, "the category list is sorted by size") end
	previous = bytes or previous
end
app.env.management:close()

-- The same route from every other place that opens a resource.
app:open("simulators")
t.assertEqual(app.destination, "simulators", "the root route opens the page")
app:show("overview")
app.pages.overview.actions.openLargest(nil, nil, {id = "projects"})
t.assertEqual(app.destination, "projects", "the Overview's largest items use it")
app:show("developer")
app.page.request:activateRow({id = "simulators"})
t.assertEqual(app.destination, "simulators", "the Developer page uses it")
app:show("developer")
app.page.request:activateRow({id = "xcode-app"})
t.expect(app.env.sdks.sheet ~= nil, "an Xcode installation opens the SDK sheet")
app.env.sdks:close()
app:show("cleanup")
app.page.request:activateRow({id = "simulators"})
t.assertEqual(app.destination, "simulators", "Clean Up uses it")
app:show("cleanup")
app.page.request:activateRow({id = "old-files", page = "files", filter = "Unused for a year"})
t.expect(app.destination == "files" and app.env:page("files").filterIndex == 3, "a row that stands for a page opens it filtered")
-- Inside a category list, a row that lives elsewhere leaves the sheet.
app:open("developer")
t.assertEqual(app.env.management.rootId, "developer", "a category opens its sheet")
app.env.management:review("simulators")
t.expect(app.env.management.sheet == nil and app.destination == "simulators", "its simulator row opens the Simulators page")
app:open("updates")
t.assertEqual(app.destination, "updates", "an id that names no resource is a page")

window:close()
os.exit(t.summary() and 0 or 1)
