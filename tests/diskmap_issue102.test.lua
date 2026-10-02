_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local Model = require("apps.diskmap.Model")
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.Controller")
local Files = require("apps.diskmap.models.Files")
local Recommendations = require("apps.diskmap.models.Recommendations")
local Navigation = require("apps.diskmap.controllers.NavigationController")
local SimulatorsController = require("apps.diskmap.controllers.SimulatorsController")
local WorktreeService = require("apps.diskmap.services.Worktrees")

-- #102: every destination leads with a concrete decision (what to review,
-- why, what it could recover, and the action that starts it) before any
-- chart, inventory or empty inspector, at the smallest window size.
local service = Mock.new()
local app = Controller.new(service)
local window = app:createWindow()
app.scan:start()
window.size = ns.Size(950, 580); window:layout()

local function source(path) local file = assert(io.open(path)); local text = file:read("a"); file:close(); return text end

-- The bottom of `view`, in points from the top of its scrolling page.
local function bottomFromTop(view)
	local content = app.page.refs.pageContent
	local y = 0
	while view and view ~= content do y = y + view.frame.origin.y; view = view.superview end
	return content.frame.size.height - y
end
local function visible(id, label)
	app:show(id)
	bridge._flushLayout()
	local refs = app.page.refs
	local host = refs.lead or refs.decisionHost or (app.page.planRefs and app.page.planRefs.planCard) or refs.decision
	t.expect(host ~= nil and not host.hidden, label .. ": the page has a leading decision")
	local bottom = bottomFromTop(host)
	t.expect(bottom <= refs.page.contentView.bounds.size.height,
		label .. ": the decision and its action fit the first screen at 950 × 580 (" .. bottom .. " of " .. refs.page.contentView.bounds.size.height .. ")")
end
visible("cleanup", "Clean Up")
visible("simulators", "Simulators")
visible("worktrees", "Worktrees")
visible("applications", "Applications")
visible("kinds", "File Types")
visible("updates", "Updates")

-- Clean Up: the empty inspector takes no space; the lead is the top-ranked
-- suggestion; amounts say whether they could be recovered or are to review.
app:show("cleanup")
local cleanup = app.page
t.expect(cleanup.refs.selectionDetails.hidden, "Clean Up has no empty inspector")
local data = Recommendations.presentation(app.model, "", app.cleanupSources())
local top = data.lead
for _, row in ipairs(data.rebuildable) do t.expect(row.score <= top.score, "the lead outranks every rebuildable row: " .. row.id) end
for _, row in ipairs(data.decisions) do t.expect(row.score <= top.score, "and every decision: " .. row.id) end
local lead = cleanup.refs
t.expect(lead.decisionAction ~= nil and lead.decisionAction.enabled, "the lead has its action")
t.assertEqual(lead.decisionAmount.stringValue, top.size, "and its amount")
for _, list in ipairs({data.rebuildable, data.decisions}) do
	for _, row in ipairs(list) do
		if row.eligibleBytes and row.eligibleBytes > 0 then
			t.assertEqual(row.shareText, "could recover", row.id .. ": a proven amount says could recover")
			t.assertEqual(row.shownBytes, row.eligibleBytes, row.id .. ": and shows the recoverable bytes")
		else
			t.assertEqual(row.shareText, "to review", row.id .. ": an unproven amount says to review")
		end
	end
end
-- The simulator suggestion leads with what the plan removes, not the group.
local plan = {removalBytes = 13e9, removalCount = 3, blockedBytes = 0, complete = true}
local probe = Model.new("/Users/test")
probe.measurements.simulators = {status = "complete", bytes = 22e9}
probe.simulatorPlan = plan
local simulatorRow
for _, row in ipairs(Recommendations.presentation(probe, "", {}).decisions) do if row.id == "simulators" then simulatorRow = row end end
t.assertEqual(simulatorRow and simulatorRow.size, "13.0 GB", "the simulator suggestion shows what the minimal set could recover")
t.assertEqual(simulatorRow.shareText, "could recover", "and names it")
t.expect(simulatorRow.subtitle:find("22.0 GB is stored", 1, true), "the whole inventory is stated as stored, apart: " .. simulatorRow.subtitle)
t.expect(Recommendations.lead(Recommendations.presentation(probe, "", {})).title:find("Keep one iPhone and one iPad", 1, true),
	"the lead names the concrete decision")
local empty = Recommendations.lead({count = 0})
t.assertEqual(empty.action, "leadFiles", "with nothing to suggest the lead routes to where a person can still look")

-- The sidebar badge for Clean Up is its recoverable estimate, the number its page leads with.
local badges = app:badges()
t.assertEqual(badges.cleanup, Model.size(data.eligibleBytes), "Clean Up's badge is what it could recover")

-- The Overview's call to action names the same estimate.
local Overview = require("apps.diskmap.models.Overview")
t.assertEqual(Overview.reclaim(app.model, app.cleanupSources()).title, Model.size(data.eligibleBytes) .. " could recover",
	"the Overview headline, Clean Up and its badge name one number")

-- Meters: a capsule half the height of AppKit's 18-point capacity cell.
local gauge = ns.Gauge {value = 0.4, tint = "systemBlue", thickness = 9}
t.assertEqual(gauge.intrinsicContentSize.height, 9, "a gauge with a thickness is that tall")
t.assertEqual(gauge.className, "LuaLevelIndicator", "and is still the native level indicator")
t.assertEqual(ns.Gauge {value = 0.4}.intrinsicContentSize.height, 18, "without one it keeps AppKit's cell")
t.expect(source("apps/diskmap/views/cells/Meter.etlua"):find("thickness=", 1, true), "every Diskmap meter uses the capsule")

-- File Types: the installers kind states its total stored and the user-owned
-- part apart; archives are never counted as installers.
app:show("kinds")
local kinds = Files.kinds(app.model)
local installers, archives
for _, kind in ipairs(kinds) do
	if kind.id == "installers" then installers = kind elseif kind.id == "archives" then archives = kind end
end
local ownInstallers, ownArchives = 0, 0
for _, row in ipairs(Files.rows(app.model, "Installers & archives")) do
	if row.kindId == "installers" then ownInstallers = ownInstallers + row.bytes else ownArchives = ownArchives + row.bytes end
end
t.assertEqual(installers.removableBytes, ownInstallers, "the installers kind counts only its own user-owned files")
t.assertEqual(archives and archives.removableBytes, archives and ownArchives, "and archives theirs")
local kindsPage = app.page
local decision = kindsPage:decisionData(kinds)
t.assertEqual(decision.amount, Model.size(ownInstallers + ownArchives), "the decision's amount is the user-owned review set")
t.assertEqual(decision.amountCaption, "could recover", "which it names")
t.expect(decision.detail:find("installed or extracted", 1, true), "the lead explains the review before removal")
local shown
kindsPage.show = function(id, filter) shown = {id, filter} end
app.page.template.actions.decisionInstallers()
t.assertEqual(shown[1] .. "/" .. shown[2], "files/Installers & archives", "its action opens the reviewable files")

-- Updates routes to Clean Up with the same estimate Clean Up states.
app:show("updates")
t.expect(app.page.refs.decisionAction ~= nil, "Updates offers a direct route to Clean Up")
t.assertEqual(app.page.refs.decisionAmount.stringValue, Model.size(data.eligibleBytes), "with Clean Up's own estimate")
ns._invokeAction(app.page.refs.decisionAction)
t.assertEqual(app.destination, "cleanup", "and opens it")

-- Sidebar: the cleanup entry points come before the browsing tools.
local index = {}
for position, row in ipairs(Navigation.destinations) do if row.id then index[row.id] = position end end
for _, id in ipairs({"cleanup", "applications", "files", "simulators", "worktrees"}) do
	t.expect(index[id] < index.map and index[id] < index.largest and index[id] < index.kinds, id .. " is listed before the browsing tools")
end

-- Critical guidance wraps instead of truncating.
t.expect(source("apps/diskmap/views/SectionHeader.etlua"):find('lines="0"', 1, true) and not source("apps/diskmap/views/SectionHeader.etlua"):find('lines="2"', 1, true),
	"section explanations wrap")
local function wraps(path, id)
	local text = source(path)
	local start = text:find('id="' .. id .. '"', 1, true)
	local tag = start and text:sub(start, text:find("/>", start, true))
	return tag ~= nil and tag:find('lines="0"', 1, true) ~= nil and not tag:find("truncation", 1, true)
end
t.expect(wraps("apps/diskmap/views/Decision.etlua", "<%= id %>Title"), "a decision's title wraps")
t.expect(wraps("apps/diskmap/views/Decision.etlua", "<%= id %>Detail"), "a decision's detail wraps")
t.expect(wraps("apps/diskmap/views/SimulatorPlan.etlua", "planSummary"), "the plan's qualifications wrap")
t.expect(wraps("apps/diskmap/views/Folder.etlua", "folderHover"), "the Folder Map's guidance wraps in a narrow pane")
window:close()

-- #100 P1: Simulators. The root reads the inventory when a scan finishes,
-- before the page mounts; replies arrive later. Navigation away and back
-- while they are pending must not strand the page in loading.
local delayed = Mock.new()
local replies = {}
local runtimes = delayed.simulatorRuntimes
delayed.simulatorRuntimes = function(done) table.insert(replies, function() runtimes(done) end) end
local model = Model.new(delayed.home)
local simulators = SimulatorsController.new({model = model, service = delayed, rescan = function() end})
simulators:load()
t.expect(simulators.busy and simulators.loading, "a background read is pending before the page mounts")
simulators:mount(ns.VStack {}, {query = ""})
t.assertEqual(#replies, 1, "mounting during the read does not start another")
t.assertEqual(simulators.refs.summary.text, "Reading simulator devices and runtimes…", "the page shows the pending read")
simulators:dispose()
simulators:mount(ns.VStack {}, {query = ""})
for _, reply in ipairs(replies) do reply() end
t.expect(not simulators.busy and simulators.loaded, "the read finishes after navigating away and back")
t.expect(simulators.refs.summary.text:find("stored in", 1, true), "and the mounted page shows it: " .. simulators.refs.summary.text)
t.expect(simulators.planRefs.planReview ~= nil and simulators.planRefs.planAmount.text ~= "—", "with the plan's amount beside its review button")
t.expect(model.simulatorPlan ~= nil, "and the plan is published for Clean Up")
t.expect(simulators.refs.retry.enabled, "Retry is available again")
-- A read that completes while the page is closed still records the inventory.
replies = {}
local closed = SimulatorsController.new({model = Model.new(delayed.home), service = delayed, rescan = function() end})
closed:load(); closed:mount(ns.VStack {}, {query = ""}); closed:dispose()
for _, reply in ipairs(replies) do reply() end
t.expect(closed.loaded and not closed.busy and closed.model.simulatorPlan ~= nil, "a read that finishes while the page is closed publishes its plan")
closed:mount(ns.VStack {}, {query = ""})
t.expect(closed.refs.summary.text:find("stored in", 1, true), "and the next visit shows it at once")

-- Simulators: keep choices, recoverable bytes and the review action sit
-- together, before the plan's list; the full inventory is collapsed.
local plain = SimulatorsController.new({model = Model.new(service.home), service = service, rescan = function() end})
plain:mount(ns.VStack {}, {query = ""})
local planRefs = plain.planRefs
local order = {}
for position, view in ipairs(planRefs.planCard.subviews[1].subviews) do order[view] = position end
local actionRow = planRefs.planReview.superview
t.expect(planRefs.planAmount.superview.superview == actionRow, "the amount sits beside the review button")
t.assertEqual(planRefs.planCaption.text, "could recover", "and says it could be recovered")
t.expect(plain.refs.inventory.subviews[2].hidden, "the full device inventory is collapsed")

-- Worktree discovery: primary checkouts are neither measured nor queried;
-- activity is read before git status refreshes the index; worktrees are read
-- several at a time, with progress.
local calls = {}
local function run(argv, done)
	table.insert(calls, table.concat(argv, " "))
	local command = argv[#argv]
	if argv[1] == "/bin/test" then done(true, "") return end
	if argv[4] == "rev-parse" and argv[5] == "--absolute-git-dir" then done(true, "/repo/.git/worktrees/x\n") return end
	if argv[1] == "/usr/bin/stat" then done(true, "100\n200\n300\n") return end
	done(true, "")
end
local measured = {}
local function measure(paths, done) for _, path in ipairs(paths) do table.insert(measured, path) end; local sizes = {}; for i = 1, #paths do sizes[i] = 1 end; done(sizes) end
WorktreeService.facts(run, measure, {path = "/repo", primary = true}, function(facts)
	t.assertEqual(facts.exists, true, "a primary checkout's existence is known")
	t.assertEqual(facts.bytes, nil, "but it is not measured")
end)
t.assertEqual(#calls, 1, "and no Git command is run for it")
t.assertEqual(#measured, 0, "nothing of it is measured")
calls = {}
WorktreeService.facts(run, measure, {path = "/wt"}, function(facts) t.assertEqual(facts.lastActivity, 300, "the newest timestamp is the last change") end)
local statAt, statusAt
for position, call in ipairs(calls) do
	if call:find("^/usr/bin/stat") then statAt = statAt or position end
	if call:find(" status ") then statusAt = statusAt or position end
end
t.expect(statAt and statusAt and statAt < statusAt, "timestamps are read before git status can refresh the index")
local queued, progress = {}, {}
local function slow(argv, done) table.insert(queued, function() run(argv, done) end) end
local entries = {}
for i = 1, 6 do table.insert(entries, {path = "/wt" .. i}) end
local all
WorktreeService.allFacts(slow, measure, entries, function(facts) all = facts end, function(done, total) table.insert(progress, done .. "/" .. total) end)
t.assertEqual(#queued, WorktreeService.parallel, "worktrees are read several at a time")
while #queued > 0 do table.remove(queued, 1)() end
t.expect(all and all["/wt6"] ~= nil, "every worktree's facts arrive")
t.assertEqual(progress[#progress], "6/6", "progress reports each finished worktree")

-- Folder Map: a build folder is named by itself, not "CMake builds › CMake build output".
local FolderController = require("apps.diskmap.controllers.FolderController")
local folderModel = Model.new("/Users/test")
local artifact = {path = "/Users/test/p/build", name = "CMake build output", policy = "Rebuildable", artifact = true,
	getParent = function() return {name = "CMake builds"} end}
folderModel.resources.owner = function() return artifact end
local name = FolderController.catalogName({model = folderModel}, "/Users/test/p/build")
t.assertEqual(name, "CMake build output · Rebuildable", "a build folder's name does not repeat its kind")

os.exit(t.summary() and 0 or 1)
