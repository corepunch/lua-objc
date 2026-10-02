_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local Format = require("apps.diskmap.helpers.Format")
local Store = require("apps.diskmap.Store")
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.Controller")
local SheetRoute = require("apps.diskmap.pages.SheetRoute")
local Sheets = require("apps.diskmap.pages.Sheets")

-- A sheet is a request: its model answers data() and has an action per button,
-- and the shell hosts the body the framework's page controller draws.
local parent = ns.Window {visible = false, width = 1000, height = 700}

-- Settings: a switch the person flipped goes back when the change is refused.
local saved, errors = true, {}
local flags = {}
local service = {loadSettings = function() return true end, saveSettings = function() return saved end,
	showError = function(title) table.insert(errors, title) end,
	loadFlag = function(name) return flags[name] end, saveFlag = function(name, value) flags[name] = value end}
local notifications = {available = function() return false end, enabled = function() return false end}
local settings = SheetRoute.page(Sheets.settings, "settings", {service = service, model = Store.new("/Users/test"), notifications = notifications,
	rescan = function() end})
settings:open(parent)
t.expect(settings.sheet ~= nil and settings.refs.monitor.state == 1, "Settings opens with the monitor switch on")
t.expect(settings.refs.reminder.disabled == true or not settings.refs.reminder.enabled, "notification switches are off without a notification center")
t.expect(not settings.refs.notificationsUnavailable.hidden, "and the sheet says why")
saved = false
settings.refs.monitor.state = 0
ns._invokeAction(settings.refs.monitor)
t.assertEqual(settings.refs.monitor.state, 1, "a refused save flips the switch back")
t.assertEqual(errors[1], "Could not save Settings", "and says so")
settings:close()
t.expect(settings.sheet == nil and settings.refs == nil, "closing releases the sheet and its refs")
settings:close()

-- History: the log is read each time the sheet draws.
local lines = {}
local history = SheetRoute.page(Sheets.history, "history", {service = {operationLog = function() return lines end}})
history:open(parent)
t.assertEqual(history.refs.entries.rowCount, 0, "an empty log lists nothing")
t.expect(history.refs.detail.text:find("not changed anything", 1, true) ~= nil, "and says so")
table.insert(lines, "2026-09-25T10:00:00Z\tMove to Trash\tok\t1000\t/tmp/a\t")
history:draw()
t.assertEqual(history.refs.entries.rowCount, 1, "a new action appears when the sheet draws again")
history:close()

-- SDKs: sizes being measured show one progress state, then the list.
local pending
local sdkService = {bundles = function() return {{path = "/x/A.sdk", name = "A.sdk"}, {path = "/x/B.sdk", name = "B.sdk", bytes = 5}} end,
	measure = function(_, done) pending = done end}
local sdks = SheetRoute.page(Sheets.sdks, "sdks", {service = sdkService})
sdks:open(parent, {path = "/x", name = "Xcode"})
t.assertEqual(sdks.refs.rows.rowCount, 0, "no half-measured rows while sizes are read")
t.assertEqual(sdks.refs.status.text, "Measuring SDKs…", "the status says what is happening")
pending({1e9})
t.assertEqual(sdks.refs.rows.rowCount, 2, "the list appears once measured")
t.assertEqual(sdks.refs.title.text, "Xcode", "the sheet is titled with the installation")
sdks:close()
pending({2e9})
t.expect(sdks.body == nil, "an answer after closing is dropped")

-- Management: no lists while the scan measures.
local scanning = true
local model = Store.new("/Users/test")
local manager = SheetRoute.page(Sheets.management, "management", {model = model, service = {}, scanning = function() return scanning end,
	rescan = function() end, keep = function() end, open = function() end})
manager:open(parent, "developer")
t.assertEqual(manager.refs.rows1.rowCount, 0, "a category lists nothing while it is measured")
t.assertEqual(manager.refs.status.text, "Measuring…", "and shows one status")
scanning = false
manager:draw()
t.expect(manager.refs.rows1.rowCount > 0, "its locations appear once the scan is done")
manager:close()

-- Snapshot changes: rows and a title from the comparison.
local changes = SheetRoute.page(Sheets.snapshotChanges, "snapshotChanges", {actions = {resource = function() return {} end}})
changes:open(parent, {title = "Since Sep 1", detail = "1 location changed", rows = {{id = "derived", name = "DerivedData", before = "1 GB", size = "2 GB", detail = 0.5, text = "+1 GB"}}})
t.assertEqual(changes.refs.changes.rowCount, 1, "every change is listed")
t.assertEqual(changes.refs.title.text, "Since Sep 1", "under the comparison's title")
changes:close()

-- Review: remeasuring marked items shows one progress state in the list.
local app = Controller.new(Mock.new())
app:createWindow()
local home = app.model.home
app.review:toggle({path = home .. "/Downloads/a.zip", name = "a.zip", bytes = 10})
app.review:open(app.window)
t.assertEqual(app.review.refs.items.rowCount, 1, "the sheet lists the marked item")
t.assertEqual(app.review.selected.path, home .. "/Downloads/a.zip", "and selects it")
app.review.busy = true
app.review:draw()
t.assertEqual(app.review.refs.items.rowCount, 0, "while sizes are measured again the list gives way to one progress state")
t.expect(not app.review.refs.trash.enabled and not app.review.refs.clear.enabled, "and the buttons wait")
app.review.busy = false
app.review:draw()
t.assertEqual(app.review.refs.items.rowCount, 1, "the item returns")
app.review:close()
t.expect(app.review.sheet == nil, "Close dismisses the sheet")
t.assertEqual(app.review:count(), 1, "the basket outlives its sheet")

os.exit(t.summary() and 0 or 1)
