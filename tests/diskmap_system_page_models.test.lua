_G.__headless = true
local t = require("TestKit")
local Controller = require("apps.diskmap.Controller")
local Mock = require("apps.diskmap.services.Mock")

-- The System and Learn pages are models drawn by the framework's page
-- controller: a page is a request, answered with data. While a page's own
-- request runs (a read of the system, a search) it computes, with one
-- spinner and no half-filled rows; a scan shows nothing in progress.
local service = Mock.new()
local app = Controller.new(service)
app:createWindow()

-- Updates & Snapshots asks for installers and snapshots each visit.
app:show("updates")
local updates = app.env:page("updates")
t.expect(app.page.refs.computing == nil and app.page.refs.decisionAction ~= nil, "answered, the page is drawn in full")
updates.installerFiles = nil
t.assertEqual(updates:data({}).computing, "Looking for installers and local snapshots…", "an unanswered request is one status line")
updates.installerFiles, updates.snapshotDates = {}, nil
t.expect(updates:data({}).computing ~= nil, "a pending snapshot list computes too")
updates.snapshotDates = {}
t.expect(updates:data({}).lists == nil, "no installers, no list to fill")
updates.installerFiles = {{path = "/Users/test/Downloads/Tool.dmg", bytes = 2e8}}
local rows = updates:data({}).lists.installers
t.assertEqual(rows[1].detail, "Disk image", "an installer file is a row of the list")
app:show("overview")
t.expect(updates.installerFiles == nil, "leaving the page forgets its answers")

-- Disks & Volumes waits for the disk read.
app:show("disks")
local disks = app.env:page("disks")
t.expect(app.page.refs.volumes ~= nil and disks.volumes ~= nil, "the disk read fills the page")
disks.volumes = nil
t.assertEqual(disks:data({}).computing, "Reading disk information…", "before the read the page computes")
app:show("overview")
t.expect(disks.volumes == nil, "each visit reads the disk again")

-- macOS Folders measures what no scan covers, once the scan is done; while
-- the scan runs the rows say Not measured and nothing spins.
local filesystem = {model = app.env:page("filesystem")}
app.env.model.scan.running, app.env.model.folderSizes = true, nil
t.expect(filesystem.model:data({}).computing == nil, "a running scan is not the page's request")
app.env.model.scan.running = false
t.assertEqual(filesystem.model:data({}).computing, "Measuring folders…", "its own measurement is")
local data = filesystem.model:data({})
local first = data.areas[1].rows[1]
t.expect(data.handlers["reveal_" .. data.areas[1].id .. "_1"] ~= nil and first.calculating == nil, "row buttons are named by the data")

-- Duplicates computes while the search runs, and Stop ends it.
local cancelled = false
service.findDuplicates = function() return {cancel = function() cancelled = true end} end
service.pickFolder = function() return service.home .. "/Library" end
app:show("duplicates")
local duplicates = app.page
duplicates.actions.addFolder()
duplicates.actions.search()
t.expect(duplicates.refs.computing ~= nil and duplicates.refs.computingStatus.text:find("Comparing", 1, true), "a running search is one status line")
t.assertEqual(duplicates.refs.search.title, "Stop", "whose button stops it")
t.expect(not duplicates.refs.addFolder.enabled, "and nothing else starts meanwhile")
duplicates.actions.search()
t.expect(cancelled and duplicates.refs.search.title == "Find Duplicates", "stopping returns the page to ready")

-- The Guide and Help are asked again only when the search or a scan changes.
app:show("guide")
local guide = app.env:page("guide")
local before = guide:data({}).chapters
t.expect(guide:data({}).chapters == before, "the same search is the same answer")
t.expect(guide:data({query = "swap"}).chapters ~= before, "another search is asked again")
t.expect(app.page.actions["open_preboot"] ~= nil, "a topic that opens something has an action")
app:show("help")
t.expect(app.page.refs.help_welcome ~= nil, "Help is the same class under its own id")
os.exit(t.summary() and 0 or 1)
