_G.__headless = true
-- Regressions for the QA pass in #59: numbers that reconcile, lists that
-- say what they hold, and states that never read as a measured zero.
local Locations = require("apps.diskmap.models.Locations")
local t = require("TestKit")
local Model = require("data.model")
local ns = require("AppKit")
local Format = require("apps.diskmap.helpers.Format")
local Store = require("apps.diskmap.Store")
local Mock = require("apps.diskmap.services.Mock")
local Overview = require("apps.diskmap.helpers.Overview")
local Xcode = require("apps.diskmap.helpers.Xcode")
local Projects = require("apps.diskmap.models.Projects")
local Files = require("apps.diskmap.models.Files")
local Applications = require("apps.diskmap.models.Applications")
local Simulators = require("apps.diskmap.helpers.Simulators")
local Updates = require("apps.diskmap.helpers.Updates")
local developerWorkflow = require("apps.diskmap.models.Workflows"):find("developer")
local Controller = require("apps.diskmap.Controller")
local Scans = require("apps.diskmap.models.Scans")
local Categories = require("apps.diskmap.models.Categories")
local Suggestions = require("apps.diskmap.models.Suggestions")
local home = "/Users/test"

-- The unreadable notice and the Unreadable locations row name one number,
-- though the scan keeps only its first thousand paths.
local model = Store.new(home)
local issues = {}
for index = 1, 1000 do table.insert(issues, {path = home .. "/Library/Locked/" .. index}) end
model.scan = {errors = 1011, issues = issues}
local unreadable = Scans:unreadable()
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
Scans:apply({"mail", "downloads"}, {trees = {{kb = 0, partial = true}, {kb = 2048, partial = true}},
	rootStates = {"unreadable", "unreadable"}})
t.assertEqual(model.measurements.mail.status, "denied", "an unreadable location is denied")
local row = Format.sizeLabel({}, model.measurements.mail.status, model.measurements.mail.bytes)
t.assertEqual(row.size, "No access", "and reads No access, not ≥ 0 KB")
t.assertEqual(model.measurements.downloads.status, "partial", "a partly read location keeps its lower bound")
t.assertEqual(Format.atLeast(model.measurements.downloads.bytes, true), "≥ 2.1 MB", "which reads at least")

-- A group of locations that could not be read has no access either.
local denied = Store.new(home)
local mailGroup = Locations:find("mail"):parent()
for _, child in ipairs(mailGroup:children()) do denied.measurements[child.id] = {status = "complete", bytes = 0} end
denied.measurements.mail = {status = "denied"}
local mailRow = Categories:row(mailGroup.id)
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
t.assertEqual(require("apps.diskmap.routes").xcode.statuses.Shared, "Rebuildable", "shared caches are rebuildable")

-- Projects are told apart by where they are; a tool's folder is not one.
t.assertEqual(require("apps.diskmap.helpers.Format").tilde(home .. "/Developer/Temp/vue-frontend", home), "~/Developer/Temp/vue-frontend", "a project shows its folder")
t.expect(Projects.isToolFolder(home .. "/Developer/orca/.opencode", home .. "/Developer"), "a hidden tool folder in a repository is not a project")
t.expect(Projects.isToolFolder(home .. "/Developer/.cache/tool/pkg", home .. "/Developer"), "nor is anything below a hidden folder")
t.expect(not Projects.isToolFolder(home .. "/Developer/orca/web", home .. "/Developer"), "an ordinary folder is a project")
t.expect(not Projects.isToolFolder(home .. "/.projects/site", home .. "/.projects"), "a hidden search root does not hide its projects")
t.assertEqual(Projects.gitText(nil), "Not in git", "the git state fits its column")

-- Installers name their kind in the detail column; the path is the subtitle.
local installers = Updates.installers(Locations:installers(), {{path = home .. "/Downloads/Tool.dmg", bytes = 2e9}, {path = home .. "/Desktop/Xcode.xip", bytes = 3e9}})
t.assertEqual(installers[1].type, "Xcode archive", "an installer's type is short")
t.assertEqual(installers[2].type, "Disk image", "and leaves out where it is")
t.assertEqual(installers[2].kind, "Disk image in Downloads", "the full description stays available")

-- Simulator rows name their values and carry a device symbol.
t.assertEqual(Simulators.symbol("iPad Pro 13-inch (M5)"), "ipad", "an iPad has an iPad symbol")
t.assertEqual(Simulators.symbol("Apple Watch Series 11"), "applewatch", "a watch has a watch symbol")
t.assertEqual(Simulators.symbol("iPhone 17"), "iphone", "anything else is a phone")
local devices = Simulators.rows({runtimes = {}, devices = {["com.apple.CoreSimulator.SimRuntime.iOS-26-5"] = {
	{name = "iPhone 17", udid = "A", isAvailable = true, dataPathSize = 1e9}}}})
t.assertEqual(devices[1].state, "State unknown", "missing device state is explicit")
t.assertEqual(devices[1].lastUse, "Last use unknown", "a missing last-use date stays unknown")
t.assertEqual(devices[1].icon, "iphone", "device rows have an icon")

-- The mock app: pages as they are mounted.
local app = Controller.new(Mock.new())
local window = app:createWindow()
local deadline = os.time() + 10
while not app.env.model.files and os.time() < deadline do ns.sleep(0.05) end
t.expect(app.env.model.files ~= nil, "the mock scan finishes")

-- Large Files leads with discovery; Yours is the actionable subset.
t.expect(Files.filters:index("All") ~= nil and Files.filters:index("Yours") ~= nil, "Large Files distinguishes discovery and review")
t.assertEqual(Files.filters:index("Installers & archives"), 4, "pages open a filter by name")
local yours, all = Files:rows("Yours"), Files:rows("All")
t.expect(#yours > 0 and #yours < #all, "Yours is a part of All")
for _, file in ipairs(yours) do t.expect(file.trashable, file.name .. " can be moved to the Trash") end
app:show("files")
t.assertEqual(app.page.refs.files.rowCount, #all, "the page opens on All measured files")
t.expect(app.page.refs.filesEmpty.hidden, "a list with files shows no empty state")

-- The Map lists every category of its level, one per sector.
app:show("map")
t.assertEqual(app.page.refs.mapList.rowCount, #app.env:page("map"):data(app:state()).rows, "the map's list has every row of its level")
t.expect(app.page.refs.mapSummary.text:find(" measured of ", 1, true) ~= nil, "the Map names its base beside the disk's used space")

-- The sidebar badge and the Developer page name one total.
t.assertEqual(app:badges().developer, developerWorkflow:presentation().total, "the Developer badge is the page's total")

-- Clean Up lists read by recovery score: eligible bytes x confidence / effort.
local cleanup = Suggestions:presentation()
for _, list in ipairs({cleanup.now, cleanup.app, cleanup.restart, cleanup.decisions}) do
	for index = 2, #list do t.expect(list[index - 1].score >= list[index].score, "cleanup suggestions are ranked by recovery score") end
end
t.expect(#cleanup.decisions > 1, "the mock has suggestions to order")

-- Apps are called what Finder calls them.
local bundle = Applications:all()[1]
Model.db.applicationInfo = {[bundle.path] = {displayName = "Other", bundleId = "com.example.shown"}}
for _, entry in ipairs(Applications:rows("All")) do
	t.assertEqual(entry.name, entry.path:match("([^/]+)%.app$"), "an app is named as Finder names it, by its file")
end
local rawModel = Store.new(home)
Locations:add("applications", {id = "raw-app", name = "logioptionsplus.app", subtitle = "Installed application", path = "/Applications/logioptionsplus.app"})
rawModel.measurements["raw-app"] = {status = "complete", bytes = 5e8}
local raw
Model.db.applicationInfo = {["/Applications/logioptionsplus.app"] = {displayName = "Logi Options+"}}
for _, entry in ipairs(Applications:rows("All")) do
	if entry.path == "/Applications/logioptionsplus.app" then raw = entry end
end
t.assertEqual(raw and raw.name, "Logi Options+", "a file name that is only an identifier gives way to the display name")
t.expect(raw.usageUnknown and not raw.unused, "an app without a recorded date has unknown usage, not inactivity")
t.assertEqual(raw.detail, "Last use unknown", "and says so")
t.assertEqual(Applications.summary({raw}).unused, 0, "unknown usage never counts as unused")
Model.db.applicationInfo = {["/Applications/logioptionsplus.app"] = {displayName = "Logi Options+"}}
t.assertEqual(#Applications:rows("Unused for 6 months"), 0,
	"the Unused filter excludes unknown usage")

-- Include media libraries is remembered.
t.assertEqual(app.env.model.includeMedia, false, "media libraries start excluded")
app.env.settings:setMedia(true)
t.expect(app.env.service.loadFlag("media"), "the choice is saved")
local relaunched = Store.new(home)
require("tests.diskmap_sheet").new("settings", {service = app.env.service, model = relaunched, notifications = app.env.notifications})
t.expect(relaunched.includeMedia,
	"and restored at the next launch")
app.env.settings:setMedia(false)

-- Simulators claim no totals and list no half-read rows while they load: the
-- page is one progress state until the read ends.
app:show("simulators")
local simulators = app.env:page("simulators")
simulators.stock.loaded = false
app:updateRows()
t.assertEqual(app.page.refs.computingStatus.text, "Reading simulator devices and runtimes…", "a loading page claims no totals")
t.expect(app.page.refs.computingSpinner ~= nil and app.page.refs.devices == nil and app.page.refs.planAmount == nil, "and shows no lists or plan")
simulators.stock.loaded = true
app:updateRows()
t.expect(app.page.refs.planAmount ~= nil and app.page.refs.planAmount.text ~= "", "a loaded plan has its amount")
t.expect(not app.page.refs.summary.text:find(" 1 runtimes", 1, true) and not app.page.refs.summary.text:find(" 1 devices", 1, true), "counts are pluralized")

-- Overview sections with nothing to show take no place.
app:show("overview")
-- The synthetic disk leaves its media libraries out, so the card names them
-- and asks for no access it does not need.
t.expect(not app.page.refs.notMeasured.hidden and app.page.refs.unmeasured_media ~= nil, "what was not measured is named")
t.expect(app.page.refs.grantAccess == nil, "no access is requested when nothing was refused")
window.size = ns.Size(950, 580); window:layout()
os.exit(t.summary() and 0 or 1)
