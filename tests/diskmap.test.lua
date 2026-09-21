_G.__headless = true
local t = require("TestKit")
local Model = require("apps.diskmap.Model")
local Controller = require("apps.diskmap.Controller")
local System = require("apps.diskmap.services.System")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local xml = require("ui.xml")

t.assertEqual(Model.humanKb(1024), "1.0 MB", "formats megabytes")
t.assertEqual(Model.humanKb(-1), "0 KB", "clamps negative measurements")
local shares = {trees = {{kb = 1000, children = {
	{name = "Large", kb = 600, directory = true}, {name = "Medium", kb = 399}, {name = "Tiny", kb = 1}, {name = "Zero", kb = 0},
}}}}
local shareRows = Model.rows(shares, "Disk Map")
t.assertEqual(shareRows[1].percentage, "60%", "folder percentage uses measured root")
t.assertEqual(shareRows[3].percentage, "<1%", "tiny nonzero shares remain meaningful")
t.assertEqual(shareRows[4].percentage, "0%", "empty rows have zero share")
t.assertEqual(shareRows[1].iconColor, "systemBlue", "folder symbols use native blue")
local filtered = Model.rows(shares, "Disk Map", "Medium")[1]
t.assertEqual(filtered.share, 0.399, "filter does not change denominator")
t.assertEqual(filtered.shareColor, Model.segments(shares)[2].color, "filter preserves chart color")
shares.trees[1].kb = 0
t.assertEqual(Model.rows(shares, "Disk Map")[1].percentage, "—", "zero total has no misleading percentage")
shares.trees[1].kb = 1
t.assertEqual(Model.rows(shares, "Disk Map")[1].share, 1, "inconsistent measurements cannot overflow bar")
local rules = Model.rules("/Users/test")
local measurements = {trees = {}}
for i in ipairs(rules) do measurements.trees[i] = {kb = i * 1024} end
local suggestions, reclaimable = Model.suggestions(rules, measurements)
t.expect(reclaimable > 0, "rebuildable caches contribute to estimate")
t.expect(suggestions[1].kb > suggestions[#suggestions].kb, "sorts numeric sizes, not formatted text")
local expected = 0
for i, rule in ipairs(rules) do if rule.action == "trash" then expected = expected + i * 1024 end end
t.assertEqual(reclaimable, expected, "does not sum overlapping generic caches or personal data")
local calls = 0
local service = {trash = function() calls = calls + 1; return true end}
t.expect(Model.trash(rules[1], rules, service), "allows exact rebuildable location")
t.expect(not Model.trash({id = rules[1].id, path = "/Users/test/Documents"}, rules, service), "rejects modified path")
t.expect(not Model.trash(rules[2], rules, service), "archives require individual review")
t.assertEqual(calls, 1, "rejected requests never call trash service")
t.assertEqual(#Model.suggestions(rules, {}), 0, "missing results do not fabricate savings")
local result = {trees = {{children = {{name = "Small", kb = 5}, {name = "BIG", kb = 10240}}}}, types = {lua = {kb = 12, items = 3}}}
t.assertEqual(Model.rows(result, "Disk Map")[1].name, "BIG", "sorts storage descending")
t.assertEqual(#Model.rows(result, "Disk Map", "small"), 1, "case insensitive search")
t.assertEqual(#Model.rows(result, "Disk Map", "["), 0, "search is literal")
t.assertEqual(Model.rows(result, "File Types")[1].status, "3 files", "type counts")
t.assertEqual(result.trees[1].children[1].name, "Small", "view sorting preserves scan state")
t.assertEqual(System.quote("a'b $(echo bad)"), "'a'\\''b $(echo bad)'", "shell quotes hostile paths")
local cfg = xml.renderFile("apps/diskmap/views/Window.etlua", {}, ns)
t.assertEqual(cfg.toolbar[1].id, "toggleSidebar", "native sidebar toggle")
t.assertEqual(cfg.toolbar[10].id, "search", "search belongs in toolbar")
local view, refs = xml.renderFile("apps/diskmap/views/Dashboard.etlua", {title = "Suggestions", section = "Suggestions", subtitle = "Review caches", status = "Ready", actions = {}}, ns)
refs.results:replaceRows(suggestions)
view:layout(600)
local columns = bridge._tableColumnWidths(refs.results)
t.expect(#columns == 3, "native table has three columns")
refs.results:showLoading(); refs.results:hideLoading()
local barsView, barsRefs = xml.renderFile("apps/diskmap/views/Dashboard.etlua", {title = "Disk Map", section = "Disk Map", subtitle = "Fixture", status = "Ready", actions = {}}, ns)
barsRefs.results:replaceRows(shareRows)
barsView.size = ns.Size(600, 400)
barsView:layout(600)
barsRefs.results.size = ns.Size(600, 200)
barsRefs.results:layout(600)

local level = bridge._tableCell(barsRefs.results, 2, 0).levelIndicator
t.expect(level ~= nil, "percentage cells contain a native level indicator")
if level then
	t.assertEqual(level.doubleValue, 0.6, "native bar receives measured fraction")
	t.expect(not level.editable, "storage indicator is read-only")
end
t.assertEqual(bridge._tableCell(barsRefs.results, 0, 0).imageView.frame.size.width, 20, "disk map folder symbols use the larger result-row size")
t.assertEqual(barsRefs.results.documentView.rowHeight, 44, "folder rows have consistent breathing room")
barsRefs.results:replaceRows({{name = "Missing", percentage = "—"}})
barsView:layout(600)
barsRefs.results.size = ns.Size(600, 200)
barsRefs.results:layout(600)

level = bridge._tableCell(barsRefs.results, 2, 0).levelIndicator
if level then
	t.assertEqual(level.doubleValue, 0, "replacing measurements clears bar value")
	t.expect(level.hidden, "missing measurement hides bar")
end
barsRefs.results:replaceRows({{name = "Oversized", percentage = "100%", share = 2}, {name = "Negative", percentage = "0%", share = -1}})
t.assertEqual(bridge._tableCell(barsRefs.results, 2, 0).levelIndicator.doubleValue, 1, "native indicator clamps excessive fractions")
t.assertEqual(bridge._tableCell(barsRefs.results, 2, 1).levelIndicator.doubleValue, 0, "native indicator clamps negative fractions")
t.assertEqual(bridge._tableCell(barsRefs.results, 0, 0).textField.stringValue, "Oversized", "bar binding leaves name column intact")
local detail = xml.renderFile("apps/diskmap/views/RightSidebar.etlua", {name = "Test", path = "/tmp", size = "1 MB", icon = "folder", heading = "Review", message = "Consequences", review = true, hasPath = true, outcome = "After emptying Trash", primary = "Review", actions = {}}, ns)
t.expect(detail ~= nil, "review displays outcome and actions")
local search = xml.renderFile("apps/diskmap/views/ToolbarSearch.etlua", {actions = {search = function() end}}, ns)
t.expect(search ~= nil, "native toolbar search renders with change callback")
local segments = Model.segments({trees = {{kb = 100, children = {{name = "A", kb = 60}, {name = "B", kb = 20}, {name = "C", kb = 10}, {name = "D", kb = 10}}}}})
local weight = 0; for _, segment in ipairs(segments) do weight = weight + segment.weight end
t.assertEqual(weight, 1, "storage bar accounts for every measured block")
t.assertEqual(segments[4].name, "Other", "remaining entries grouped without omission")
t.assertEqual(#Model.segments({trees = {{kb = 0}}}), 0, "zero-size root has no misleading bar")
local locked = Model.suggestions(rules, {}, {})
t.assertEqual(#locked, #rules, "unmeasured locations remain visible")
t.assertEqual(locked[1].size, "Not measured", "unknown is never presented as zero")
local partial, partialTotal = Model.suggestions(rules, {trees = {{kb = 400, partial = true}}})
t.assertEqual(partialTotal, 0, "incomplete measurement never promises reclaimable space")
t.assertEqual(partial[1].action, "measure", "incomplete caches must be remeasured before cleanup")
for _, rule in ipairs(rules) do
	if rule.id == "backups" or rule.id == "docker" or rule.id == "trash" or rule.id == "caches" then
		t.expect(not rule.automatic, rule.id .. " is never scanned automatically")
	end
end
local controller = Controller.new(service)
t.assertEqual(controller.section, "Disk Map", "starts with disk map")
-- Exercise the real worker without windows or asynchronous waits.
local pipe = assert(io.popen("/usr/bin/mktemp -d /tmp/diskmap-test.XXXXXXXX"))
local root = pipe:read("*l"); pipe:close()
local hostile = root .. "/quote' dollar$ tab\tline\n.txt"
local file = assert(io.open(hostile, "wb")); file:write(string.rep("x", 8192)); file:close()
os.execute("/bin/mkdir " .. System.quote(root .. "/empty"))
os.execute("/bin/ln " .. System.quote(hostile) .. " " .. System.quote(root .. "/hardlink.txt"))
os.execute("/bin/ln -s / " .. System.quote(root .. "/outside"))
local output = root .. ".json"
t.expect(os.execute("/usr/bin/perl apps/diskmap/services/scan.pl " .. System.quote(output) .. " 0 tree " .. System.quote(root)), "worker exits successfully")
local f = assert(io.open(output)); local scan = ns.json_parse(f:read("*a")); f:close()
t.assertEqual(scan.failure, "", "worker completes")
t.assertEqual(scan.errors, 0, "readable fixture has no errors")
t.assertEqual(#scan.trees[1].children, 3, "symlink excluded, empty directory included")
t.assertEqual(scan.types.txt.items, 2, "hardlinks counted as entries")
t.assertEqual(scan.types.txt.kb, 8, "hardlink blocks counted once")
local found = false
for _, row in ipairs(scan.trees[1].children) do if row.path == hostile then found = true end end
t.expect(found, "arbitrary filename round-trips through JSON")
os.remove(hostile); os.remove(root .. "/hardlink.txt"); os.remove(root .. "/outside"); os.remove(root .. "/empty"); os.remove(root); os.remove(output)
-- Startup must not recursively scan the user's home or protected app data.
local started, cancelled = {}, 0
local fake = {
	start = function(paths, mode) started[#started + 1] = {paths = paths, mode = mode}; return {paths = paths} end,
	poll = function() return true, {trees = {}, rootStates = {}, failure = "", errors = 0} end,
	cancel = function() cancelled = cancelled + 1 end,
	diskSpace = function() return {totalKb = 10000, freeKb = 5000} end,
	pickFolder = function() return nil end,
}
local savedArgs = arg; arg = {}
local app = Controller.new(fake)
local window = app:createWindow()
t.assertEqual(#started, 1, "startup only scans suggestion allowlist")
t.assertEqual(started[1].mode, "summary", "background scan retains aggregate sizes only")
for _, path in ipairs(started[1].paths) do
	t.expect(path ~= app.home and not path:find("Containers", 1, true) and not path:find("MobileSync", 1, true), "startup avoids broad and protected locations")
end
t.expect(not ns.ToolbarItem(window, "back").enabled, "Back disabled without history")
t.expect(not ns.ToolbarItem(window, "cancel").enabled, "Cancel disabled when no folder scan runs")
app:chooseFolder()
t.assertEqual(#started, 1, "cancelled folder picker never starts a scan")
local function originX(view)
	local x = 0
	while view do x = x + view.frame.origin.x; view = view.superview end
	return x
end
local sidebarView = window.contentViewController.splitViewItems[1].viewController.view
t.expect(originX(app.refs.content) >= originX(sidebarView) + sidebarView.frame.size.width - 1, "three-pane content clears native sidebar")
app:showSection("Suggestions")
t.expect(app.results ~= nil, "suggestions uses native table")
app.query = "no such suggestion"; app:updateRows()
t.assertEqual(app.results.rowCount, 0, "empty search clears table")
local captured
xml.render('<List><Column id="name" imageKey="symbol" /></List>', {}, {List = function(props) captured = props; return props end})
t.assertEqual(captured.columns[1].cell.image, "symbol", "XML binds per-row symbols into native cell schema")
app.await = function(_, job, completion) job.complete = completion end
app.section = "Disk Map"
app.query = ""
app:startScan("/First", true)
local older = app.scanJob
app:startScan("/Second", true)
local newer = app.scanJob
t.expect(older.cancelled, "new scans cancel prior workers")
older.complete({trees = {{path = "/First", kb = 1, children = {}}}, failure = ""})
t.assertEqual(app.result, nil, "stale completion cannot replace newer scan")
t.assertEqual(app.currentPath, "/Second", "stale scan preserves navigation")
newer.complete({trees = {{name = "Second", path = "/Second", directory = true, kb = 10, children = {{name = "child", path = "/Second/child", kb = 5, directory = true}}}}, failure = "", errors = 0, seconds = 0})
t.assertEqual(app.results.rowCount, 1, "latest scan displays rows")
window.size = ns.Size(1000, 600); window:layout()
local resultsFrame = app.results.frame
local dashboard = app.refs.content.subviews[1]
t.expect(dashboard.frame.origin.y >= 0 and dashboard.frame.size.height <= app.refs.content.frame.size.height, "dashboard shrinks with its native pane")
local lastCell = bridge._tableCellFrames(app.results, 0)[3]
t.expect(lastCell.maxX <= resultsFrame.size.width + 1, "all columns remain inside the small viewport " .. lastCell.maxX .. " <= " .. resultsFrame.size.width)
app.results:activateRow(0)
t.assertEqual(app.currentPath, "/Second/child", "native activation navigates into folders")
t.assertEqual(app.history[#app.history], "/Second", "folder navigation preserves back history")
app:goBack()
t.assertEqual(app.currentPath, "/Second", "Back restores parent")
app:goForward()
t.assertEqual(app.currentPath, "/Second/child", "Forward restores child")
window:close(); arg = savedArgs
os.exit(t.summary() and 0 or 1)
