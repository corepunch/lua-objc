local Categories = require("apps.diskmap.models.Categories")
local Preferences = require("apps.diskmap.models.Preferences")
local Cleanup = require("apps.diskmap.models.Cleanup")
_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local xml = require("ui.xml")
local Model = require("apps.diskmap.Model")
local Inventory = require("apps.diskmap.models.Inventory")
local System = require("apps.diskmap.services.System")
local Controller = require("apps.diskmap.Controller")
local model = Model.new("/Users/test")
t.expect(#model.leaves > 60, "catalog describes macOS and developer storage")
local unique = {}
for _, row in ipairs(model.leaves) do
	t.expect(not unique[row.id], "stable unique resource " .. row.id); unique[row.id] = true
	t.expect(row.subtitle ~= nil, "resource explains purpose")
	if row.action == "trash" then t.expect(row.id == "derived" or row.id == "npm" or row.id == "pip" or row.id == "brew", "only verified caches can be trashed") end
end
t.assertEqual(model.byId['codex-worktrees'].action, "finder", "worktrees never treated as cache")
t.assertEqual(model.byId['preboot'].action, "settings", "boot assets system managed")
t.assertEqual(model.byId['xcode-app'].action, "xcode", "bundled SDKs managed as installation")
t.assertEqual(Model.size(1e9), "1.0 GB", "decimal bytes")
t.assertEqual(Model.size(nil), "Not measured", "unknown is not zero")
Inventory.apply(model, {"derived", "archives"}, {trees = {{kb = 100}, {kb = 200, partial = true}}, rootStates = {"measured", "unreadable"}})
t.assertEqual(model.measurements.derived.bytes, 102400, "normalizes worker units")
t.assertEqual(Model.total(model), 307200, "disjoint ledger totals")
t.expect(Preferences.canTrash(model, "derived"), "complete cache eligible")
t.expect(not Preferences.canTrash(model, "archives"), "personal history never eligible")
model.kept.xcode = true
t.expect(not Preferences.canTrash(model, "derived"), "kept parent protects descendants")
model.kept.xcode = nil
local filtered = Categories.rows(model, nil, "DerivedData")
t.assertEqual(#filtered, 1, "search preserves one semantic ancestor")
t.assertEqual(filtered[1].id, "developer", "search retains category")
t.assertEqual(filtered[1].bytes, 307200, "filter does not change category total")
t.assertEqual(#Categories.rows(model, nil, "["), 0, "search is literal")
Inventory.apply(model, {"derived"}, {failure = "cancelled"})
t.expect(not Preferences.canTrash(model, "derived"), "failed measurement disables removal")
t.assertEqual(model.measurements.derived.bytes, nil, "failure discards old bytes")
Inventory.apply(model, {"derived"}, {trees = {}, rootStates = {"missing"}})
t.assertEqual(model.measurements.derived.bytes, 0, "confirmed missing is zero")
Inventory.apply(model, {"derived"}, {trees = {}, rootStates = {"unreadable"}})
t.assertEqual(model.measurements.derived.bytes, nil, "denied is unknown")
local paths, ids = Inventory.plan(model)
local targets = {}; for i, path in ipairs(paths) do targets[ids[i]] = path end
for _, row in ipairs(model.leaves) do
	if row.path then t.assertEqual(targets[row.id], row.path, "startup includes " .. row.id) end
end
t.assertEqual(targets["home-other"], "/Users/test", "unrecognized home files are measured")
t.assertEqual(targets["root-system"], "/", "root residual closes inventory gaps")
t.assertEqual(model.measurements.snapshots.status, "unsupported", "snapshot allocation is explicitly system managed")
local chartModel = Model.new("/Users/test")
chartModel.measurements["apps-system"] = {bytes = 58e9, status = "complete"}
chartModel.measurements.derived = {bytes = 4.9e9, status = "complete"}
local disk = {totalKb = 494e9 / 1024, freeKb = 157e9 / 1024}
local segments = Categories.distribution(chartModel, disk)
local sum = 0
for _, segment in ipairs(segments) do sum = sum + segment.weight end
t.expect(math.abs(sum - 1) < 0.000001, "breakdown accounts for all capacity")
t.assertEqual(segments[1].color, "systemBlue", "applications retain blue category color")
t.assertEqual(segments[2].color, "systemPurple", "developer retains purple category color")
t.assertEqual(segments[#segments].bytes, 157e9, "free space represented separately")
t.expect(segments[#segments-1].bytes > 0, "unclassified and other bytes remain visible")
t.assertEqual(#Categories.distribution(chartModel, {totalKb = 1, freeKb = 0}), 0, "overcount does not fabricate a capacity chart")
local startCalls = 0
local service = {monitor = function() end, start = function() startCalls = startCalls + 1; return {} end,
	await = function(job, completion) job.complete = completion end,
	cancel = function() end, diskSpace = function() return {totalKb = 10000, freeKb = 5000} end}
local app = Controller.new(service)
app.scan:start(); local old = app.scan.job
app.scan:start(); local current = app.scan.job
local _, scanIds = Inventory.plan(app.model)
local function measuredResult(id, kb)
	local result = {trees = {}, rootStates = {}}
	for index, target in ipairs(scanIds) do
		result.rootStates[index] = target == id and "measured" or "missing"
		if target == id then result.trees[index] = {kb = kb} end
	end
	return result
end
old.complete(measuredResult("derived", 200))
t.assertEqual(app.model.measurements.derived.status, "calculating", "late completion cannot change pending measurement")
current.complete(measuredResult("npm", 300))
t.assertEqual(app.model.measurements.npm.bytes, 307200, "current result accepted")
local ui = Controller.new(service)
local window = ui:createWindow()
t.assertEqual(startCalls, 3, "every window launch starts a fresh scan")
ui.scan.job.complete(measuredResult("derived", 4900000))
t.expect(ui.capacity ~= nil, "capacity label retained from toolbar")
t.expect(ui.toolbarTitle ~= nil, "toolbar title ref retained")
t.assertEqual(ui.capacity.text, ui.categories:capacity(ui.scan.disk), "toolbar shows measured capacity")
local config = xml.renderFile("apps/diskmap/views/Window.etlua", {capacity = ui.categories:capacity(ui.scan.disk)}, ns)
t.assertEqual(config.width, 1024, "compact default window width")
t.assertEqual(config.height, 768, "compact default window height")
t.assertEqual(ui.navigation.documentView.style, ui.settingsNavigation.documentView.style, "Settings shares native navigation style")
t.assertEqual(ui.settingsNavigation.frame.origin.y, 0, "Settings uses native bottom row inset without extra outer padding")
local navigationCell = bridge._tableCell(ui.navigation, 0, 0)
local settingsCell = bridge._tableCell(ui.settingsNavigation, 0, 0)
t.assertEqual(navigationCell.textField.frame.origin.x, settingsCell.textField.frame.origin.x, "sidebar text shares one leading grid")
t.assertEqual(navigationCell.imageView.frame.origin.x, settingsCell.imageView.frame.origin.x, "sidebar symbols share one leading grid")
ui.settingsNavigation:selectRow(0)
t.assertEqual(ui.section, "Settings", "native Settings row navigates")
t.assertEqual(ui.navigation.documentView.selectedRow, -1, "Settings clears sidebar selection")
ui.navigation:selectRow(0)
t.assertEqual(ui.section, "Storage", "Storage can be revisited from Settings")
t.assertEqual(ui.settingsNavigation.documentView.selectedRow, -1, "main navigation clears Settings selection")
local scroll = ui.refs.opportunitiesScroll
local function atTop()
	return math.abs(scroll.documentView.size.height - scroll.contentSize.height - scroll.contentView.bounds.origin.y) < 1
end
t.expect(atTop(), "new opportunity content starts at top")
ui:updateRows(); t.expect(atTop(), "unchanged model preserves scroll position")
t.assertEqual(ui.refs.categoriesPane.frame.size.width - ui.refs.coveragePanel.frame.size.width, 16, "coverage panel keeps trailing divider inset")
ui:select("developer")
t.expect(not ui.refs.inspector.hidden, "selection exposes the inspector")
t.expect(ui.refs.measure.enabled, "selection allows a fresh measurement")
local sizeCell = bridge._tableCell(ui.refs.results, 1, 0)
t.assertEqual(sizeCell.textField.alignment, 2, "Diskmap values use native right alignment")
t.expect(sizeCell.loadingIndicator.hidden, "loaded category has no spinner")
local _, loadingIds = Inventory.plan(ui.model)
Inventory.begin(ui.model, loadingIds); ui:updateRows()
sizeCell = bridge._tableCell(ui.refs.results, 1, 0)
t.expect(not sizeCell.loadingIndicator.hidden, "pending category has its own native spinner")
t.assertEqual(sizeCell.textField.stringValue, "Calculating…", "loading replaces numeric value")
t.assertEqual(ui.refs.results.rowCount, 9, "per-category loading preserves category rows")
Inventory.cancel(ui.model); ui:updateRows()
t.expect(bridge._tableCell(ui.refs.results, 1, 0).loadingIndicator.hidden, "cancel removes category spinner")
ui:showSection("Developer"); ui.query = "no match"; ui:updateRows()
t.assertEqual(ui.refs.results.rowCount, 0, "empty category search")
window.size = ns.Size(1000, 640); window:layout()
local dashboard = ui.content.subviews[1]
t.expect(dashboard.frame.origin.y >= 0, "small window keeps dashboard within content")
t.expect(ui.refs.results.contentView.clipsToBounds, "outline rows clip within native scroll viewport")
window:close()
-- Real scanner: parent residual excludes named children and hard links count once.
local pipe = assert(io.popen("/usr/bin/mktemp -d /private/tmp/diskmap-test.XXXXXXXX"))
local root = pipe:read("*l"); pipe:close()
os.execute("/bin/mkdir " .. System.quote(root .. "/cache"))
local hostile = root .. "/cache/quote' dollar$ tab\tline\n.txt"
local f = assert(io.open(hostile, "w")); f:write(string.rep("x", 8192)); f:close()
os.execute("/bin/ln " .. System.quote(hostile) .. " " .. System.quote(root .. "/cache/link"))
os.execute("/bin/ln -s / " .. System.quote(root .. "/outside"))
local plan, output = root .. ".plan", root .. "/result.json"
f = assert(io.open(plan, "w"))
f:write(string.format('{"roots":[%q,%q],"exclusions":[%q,%q]}', root, root .. "/cache", root, root .. "/cache")); f:close()
t.expect(os.execute("/usr/bin/perl apps/diskmap/services/scan.pl " .. System.quote(output) .. " 0 " .. System.quote(plan)), "inventory scanner finishes")
f = assert(io.open(output)); local scanned = ns.json_parse(f:read("*a")); f:close()
t.assertEqual(scanned.trees[2].kb, 8, "hard links have one allocation")
t.assertEqual(scanned.trees[1].kb, 0, "parent excludes separately owned child")
t.assertEqual(scanned.trees[1].children, nil, "inventory retains no folder tree")
for _, path in ipairs({hostile, root .. "/cache/link", root .. "/cache", root .. "/outside", plan, output, root .. "/progress.json", root}) do os.remove(path) end
local features = Model.new("/Users/test")
local uniquePaths = {}
for _, leaf in ipairs(features.leaves) do
	if leaf.path then t.expect(not uniquePaths[leaf.path], "one catalog owner per exact path"); uniquePaths[leaf.path] = true end
end
t.assertEqual(features.byId["vscode-cache"].appIcon, "com.microsoft.VSCode", "resource inherits owning application icon")
t.assertEqual(features.byId["temporary"].color, "systemYellow", "temporary files have yellow badge")
t.assertEqual(features.byId["dictation-1"].policy, "System managed", "recognition assets never become disposable caches")
features.measurements["siri-assets-1"] = {bytes = 1200, status = "complete"}
features.measurements["dictation-1"] = {bytes = 800, status = "complete"}
local rolled = Categories.rows(features, "intelligence")
t.assertEqual(rolled[2].bytes, 1200, "Siri has independent measured total")
t.assertEqual(rolled[3].bytes, 800, "Dictation has independent measured total")
t.assertEqual(rolled[2].status, "partial", "unmeasured asset classes remain explicit")
t.assertEqual(#Cleanup.suggestions(features), 0, "system feature data is never a cleanup suggestion")
os.exit(t.summary() and 0 or 1)
