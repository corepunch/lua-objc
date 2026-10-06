_G.__headless = true
-- Refresh and Stop are one toolbar button, as in SwiftUI's
-- `if scanning { Button("Stop") } else { Button("Refresh") }`: Stop takes
-- Refresh's place while Diskmap measures and gives it back when the scan
-- finishes or is stopped.
local t = require("TestKit")
local bridge = require("AppKitNative")
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.Controller")

local service = Mock.new()
local pending = {}
service.await = function(job, completion) table.insert(pending, {job = job, completion = completion}) end
local app = Controller.new(service)
local window = app:createWindow()

local function item(id)
	for _, entry in ipairs(window.toolbar.items) do if entry.itemIdentifier == id then return entry end end
end
local function ids()
	local list = {}
	for _, entry in ipairs(window.toolbar.items) do table.insert(list, entry.itemIdentifier) end
	return table.concat(list, ",")
end
local order = ids()
t.expect(item("refresh") == nil and item("cancel") == nil, "Refresh and Stop are not separate items")
t.expect(app.env.scan.job ~= nil, "the launch scan is running")
local measure = item("measure")
local button = measure.view
t.assertEqual(measure.label, "Stop", "Stop shows while the launch scan runs")
t.assertEqual(button.toolTip, "Stop measuring", "its tooltip says what it does")

-- Stop cancels and the button becomes Refresh in the same place.
bridge._invokeAction(button)
t.assertEqual(app.env.scan.job, nil, "Stop cancels the measurement")
t.assertEqual(measure.label, "Refresh", "Refresh returns once the scan stops")
t.assertEqual(button.toolTip, "Measure all storage again", "with its own tooltip")
t.expect(item("measure") == measure and measure.view == button, "the same item and button change their content")
t.assertEqual(ids(), order, "no toolbar item moves")

-- Refresh measures again; Stop is back until the scan completes.
bridge._invokeAction(button)
t.expect(app.env.scan.job ~= nil, "Refresh starts a measurement")
t.assertEqual(measure.label, "Stop", "Stop replaces Refresh while measuring")
local last = pending[#pending]
last.completion(last.job.result)
t.assertEqual(app.env.scan.job, nil, "the measurement completes")
t.assertEqual(measure.label, "Refresh", "Refresh returns when the scan completes")
t.assertEqual(ids(), order, "the toolbar keeps its order through the scan")

app.env.scan:dispose(); window:close()
os.exit(t.summary() and 0 or 1)
