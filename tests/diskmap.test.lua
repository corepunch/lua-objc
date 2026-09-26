local Categories = require("apps.diskmap.models.Categories")
local Preferences = require("apps.diskmap.models.Preferences")
local Cleanup = require("apps.diskmap.models.Cleanup")
local Inspector = require("apps.diskmap.models.Inspector")
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
t.expect(#model.resources:leaves() > 60, "catalog describes macOS and developer storage")
local unique = {}
for _, row in ipairs(model.resources:leaves()) do
	t.expect(not unique[row.id], "stable unique resource " .. row.id); unique[row.id] = true
	t.expect(row.subtitle ~= nil, "resource explains purpose")
	if row.action == "trash" then t.expect(row.id == "derived" or row.id == "brew" or row.id == "documentation" or row.id == "opencode-downloads" or row.id == "codex-cache" or row.id == "grok-cache" or row.id == "claude-cache" or row.id == "cursor-cache" or row.id == "cursor-cached-data" or row.id == "cursor-gpu-cache" or row.id == "pnpm-store" or row.id == "yarn-cache" or row.id == "swiftpm-cache" or row.id == "flutter-pub", "only verified caches or offline documentation can be trashed: " .. row.id) end
end
t.assertEqual(model.resources:find("npm").action, "ownerCleanup", "npm cache uses npm's cache command")
t.assertEqual(model.resources:find("pip").action, "ownerCleanup", "pip cache uses pip's cache command")
t.assertEqual(model.resources:find('codex-worktrees').action, "finder", "worktrees never treated as cache")
t.assertEqual(model.resources:find('preboot').action, "settings", "boot assets system managed")
t.assertEqual(model.resources:find('xcode-app').action, "sdks", "bundled SDKs open as the installation's SDK list")
t.assertEqual(model.resources:find('clt').action, "sdks", "Command Line Tools open as that installation's SDK list")
t.assertEqual(Model.size(1e9), "1.0 GB", "decimal bytes")
t.assertEqual(Model.size(nil), "Not measured", "unknown is not zero")
Inventory.apply(model, {"derived", "archives"}, {trees = {{kb = 100}, {kb = 200, partial = true}}, rootStates = {"measured", "unreadable"}})
t.assertEqual(model.measurements.derived.bytes, 102400, "normalizes worker units")
t.assertEqual(Model.total(model), 307200, "disjoint ledger totals")
t.expect(model.resources:find("derived"):validateTrash(), "complete cache eligible")
t.expect(not model.resources:find("archives"):validateTrash(), "personal history never eligible")
model.kept.xcode = true
t.expect(not model.resources:find("derived"):validateTrash(), "kept parent protects descendants")
model.kept.xcode = nil
local filtered = Categories.rows(model, nil, "DerivedData")
t.assertEqual(#filtered, 1, "search preserves one semantic ancestor")
t.assertEqual(filtered[1].id, "developer", "search retains category")
t.assertEqual(filtered[1].bytes, 307200, "filter does not change category total")
t.assertEqual(#Categories.rows(model, nil, "["), 0, "search is literal")
local downloadSearch = Categories.rows(model, nil, "Downloads")
local documents
for _, row in ipairs(downloadSearch) do if row.id == "documents" then documents = row end end
t.expect(documents and documents.forceExpanded, "resource search expands its semantic category")
local downloadFound = false
for _, child in ipairs(documents and documents.children or {}) do if child.id == "downloads" then downloadFound = true end end
t.expect(downloadFound, "storage search returns the matching resource, not only its category")
t.expect(Inspector.details(model, "applications").text:find("Review its measured resources", 1, true) ~= nil,
	"category guidance points to resources in the management sheet")
Inventory.apply(model, {"derived"}, {failure = "cancelled"})
t.expect(not model.resources:find("derived"):validateTrash(), "failed measurement disables removal")
t.assertEqual(model.measurements.derived.bytes, nil, "failure discards old bytes")
Inventory.apply(model, {"derived"}, {trees = {}, rootStates = {"missing"}})
t.assertEqual(model.measurements.derived.bytes, 0, "confirmed missing is zero")
Inventory.apply(model, {"derived"}, {trees = {}, rootStates = {"unreadable"}})
t.assertEqual(model.measurements.derived.bytes, nil, "denied is unknown")
Inventory.apply(model, {"derived"}, {trees = {{kb = 125}}, rootStates = {"measured"}})
model.measurements.derived.status = "partial"
t.expect(Inspector.details(model, "derived").location:find("At least 128 KB measured · partial", 1, true) ~= nil,
	"inspector describes partial size as a measured lower bound")
local paths, ids = Inventory.plan(model)
local targets = {}; for i, path in ipairs(paths) do targets[ids[i]] = path end
for _, row in ipairs(model.resources:leaves()) do
	if row.path and not row.mediaAccess then t.assertEqual(targets[row.id], row.path, "startup includes " .. row.id) end
end
t.assertEqual(targets["home-other"], "/Users/test", "unrecognized home files are measured")
t.assertEqual(targets["root-system"], "/", "root residual closes inventory gaps")
t.assertEqual(model.measurements.snapshots.status, "unsupported", "snapshot allocation is explicitly system managed")
local chartModel = Model.new("/Users/test")
chartModel.measurements["apps-system-other"] = {bytes = 58e9, status = "complete"}
chartModel.measurements.derived = {bytes = 4.9e9, status = "complete"}
chartModel.measurements["codex-cache"] = {bytes = 10e9, status = "complete"}
chartModel.measurements["siri-assets-1"] = {bytes = 3e9, status = "complete"}
chartModel.measurements["dictation-1"] = {bytes = 2e9, status = "complete"}
local disk = {totalKb = 494e9 / 1024, freeKb = 157e9 / 1024}
local segments = Categories.distribution(chartModel, disk)
local sum = 0
for _, segment in ipairs(segments) do sum = sum + segment.weight end
t.expect(math.abs(sum - 1) < 0.000001, "breakdown accounts for all capacity")
t.assertEqual(segments[1].color, "systemBlue", "applications retain blue category color")
t.assertEqual(segments[1].id, "applications", "measured categories rank by size")
local byId = {}; for _, segment in ipairs(segments) do byId[segment.id] = segment end
t.assertEqual(segments[2].id, "ai-agents", "AI agents rank by their measured size")
t.assertEqual(byId.developer.color, "systemPurple", "developer retains purple category color")
t.assertEqual(byId["ai-agents"].bytes, 13e9, "AI tools and Siri share one category total")
t.assertEqual(byId["system-data"].bytes, 2e9, "Dictation remains in System Data without double counting Siri")
t.assertEqual(byId.developer.bytes, 4.9e9, "Developer excludes AI coding tools")
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
t.expect(ui.capacity ~= nil and ui.toolbarTitle ~= nil, "the toolbar keeps the two-line storage title")
t.assertEqual(ui.capacity.text, ui.categories:capacity(ui.scan.disk), "toolbar shows measured capacity")
local config = xml.renderFile("apps/diskmap/views/Window.etlua", {capacity = ui.categories:capacity(ui.scan.disk)}, ns)
t.assertEqual(config.width, 700, "narrow default window width")
t.assertEqual(config.height, 720, "default window height")
t.assertEqual(config.minWidth, 620, "category list remains usable at minimum width")
t.expect(config.hideTitle, "the single window title does not sit beside the toolbar title")
t.assertEqual(config.sidebar, nil, "storage window has no sidebar")
t.assertEqual(config.sidebarWidth, nil, "storage window does not reserve sidebar width")
local toolbarIds = {}
for _, item in ipairs(config.toolbar) do toolbarIds[item.id] = true end
t.expect(toolbarIds.settings, "settings open from the toolbar")
t.expect(toolbarIds.reclaim, "suggested cleanups open from the toolbar")
t.expect(toolbarIds.drive, "the two-line storage title is the leading toolbar item")
t.expect(not toolbarIds.toggleSidebar, "toolbar has no sidebar toggle")
t.assertEqual(ui.navigation, nil, "category list is the only destination")
t.expect(ui.refs.openReclaim == nil and ui.refs.openCategory == nil, "the storage list has no trailing command buttons")
local categoryRows = ui.refs.results.rowCount
ui:openReclaim()
t.expect(ui.reclaimSheet ~= nil, "suggested cleanups open in a sheet")
t.expect(ui.reclaimRefs.opportunities ~= nil and ui.reclaimRefs.tips ~= nil, "cleanup sheet owns opportunities and tips")
t.assertEqual(ui.refs.results.rowCount, categoryRows, "cleanup sheet leaves the category list in place")
ui.capacity.text = "stale"
ui:updateRows()
t.assertEqual(ui.capacity.text, ui.categories:capacity(ui.scan.disk), "scan updates continue while cleanups are open")
t.expect(not ui.refs.results.hasVerticalScroller, "the category list has no scrollbar of its own")
t.expect(ui.refs.results.fixedHeight >= categoryRows * 44, "category rows extend with the page")
local filteredReclaim = ui.cleanup:presentation("DerivedData")
t.assertEqual(#filteredReclaim.groups[1].rows, 1, "cleanup search finds a matching measured candidate")
t.assertEqual(#ui.cleanup:presentation("no match").groups[1].rows, 0, "cleanup search can show an empty group")
local scroll = ui.reclaimRefs.opportunitiesScroll
local function atTop()
	return math.abs(scroll.documentView.size.height - scroll.contentSize.height - scroll.contentView.bounds.origin.y) < 1
end
t.expect(atTop(), "new opportunity content starts at top")
ui:updateRows(); t.expect(atTop(), "unchanged model preserves scroll position")
ui:closeReclaim()
t.assertEqual(ui.reclaimSheet, nil, "closing cleanups returns to the category list")
t.assertEqual(ui.opportunities, nil, "closing cleanups removes the suggestion list")
t.assertEqual(ui.refs.results.rowCount, categoryRows, "category rows remain after closing cleanups")
ui:openSettings()
t.expect(ui.settingsSheet ~= nil and ui.settingsRefs.monitor ~= nil, "settings open in a sheet")
t.assertEqual(ui.refs.results.rowCount, categoryRows, "settings leave the category list in place")
ui:closeSettings()
t.assertEqual(ui.refs.coveragePanel.frame.size.width, ui.refs.categoriesPanel.frame.size.width, "scan status and categories use one content column")
t.assertEqual(ui.refs.access.title, "Scan access…", "access settings are offered without implying Full Disk Access is required")
ui.model.scan.errors = 7; ui:updateRows()
t.assertEqual(ui.refs.access.title, "Review scan access…", "access guidance becomes specific when scan issues exist")
ui.model.scan.errors = 0; ui:updateRows()
ui:select("developer")
ui:openManagement("developer")
t.assertEqual(ui.management.rootId, "developer", "opening a category shows its sheet")
t.assertEqual(ui.management.refs.categoryName.text, "Developer", "selected category appears in its sheet")
t.assertEqual(ui.management.sheet.size.width, ui.window.size.width - 80, "category sheet is 80 points narrower than the window")
ui.management:close()
local sizeCell = bridge._tableCell(ui.refs.results, 1, 0)
t.assertEqual(sizeCell.textField.alignment, 2, "Diskmap values use native right alignment")
t.expect(bridge._pressColumnButton(ui.refs.results, 2, 0), "category rows have an info button")
t.expect(ui.management.sheet ~= nil, "the info button opens that category")
ui.management:close()
t.expect(sizeCell.loadingIndicator.hidden, "loaded category has no spinner")
local _, loadingIds = Inventory.plan(ui.model)
Inventory.begin(ui.model, loadingIds); ui:updateRows()
sizeCell = bridge._tableCell(ui.refs.results, 1, 0)
t.expect(not sizeCell.loadingIndicator.hidden, "pending category has its own native spinner")
t.assertEqual(sizeCell.textField.stringValue, "Calculating…", "loading replaces numeric value")
t.assertEqual(ui.refs.results.rowCount, 20, "per-category loading preserves category rows")
window:layout()
t.expect(ui.refs.page.documentView.frame.size.height > ui.refs.page.contentView.bounds.size.height, "the storage page scrolls past the category list")
Inventory.cancel(ui.model); ui:updateRows()
t.expect(bridge._tableCell(ui.refs.results, 1, 0).loadingIndicator.hidden, "cancel removes category spinner")
ui.query = "no match"; ui:updateRows()
t.assertEqual(ui.refs.results.rowCount, 0, "empty category search")
window.size = ns.Size(720, 640); window:layout()
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
local scanned = require("StorageScan").scan({root, root .. "/cache"}, {root, root .. "/cache"})
t.assertEqual(scanned.failure, "", "native inventory scanner finishes")
t.assertEqual(scanned.trees[2].kb, 8, "hard links have one allocation")
t.assertEqual(scanned.trees[1].kb, 0, "parent excludes separately owned child")
t.assertEqual(scanned.trees[1].children, nil, "inventory retains no folder tree")
for _, path in ipairs({hostile, root .. "/cache/link", root .. "/cache", root .. "/outside", root}) do os.remove(path) end
local features = Model.new("/Users/test")
local uniquePaths = {}
for _, leaf in ipairs(features.resources:leaves()) do
	if leaf.path then t.expect(not uniquePaths[leaf.path], "one catalog owner per exact path"); uniquePaths[leaf.path] = true end
end
t.assertEqual(features.resources:find("vscode-cache").appIcon, "com.microsoft.VSCode", "resource inherits owning application icon")
t.assertEqual(features.resources:find("temporary").color, "systemYellow", "temporary files have yellow badge")
t.assertEqual(features.resources:find("dictation-1").policy, "System managed", "recognition assets never become disposable caches")
features.measurements["siri-assets-1"] = {bytes = 1200, status = "complete"}
features.measurements["dictation-1"] = {bytes = 800, status = "complete"}
local rolled = Categories.rows(features, "intelligence")
t.assertEqual(rolled[2].bytes, 1200, "Siri has independent measured total")
t.assertEqual(rolled[2].status, "partial", "unmeasured asset classes remain explicit")
local speech = Categories.rows(features, "speech-assets")
t.assertEqual(speech[1].bytes, 800, "Dictation remains independently measured with speech resources")
t.assertEqual(features.resources:find("intelligence"):getParent().id, "ai-agents", "Apple Intelligence and Siri belong to AI agents")
t.assertEqual(features.resources:find("codex"):getParent():getParent().id, "ai-agents", "AI coding tools belong to AI agents")
t.assertEqual(features.resources:find("cursor"):getParent():getParent().id, "ai-agents", "Cursor is counted with AI tools")
t.assertEqual(#Cleanup.suggestions(features), 0, "system feature data is never a cleanup suggestion")
os.exit(t.summary() and 0 or 1)
