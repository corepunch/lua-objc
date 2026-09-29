_G.__headless = true
-- Regressions for the QA pass in #59: numbers that reconcile, lists that
-- say what they hold, and states that never read as a measured zero.
local t = require("TestKit")
local ns = require("AppKit")
local Model = require("apps.diskmap.Model")
local Mock = require("apps.diskmap.services.Mock")
local Overview = require("apps.diskmap.models.Overview")
local Inventory = require("apps.diskmap.models.Inventory")
local Xcode = require("apps.diskmap.models.Xcode")
local Projects = require("apps.diskmap.models.Projects")
local Files = require("apps.diskmap.models.Files")
local Applications = require("apps.diskmap.models.Applications")
local Simulators = require("apps.diskmap.models.Simulators")
local Updates = require("apps.diskmap.models.Updates")
local Recommendations = require("apps.diskmap.models.Recommendations")
local Developer = require("apps.diskmap.models.Developer")
local Controller = require("apps.diskmap.Controller")
local home = "/Users/test"

-- The unreadable notice and the Unreadable locations row name one number,
-- though the scan keeps only its first thousand paths.
local model = Model.new(home)
local issues = {}
for index = 1, 1000 do table.insert(issues, {path = home .. "/Library/Locked/" .. index}) end
model.scan = {errors = 1011, issues = issues}
local unreadable = Overview.unreadable(model)
t.assertEqual(#unreadable.paths, 6, "the notice lists six folders")
t.assertEqual(unreadable.total, 1011, "and counts every unreadable location")
t.assertEqual(unreadable.more, 1005, "so the rest add up to the scan's total")
t.assertEqual(unreadable.moreText, "1,005", "with a thousands separator")
local disk = {totalKb = 245e6, freeKb = 17e6}
local hidden = Overview.hidden(disk, nil, 0, 1011, 0, 0, true)
local byId = {}
for _, row in ipairs(hidden) do byId[row.id] = row end
t.assertEqual(byId.unreadable.value, "1,011", "counts print as whole numbers")
t.assertEqual(byId.media.value, "Not scanned", "excluded media libraries are named on the Overview")
t.assertEqual(#Overview.hidden(disk, nil, 0, 0, 0, 0, false), 0, "included media libraries need no row")

-- A location where nothing could be read has no size.
Inventory.apply(model, {"mail", "downloads"}, {trees = {{kb = 0, partial = true}, {kb = 2048, partial = true}},
	rootStates = {"unreadable", "unreadable"}})
t.assertEqual(model.measurements.mail.status, "denied", "an unreadable location is denied")
local row = Model.sizeLabel({}, model.measurements.mail.status, model.measurements.mail.bytes)
t.assertEqual(row.size, "No access", "and reads No access, not ≥ 0 KB")
t.assertEqual(model.measurements.downloads.status, "partial", "a partly read location keeps its lower bound")
t.assertEqual(Model.atLeast(model.measurements.downloads.bytes, true), "≥ 2.1 MB", "which reads at least")

-- A group of locations that could not be read has no access either.
local Categories = require("apps.diskmap.models.Categories")
local denied = Model.new(home)
local mailGroup = denied.resources:find("mail"):getParent()
for _, child in ipairs(mailGroup:getChildren()) do denied.measurements[child.id] = {status = "complete", bytes = 0} end
denied.measurements.mail = {status = "denied"}
local mailRow = Categories.row(denied, mailGroup.id)
t.assertEqual(mailRow.size, "No access", "a group with nothing readable reads No access")
t.assertEqual(mailRow.bytes, nil, "and has no bytes to chart")

-- DerivedData's shared caches are not projects.
local derived = Xcode.derivedRows({
	{name = "App-abcdefgh", path = "/d/App-abcdefgh", bytes = 5e6, workspace = "/w/App.xcodeproj", exists = true},
	{name = "ModuleCache.noindex", path = "/d/ModuleCache.noindex", bytes = 9e9},
	{name = "SDKExplicitPrecompiledModules", path = "/d/SDKExplicitPrecompiledModules", bytes = 1e6},
	{name = "Gone-abcdefgh", path = "/d/Gone-abcdefgh", bytes = 1e6, workspace = "/w/Gone.xcodeproj", exists = false},
})
t.assertEqual(derived[1].name, "Gone", "build data of a missing project comes first")
t.assertEqual(derived[2].name, "App", "then projects")
t.assertEqual(derived[3].name, "Module cache", "shared caches follow, named for what they hold")
t.assertEqual(derived[3].status, "Shared", "and are not projects with an unknown workspace")
t.assertEqual(derived[4].subtitle, "Shared by every project · Xcode rebuilds it", "their subtitle says whose they are")
t.expect(not derived[3].missing, "a shared cache is never a missing project")
t.assertEqual(require("apps.diskmap.controllers.XcodeController").statuses.Shared, "Rebuildable", "shared caches are rebuildable")

-- Projects are told apart by where they are; a tool's folder is not one.
t.assertEqual(Projects.location(home .. "/Developer/Temp/vue-frontend", home), "~/Developer/Temp/vue-frontend", "a project shows its folder")
t.expect(Projects.isToolFolder(home .. "/Developer/orca/.opencode", home .. "/Developer"), "a hidden tool folder in a repository is not a project")
t.expect(Projects.isToolFolder(home .. "/Developer/.cache/tool/pkg", home .. "/Developer"), "nor is anything below a hidden folder")
t.expect(not Projects.isToolFolder(home .. "/Developer/orca/web", home .. "/Developer"), "an ordinary folder is a project")
t.expect(not Projects.isToolFolder(home .. "/.projects/site", home .. "/.projects"), "a hidden search root does not hide its projects")
t.assertEqual(Projects.gitText(nil), "Not in git", "the git state fits its column")

-- Installers name their kind in the detail column; the path is the subtitle.
local installers = Updates.installers(model, {{path = home .. "/Downloads/Tool.dmg", bytes = 2e9}, {path = home .. "/Desktop/Xcode.xip", bytes = 3e9}})
t.assertEqual(installers[1].type, "Xcode archive", "an installer's type is short")
t.assertEqual(installers[2].type, "Disk image", "and leaves out where it is")
t.assertEqual(installers[2].kind, "Disk image in Downloads", "the full description stays available")

-- Simulator rows name their values and carry a device symbol.
t.assertEqual(Simulators.symbol("iPad Pro 13-inch (M5)"), "ipad", "an iPad has an iPad symbol")
t.assertEqual(Simulators.symbol("Apple Watch Series 11"), "applewatch", "a watch has a watch symbol")
t.assertEqual(Simulators.symbol("iPhone 17"), "iphone", "anything else is a phone")
local devices = Simulators.rows({runtimes = {}, devices = {["com.apple.CoreSimulator.SimRuntime.iOS-26-5"] = {
	{name = "iPhone 17", udid = "A", isAvailable = true, dataPathSize = 1e9}}}})
t.assertEqual(devices[1].state, "", "an unknown state is left empty, not dashed")
t.assertEqual(devices[1].lastUse, "Never started", "a device never booted says so")
t.assertEqual(devices[1].icon, "iphone", "device rows have an icon")

-- The mock app: pages as they are mounted.
local app = Controller.new(Mock.new())
local window = app:createWindow()
local deadline = os.time() + 10
while not app.model.files and os.time() < deadline do ns.sleep(0.05) end
t.expect(app.model.files ~= nil, "the mock scan finishes")

-- Large Files leads with what can be acted on.
t.assertEqual(Files.filters[1], "Yours", "Large Files opens on the files a person can act on")
t.assertEqual(Files.filterIndex("Installers & archives"), 4, "pages open a filter by name")
local yours, all = Files.rows(app.model, "Yours"), Files.rows(app.model, "All")
t.expect(#yours > 0 and #yours < #all, "Yours is a part of All")
for _, file in ipairs(yours) do t.expect(file.trashable, file.name .. " can be moved to the Trash") end
app:show("files")
t.assertEqual(app.refs.files.rowCount, #yours, "the page opens on Yours")
t.expect(app.refs.filesNoResults.hidden and app.refs.filesEmpty.hidden, "a list with files shows no empty state")
app:search("files", "no such file anywhere")
t.assertEqual(app.refs.files.rowCount, 0, "a search can match nothing")
t.expect(not app.refs.filesNoResults.hidden, "and then says No Results")
t.expect(app.refs.filesPanel.hidden, "instead of an empty list")
app:search("files", "")
t.expect(app.refs.filesNoResults.hidden and not app.refs.filesPanel.hidden, "clearing the search brings the list back")

-- Search narrows the Map's list; the chart keeps the level.
app:show("map")
local everything = app.refs.mapList.rowCount
local marks = #app.pages.map:presentation().nodes
app:search("map", "developer")
t.expect(app.refs.mapList.rowCount > 0 and app.refs.mapList.rowCount < everything, "search narrows the map's list")
t.assertEqual(#app.pages.map:presentation().nodes, marks, "the chart keeps every sector")
app:search("map", "no such category")
t.expect(app.refs.mapNoResults ~= nil, "a map search without matches says No Results")
app:search("map", "")
t.assertEqual(app.refs.mapList.rowCount, everything, "clearing the search restores the list")
t.expect(app.refs.mapSummary.text:find(" measured of ", 1, true) ~= nil, "the Map names its base beside the disk's used space")

-- The sidebar badge and the Developer page name one total.
t.assertEqual(app:badges().developer, Developer.presentation(app.model).total, "the Developer badge is the page's total")

-- Clean Up lists read largest first.
local cleanup = Recommendations.presentation(app.model)
for _, list in ipairs({cleanup.rebuildable, cleanup.review}) do
	for index = 2, #list do t.expect(list[index - 1].bytes >= list[index].bytes, "cleanup suggestions are largest first") end
end
t.expect(#cleanup.review > 1, "the mock has suggestions to order")

-- Apps are called what Finder calls them.
local bundle = Applications.bundles(app.model)[1]
for _, entry in ipairs(Applications.rows(app.model, {[bundle.path] = {displayName = "Other", bundleId = "com.example.shown"}}, "All")) do
	t.assertEqual(entry.name, entry.path:match("([^/]+)%.app$"), "an app is named as Finder names it, by its file")
end
local rawModel = Model.new(home)
rawModel.resources:add("applications", {id = "raw-app", name = "logioptionsplus.app", subtitle = "Installed application", path = "/Applications/logioptionsplus.app"})
rawModel.measurements["raw-app"] = {status = "complete", bytes = 5e8}
local raw
for _, entry in ipairs(Applications.rows(rawModel, {["/Applications/logioptionsplus.app"] = {displayName = "Logi Options+"}}, "All")) do
	if entry.path == "/Applications/logioptionsplus.app" then raw = entry end
end
t.assertEqual(raw and raw.name, "Logi Options+", "a file name that is only an identifier gives way to the display name")
t.expect(raw.neverOpened, "an app Spotlight never saw opened is never opened")
t.assertEqual(Applications.summary({raw}).unused, 1, "and counts as unused, as the Unused filter lists it")

-- Include media libraries is remembered.
t.assertEqual(app.model.includeMedia, false, "media libraries start excluded")
app.settings:setMedia(true)
t.expect(app.service.loadFlag("media"), "the choice is saved")
t.expect(require("apps.diskmap.controllers.SettingsController").new(app.service, Model.new(home), function() end, app.notifications).model.includeMedia,
	"and restored at the next launch")
app.settings:setMedia(false)

-- Simulators never show zeros while they load.
app:show("simulators")
local simulators = app.pages.simulators
simulators.busy, simulators.loading = true, true
simulators:show()
t.assertEqual(app.refs.devicesTileValue.text, "—", "a loading tile has no value")
t.assertEqual(app.refs.devicesTileDetail.text, "Reading…", "and says it is reading")
t.assertEqual(app.refs.unavailableTileDetail.text, "Reading…", "nothing is claimed about devices not read yet")
simulators.busy, simulators.loading = false, false
simulators:show()
t.expect(app.refs.devicesTileValue.text ~= "—", "a loaded tile has its value")
t.expect(not app.refs.summary.text:find(" 1 runtimes", 1, true) and not app.refs.summary.text:find(" 1 devices", 1, true), "counts are pluralized")

-- Overview sections with nothing to show take no place.
app:show("overview")
t.expect(app.refs.accessNotice.hidden, "no access notice, no gap")
window.size = ns.Size(950, 580); window:layout()
os.exit(t.summary() and 0 or 1)
