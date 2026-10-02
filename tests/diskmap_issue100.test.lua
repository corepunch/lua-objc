_G.__headless = true
local Locations = require("apps.diskmap.models.Locations")
local t = require("TestKit")
local Model = require("data.model")
local Format = require("apps.diskmap.helpers.Format")
local Store = require("apps.diskmap.Store")
local Cleanup = require("apps.diskmap.helpers.Cleanup")
local Files = require("apps.diskmap.models.Files")
local Recommendations = require("apps.diskmap.helpers.Recommendations")

-- Clean Up leads with actions: no summary tiles, files and apps before the
-- review inventory, and the checked inventory collapsed.
local page = require("apps.diskmap.routes").cleanup
t.expect(page.layout.tiles == nil, "Clean Up has no summary tiles ahead of its lists")
local order = {}
for _, section in ipairs(page.layout.sections) do table.insert(order, section.id) end
t.assertEqual(table.concat(order, ","), "section_rebuildable,section_decisions,section_context,section_checked",
	"rebuildable, then decisions, then collapsed context and checked inventory")
t.expect(page.layout.sections[3].collapsed and page.layout.sections[4].collapsed, "context and the checked inventory are collapsed by default")
t.assertEqual(page:details(nil).detail, "", "an empty inspector stays compact")

-- Group recommendations agree with their children's eligibility.
local model = Store.new("/Users/test")
local function dirs(list)
	local result = {}
	for _, item in ipairs(list) do table.insert(result, {name = item[1], kb = item[2] / 1024, directory = true}) end
	return result
end
model.measurements.devices = {status = "complete", bytes = 4e9}
local function suggested(id)
	for _, row in ipairs(Cleanup.suggestions()) do if row.id == id then return row end end
end
model.breakdowns.devices = dirs({{"iPhone17,1 26.0 (23A341)", 4e9}})
t.assertEqual(suggested("devices"), nil, "device support holding only the newest version is not a dead-end suggestion")
t.expect(Cleanup.ineligible.devices:find("newest", 1, true), "and the reason is recorded: " .. tostring(Cleanup.ineligible.devices))
model.measurements.devices.bytes = 7e9
model.breakdowns.devices = dirs({{"iPhone17,1 26.0 (23A341)", 4e9}, {"18.6 (22G86)", 3e9}})
local devices = suggested("devices")
t.assertEqual(devices and devices.eligibleBytes, 3e9, "an older version is eligible; the newest is not")
t.assertEqual(devices and devices.bytes, 7e9, "bytes to review stay the measured total")

-- Simulators: eligible bytes are the minimal device set's removal, not the group.
model.measurements.simulators = {status = "complete", bytes = 22e9}
local sim = suggested("simulators")
t.assertEqual(sim.eligibleBytes, nil, "without a plan, simulator recovery is unknown, not the group total")
model.simulatorPlan = {removalBytes = 13e9, removalCount = 3, blockedBytes = 4e9, complete = true}
sim = suggested("simulators")
t.assertEqual(sim.eligibleBytes, 13e9, "with a plan, only the redundant devices count")
model.simulatorPlan = {removalBytes = 0, removalCount = 0, blockedBytes = 0, complete = true}
t.assertEqual(suggested("simulators"), nil, "a plan that removes nothing is not a suggestion")
model.simulatorPlan = nil

-- Ranking: eligible bytes x confidence / effort; unknown eligibility ranks by a fraction of its size.
local rebuildable = {bytes = 5e9, eligibleBytes = 5e9, confidence = "High", effort = "Low"}
local review = {bytes = 50e9, confidence = "Low", effort = "High"}
t.assertEqual(Cleanup.score(rebuildable), 5e9, "a proven rebuildable cache scores its size")
t.expect(Cleanup.score(review) < Cleanup.score(rebuildable), "50 GB to review does not outrank 5 GB that is certain")
t.expect(Cleanup.score({bytes = 10e9, eligibleBytes = 10e9, confidence = "Medium", effort = "Low"}) > Cleanup.score(rebuildable),
	"more recoverable bytes outrank fewer even at lower confidence")

-- Presentation separates review bytes from recoverable bytes and exposes the accounting.
model.measurements.simulators = {status = "complete", bytes = 22e9}
model.simulatorPlan = {removalBytes = 13e9, removalCount = 3, blockedBytes = 0, complete = true}
local data = Recommendations.presentation("", {})
local row
for _, item in ipairs(data.decisions) do if item.id == "simulators" then row = item end end
t.expect(row and row.page == "simulators", "the simulator suggestion opens the minimal device set")
t.expect(row.decisionTitle:find("Keep one iPhone and one iPad", 1, true), "and says what it proposes")
t.assertEqual(data.eligibleBytes, 13e9 + 3e9, "the page total adds eligible bytes only: " .. tostring(data.eligibleBytes))
t.expect(data.reviewBytes >= 22e9, "bytes to review are reported separately")
t.expect(Recommendations.recovery(row):find("Estimated recoverable 13", 1, true), "the inspector shows estimated recoverable bytes")
t.expect(Recommendations.recovery({bytes = 9e9}):find("recoverable space is unknown", 1, true), "unknown eligibility says so")
t.expect(data.summary:find("estimated recoverable", 1, true) and data.summary:find("to review", 1, true), "the headline keeps the two apart")

-- Applications: unknown usage never reaches Clean Up; high-confidence leftovers are the eligible part.
local Applications = require("apps.diskmap.models.Applications")
local summary = Applications.summary({{appBytes = 1e9, dataBytes = 0, bytes = 1e9, usageUnknown = true}}, {
	{bytes = 3e9, tier = "high"}, {bytes = 2e9, tier = "low"}})
t.assertEqual(summary.unused, 0, "an app with unknown usage is not unused")
t.assertEqual(summary.leftoversHighBytes, 3e9, "only high-confidence leftovers are eligible")
t.assertEqual(summary.leftoverBytes, 5e9, "all leftovers are bytes to review")
local out = Recommendations.presentation("", {apps = summary})
local leftovers
for _, item in ipairs(out.decisions) do if item.id == "leftovers" then leftovers = item end end
t.assertEqual(leftovers and leftovers.eligibleBytes, 3e9, "Clean Up carries the eligible part")
for _, item in ipairs(out.decisions) do t.expect(item.id ~= "unused-apps", "no inactivity suggestion from unknown usage") end

-- File kinds: the installer inventory is separate from what could be removed.
local Mock = require("apps.diskmap.services.Mock")
local AppController = require("apps.diskmap.Controller")
local app = AppController.new(Mock.new())
app.scan:start()
local all, removable = 0, 0
for _, row in ipairs(Files:rows("All")) do
	if row.kindId == "installers" or row.kindId == "archives" then all = all + 1 end
end
for _, row in ipairs(Files:rows("Installers & archives")) do
	removable = removable + 1
	t.expect(row.trashable, "the installers filter lists only files this app can move to the Trash: " .. row.path)
end
t.expect(removable > 0 and removable <= all, "removable installers are a subset of the installer-kind files")
local kinds = Files:kinds()
local installerKind
for _, kind in ipairs(kinds) do if kind.id == "installers" then installerKind = kind end end
t.expect(installerKind and installerKind.subtitle:find("total stored", 1, true), "the File Types row calls its total what is stored")
t.expect(installerKind.removableBytes and installerKind.removableBytes <= installerKind.bytes, "and shows the removable part apart from it")

-- Generated project output is one decision per artifact and project, counted once.
local Projects = require("apps.diskmap.models.Projects")
local Scan = require("apps.diskmap.services.Scan")
local pm = Store.new("/Users/test")
Scan.register(pm, {
	{id = "cm1", name = "CMake build output · engine", path = "/Users/test/Developer/engine/build", policy = "Rebuildable", action = "trash",
		artifact = "CMake build output", project = "/Users/test/Developer/engine", projectName = "engine", reviewThreshold = 500e6},
	{id = "cm2", name = "CMake build output · tools", path = "/Users/test/Developer/tools/build", policy = "Rebuildable", action = "trash",
		artifact = "CMake build output", project = "/Users/test/Developer/tools", projectName = "tools", reviewThreshold = 500e6},
})
pm.measurements.cm1 = {status = "complete", bytes = 400e6}
pm.measurements.cm2 = {status = "complete", bytes = 300e6}
Model.db.projectInfo = {}
local groups = Projects:groups(nil, nil, nil)
local projectTotal = 0
for _, group in ipairs(groups) do projectTotal = projectTotal + group.bytes end
local ecosystem
for _, value in ipairs(Cleanup.suggestions()) do if value.group then ecosystem = value end end
t.assertEqual(projectTotal, 700e6, "the Projects page counts each artifact once")
t.assertEqual(ecosystem and ecosystem.bytes, 700e6, "the ecosystem group counts the same artifacts once, not again")
t.assertEqual(ecosystem and ecosystem.eligibleBytes, 700e6, "and its eligible bytes equal its measured, proven rebuildable bytes")
pm.files = {large = {{path = "/Users/test/Developer/engine/build/obj/index.bin", bytes = 100e6, used = os.time()}}, old = {}, extensions = {}}
local ok, reason = Files:validateTrash("/Users/test/Developer/engine/build/obj/index.bin")
t.assertEqual(ok, false, "a single file inside generated output is not a trash candidate")
t.assertEqual(reason.code, "artifact", "the reason names the artifact: " .. tostring(reason and reason.message))
-- A running app is never inactive, whatever its date says.
local appModel = Store.new("/Users/test")
Locations:add("applications", {id = "run-app", name = "Busy.app", subtitle = "Installed application", path = "/Applications/Busy.app"})
appModel.measurements["run-app"] = {status = "complete", bytes = 5e8}
local oldDate = os.time() - 400 * 86400
Model.db.applicationInfo = {["/Applications/Busy.app"] = {bundleId = "com.example.busy", lastUsed = oldDate, running = true}}
local busy = Applications:rows("All")[1]
t.expect(busy.running and not busy.unused, "an app that is open now is not unused")
t.assertEqual(busy.detail, "Running now", "and says so")
Model.db.applicationInfo = {["/Applications/Busy.app"] = {bundleId = "com.example.busy", lastUsed = oldDate, running = true}}
t.assertEqual(#Applications:rows("Unused for 6 months"), 0,
	"the Unused filter leaves it out")
Model.db.applicationInfo = {["/Applications/Busy.app"] = {bundleId = "com.example.busy", lastUsed = oldDate}}
local idle = Applications:rows("Unused for 6 months")[1]
t.expect(idle and idle.unused, "the same app closed with a known old date is unused")

-- Totals say what they cover and what the scan could not see.
local Scope = require("apps.diskmap.helpers.Scope")
local scoped = Store.new("/Users/test")
t.expect(Scope.coverage():find("Photos, Music and TV libraries excluded", 1, true), "excluded media is stated")
scoped.includeMedia = true
t.assertEqual(Scope.coverage(), "Coverage: complete.", "a complete scan says so")
scoped.scan = {running = true, protected = 2}
t.expect(Scope.coverage():find("still growing", 1, true) and Scope.coverage():find("2 protected locations", 1, true), "an unfinished, partly unreadable scan says both")
for _, page in ipairs({"largest", "cleanup", "files", "kinds"}) do
	t.expect(Scope.text(page):find("Coverage:", 1, true) and #Scope.pages[page] > 20, page .. " states its population and coverage")
end
t.expect(Scope.pages.files:find("Largest Locations", 1, true) and Scope.pages.kinds:find("over 50 MB", 1, true), "overlaps between pages are named")
local scopeApp = AppController.new(Mock.new())
scopeApp:createWindow()
scopeApp.scan:start()
for _, id in ipairs({"largest", "cleanup", "files", "kinds"}) do
	scopeApp:show(id)
	t.expect(scopeApp.refs.scopeNote and scopeApp.refs.scopeNote.text:find("Coverage:", 1, true), id .. " shows its scope note beside its totals")
end

-- Every sidebar destination has an audited conclusion and next step, or a stated reason for none.
local Audit = require("apps.diskmap.knowledge.Audit")
local Navigation = require("apps.diskmap.controllers.NavigationController")
local seen = {}
for _, row in ipairs(Navigation.destinations) do
	if row.id then
		seen[row.id] = true
		local entry = Audit[row.id]
		t.expect(entry ~= nil, row.id .. " is in the cleanup audit")
		if entry then t.expect((entry.conclusion and entry.next) or entry.none, row.id .. " states a conclusion and next step, or why it has none") end
	end
end
for id in pairs(Audit) do t.expect(seen[id], "the audit names a real destination: " .. id) end

-- Updates: download size is not installation space, and no recovery target is invented.
local Updates = require("apps.diskmap.helpers.Updates")
local waiting = Updates.softwareUpdate({RecommendedUpdates = {{["Display Name"] = "macOS Tahoe 26.1"}}, LastSuccessfulDate = "2026-09-24 08:12:00 +0000"})
local note = Updates.spaceNote(waiting, 4e9)
t.expect(note:find("download size", 1, true) and note:find("needs more room", 1, true), "the note separates download size from installation space")
t.expect(note:find("unknown, not zero", 1, true) and not note:find("%d+%.?%d* GB to recover"), "the recovery target is stated unknown, never made up")
t.expect(note:find("do not remove them by hand", 1, true) and note:find("Update and Preboot", 1, true), "staging is explained without suggesting removing protected volumes")
t.expect(note:find("Free space now: 4.0 GB", 1, true), "the free space it does know is shown")
t.expect(Updates.spaceNote(Updates.softwareUpdate({}), nil):find("no space target applies", 1, true), "with no update there is nothing to make room for")
t.expect(Updates.spaceNote(Updates.softwareUpdate(nil), nil):find("Open Software Update", 1, true), "an unreadable record says to check Software Update")

-- Results report measured free space the same way everywhere.
local Outcome = require("apps.diskmap.helpers.Outcome")
t.assertEqual(Outcome.freeText(10e9, 12.1e9), "Free space 10.0 GB → 12.1 GB (+2.1 GB)", "a freed amount is shown")
t.expect(Outcome.freeText(10e9, 10e9, true):find("after a short delay", 1, true), "no change right after a removal explains the delay")
t.assertEqual(Outcome.freeText(nil, 1), "Free space could not be measured.", "an unmeasured figure says so")
t.assertEqual(Outcome.free({diskSpace = function() return {freeKb = 1000} end}, "/"), 1000 * 1024, "free space is read from the service")
t.assertEqual(Outcome.free({}, "/"), nil, "a service that cannot say gives nil")

-- One batch flow: refresh, validate, execute; skips and failures never stop the rest.
local Batch = require("apps.diskmap.helpers.Batch")
local log = {}
local outcome
Batch.run({{name = "a", bytes = 100}, {name = "b", bytes = 200}, {name = "c", bytes = 300}, {name = "d", bytes = 400}}, {
	label = function(item) return item.name end,
	bytes = function(item) return item.bytes end,
	refresh = function(item, done) table.insert(log, "refresh " .. item.name); done({stale = item.name == "b"}) end,
	validate = function(item, fresh) if fresh.stale then return false, {message = "changed"} end return true end,
	execute = function(item, done) table.insert(log, "run " .. item.name); if item.name == "c" then done(false, "boom\nmore") else done(true) end end,
}, function(result) outcome = result end)
t.assertEqual(table.concat(log, ","), "refresh a,run a,refresh b,refresh c,run c,refresh d,run d", "each item is refreshed first and a refused one is never run")
t.assertEqual(outcome.removed, 2, "two items were done")
t.assertEqual(outcome.bytes, 500, "their bytes add up")
t.assertEqual(outcome.skipped[1], "b (changed)", "the refused item is reported with its reason")
t.assertEqual(outcome.failed[1], "c (boom)", "a failure is reported on one line")
t.assertEqual(Batch.report(outcome, "Removed", "worktree"), "Removed 2 worktrees (0 KB). Skipped b (changed). Failed c (boom)", "the report reads as one sentence list")
t.assertEqual(Batch.report({removed = 0, bytes = 0, skipped = {}, failed = {}}, "Deleted", "device"), "Nothing was deleted", "an empty run says so")
os.exit(t.summary() and 0 or 1)
