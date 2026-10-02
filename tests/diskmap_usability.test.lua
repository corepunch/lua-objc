_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Model = require("apps.diskmap.Model")
local Mock = require("apps.diskmap.services.Mock")
local Inventory = require("apps.diskmap.models.Inventory")
local Scan = require("apps.diskmap.controllers.ScanController")
local Simulators = require("apps.diskmap.models.Simulators")
local SimulatorController = require("apps.diskmap.controllers.SimulatorsController")
local Controller = require("apps.diskmap.Controller")
local Recommendations = require("apps.diskmap.models.Recommendations")
local Categories = require("apps.diskmap.models.Categories")
local System = require("apps.diskmap.services.System")

-- Command failures and malformed JSON remain distinct from an empty result.
local command, answer, success = System.command, nil, true
local observed
System.command = function(argv, done) observed = argv; done(success, answer) end
answer = '{"devices":{}}'
local listed, listingError
System.simulatorDevices(function(value, error) listed, listingError = value, error end)
t.expect(listed and listed.devices and listingError == nil, "valid empty device listing succeeds")
t.assertEqual(observed[3], "list", "device inventory asks simctl for live state")
answer, success = "CoreSimulator connection failed", false
System.simulatorDevices(function(value, error) listed, listingError = value, error end)
t.expect(listed == nil and listingError:find("Retry", 1, true), "failed device command returns an actionable error")
success = true
System.simulatorRuntimes(function(value, error) listed, listingError = value, error end)
t.expect(listed == nil and listingError:find("Retry", 1, true), "malformed runtime JSON is not an empty inventory")
System.command = command

-- A single large location may keep the completed count unchanged for minutes.
-- Its file findings and live counters must still reach pages; none is a final
-- reclaim estimate, and cancelling must retain the useful partial findings.
local model = Model.new("/Users/test")
local paths, ids = Inventory.plan(model)
local pending
local scan = Scan.new(model, {
	start = function() return {} end,
	await = function(_, done, progress) pending = {done = done, progress = progress} end,
	cancel = function() end,
	diskSpace = function() return {totalKb = 256e9 / 1024, freeKb = 4.5e9 / 1024} end,
}, model.home)
scan:start()
local function progress(visited, seconds)
	pending.progress({completed = 0, total = #ids, visited = visited, seconds = seconds,
		currentPath = model.home .. "/Downloads", largeFiles = {{path = model.home .. "/Downloads/installer.dmg", bytes = 2e9, used = os.time()}},
		extensions = {{extension = "dmg", count = 1, bytes = 2e9}}})
end
progress(10, 1)
t.expect(model.files.measuring and model.files.partial, "live file ranking is marked incomplete")
t.assertEqual(model.files.large[1].bytes, 2e9, "large file is available before a root finishes")
t.expect(scan.status:find("Measuring ~/Downloads", 1, true) ~= nil, "current location is shown")
local first = scan.status
progress(50, 8)
t.expect(first ~= scan.status and scan.status:find("50 items checked", 1, true), "same completed count still advances live counters")
t.expect(not scan.status:find("%%"), "root count does not masquerade as time progress")
t.expect(not Categories.coverage(model, scan.disk):find("not attributed", 1, true), "in-progress coverage is not reported as unexplained usage")
local chart = require("apps.diskmap.models.Overview").chart(model, scan.service.diskSpace())
t.assertEqual(chart.marks[1].label, "Not measured yet", "unfinished chart names the pending allocation")
t.expect(chart.explanation:find("still arriving", 1, true), "unfinished chart explains its gray sector")
local apps = require("apps.diskmap.controllers.ApplicationsController").new({model = model, service = {}, actions = {}})
t.assertEqual(apps:summary(), nil, "live file findings do not imply app-data breakdowns are ready")
local filesPage = require("apps.diskmap.models.FilesPage").new({storage = model, session = {query = ""}}, {service = {}, actions = {
	file = function() return {} end, annotate = function(_, rows) return rows end,
	isMarked = function() return false end, isIncluded = function() return false end,
	handlers = {},
}})
filesPage:prepare()
t.assertEqual(#filesPage.rows, 1, "partial file appears in the list")
t.expect(filesPage:summary():find("Found so far", 1, true), "file page names partial results")
scan:cancel()
t.expect(not model.files.measuring and model.files.partial, "cancellation keeps findings as a lower bound")
scan:start()
t.assertEqual(model.files, nil, "refresh clears file findings before collecting a new scan")
filesPage.storage = model
filesPage:prepare()
t.assertEqual(filesPage:largeTile().value, "—", "refresh clears displayed file totals from the previous scan")
t.expect(not filesPage.noResults and not filesPage.emptyFilter, "loading does not show an empty-result message")
pending.done({largeFiles = {}, extensions = {}, trees = {}, rootStates = {}})
t.expect(not model.files.measuring and not model.files.partial, "final summary clears in-progress flags")

-- A folder and a missing timestamp are not evidence of an unused device.
local uuid = "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE"
local runtime = "com.apple.CoreSimulator.SimRuntime.iOS-26-5"
local service = {
	children = function() return {{name = uuid, path = model.home .. "/Devices/" .. uuid, bytes = 4e9}} end,
	readPropertyList = function() return {name = "iPhone", runtime = runtime} end,
}
local unknown = Simulators.discover(service, model.home)
local row = Simulators.rows(unknown)[1]
t.assertEqual(row.lastUse, "Last use unknown", "no boot date does not imply never started")
t.assertEqual(row.available, nil, "filesystem discovery cannot prove runtime availability")
t.assertEqual(#Simulators.rows(unknown, nil, "Unavailable"), 0, "unknown device is not falsely called unavailable")
t.assertEqual(#Simulators.rows(unknown, nil, "Unused for 90 days"), 0, "unknown age cannot qualify as stale")
local ok, reason = Simulators.validate("delete", row)
t.expect(not ok and reason.code == "state_unknown", "unknown running state prevents device deletion")
local live = {devices = {[runtime] = {{udid = uuid, state = "Booted", isAvailable = true}}}}
t.expect(Simulators.rows(Simulators.discover(service, model.home, live))[1].running, "live simulator state reaches the row")
live.devices[runtime][1].state = "Creating"
t.expect(not Simulators.validate("delete", Simulators.rows(Simulators.discover(service, model.home, live))[1]), "unrecognized state is not treated as shutdown")
live.devices[runtime][1].state = "Shutdown"
t.expect(Simulators.validate("erase", Simulators.rows(Simulators.discover(service, model.home, live))[1]), "verified shutdown device can be reviewed for erase")
service.simulatorDevices = function(done) done(nil, "Device state could not be checked. Retry.") end
service.simulatorRuntimes = function(done) done(nil, "Runtimes could not be read. Retry.") end
local simulator = SimulatorController.new({model = model, service = service, rescan = function() end})
simulator:mount(ns.VStack {}, {query = ""})
t.expect(simulator.refs.devicesDetail.text:find("could not be checked for availability", 1, true) ~= nil, "failed availability check is not a fabricated zero")
t.expect(not simulator.refs.devicesDetail.text:find("unavailable,", 1, true), "runtime failure does not promise availability")
t.expect(not simulator.refs.summary.text:find("0 runtimes", 1, true), "failed runtime listing is not an empty inventory")
t.expect(simulator.refs.retry.enabled, "failed reads can be retried")
simulator.refs.devices:selectRow(0)
t.expect(not simulator.refs.erase.enabled and not simulator.refs.delete.enabled, "unverified devices cannot be erased or deleted")
t.expect(simulator.refs.status.text:find("could not be checked", 1, true), "disabled action explains how to proceed")
local token = simulator.loadToken
simulator:dispose()
simulator:finish(token, live, {})
t.assertEqual(simulator.refs, nil, "late replies cannot remount a disposed page")
t.assertEqual(simulator.inventory, live, "but they still record the inventory for the next visit")

-- Low-space launch reaches the inventory without a ten-page modal detour.
local mock = Mock.new()
mock.hasFullDiskAccess = function() return true end
local app = Controller.new(mock)
app:createWindow()
app.tour:finish()
local disk = {totalKb = 256e9 / 1024, freeKb = 4.5e9 / 1024}
t.expect(not app.tour:needed(disk), "low-space launch bypasses automatic tour")
t.expect(app.tour:needed({totalKb = 256e9 / 1024, freeKb = 100e9 / 1024}), "normal-space launch preserves the tour preference")
app:show("cleanup")
local page = app.page
local data = Recommendations.presentation(app.model, "")
local expected = data.decisions[1]
-- #102: with nothing selected the inspector takes no space.
t.expect(page.refs.selectionDetails.hidden, "an empty inspector is hidden until a suggestion is selected")
page.refs.list_rebuildable:selectRow(0)
t.expect(not page.refs.selectionDetails.hidden, "selecting a suggestion shows the inspector")
page.refs.list_decisions:selectRow(0)
t.assertEqual(page.selectedRow.id, expected.id, "single selection chooses its suggestion")
t.assertEqual(page.refs.list_rebuildable.documentView.selectedRow, -1, "selecting a different section clears the previous highlight")
t.assertEqual(page.detailsTemplate.refs.selectionAdvice.text, expected.subtitle, "full advice is shown without truncation")
t.expect(page.detailsTemplate.refs.openSelection.title:find("Open", 1, true) == 1, "selected suggestion has a visible detail action")
page:update(app:state())
t.assertEqual(page.selectedRow.id, expected.id, "live measurements preserve the selection by id")
t.assertEqual(page.detailsTemplate.refs.selectionAdvice.text, expected.subtitle, "refresh keeps the matching explanation")
page:update({query = "no-such-suggestion", disk = disk})
t.assertEqual(page.selectedRow, nil, "filtering away a suggestion removes the stale detail")
t.expect(page.refs.selectionDetails.hidden, "an empty selection hides the inspector, so no stale item can be opened")
local opened
page.handlers.show = function(id, filter) opened = {id, filter} end
page.selectedRow = {id = "unused-apps", page = "applications", filter = "Unused for 6 months"}
page:showDetails()
page.detailsTemplate.actions.openSelection()
t.assertEqual(opened[1], "applications", "visible action navigates to the suggested page")
t.assertEqual(opened[2], "Unused for 6 months", "visible action preserves its review filter")
local long = string.rep("Keep personal documents. Review installed test apps and their data. ", 12)
local detail, refs = xml.renderFile("apps/diskmap/views/SelectionDetails.etlua", {title = "A very long suggestion name", detail = long, actionTitle = "Open Simulators…", size = "25.7 GB"}, ns)
detail.size = ns.Size(540, 700); detail:layout(540)
t.expect(refs.selectionAdvice.frame.size.height > 40, "long consequences wrap over multiple lines")
t.expect(refs.openSelection.frame.size.width >= refs.openSelection.fittingSize.width, "explicit action fits at narrow width")
os.exit(t.summary() and 0 or 1)
