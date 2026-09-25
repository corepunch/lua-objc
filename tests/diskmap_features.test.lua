_G.__headless = true
local t = require("TestKit")
local Model = require("apps.diskmap.Model")
local Cleanup = require("apps.diskmap.models.Cleanup")
local Tips = require("apps.diskmap.models.Tips")
local Inspector = require("apps.diskmap.models.Inspector")
local Scan = require("apps.diskmap.controllers.ScanController")
local CleanupController = require("apps.diskmap.controllers.CleanupController")
local CategoriesController = require("apps.diskmap.controllers.CategoriesController")
local InspectorController = require("apps.diskmap.controllers.InspectorController")
local TipsController = require("apps.diskmap.controllers.TipsController")
local SettingsController = require("apps.diskmap.controllers.SettingsController")
local Rules = require("apps.diskmap.knowledge.CleanupRules")
local model = Model.new("/Users/test")
for id, rule in pairs(Rules) do
	t.expect(model.resources:find(id) ~= nil, "rule has a known resource: " .. id)
	model.measurements[id] = {bytes = rule.threshold - 1, status = "complete"}
end
t.assertEqual(#Cleanup.suggestions(model), 0, "below-threshold resources produce no suggestions")
model.measurements.simulators.bytes = Rules.simulators.threshold
local suggestions = Cleanup.suggestions(model)
t.assertEqual(#suggestions, 1, "threshold boundary includes one recognized resource")
t.assertEqual(suggestions[1].id, "simulators", "simulator knowledge is selected")
t.expect(suggestions[1].subtitle:find("test apps", 1, true) ~= nil, "suggestion explains consequences")
t.expect(suggestions[1].evidence:find("Review threshold", 1, true) ~= nil, "suggestion explains why it appeared")
model.measurements.projects = {bytes = 900e9, status = "complete"}
model.measurements["xcode-app"] = {bytes = 200e9, status = "complete"}
t.assertEqual(#Cleanup.suggestions(model), 1, "large projects and installations do not become cleanup opportunities")
for _, status in ipairs({"failed", "denied", "skipped"}) do
	model.measurements.simulators.status = status
	t.assertEqual(#Cleanup.suggestions(model), 0, "uncertain measurement cannot recommend cleanup: " .. status)
end
model.measurements.simulators.status = "partial"
t.assertEqual(Cleanup.suggestions(model)[1].impact, "Needs review", "partial measurements still offer review")
t.expect(Cleanup.suggestions(model)[1].size:find("≥", 1, true), "partial review is explicitly a lower bound")
model.measurements.simulators.status = "complete"
model.kept.xcode = true
t.assertEqual(#Cleanup.suggestions(model), 0, "keeping parent suppresses all descendant recommendations")
model.kept.xcode = nil
local selected, saved, refreshed = nil, 0, 0
local keepMessage
local cleanup = CleanupController.new(model, {saveKeep = function() saved = saved + 1; return true end}, function(id) selected = id end, function(message) keepMessage = message end)
local presentation = cleanup:presentation(); presentation.actions.review_simulators()
t.assertEqual(selected, "simulators", "review callback keeps resource identity")
t.assertEqual(#cleanup:rows("unfindable"), 0, "cleanup filter is independent")
cleanup:toggleKeep("simulators")
t.assertEqual(saved, 1, "keep change persists the preference")
t.assertEqual(model.measurements.projects.bytes, 900e9, "keep preserves unrelated measured state")
cleanup:toggleKeep("simulators")
t.assertEqual(saved, 2, "unkeep change also saves")
t.assertEqual(keepMessage, nil, "successful persistence does not report an error")
t.assertEqual(#cleanup:rows(), 1, "unkeep restores eligible resource")
t.assertEqual(#Tips.forInventory(model, {totalKb = 100, freeKb = 40}), 1, "ordinary capacity gets the system tip")
model.scan.errors = 4
local tips = Tips.forInventory(model, {totalKb = 100, freeKb = 9})
t.assertEqual(tips[1].id, "access", "access evidence produces a targeted tip")
t.expect(tips[1].title == "Some files could not be measured" and tips[1].text:find("Full Disk Access may improve coverage", 1, true) ~= nil,
	"access guidance describes filesystem issues and keeps Full Disk Access optional")
t.assertEqual(tips[2].id, "capacity", "low available space produces a separate tip")
t.assertEqual(tips[2].action, nil, "low-space guidance stays on the opportunities page")
local routed
local tipsController = TipsController.new(model, function(action) routed = action end)
tipsController:presentation({totalKb = 100, freeKb = 9}).actions.tip_access()
t.assertEqual(routed, "settings", "tip controller routes the model action")
local categories = CategoriesController.new(model, function(id) routed = id end)
local bar = categories:bar({totalKb = 2e12, freeKb = 1e12})
bar.actions.category_documents()
t.assertEqual(routed, "documents", "category navigation is testable without widgets")
local details = Inspector.details(model, "simulators")
t.expect(details.text:find("Review threshold", 1, true) ~= nil, "inspector reuses cleanup evidence")
t.expect(details.canManage, "fresh measurement allows live actions")
local deletes = 0
local inspector = InspectorController.new(model, {confirmTrash = function() return true end,
	trash = function() deletes = deletes + 1; return true end}, function() refreshed = refreshed + 1 end)
model.measurements.derived.bytes = 2e9
inspector:select("derived")
inspector:manage()
t.assertEqual(deletes, 1, "allowed action uses injected filesystem service")
t.assertEqual(refreshed, 1, "successful mutation requests fresh full inventory")
local ownerCalls = {}
model.measurements.npm = {bytes = 20e6, status = "complete"}
local ownerInspector = InspectorController.new(model, {
	confirmOwnerCleanup = function(row, size) ownerCalls.confirmed = row.id == "npm" and size == "20.0 MB"; return true end,
	runOwnerCleanup = function(commandId, home, done) ownerCalls.commandId, ownerCalls.home = commandId, home; done(true) end,
}, function() refreshed = refreshed + 1 end)
ownerInspector:select("npm"); ownerInspector:manage()
t.expect(ownerCalls.confirmed, "owner command requires review of measured cache size")
t.assertEqual(ownerCalls.commandId, "npm-cache", "npm resource routes to its fixed owner command")
t.assertEqual(ownerCalls.home, model.home, "owner command uses the active account location")
t.assertEqual(refreshed, 2, "owner cleanup triggers a fresh measurement")
model.kept.xcode = true
t.expect(not inspector:manage(), "kept ancestor prevents mutation")
local settings = SettingsController.new({loadSettings = function() return true end, saveSettings = function() return false end})
t.expect(not settings:toggle() and settings.enabled, "failed setting save preserves previous state")
local pending, cancelled = {}, 0
local scanner = Scan.new(Model.new("/Users/test"), {
	start = function(paths) local job = {}; table.insert(pending, job); return job end,
	await = function(job, done, progress) job.done = done; job.progress = progress end,
	cancel = function() cancelled = cancelled + 1 end,
	diskSpace = function() return {totalKb = 100, freeKb = 50} end,
}, "/Users/test")
scanner:start()
pending[1].progress({completed = 3, total = 153})
t.expect(scanner.status:find("Scanning 3 of 153 locations (1%)", 1, true) == 1, "worker progress reports location and percent in plain language")
scanner:start(); local status = scanner.status
pending[1].progress({completed = 100, total = 153}); pending[1].done({failure = "Old failure"})
t.assertEqual(scanner.status, status, "cancelled generation cannot overwrite status")
pending[2].done({failure = "Worker failed"})
t.assertEqual(scanner.status, "Worker failed", "worker failure is visible")
scanner:dispose(); t.assertEqual(cancelled, 1, "completed job is not cancelled again")
local failed = Scan.new(model, {start = function() error("Unavailable") end}, "/Users/test")
failed:start(); t.expect(failed.status:find("Could not start", 1, true) ~= nil, "start failure is visible without a window")
os.exit(t.summary() and 0 or 1)
