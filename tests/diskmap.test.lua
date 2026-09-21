_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local xml = require("ui.xml")
local Model = require("apps.diskmap.Model")
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
Model.apply(model, {"derived", "archives"}, {trees = {{kb = 100}, {kb = 200, partial = true}}, rootStates = {"measured", "unreadable"}})
t.assertEqual(model.measurements.derived.bytes, 102400, "normalizes worker units")
t.assertEqual(Model.total(model), 307200, "disjoint ledger totals")
t.expect(Model.canTrash(model, "derived"), "complete cache eligible")
t.expect(not Model.canTrash(model, "archives"), "personal history never eligible")
model.kept.xcode = true
t.expect(not Model.canTrash(model, "derived"), "kept parent protects descendants")
model.kept.xcode = nil
local filtered = Model.rows(model, nil, "DerivedData")
t.assertEqual(#filtered, 1, "search preserves one semantic ancestor")
t.assertEqual(filtered[1].id, "developer", "search retains category")
t.assertEqual(filtered[1].bytes, 307200, "filter does not change category total")
t.assertEqual(#Model.rows(model, nil, "["), 0, "search is literal")
Model.apply(model, {"derived"}, {failure = "cancelled"})
t.expect(not Model.canTrash(model, "derived"), "stale measurement disables removal")
t.assertEqual(model.measurements.derived.bytes, 102400, "failure preserves old bytes")
Model.apply(model, {"derived"}, {trees = {}, rootStates = {"missing"}})
t.assertEqual(model.measurements.derived.bytes, 0, "confirmed missing is zero")
Model.apply(model, {"derived"}, {trees = {}, rootStates = {"unreadable"}})
t.assertEqual(model.measurements.derived.bytes, nil, "denied is unknown")
local paths, ids = Model.targets(model)
for _, path in ipairs(paths) do t.expect(path ~= "/Users/test" and not path:find("Containers", 1, true), "bounded startup") end
local cache = assert(System.readCache("tests/fixtures/diskmap.json"))
t.expect(cache.fixture, "example values are identified as fixtures")
local chartModel = Model.new("/Users/test")
chartModel.measurements = cache.measurements
local segments = Model.distribution(chartModel, cache.disk)
local sum = 0
for _, segment in ipairs(segments) do sum = sum + segment.weight end
t.expect(math.abs(sum - 1) < 0.000001, "breakdown accounts for all capacity")
t.assertEqual(segments[1].color, "systemBlue", "applications retain blue category color")
t.assertEqual(segments[2].color, "systemPurple", "developer retains purple category color")
t.assertEqual(segments[8].bytes, 157e9, "free space represented separately")
t.expect(segments[7].bytes > 0, "unclassified and other bytes remain visible")
t.assertEqual(#Model.distribution(chartModel, {totalKb = 1, freeKb = 0}), 0, "overcount does not fabricate a capacity chart")
local temp = os.tmpname()
t.expect(System.writeCache(temp, cache), "cache writes")
t.assertEqual(assert(System.readCache(temp)).measurements.derived.bytes, 4.9e9, "cache round trip")
os.remove(temp)
local startCalls = 0
local service = {readCache = System.readCache, start = function() startCalls = startCalls + 1; return {} end,
	cancel = function() end, diskSpace = function() return {totalKb = 10000, freeKb = 5000} end}
local app = Controller.new(service)
app.await = function(_, job, completion) job.complete = completion end
app:scan("derived"); local old = app.job
app:scan("npm"); local current = app.job
old.complete({trees = {{kb = 200}}, rootStates = {"measured"}})
t.assertEqual(app.model.measurements.derived, nil, "late completion rejected")
current.complete({trees = {{kb = 300}}, rootStates = {"measured"}})
t.assertEqual(app.model.measurements.npm.bytes, 307200, "current result accepted")
app.cachePath = "test"; app:scan(); t.assertEqual(startCalls, 2, "cache mode never scans")
local savedArgs = arg; arg = {"-cache=tests/fixtures/diskmap.json"}
local ui = Controller.new(service)
local window = ui:createWindow()
t.assertEqual(startCalls, 2, "cache startup does not scan")
ui:showSection("Settings")
t.assertEqual(ui.navigation.documentView.selectedRow, -1, "Settings clears sidebar selection")
ui.navigation:selectRow(0)
t.assertEqual(ui.section, "Storage", "Storage can be revisited from Settings")
ui:showSection("Developer"); ui.query = "no match"; ui:updateRows()
t.assertEqual(ui.refs.results.rowCount, 0, "empty category search")
window.size = ns.Size(1000, 640); window:layout()
local dashboard = ui.content.subviews[1]
t.expect(dashboard.frame.origin.y >= 0, "small window keeps dashboard within content")
t.expect(ui.refs.results.contentView.clipsToBounds, "outline rows clip within native scroll viewport")
window:close(); arg = savedArgs
-- Real scanner: parent residual excludes named children and hard links count once.
local pipe = assert(io.popen("/usr/bin/mktemp -d /tmp/diskmap-test.XXXXXXXX"))
local root = pipe:read("*l"); pipe:close()
os.execute("/bin/mkdir " .. System.quote(root .. "/cache"))
local hostile = root .. "/cache/quote' dollar$ tab\tline\n.txt"
local f = assert(io.open(hostile, "w")); f:write(string.rep("x", 8192)); f:close()
os.execute("/bin/ln " .. System.quote(hostile) .. " " .. System.quote(root .. "/cache/link"))
os.execute("/bin/ln -s / " .. System.quote(root .. "/outside"))
local plan, output = root .. ".plan", root .. ".json"
System.writeCache(plan, {roots = {root, root .. "/cache"}, exclusions = {root, root .. "/cache"}})
t.expect(os.execute("/usr/bin/perl apps/diskmap/services/scan.pl " .. System.quote(output) .. " 0 inventory " .. System.quote(plan)), "inventory scanner finishes")
f = assert(io.open(output)); local scanned = ns.json_parse(f:read("*a")); f:close()
t.assertEqual(scanned.trees[2].kb, 8, "hard links have one allocation")
t.assertEqual(scanned.trees[1].kb, 0, "parent excludes separately owned child")
t.assertEqual(#scanned.trees[1].children, 0, "inventory retains no folder tree")
for _, path in ipairs({hostile, root .. "/cache/link", root .. "/cache", root .. "/outside", root, plan, output}) do os.remove(path) end
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
local rolled = Model.rows(features, "intelligence")
t.assertEqual(rolled[2].bytes, 1200, "Siri has independent measured total")
t.assertEqual(rolled[3].bytes, 800, "Dictation has independent measured total")
t.assertEqual(rolled[2].status, "partial", "unmeasured asset classes remain explicit")
t.assertEqual(#Model.suggestions(features), 0, "system feature data is never a cleanup suggestion")
cache.version = 1
System.writeCache(temp, cache)
t.expect(System.readCache(temp) == nil, "old unsplit catalog cache is rejected")
os.remove(temp)
os.exit(t.summary() and 0 or 1)
