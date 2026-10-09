local O = require("tests.support.diskmap_operations")
local Locations = require("apps.diskmap.models.Locations")
_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local xml = require("ui.xml")
local Format = require("apps.diskmap.helpers.Format")
local Store = require("apps.diskmap.Store")
local System = require("apps.diskmap.services.System")
local Controller = require("apps.diskmap.Controller")
local Scans = require("apps.diskmap.models.Scans")
local Categories = require("apps.diskmap.models.Categories")
local Suggestions = require("apps.diskmap.models.Suggestions")
local model = Store.new("/Users/test")
t.expect(#Locations:leaves() > 60, "catalog describes macOS and developer storage")
local unique = {}
for _, row in ipairs(Locations:leaves()) do
	t.expect(not unique[row.id], "stable unique resource " .. row.id); unique[row.id] = true
	t.expect(row.subtitle ~= nil, "resource explains purpose")
	local trashable = {derived = true, brew = true, documentation = true, ["opencode-downloads"] = true, ["codex-cache"] = true,
		["grok-cache"] = true, ["claude-cache"] = true, ["cursor-cache"] = true, ["cursor-cached-data"] = true, ["cursor-gpu-cache"] = true,
		["pnpm-store"] = true, ["yarn-cache"] = true, ["swiftpm-cache"] = true, ["flutter-pub"] = true,
		-- Download and build caches whose owners document them as re-creatable.
		["sim-caches"] = true, ["bun-cache"] = true, ["uv-cache"] = true, ["go-build"] = true, ["deno-cache"] = true,
		["carthage-cache"] = true, ["node-gyp"] = true, playwright = true, puppeteer = true, cypress = true, ["electron-cache"] = true,
		["iphone-updates"] = true, ["ipad-updates"] = true, ["mail-downloads"] = true}
	if row.action == "trash" then t.expect(trashable[row.id], "only verified caches or offline documentation can be trashed: " .. row.id) end
end
t.assertEqual(Locations:find("npm").action, "ownerCleanup", "npm cache uses npm's cache command")
t.assertEqual(Locations:find("pip").action, "ownerCleanup", "pip cache uses pip's cache command")
t.assertEqual(Locations:find('codex-worktrees').action, "finder", "worktrees never treated as cache")
t.assertEqual(Locations:find('preboot').action, "settings", "boot assets system managed")
t.assertEqual(Locations:find('xcode-app').action, "sdks", "bundled SDKs open as the installation's SDK list")
t.assertEqual(Locations:find('clt').action, "sdks", "Command Line Tools open as that installation's SDK list")
t.assertEqual(Format.size(1e9), "1.0 GB", "decimal bytes")
t.assertEqual(Format.size(nil), "Not measured", "unknown is not zero")
Scans:apply({"derived", "archives"}, {trees = {{kb = 100}, {kb = 200, partial = true}}, rootStates = {"measured", "unreadable"}})
t.assertEqual(model.measurements.derived.bytes, 102400, "normalizes worker units")
t.assertEqual(Scans:measured(), 307200, "disjoint ledger totals")
t.expect(Locations:find("derived"):validateTrash(), "complete cache eligible")
t.expect(not Locations:find("archives"):validateTrash(), "personal history never eligible")
model.kept.xcode = true
t.expect(not Locations:find("derived"):validateTrash(), "kept parent protects descendants")
model.kept.xcode = nil
local developer
for _, row in ipairs(Categories:rows()) do if row.id == "developer" then developer = row end end
t.assertEqual(developer.bytes, 307200, "a category totals its locations")
t.expect(Locations:details("applications").text:find("Review its measured resources", 1, true) ~= nil,
	"category guidance points to resources in the management sheet")
Scans:apply({"derived"}, {failure = "cancelled"})
t.expect(not Locations:find("derived"):validateTrash(), "failed measurement disables removal")
t.assertEqual(model.measurements.derived.bytes, nil, "failure discards old bytes")
Scans:apply({"derived"}, {trees = {}, rootStates = {"missing"}})
t.assertEqual(model.measurements.derived.bytes, 0, "confirmed missing is zero")
Scans:apply({"derived"}, {trees = {}, rootStates = {"unreadable"}})
t.assertEqual(model.measurements.derived.bytes, nil, "denied is unknown")
Scans:apply({"derived"}, {trees = {{kb = 125}}, rootStates = {"measured"}})
model.measurements.derived.status = "partial"
t.expect(Locations:details("derived").location:find("At least 128 KB measured · partial", 1, true) ~= nil,
	"inspector describes partial size as a measured lower bound")
local paths, ids = Scans:plan()
local targets = {}; for i, path in ipairs(paths) do targets[ids[i]] = path end
for _, row in ipairs(Locations:leaves()) do
	if row.path and not row.mediaAccess then t.assertEqual(targets[row.id], row.path, "startup includes " .. row.id) end
end
t.assertEqual(targets["home-other"], "/Users/test", "unrecognized home files are measured")
t.assertEqual(targets["root-system"], "/", "root residual closes inventory gaps")
t.assertEqual(model.measurements.snapshots.status, "unsupported", "snapshot allocation is explicitly system managed")
local chartModel = Store.new("/Users/test")
chartModel.measurements["apps-system-other"] = {bytes = 58e9, status = "complete"}
chartModel.measurements.derived = {bytes = 4.9e9, status = "complete"}
chartModel.measurements["codex-cache"] = {bytes = 10e9, status = "complete"}
chartModel.measurements["siri-assets-1"] = {bytes = 3e9, status = "complete"}
chartModel.measurements["dictation-1"] = {bytes = 2e9, status = "complete"}
local disk = {totalKb = 494e9 / 1024, freeKb = 157e9 / 1024}
local segments = Categories:distribution(disk)
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
t.assertEqual(#Categories:distribution({totalKb = 1, freeKb = 0}), 0, "overcount does not fabricate a capacity chart")
local startCalls = 0
local service = require("apps.diskmap.services.Contract").stub({monitor = function() end, start = function() startCalls = startCalls + 1; return {} end,
	await = function(job, completion) job.complete = completion end,
	cancel = function() end, diskSpace = function() return {totalKb = 10000, freeKb = 5000} end,
	-- A Mac with developer data, so the Developer section is listed.
	exists = function(path) return path:find("/Library/Developer", 1, true) ~= nil end})
local app = Controller.new(service)
app.env.scan:start(); local old = app.env.scan.job
app.env.scan:start(); local current = app.env.scan.job
local _, scanIds = Scans:plan()
local function measuredResult(id, kb)
	local result = {trees = {}, rootStates = {}}
	for index, target in ipairs(scanIds) do
		result.rootStates[index] = target == id and "measured" or "missing"
		if target == id then result.trees[index] = {kb = kb} end
	end
	return result
end
old.complete(measuredResult("derived", 200))
t.assertEqual(app.env.model.measurements.derived.status, "calculating", "late completion cannot change pending measurement")
current.complete(measuredResult("npm", 300))
t.assertEqual(app.env.model.measurements.npm.bytes, 307200, "current result accepted")
local ui = Controller.new(service)
local window = ui:createWindow()
t.assertEqual(startCalls, 3, "every window launch starts a fresh scan")
ui.env.scan.job.complete(measuredResult("derived", 4900000))
t.assertEqual(window.subtitle, "5.1 MB free of 10.2 MB", "the window subtitle reports free space beneath the title")
local windowData = ui.commands:data()
windowData.windowTitle, windowData.subtitle = "Diskmap", "1 TB free"
windowData.navigation = true
windowData.charted, windowData.chartStyle = true, "rings"
windowData.actions = setmetatable({search = function() end, chartStyle = function() end}, {__index = ui.commandActions})
local config = xml.renderFile("apps/diskmap/views/layouts/Window.etlua", windowData, ns)
t.assertEqual(bridge._tableCell(ui.navigation.refs.sidebar, 0, 0).badgeField.stringValue, "5.1 MB", "the overview row shows used capacity as a badge")
t.assertEqual(config.width, 1100, "default window fits sidebar, chart and legend")
t.assertEqual(config.minWidth, 950, "the sidebar, the Map's list and its rings fit the minimum width")
t.assertEqual(config.sidebarWidth, 226, "navigation uses a native sidebar, wide enough for its longest row beside a scroller")
t.expect(not config.hideTitle, "the window title and subtitle stay visible")
t.assertEqual(config.subtitle, "1 TB free", "the subtitle is part of the window configuration")
local toolbarIds = {}
for _, item in ipairs(config.toolbar) do toolbarIds[item.id] = true end
t.expect(toolbarIds.toggleSidebar, "the sidebar can be collapsed from the toolbar")
t.expect(toolbarIds.settings and toolbarIds.chartStyle and toolbarIds.measure and toolbarIds.search, "window-wide actions live in the toolbar")
t.expect(not toolbarIds.reclaim, "Clean Up is a sidebar page, not a toolbar button")
t.expect(toolbarIds.back and toolbarIds.forward, "history lives in the toolbar")
t.expect(not toolbarIds.review, "flagged items are a sidebar row, not a toolbar button")
t.assertEqual(ui.destination, "overview", "the overview is the first destination")
local sidebar = ui.navigation.refs.sidebar
t.assertEqual(sidebar.rowCount, 25, "sidebar lists sections and destinations")
t.assertEqual(sidebar.documentView.selectedRow, 0, "the overview row starts selected")
t.assertEqual(bridge._tableCell(sidebar, 0, 1).textField.stringValue, "Clean Up", "Overview and Clean Up lead the sidebar without a header")
t.assertEqual(bridge._tableCell(sidebar, 0, 2).textField.stringValue, "Flagged", "flagged items follow Clean Up")
t.assertEqual(bridge._tableCell(sidebar, 0, 3).textField.stringValue, "Free Up Space", "sidebar sections are native group headers")
t.expect(ui.page.refs.results ~= nil and ui.page.refs.largest ~= nil, "overview shows categories and largest items")
t.expect(ui.page.refs.breakdownChart ~= nil, "overview leads with the storage chart")
t.expect(ui.page.refs.breakdownChart.subviews[1].className == "LuaArcView", "the overview chart uses calm flat sectors")
local categoryRows = ui.page.refs.results.rowCount
t.expect(not ui.page.refs.results.hasVerticalScroller, "the category list has no scrollbar of its own")
t.expect(ui.page.refs.results.scrollDisabled, "the category list is declared scrollDisabled")
t.expect(ui.page.refs.results.frame.size.height >= categoryRows * 44, "category rows extend with the page")
-- Clean Up is a sidebar page; the toolbar button and the hero both open it.
ui:show("cleanup")
t.assertEqual(ui.destination, "cleanup", "suggested cleanups open as a page")
t.expect(ui.page.refs.list_now ~= nil and ui.page.refs.list_checked ~= nil and ui.page.refs.tips ~= nil, "clean up lists suggestions, the checked list and tips")
t.expect(ui.page.refs.list_now.scrollDisabled and ui.page.refs.page ~= nil, "clean up scrolls as one page")
window.subtitle = "stale"
ui:updateRows()
t.expect(window.subtitle:find("could recover", 1, true) or window.subtitle:find("to review", 1, true), "Clean Up names what it could recover in the window subtitle: " .. window.subtitle)
t.assertEqual(#Suggestions:presentation().now, 1, "clean up finds the measured candidate")
t.expect(#bridge._tableRowMenu(ui.page.refs.list_now, 1) > 0, "each suggestion has a row menu")
ui:show("overview")
t.assertEqual(ui.page.refs.results.rowCount, categoryRows, "category rows remain after returning from clean up")
ui:openSettings()
t.expect(ui.destination == "settings" and ui.env.settings.refs.monitor ~= nil, "settings navigate to a page")
ui:show("overview")
t.assertEqual(O(ui, "access").title, "Scan access…", "access settings are offered without implying Full Disk Access is required")
ui.env.model.scan.errors = 7; ui:updateRows()
t.assertEqual(O(ui, "access").title, "Review scan access…", "access guidance becomes specific when scan issues exist")
ui.env.model.scan.errors = 0; ui:updateRows()
ui:open("developer")
t.assertEqual(ui.destination, "map", "a category opens its Storage Map")
t.assertEqual(ui.page.request.focusId, "developer", "focused on the category")
t.expect(ui.window.attachedSheet == nil, "the category has no sheet")
ui.navigation:back()
t.assertEqual(ui.destination, "overview", "Back restores Overview")

local meterOf = dofile("tests/fixtures/meter.lua")
t.expect(not meterOf(bridge._tableCell(ui.page.refs.results, 1, 0)).bar.hidden, "measured categories show a share bar")
local _, loadingIds = Scans:plan()
-- A running scan is shown by the app's progress window, not by half-filled lists:
-- the Overview draws its empty state and is drawn again when the scan finishes.
Scans:begin(loadingIds); ui:updateRows()
t.assertEqual(ui.page.refs.results, nil, "while the scan runs the Overview draws no category list")
t.assertEqual(ui.page.refs.largestSection, nil, "nor the largest items")
Scans:cancel(); ui:updateRows()
t.assertEqual(ui.page.refs.results.rowCount, 23, "the categories return with the scan's end")
window:layout()
t.expect(ui.page.refs.page.documentView.frame.size.height > ui.page.refs.page.contentView.bounds.size.height, "the overview scrolls past the category list")
t.expect(dofile("tests/fixtures/meter.lua")(bridge._tableCell(ui.page.refs.results, 1, 0)).spinner.hidden, "a finished scan leaves no category spinner")
ui.query = "no match"; ui:updateRows()
t.assertEqual(ui.page.refs.results.rowCount, 23, "the Overview never filters by text; Search does")
ui.query = ""; ui:updateRows()
ui.env.model.measurements.derived = {status = "complete", bytes = 4900000}
-- Rows are found by destination: the order is the sidebar's hierarchy,
-- checked on its own below.
local function row(id) return ui.navigation:index(id) end
sidebar:selectRow(row("developer"))
t.assertEqual(ui.destination, "developer", "selecting a sidebar row shows its page")
t.expect(ui.page.refs.list_xcode ~= nil and ui.page.refs.list_xcode.scrollDisabled, "developer sections are lists inside the page scroll")
local developerRows = {}
for index = 1, ui.page.refs.list_xcode.rowCount do developerRows[bridge._tableCell(ui.page.refs.list_xcode, 0, index - 1).textField.stringValue] = true end
t.expect(developerRows["Xcode DerivedData"], "developer lists present Xcode resources")
local developerMenu = bridge._tableRowMenu(ui.page.refs.list_xcode, 1)
t.expect(#developerMenu >= 3, "developer rows keep their actions in the row menu")
sidebar:selectRow(row("simulators"))
t.assertEqual(ui.destination, "simulators", "simulators are a sidebar destination")
t.expect(ui.page.refs.devices ~= nil and ui.page.refs.runtimes ~= nil and ui.page.refs.filter == nil,
	"the simulators page lists every device and runtime, without a filter")
sidebar:selectRow(row("updates"))
t.assertEqual(ui.destination, "updates", "updates and snapshots are a sidebar destination")
t.expect(ui.page.refs.updateTitle ~= nil and ui.page.refs.snapshotTitle ~= nil, "the updates page shows Software Update and snapshots")
t.assertEqual(bridge._tableCell(sidebar, 0, row("disks") - 1).textField.stringValue, "System", "system pages have their own section")
t.assertEqual(bridge._tableCell(sidebar, 0, row("developer") - 1).textField.stringValue, "Developer", "developer pages follow the system pages")
t.expect(row("developer") > row("updates"), "the Developer section follows System")
sidebar:selectRow(row("disks"))
t.assertEqual(ui.destination, "disks", "disks and volumes are a sidebar destination")
sidebar:selectRow(row("worktrees"))
t.assertEqual(ui.destination, "worktrees", "worktrees are a sidebar destination")
t.expect(ui.page.refs.removeList ~= nil and ui.page.refs.decisionHost ~= nil, "the worktrees page lists worktrees under its review decision")
sidebar:selectRow(row("guide"))
t.assertEqual(ui.destination, "guide", "the storage guide is a sidebar destination")
t.expect(ui.page.refs.topic_preboot ~= nil and ui.page.refs.details_preboot ~= nil, "guide topics disclose their details")
for _, id in ipairs({"files", "kinds", "duplicates", "cleanup", "applications"}) do
	sidebar:selectRow(row(id))
	t.assertEqual(ui.destination, id, "sidebar opens " .. id)
	t.expect(ui.page.refs.page ~= nil and ui.page.refs.page.documentView ~= nil, id .. " scrolls as one page")
end
for _, id in ipairs({"map", "xcode", "projects"}) do sidebar:selectRow(row(id)) end
t.assertEqual(ui.destination, "projects", "map, Xcode and projects are sidebar destinations")
t.expect(ui.navigation:canGoBack(), "visited pages form a back history")
ui.navigation:back()
t.assertEqual(ui.destination, "xcode", "back returns to the previous page")
ui.navigation:forward()
t.assertEqual(ui.destination, "projects", "forward returns again")
sidebar:selectRow(row("largest"))
t.assertEqual(ui.destination, "largest", "largest items are a sidebar destination")
t.expect(ui.page.refs.largest.scrollDisabled and ui.page.refs.page.documentView ~= nil, "largest items scroll with the page, not inside it")
t.assertEqual(ui.page.refs.reveal, nil, "largest items keep actions in row menus instead of buttons under the list")
sidebar:selectRow(row("overview"))
window.size = ns.Size(900, 600); window:layout()
t.expect(ui.page.refs.page.frame.origin.y >= 0, "small window keeps the overview within content")
t.expect(ui.page.refs.results.contentView.clipsToBounds, "rows clip within native scroll viewport")
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
local features = Store.new("/Users/test")
local uniquePaths = {}
for _, leaf in ipairs(Locations:leaves()) do
	if leaf.path then t.expect(not uniquePaths[leaf.path], "one catalog owner per exact path"); uniquePaths[leaf.path] = true end
end
t.assertEqual(Locations:find("vscode-cache").appIcon, "com.microsoft.VSCode", "resource inherits owning application icon")
t.assertEqual(Locations:find("temporary").color, "systemYellow", "temporary files have yellow badge")
t.assertEqual(Locations:find("dictation-1").policy, "System managed", "recognition assets never become disposable caches")
features.measurements["siri-assets-1"] = {bytes = 1200, status = "complete"}
features.measurements["dictation-1"] = {bytes = 800, status = "complete"}
local rolled = Categories:rows("intelligence")
t.assertEqual(rolled[2].bytes, 1200, "Siri has independent measured total")
t.assertEqual(rolled[2].status, "partial", "unmeasured asset classes remain explicit")
local speech = Categories:rows("speech-assets")
t.assertEqual(speech[1].bytes, 800, "Dictation remains independently measured with speech resources")
t.assertEqual(Locations:find("intelligence"):parent().id, "ai-agents", "Apple Intelligence and Siri belong to AI agents")
t.assertEqual(Locations:find("codex"):parent():parent().id, "ai-agents", "AI coding tools belong to AI agents")
t.assertEqual(Locations:find("cursor"):parent():parent().id, "ai-agents", "Cursor is counted with AI tools")
t.assertEqual(#Suggestions:ranked(), 0, "system feature data is never a cleanup suggestion")
os.exit(t.summary() and 0 or 1)
