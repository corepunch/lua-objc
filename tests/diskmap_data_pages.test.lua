_G.__headless = true
local Locations = require("apps.diskmap.models.Locations")
local t = require("TestKit")
local ns = require("AppKit")
local Store = require("apps.diskmap.Store")
local Model = require("data.model")
local Routes = require("data.routes")
local PageController = require("data.pagecontroller")

-- Large Files, File Types, Applications, Projects and Xcode are routes drawn
-- by the framework's page controller. The scan is shown by the app, so while
-- it runs a page says it is not measured yet; a request of the page's own
-- (a plist, git, a measurement) keeps one page-level spinner, and the page is
-- drawn again when the answer arrives.
local home = "/Users/test"
local refreshed = 0
local function open(id, service, model)
	model = model or Store.new(home)
	model.scan = model.scan or {}
	local actions = {annotate = function(_, rows) return rows end, isMarked = function() return false end,
		isIncluded = function() return false end, covering = function() return nil end,
		file = function() return {} end, application = function() return {} end, folder = function() return {} end,
		reveal = function() return {} end, copyPath = function() return {} end, markAll = function(_, items) return #items end}
	local page
	-- The app draws the page again when asked to.
	local services = {model = model, service = service or {}, actions = actions,
		refresh = function() refreshed = refreshed + 1; if page and page.template then page:update(page.state) end end,
		rescan = function() end, show = function() end}
	services.service = require("apps.diskmap.services.Contract").stub(services.service)
	services.inventories = require("apps.diskmap.services.Inventories").new(services.service, services.refresh, function() return 0 end)
	Model.bind(model)
	local entry = {id = id, title = id, icon = "doc.fill", color = "systemBlue", attrs = {}}
	page = PageController.new({page = entry, request = Routes.page(Routes.find(require("apps.diskmap.routes"), entry), entry, services, "apps.diskmap"),
		ns = ns, viewsDir = "apps/diskmap/views/", store = model})
	page:mount(ns.VStack {}, {query = ""})
	return page, model, services
end

-- Large Files: waiting, then the list; the filter and a kind are the model's.
local model = Store.new(home)
model.scan = {running = true}
model.files = {large = {{path = home .. "/Downloads/a.dmg", bytes = 3e9, used = os.time()}}, old = {}, extensions = {}, oldBytes = 0, oldCount = 0}
local page = open("files", nil, model)
t.expect(page.refs.waiting ~= nil and page.refs.files == nil, "a running scan draws the empty state, not partial rows")
model.scan = {running = false}
page:update({query = ""})
t.expect(page.refs.waiting == nil and page.refs.files ~= nil, "the finished scan is drawn")
t.assertEqual(page.refs.filter.selectedSegment, 1, "the page opens on All measured files")
page.actions.filter(1)
t.assertEqual(page.request.filterIndex, 2, "the picker is the model's filter index")
t.assertEqual(page.refs.filter.selectedSegment, 1, "and the picker follows it")
page.request:focus({kind = "installers", filter = "Installers & archives"})
page:update({query = ""})
t.expect(not page.refs.clearKind.hidden, "a narrowed list offers all kinds")
page.actions.clearKind()
t.expect(page.refs.clearKind.hidden and page.request.kind == nil, "and clearing the kind restores them")
t.assertEqual(page.request.filterIndex, 4, "without touching the filter")
page.request:focus({})
t.assertEqual(page.request.filterIndex, 2, "focusing without a filter opens All")
page:dispose()

-- File Types waits for the scan too.
local kinds = open("kinds", nil, model)
t.assertEqual(kinds.refs.kinds, nil, "File Types lists what the finished scan measured")
kinds:dispose()
model.scan = {running = true}
kinds = open("kinds", nil, model)
t.expect(kinds.refs.waiting ~= nil and kinds.refs.kindsChart == nil, "File Types draws the empty state while the scan runs")
kinds:dispose()

-- Applications: the page's own requests keep one spinner.
model = Store.new(home)
model.scan = {running = false}
model.files = {large = {}, old = {}, extensions = {}, oldBytes = 0, oldCount = 0}
local infoDone, idsDone
local service = require("apps.diskmap.services.Contract").stub({applicationInfo = function(_, done) infoDone = done end, installedBundleIds = function(done) idsDone = done end})
local apps
apps = open("applications", service, model)
t.expect(apps.refs.computing ~= nil and apps.refs.apps == nil, "unanswered requests draw one page-level spinner and no rows")
model.files.measuring = true
t.assertEqual(require("apps.diskmap.models.Inventories"):applicationsSummary(), nil, "the Clean Up summary waits for the measured data folders")
model.files.measuring = nil
t.assertEqual(type(require("apps.diskmap.models.Inventories"):applicationsSummary()), "table", "and states the app totals once they are measured")
local before = refreshed
infoDone({})
t.expect(apps.refs.computing ~= nil and refreshed == before + 1, "an answer asks the app to draw again; the other request is still out")
idsDone({})
apps:update({query = ""})
t.expect(apps.refs.computing == nil and apps.refs.apps ~= nil, "both answers draw the list")
apps.request.app.inventories:load("applications")
t.assertEqual(refreshed, before + 2, "facts load once per set of bundles")
model.scan = {running = true}
apps:update({query = ""})
t.expect(apps.refs.waiting ~= nil and apps.refs.apps == nil, "a running scan draws the empty state")
apps:dispose()

-- Projects: git state is read project by project; leaving ends the visit.
model = Store.new(home)
model.scan = {running = false}
Locations:add("developer", {id = "proj-node", name = "node_modules", path = home .. "/Developer/app/node_modules", project = home .. "/Developer/app", artifact = "node_modules"})
model.measurements["proj-node"] = {status = "complete", bytes = 2e9}
local answers = {}
local projects = open("projects", {
	projectInfo = function(path, done) table.insert(answers, {path = path, done = done}) end}, model)
t.expect(projects.refs.computing ~= nil and projects.refs.projects == nil, "projects wait for their git state")
local stock = require("apps.diskmap.models.Inventories"):state("projects")
t.assertEqual(#answers, 1, "one project is asked at a time")
answers[1].done({git = {branch = "main", changes = 0, ahead = 0, clean = true}, modified = os.time() - 200 * 86400})
t.expect(projects.refs.computing == nil and projects.refs.projects.rowCount == 1, "the answer draws the project")
t.expect(projects.refs.markStale.enabled, "a clean, old project can be marked in bulk")
t.assertEqual(require("apps.diskmap.models.Projects"):badge(), "2.0 GB", "the sidebar badge totals the build data")
local projectModel = projects.request
projects:dispose()
t.expect(projects.template == nil and stock.loaded, "leaving a page ends its visit")
projects:mount(ns.VStack {}, {query = ""})
t.expect(projects.request == projectModel and stock.loaded, "every visit has its own generation")

-- Xcode: folders are read when the page appears; an answer after leaving is ignored.
local measured
local xcodeService = {children = function(path)
	if path:find("iOS DeviceSupport", 1, true) then return {{name = "17.2 (21C62)", path = path .. "/17.2"}, {name = "18.0 (22A)", path = path .. "/18.0"}} end
	return {}
end, measure = function(paths, done) measured = {paths = paths, done = done} end}
local xcode, _, services = open("xcode", xcodeService)
t.expect(xcode.refs.computing ~= nil and xcode.refs.list_support == nil, "Xcode shows one spinner while it measures")
t.assertEqual(require("apps.diskmap.models.Inventories"):xcodeBadge(), nil, "and has no badge yet")
t.assertEqual(#measured.paths, 2, "the unsized folders are measured")
local xcodeModel = xcode.request
xcode:dispose()
measured.done({1e9, 2e9})
t.assertEqual(xcodeModel.stock.loaded, true, "an answer after the visit is retained in the shared inventory")
xcode, _, services = open("xcode", xcodeService)
measured.done({1e9, 2e9})
xcode:update({query = ""})
t.assertEqual(xcode.refs.list_support.rowCount, 2, "the answer draws device support")
t.expect(xcode.refs.derivedSection.hidden and xcode.refs.archivesSection.hidden, "empty sections hide")
t.assertEqual(xcode.refs.xcodeSummary.text, "3.0 GB in device support, build data and archives", "the summary totals the sections")
t.assertEqual(require("apps.diskmap.models.Inventories"):xcodeBadge(), "3.0 GB", "and so does the badge")

os.exit(t.summary() and 0 or 1)
