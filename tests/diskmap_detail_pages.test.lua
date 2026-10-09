_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local Controller = require("apps.diskmap.Controller")
local Mock = require("apps.diskmap.services.Mock")
local service = Mock.new()
local saved, errors = true, {}
service.loadSettings = function() return true end
service.saveSettings = function() return saved end
service.showError = function(title) table.insert(errors, title) end
local app = Controller.new(service)
app:createWindow()
app:openSettings()
local settings = app.env.settings
t.expect(app.destination == "settings" and settings.refs.monitor.state == 1, "Settings is a normal page with current preferences")
saved = false
settings.refs.monitor.state = 0
ns._invokeAction(settings.refs.monitor)
t.assertEqual(settings.refs.monitor.state, 1, "a refused save restores the native switch")
t.assertEqual(errors[1], "Could not save Settings", "a refused save explains the error")
app.navigation:back()
t.assertEqual(app.destination, "overview", "Back leaves Settings")
app:show("history")
t.assertEqual(app.page.refs.entries.rowCount, 0, "empty history has no rows")
t.expect(app.page.refs.entries.hidden and not app.page.refs.historyEmpty.hidden, "empty history explains itself without an empty table")
app:open("xcode-app")
t.assertEqual(app.destination, "sdks", "SDKs navigate in the same window")
t.expect(app.page.refs.rows ~= nil, "the SDK page renders its rows")
local sdkLocation = app:location()
app:show("overview")
app.navigation:back()
t.assertEqual(app:location(), sdkLocation, "SDK installation survives Back")
app.env.snapshots = {result = {title = "Since Sep 1", detail = "1 location changed", rows = {{id = "derived", name = "DerivedData", before = "1 GB", size = "2 GB"}}}}
app:show("snapshotChanges")
t.assertEqual(app.window.title, "Since Sep 1", "comparison page is titled by the current result")
t.assertEqual(app.page.refs.changes.rowCount, 1, "comparison page lists every change")
bridge._flushLayout()
t.expect(app.page.refs.pageHeader == nil, "the page has no heading of its own; the window title names it")
t.expect(app.page.refs.changes.frame.size.height > 200, "the comparison table fills the available workspace")
local width = 0
for _, column in ipairs(bridge._tableColumnWidths(app.page.refs.changes)) do width = width + column.minWidth end
t.expect(width <= 595, "comparison columns leave room for a review flag in a narrow window")
t.expect(app.window.attachedSheet == nil, "none of the detail pages attach a modal sheet")
app.env.snapshots = nil
app:dispose()
os.exit(t.summary() and 0 or 1)
