local O = require("tests.support.diskmap_operations")
_G.__headless = true
local Locations = require("apps.diskmap.models.Locations")
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local Store = require("apps.diskmap.Store")
local Simulators = require("apps.diskmap.helpers.Simulators")
local Host = require("tests.diskmap_page")
local Scans = require("apps.diskmap.models.Scans")
local Categories = require("apps.diskmap.models.Categories")
local Suggestions = require("apps.diskmap.models.Suggestions")
local model = Store.new("/Users/test")
local paths, ids = {}, {}
for _, row in ipairs(Locations:leaves()) do
	t.expect(not ids[row.id], "unique ID: " .. row.id); ids[row.id] = true
	if row.path then t.expect(not paths[row.path], "unique measured path: " .. row.id); paths[row.path] = row.id end
end
local runtimePath = "/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime"
t.assertEqual(paths[runtimePath], "runtime-assets", "runtime asset has one ledger owner")
t.assertEqual(Locations:find("runtime-assets"):parent().id, "runtimes", "downloaded runtime contributes to runtime category")
model.measurements["runtime-images"] = {bytes = 4096, status = "complete"}
model.measurements["runtime-assets"] = {bytes = 8.5e9, status = "complete"}
model.measurements["runtime-bundles"] = {bytes = 0, status = "complete"}
local xcode = Categories:rows("xcode")
t.assertEqual(xcode[1].bytes, 8.5e9 + 4096, "runtime total includes MobileAsset storage")
t.assertEqual(#Suggestions:ranked(), 0, "installed runtimes never become cleanup suggestions")
for _, id in ipairs({"simulators", "documentation-assets", "siri-assets-6", "dictation-1", "voices-1", "codex-plugins", "opencode-other"}) do model.measurements[id] = {bytes = 11e9, status = "complete"} end
local candidates = {}; for _, row in ipairs(Suggestions:ranked()) do candidates[row.id] = row end
t.expect(candidates.simulators and candidates["documentation-assets"] and candidates["voices-1"], "devices, offline documentation and downloaded voices are actionable review candidates")
t.expect(not candidates["siri-assets-6"] and not candidates["dictation-1"], "Siri and Dictation assets are never suggested: turning the feature off promises nothing")
local context = {}; for _, row in ipairs(Suggestions:context()) do context[row.id] = row end
t.expect(context["siri-assets-6"] and context["dictation-1"], "Siri and Dictation assets are system-managed context instead")
t.expect(not candidates["codex-plugins"] and not candidates["opencode-other"], "opaque agent storage has no threshold and is never suggested")
model.kept["system-data"] = true
t.expect(not Locations:find("siri-assets-6"):validateTrash(), "system asset has no trash path")
local fixture = {{agent = "codex", name = "state_99.sqlite", path = "/Users/test/.codex/state_99.sqlite"}, {agent = "opencode", name = "opencode.db-wal", path = "/Users/test/.local/share/opencode/opencode.db-wal"}}
Locations:addAgentFiles(fixture); local leafCount = #Locations:leaves(); Locations:addAgentFiles(fixture)
t.assertEqual(#Locations:leaves(), leafCount, "metadata discovery is idempotent")
local row = Locations:find("codex-file-state_99.sqlite")
t.expect(row and row.name:find("Database", 1, true), "new database versions have named paths")
t.assertEqual(row.action, "finder", "persistent SQLite files cannot be cleared as cache")
local _, _, exclusions = Scans:plan(); local found = false
for _, path in ipairs(exclusions) do if path == row.path then found = true end end
t.expect(found, "discovered file is excluded from agent residual")
t.expect(Locations:find("grok-other") ~= nil, "Grok known local root is scanned")
local uid = "12345678-ABCD-1234-ABCD-123456789ABC"
local other = "12345678-ABCD-1234-ABCD-123456789ABD"
local data = {runtimes = {{identifier = "ios", name = "iOS 26"}}, devices = {ios = {
	{udid = uid, name = "Test iPhone", dataPathSize = 11e9, lastUsedAt = "2026-09-22T11:40:44Z", isAvailable = true, state = "Shutdown"},
	{udid = other, name = "Old iPad", isAvailable = false, state = "Shutdown"},
}}}
local rows = Simulators.rows(data, nil, os.time({year = 2026, month = 9, day = 25, hour = 12}))
t.assertEqual(rows[1].size, "11.0 GB", "simctl data size is shown")
t.assertEqual(rows[1].runtime, "iOS 26", "runtime identifier resolves to display name")
t.assertEqual(rows[1].lastUse, "Used 3 days ago", "last use is relative, never a raw timestamp")
t.assertEqual(rows[1].state, "Shutdown", "a recorded state is shown")
t.assertEqual(rows[2].lastUse, "Last use unknown", "missing last use is unknown, never claimed unused")
t.assertEqual(rows[2].size, "Not measured", "unknown size is not zero")
t.assertEqual(#Simulators.rows(data, "Unavailable"), 1, "the unavailable tab lists unavailable devices")
t.assertEqual(Simulators.command("delete", rows[1])[4], uid, "command uses exact device ID")
t.expect(not Simulators.command("erase", rows[2]), "unavailable devices cannot be erased")
rows[1].running = true
t.expect(not Simulators.command("delete", rows[1]), "running devices cannot be deleted")
rows[1].running = false; rows[1].id = "all"
t.expect(not Simulators.command("delete", rows[1]), "wildcard deletion is forbidden")
local calls, confirmed, refreshed = {}, false, 0
local service = require("apps.diskmap.services.Contract").stub({command = function(argv, completion) table.insert(calls, {argv = argv, done = completion}) end,
	decode = function() return data end, confirmAction = function() return confirmed end,
	reveal = function() end, openSettings = function() end, openOwner = function() end})
local _, controller = Host.new("simulators", {model = model, service = service, rescan = function() error("a simulator action never measures the disk again") end, removed = function() error("a failed action removes nothing") end, refresh = function() refreshed = refreshed + 1 end})
controller.stock.inventory = data; controller.selected = Simulators.rows(data)[1]
t.expect(not controller:erase(), "cancel confirmation never launches a command")
t.assertEqual(#calls, 0, "cancel has no side effects")
confirmed = true; model.kept.simulators = true
t.expect(not controller:delete(), "Keep protects simulator contents")
model.kept.simulators = nil
t.expect(controller:unavailable(), "unavailable deletion requires explicit confirmation")
t.assertEqual(#calls, 1, "only selected unavailable device is targeted")
t.assertEqual(calls[1].argv[4], other, "unavailable command is a concrete ID, never an expanding selector")
t.expect(not controller:unavailable(), "duplicate clicks cannot start concurrent mutations")
calls[1].done(false, "device busy")
t.assertEqual(refreshed, 1, "a failed action draws the page again with its error")
t.expect(controller.error:find("device busy", 1, true), "command failures remain visible")
service.simulatorRuntimes = function(completion) table.insert(calls, {done = completion}) end
controller:load(); local pending = calls[#calls]; pending.done({})
-- #100: a load belongs to the inventory, not to one visit of the page.
t.assertEqual(type(controller.stock.runtimeList), "table", "a load that finishes after its page closed still records the inventory")
t.expect(not controller.stock.busy and controller.stock.loaded, "and leaves the controller ready for the next visit")
-- Native controls and resize contracts, without showing windows.
model.measurements.archives = {bytes = 20e9, status = "complete"}
model.measurements.derived = {bytes = 12e9, status = "complete"}
local runtimeId = "0A1B2C3D-4E5F-4A6B-8C7D-9E0F1A2B3C4D"
local runtimeList = {[runtimeId] = {identifier = runtimeId, runtimeIdentifier = "ios", version = "26.0", build = "23A339",
	platformIdentifier = "com.apple.platform.iphonesimulator", deletable = true, sizeBytes = 8.4e9}}
service.simulatorRuntimes = function(completion) completion(runtimeList) end
local host = ns.VStack {}
local simulatorUI, simulatorModel = Host.new("simulators", {model = model, service = service})
simulatorUI:mount(host, {query = ""})
simulatorModel.stock.inventory, simulatorModel.stock.runtimeList = data, runtimeList
simulatorUI:update({query = ""})
t.assertEqual(simulatorUI.refs.filter.className, "NSSegmentedControl", "device filters are a segmented control")
t.assertEqual(simulatorUI.refs.devices.rowCount, 2, "every device is listed")
t.assertEqual(simulatorUI.refs.runtimes.rowCount, 1, "installed runtimes are listed")
t.assertEqual(simulatorUI.presented.subtitle, "11.0 GB stored in 2 devices · 8.4 GB in 1 runtime", "the header states totals stored, not recoverable")
t.expect(simulatorUI.refs.devicesDetail.text:find("1 device unavailable", 1, true) ~= nil, "the inventory counts devices without a runtime")
t.expect(O(simulatorUI, "deleteUnavailable").enabled, "unavailable devices can be deleted together")
simulatorUI.refs.devices:selectRow(0)
t.expect(O(simulatorUI, "erase").enabled and O(simulatorUI, "delete").enabled, "native selection enables actions for a shutdown device")
t.assertEqual(O(simulatorUI, "reveal").title, "Show in Finder", "a device can be revealed in Finder")
simulatorUI.refs.devices:selectRow(1)
t.expect(not O(simulatorUI, "erase").enabled and O(simulatorUI, "delete").enabled, "unavailable device allows delete but not erase")
simulatorUI.refs.runtimes:selectRow(0)
t.expect(O(simulatorUI, "deleteRuntime").enabled, "a deletable runtime can be deleted")
model.kept.runtimes = true
-- Reselecting the same row is not a selection change, so draw again.
simulatorUI:update({query = ""})
t.expect(not O(simulatorUI, "deleteRuntime").enabled, "Keep protects runtimes")
t.expect(simulatorUI.refs.runtimeStatus.text:find("Keep", 1, true) ~= nil, "a disabled runtime action explains why")
model.kept.runtimes = nil
-- The inventory is secondary: collapsed until its disclosure is opened.
local inventory = simulatorUI.refs.inventory
t.expect(inventory.subviews[2].hidden, "the device inventory starts collapsed below the plan")
ns._invokeAction(inventory.subviews[1].subviews[2])
t.expect(not inventory.subviews[2].hidden, "opening the disclosure shows the inventory")
host.size = ns.Size(880, 580); host:layout(880)
for _, name in ipairs({"reveal", "erase", "delete", "deleteRuntime", "deleteUnavailable", "components"}) do
	t.expect(O(simulatorUI, name).title ~= "", name .. " has a toolbar label")
	t.assertEqual(simulatorUI.refs[name], nil, name .. " has no duplicate inline button")
end
simulatorUI:dispose()
t.assertEqual(simulatorUI.refs, nil, "disposing the page releases its refs")
local native = require("StorageScan")
t.assertThrows(function() native.commandStart({}) end, "empty command rejected")
t.assertThrows(function() native.commandStart({"/bin/echo", "bad\0argument"}) end, "NUL command arguments rejected")
os.exit(t.summary() and 0 or 1)
