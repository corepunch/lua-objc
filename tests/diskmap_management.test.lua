_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local Model = require("apps.diskmap.Model")
local Categories = require("apps.diskmap.models.Categories")
local Cleanup = require("apps.diskmap.models.Cleanup")
local Inventory = require("apps.diskmap.models.Inventory")
local AgentFiles = require("apps.diskmap.models.AgentFiles")
local Simulators = require("apps.diskmap.models.Simulators")
local Management = require("apps.diskmap.controllers.ManagementController")
local SimulatorController = require("apps.diskmap.controllers.SimulatorsController")
local model = Model.new("/Users/test")
local paths, ids = {}, {}
for _, row in ipairs(model.resources:leaves()) do
	t.expect(not ids[row.id], "unique ID: " .. row.id); ids[row.id] = true
	if row.path then t.expect(not paths[row.path], "unique measured path: " .. row.id); paths[row.path] = row.id end
end
local runtimePath = "/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime"
t.assertEqual(paths[runtimePath], "runtime-assets", "runtime asset has one ledger owner")
t.assertEqual(model.resources:find("runtime-assets"):getParent().id, "runtimes", "downloaded runtime contributes to runtime category")
model.measurements["runtime-images"] = {bytes = 4096, status = "complete"}
model.measurements["runtime-assets"] = {bytes = 8.5e9, status = "complete"}
model.measurements["runtime-bundles"] = {bytes = 0, status = "complete"}
local xcode = Categories.rows(model, "xcode")
t.assertEqual(xcode[1].bytes, 8.5e9 + 4096, "runtime total includes MobileAsset storage")
t.assertEqual(#Cleanup.suggestions(model), 0, "installed runtimes never become cleanup suggestions")
for _, id in ipairs({"simulators", "documentation-assets", "siri-assets-6", "dictation-1", "voices-1", "codex-plugins", "opencode-other"}) do model.measurements[id] = {bytes = 11e9, status = "complete"} end
local candidates = {}; for _, row in ipairs(Cleanup.suggestions(model)) do candidates[row.id] = row end
t.expect(candidates.simulators and candidates["documentation-assets"] and candidates["siri-assets-6"], "devices, offline documentation and Siri are actionable review candidates")
t.assertEqual(candidates["siri-assets-6"].impact, "Needs review", "protected assets only suggest review")
t.expect(candidates["codex-plugins"] and candidates["opencode-other"], "opaque agent storage surfaces for review")
model.kept["system-data"] = true
t.expect(not model.resources:find("siri-assets-6"):validateTrash(), "system asset has no trash path")
local fixture = {{agent = "codex", name = "state_99.sqlite", path = "/Users/test/.codex/state_99.sqlite"}, {agent = "opencode", name = "opencode.db-wal", path = "/Users/test/.local/share/opencode/opencode.db-wal"}}
AgentFiles.add(model, fixture); local leafCount = #model.resources:leaves(); AgentFiles.add(model, fixture)
t.assertEqual(#model.resources:leaves(), leafCount, "metadata discovery is idempotent")
local row = model.resources:find("codex-file-state_99.sqlite")
t.expect(row and row.name:find("Database", 1, true), "new database versions have named paths")
t.assertEqual(row.action, "finder", "persistent SQLite files cannot be cleared as cache")
local _, _, exclusions = Inventory.plan(model); local found = false
for _, path in ipairs(exclusions) do if path == row.path then found = true end end
t.expect(found, "discovered file is excluded from agent residual")
t.assertEqual(#Categories.managementRows(model, "codex", "state_99.sqlite"), 1, "management searches exact paths")
t.assertEqual(#Categories.managementRows(model, "codex", "["), 0, "management search is literal")
t.assertEqual(#Categories.managementRows(model, "runtimes", nil, "Safe/rebuildable"), 0, "runtime cannot appear under safe reclaim")
t.expect(model.resources:find("grok-other") ~= nil, "Grok known local root is scanned")
local uid = "12345678-ABCD-1234-ABCD-123456789ABC"
local other = "12345678-ABCD-1234-ABCD-123456789ABD"
local data = {runtimes = {{identifier = "ios", name = "iOS 26"}}, devices = {ios = {
	{udid = uid, name = "Test iPhone", dataPathSize = 11e9, lastUsedAt = "2026-09-22T11:40:44Z", isAvailable = true, state = "Shutdown"},
	{udid = other, name = "Old iPad", isAvailable = false, state = "Shutdown"},
}}}
local rows = Simulators.rows(data)
t.assertEqual(rows[1].size, "11.0 GB", "simctl data size is shown")
t.assertEqual(rows[1].runtime, "iOS 26", "runtime identifier resolves to display name")
t.expect(rows[1].lastUse:find("UTC", 1, true), "last use has explicit timezone")
t.assertEqual(rows[2].lastUse, "Not recorded", "unknown last use is never invented")
t.assertEqual(rows[2].size, "Not measured", "unknown size is not zero")
t.assertEqual(#Simulators.rows(data, "old", "Unavailable"), 1, "unavailable tab filters and searches")
t.assertEqual(Simulators.command("delete", rows[1])[4], uid, "command uses exact device ID")
t.expect(not Simulators.command("erase", rows[2]), "unavailable devices cannot be erased")
rows[1].running = true
t.expect(not Simulators.command("delete", rows[1]), "running devices cannot be deleted")
rows[1].running = false; rows[1].id = "all"
t.expect(not Simulators.command("delete", rows[1]), "wildcard deletion is forbidden")
local calls, confirmed, refreshed = {}, false, 0
local service = {command = function(argv, completion) calls[#calls + 1] = {argv = argv, done = completion} end,
	decode = function() return data end, confirmAction = function() return confirmed end,
	reveal = function() end, openSettings = function() end}
local controller = SimulatorController.new(model, service, function() refreshed = refreshed + 1 end)
controller.filters = {"All devices", "Unavailable"}; controller.inventory = data; controller.selected = Simulators.rows(data)[1]
t.expect(not controller:perform("erase"), "cancel confirmation never launches a command")
t.assertEqual(#calls, 0, "cancel has no side effects")
confirmed = true; model.kept.simulators = true
t.expect(not controller:perform("delete"), "Keep protects simulator contents")
model.kept.simulators = nil
t.expect(controller:perform("delete", true), "unavailable deletion requires explicit confirmation")
t.assertEqual(#calls, 1, "only selected unavailable device is targeted")
t.assertEqual(calls[1].argv[4], other, "unavailable command is a concrete ID, never an expanding selector")
t.expect(not controller:perform("delete", true), "duplicate clicks cannot start concurrent mutations")
calls[1].done(false, "device busy")
t.assertEqual(refreshed, 1, "failed action refreshes potentially changed totals")
t.expect(controller.error:find("device busy", 1, true), "command failures remain visible")
controller:load(); local pending = calls[#calls]; controller:close(); pending.done(true, "{}");
t.assertEqual(controller.inventory.devices, nil, "late results cannot populate a closed sheet")
-- Native controls and resize contracts, without showing windows.
model.measurements.archives = {bytes = 20e9, status = "complete"}
model.measurements.derived = {bytes = 12e9, status = "complete"}
local manager = Management.new(model, service, function() end, function() end, function() end)
local parent = ns.Window {visible = false, width = 1000, height = 700}
manager:open(parent, "developer")
t.assertEqual(manager.sheet.className, "LuaPanel", "management uses a native sheet-capable panel")
t.assertEqual(manager.refs.tabs.className, "LuaTabView", "impact tabs are native")
local function resourceAt(index)
	return bridge._tableCell(manager.refs.rows1, 0, index).textField.stringValue
end
t.assertEqual(resourceAt(0), "Archives", "management starts with largest measured resource")
manager:sortBy("name")
local positions = {}
for index = 0, manager.refs.rows1.rowCount - 1 do positions[resourceAt(index)] = index end
t.expect(positions.Archives < positions["Xcode DerivedData"], "resource header sorts names ascending")
manager:sortBy("name")
positions = {}
for index = 0, manager.refs.rows1.rowCount - 1 do positions[resourceAt(index)] = index end
t.expect(positions["Xcode DerivedData"] < positions.Archives, "repeated resource sort reverses direction")
manager:sortBy("impact")
local previousImpact = ""
for index = 0, manager.refs.rows1.rowCount - 1 do
	local impact = bridge._tableCell(manager.refs.rows1, 1, index).textField.stringValue:lower()
	t.expect(previousImpact <= impact, "impact header sorts impact values")
	previousImpact = impact
end
manager:select("runtime-assets")
t.expect(manager.refs.manage.enabled, "runtime can be revealed for inspection")
t.expect(manager.refs.detail.text ~= "", "selected resource has consequences")
for _, size in ipairs({{800, 560}, {1100, 780}}) do
	manager.sheet:resize(size[1], size[2]); manager.sheet:layout()
	local width, height = manager.refs.rows1.size.width, manager.refs.rows1.size.height
	t.expect(width > 400 and height > 80, "native table retains usable geometry after resize")
end
manager.query = "no such resource"; manager:update()
t.assertEqual(manager.refs.rows1.rowCount, 0, "empty management search")
t.expect(not manager.refs.manage.enabled and not manager.refs.reveal.enabled, "empty result clears destructive and reveal actions")
manager:close()
local simulatorUI = SimulatorController.new(model, service, function() end)
simulatorUI:open(parent)
calls[#calls].done(true, "{}")
simulatorUI.refs.rows1:selectRow(0)
t.expect(simulatorUI.refs.erase.enabled and simulatorUI.refs.delete.enabled, "native selection enables actions for a shutdown device")
t.assertEqual(simulatorUI.refs.done.keyEquivalent, "\r", "sheet Done is the native default action")
simulatorUI.refs.rows1:selectRow(1)
t.expect(not simulatorUI.refs.erase.enabled and simulatorUI.refs.delete.enabled, "unavailable device allows delete but not erase")
simulatorUI:close(); parent:close()
local native = require("StorageScan")
t.assertThrows(function() native.commandStart({}) end, "empty command rejected")
t.assertThrows(function() native.commandStart({"/bin/echo", "bad\0argument"}) end, "NUL command arguments rejected")
os.exit(t.summary() and 0 or 1)
