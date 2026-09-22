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
	t.expect(model.byId[id] ~= nil, "rule has a known resource: " .. id)
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
for _, status in ipairs({"partial", "stale", "denied", "skipped"}) do
	model.measurements.simulators.status = status
	t.assertEqual(#Cleanup.suggestions(model), 0, "uncertain measurement cannot recommend cleanup: " .. status)
end
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
cleanup:toggleKeep("simulators", true)
t.assertEqual(saved, 0, "cache replay does not persist keep mutations")
t.assertEqual(model.measurements.projects.bytes, 900e9, "keep preserves unrelated measured state")
cleanup:toggleKeep("simulators", false)
t.assertEqual(saved, 1, "live keep change saves once")
t.assertEqual(keepMessage, nil, "successful persistence does not report an error")
t.assertEqual(#cleanup:rows(), 1, "unkeep restores eligible resource")
t.assertEqual(#Tips.forInventory(model, {totalKb = 100, freeKb = 40}), 1, "ordinary capacity gets the system tip")
model.scan.errors = 4
local tips = Tips.forInventory(model, {totalKb = 100, freeKb = 9})
t.assertEqual(tips[1].id, "access", "access evidence produces a targeted tip")
t.assertEqual(tips[2].id, "capacity", "low available space produces a separate tip")
local routed
local tipsController = TipsController.new(model, function(action) routed = action end)
tipsController:presentation({totalKb = 100, freeKb = 9}).actions.tip_access()
t.assertEqual(routed, "settings", "tip controller routes the model action")
local categories = CategoriesController.new(model, function(id) routed = id end)
local bar = categories:bar({totalKb = 2e12, freeKb = 1e12})
bar.actions.category_documents()
t.assertEqual(routed, "documents", "category navigation is testable without widgets")
local details = Inspector.details(model, "simulators", true)
t.expect(details.text:find("Review threshold", 1, true) ~= nil, "inspector reuses cleanup evidence")
t.expect(not details.canManage and not details.canMeasure, "saved measurements disable live actions")
local deletes = 0
local inspector = InspectorController.new(model, {confirmTrash = function() return true end,
	trash = function() deletes = deletes + 1; return true end}, function() refreshed = refreshed + 1 end)
model.measurements.derived.bytes = 2e9
inspector:select("derived", false)
t.expect(not inspector:manage(true), "read-only action cannot mutate filesystem")
inspector:manage(false)
t.assertEqual(deletes, 1, "allowed action uses injected filesystem service")
t.assertEqual(refreshed, 1, "successful mutation requests fresh full inventory")
model.kept.xcode = true
t.expect(not inspector:manage(false), "kept ancestor prevents mutation")
local settings = SettingsController.new({loadSettings = function() return true end, saveSettings = function() return false end})
t.expect(not settings:toggle() and settings.enabled, "failed setting save preserves previous state")
local pending, cancelled, writes = {}, 0, 0
local scanner = Scan.new(Model.new("/Users/test"), {
	start = function(paths) local job = {}; pending[#pending + 1] = job; return job end,
	await = function(job, done, progress) job.done = done; job.progress = progress end,
	cancel = function() cancelled = cancelled + 1 end,
	diskSpace = function() return {totalKb = 100, freeKb = 50} end,
	writeCache = function() writes = writes + 1; return false, "Read-only destination" end,
}, "/Users/test")
scanner:configure(nil, "/test/cache"); scanner:start()
pending[1].progress({completed = 3, total = 153})
t.expect(scanner.status:find("3/153", 1, true) ~= nil, "worker progress is independently observable")
scanner:start(); local status = scanner.status
pending[1].progress({completed = 100, total = 153}); pending[1].done({failure = "Old failure"})
t.assertEqual(scanner.status, status, "cancelled generation cannot overwrite status")
pending[2].done({failure = "Worker failed"})
t.assertEqual(writes, 1, "accepted completion writes debug snapshot once")
t.expect(scanner.status:find("Cache not saved", 1, true) ~= nil, "cache write failure is visible")
scanner:dispose(); t.assertEqual(cancelled, 1, "completed job is not cancelled again")
local warm = Scan.new(Model.new("/Users/test"), {
	readCache = function() return {measurements = {derived = {bytes = 5e9, status = "complete"}}, scan = {}} end,
	diskSpace = function() return {totalKb = 100, freeKb = 50} end,
}, "/Users/test")
warm:configure(nil, "/test/cache")
t.assertEqual(warm.model.measurements.derived.status, "stale", "warm startup marks prior measurements stale")
t.assertEqual(#Cleanup.suggestions(warm.model), 0, "warm cache cannot authorize cleanup until refreshed")
local failed = Scan.new(model, {start = function() error("Unavailable") end}, "/Users/test")
failed:start(); t.expect(failed.status:find("Could not start", 1, true) ~= nil, "start failure is visible without a window")
os.exit(t.summary() and 0 or 1)
