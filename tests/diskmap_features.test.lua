_G.__headless = true
local Locations = require("apps.diskmap.models.Locations")
local t = require("TestKit")
local Store = require("apps.diskmap.Store")
local Scan = require("apps.diskmap.services.Scan")
local Keep = require("apps.diskmap.flows.Keep")
local Manage = require("apps.diskmap.flows.Manage")
local SheetController = require("apps.diskmap.controllers.SheetController")
local Sheets = require("apps.diskmap.pages.Sheets")
local Rules = require("apps.diskmap.knowledge.CleanupRules")
local Scans = require("apps.diskmap.models.Scans")
local Suggestions = require("apps.diskmap.models.Suggestions")
local model = Store.new("/Users/test")
for id, rule in pairs(Rules) do
	t.expect(Locations:find(id) ~= nil, "rule has a known resource: " .. id)
	model.measurements[id] = {bytes = rule.threshold - 1, status = "complete"}
end
t.assertEqual(#Suggestions:ranked(), 0, "below-threshold resources produce no suggestions")
model.measurements.simulators.bytes = Rules.simulators.threshold
local suggestions = Suggestions:ranked()
t.assertEqual(#suggestions, 1, "threshold boundary includes one recognized resource")
t.assertEqual(suggestions[1].id, "simulators", "simulator knowledge is selected")
t.expect(suggestions[1].subtitle:find("test apps", 1, true) ~= nil, "suggestion explains consequences")
t.expect(suggestions[1].evidence:find("Review threshold", 1, true) ~= nil, "suggestion explains why it appeared")
model.measurements.projects = {bytes = 900e9, status = "complete"}
model.measurements["xcode-app"] = {bytes = 200e9, status = "complete"}
t.assertEqual(#Suggestions:ranked(), 1, "large projects and installations do not become cleanup opportunities")
for _, status in ipairs({"failed", "denied", "skipped"}) do
	model.measurements.simulators.status = status
	t.assertEqual(#Suggestions:ranked(), 0, "uncertain measurement cannot recommend cleanup: " .. status)
end
model.measurements.simulators.status = "partial"
t.assertEqual(Suggestions:ranked()[1].impact, "Needs review", "partial measurements still offer review")
t.expect(Suggestions:ranked()[1].size:find("≥", 1, true), "partial review is explicitly a lower bound")
model.measurements.simulators.status = "complete"
model.kept.xcode = true
t.assertEqual(#Suggestions:ranked(), 0, "keeping parent suppresses all descendant recommendations")
model.kept.xcode = nil
local saved, refreshed = 0, 0
local trashedPath, trashedBytes, remeasured
local keepMessage
local cleanup = Keep({app = {service = {saveKeep = function() saved = saved + 1; return true end}}})
t.assertEqual(Suggestions:presentation().decisions[1].id, "simulators", "clean up keeps resource identity")
t.assertEqual(#Suggestions:presentation("unfindable").decisions, 0, "clean up search is independent")
local reviewRow = Suggestions:presentation().decisions[1]
t.assertEqual(reviewRow.statusColor, "systemOrange", "a review suggestion carries an orange status symbol")
t.assertEqual(reviewRow.shareText, "to review", "a suggestion without proven recovery names its amount as bytes to review")
keepMessage = select(2, cleanup:toggle("simulators"))
t.assertEqual(#Suggestions:ranked(), 0, "a kept resource leaves the suggestions")
local keptRow; for _, row in ipairs(Suggestions:presentation().checked) do if row.id == "simulators" then keptRow = row end end
t.assertEqual(keptRow and keptRow.detail, "Kept", "a kept resource is listed as checked and kept")
t.assertEqual(keptRow and keptRow.statusIcon, "pin.circle.fill", "a kept resource shows the kept symbol")
t.assertEqual(saved, 1, "keep change persists the preference")
t.assertEqual(model.measurements.projects.bytes, 900e9, "keep preserves unrelated measured state")
keepMessage = select(2, cleanup:toggle("simulators"))
t.assertEqual(saved, 2, "unkeep change also saves")
t.assertEqual(keepMessage, nil, "successful persistence does not report an error")
t.assertEqual(#Suggestions:ranked(), 1, "unkeep restores eligible resource")
t.assertEqual(#Scans:tips({totalKb = 100, freeKb = 40}), 1, "ordinary capacity gets the system tip")
model.scan.errors = 4
local tips = Scans:tips({totalKb = 100, freeKb = 9})
t.assertEqual(tips[1].id, "access", "access evidence produces a targeted tip")
t.expect(tips[1].title == "Some files could not be measured" and tips[1].text:find("Full Disk Access may improve coverage", 1, true) ~= nil,
	"access guidance describes filesystem issues and keeps Full Disk Access optional")
t.assertEqual(tips[2].id, "capacity", "low available space produces a separate tip")
t.assertEqual(tips[2].action, nil, "low-space guidance stays on the opportunities page")
require("data.model").bind(model)
local cleanupRoute = require("data.routes").page(require("apps.diskmap.routes").cleanup, {id = "cleanup"}, {cleanupSources = function() return nil end}, "apps.diskmap")
local cleanupPage = cleanupRoute:present({disk = {totalKb = 100, freeKb = 9}})
t.assertEqual(cleanupPage.links.tip_access.settings, "privacy", "the access tip leads to privacy settings")
t.assertEqual(cleanupPage.children.tips.tips[1].id, "access", "the Clean Up page presents the tips")
local legend = require("apps.diskmap.models.Categories"):chart({totalKb = 2e12 / 1024, freeKb = 1e12 / 1024}).legend
for _, item in ipairs(legend) do
	t.expect(item.id == "#other" or Locations:find(item.id) ~= nil, "chart legend opens a registered category: " .. item.id)
end
local details = Locations:details("simulators")
t.expect(details.text:find("Review threshold", 1, true) ~= nil, "inspector reuses cleanup evidence")
t.expect(details.canManage, "fresh measurement allows live actions")
local deletes = 0
local inspector = Manage({app = {service = {confirmTrash = function() return true end,
	trash = function() deletes = deletes + 1; return true end},
	rescan = function() error("a removal never measures the disk again") end,
	trashed = function(path, bytes) trashedPath, trashedBytes = path, bytes end}})
model.measurements.derived.bytes = 2e9
inspector:manage("derived")
t.assertEqual(deletes, 1, "allowed action uses injected filesystem service")
t.assertEqual(trashedPath, Locations:find("derived").path, "the trashed location leaves the model")
t.assertEqual(trashedBytes, 2e9, "with the size the scan measured")
local ownerCalls = {}
model.measurements.npm = {bytes = 20e6, status = "complete"}
local ownerInspector = Manage({app = {service = {
	confirmOwnerCleanup = function(row, size) ownerCalls.confirmed = row.id == "npm" and size == "20.0 MB"; return true end,
	runOwnerCleanup = function(commandId, home, done) ownerCalls.commandId, ownerCalls.home = commandId, home; done(true) end,
}, rescan = function() error("owner cleanup never measures the whole disk") end,
	remeasure = function(id) remeasured = id end}})
ownerInspector:manage("npm")
t.expect(ownerCalls.confirmed, "owner command requires review of measured cache size")
t.assertEqual(ownerCalls.commandId, "npm-cache", "npm resource routes to its fixed owner command")
t.assertEqual(ownerCalls.home, model.home, "owner command uses the active account location")
t.assertEqual(remeasured, "npm", "owner cleanup measures only the location it cleaned")
model.kept.xcode = true
t.expect(not inspector:manage("derived"), "kept ancestor prevents mutation")
local settings = SheetController.page(Sheets.settings, "settings", {service = {loadSettings = function() return true end, saveSettings = function() return false end}, model = {}})
t.expect(not settings:toggle() and settings.enabled, "failed setting save preserves previous state")
local pending, cancelled = {}, 0
local scanner = Scan.new(Store.new("/Users/test"), {
	start = function(paths) local job = {}; table.insert(pending, job); return job end,
	await = function(job, done, progress) job.done = done; job.progress = progress end,
	cancel = function() cancelled = cancelled + 1 end,
	diskSpace = function() return {totalKb = 100, freeKb = 50} end,
}, "/Users/test")
scanner:start()
pending[1].progress({completed = 3, total = 153})
pending[1].progress({completed = 4, total = 153, currentPath = "/Users/test/.gradle"})
t.assertEqual(scanner.status, "~/.gradle", "worker progress names only the location being measured")
scanner:start(); local status = scanner.status
pending[1].progress({completed = 100, total = 153}); pending[1].done({failure = "Old failure"})
t.assertEqual(scanner.status, status, "cancelled generation cannot overwrite status")
pending[2].done({failure = "Worker failed"})
t.assertEqual(scanner.status, "Worker failed", "worker failure is visible")
scanner:dispose(); t.assertEqual(cancelled, 1, "completed job is not cancelled again")
local failed = Scan.new(model, {start = function() error("Unavailable") end}, "/Users/test")
failed:start(); t.expect(failed.status:find("Could not start", 1, true) ~= nil, "start failure is visible without a window")
os.exit(t.summary() and 0 or 1)
