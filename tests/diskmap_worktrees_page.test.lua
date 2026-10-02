_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local Model = require("apps.diskmap.Model")
local Mock = require("apps.diskmap.services.Mock")
local Host = require("tests.diskmap_page")
local Recommendations = require("apps.diskmap.models.Recommendations")
local Cleanup = require("apps.diskmap.models.Cleanup")

-- With the mock fixture: the page lists every worktree, offers the clean ones and holds the rest back.
local service = Mock.new()
local model = Model.new(service.home)
local confirmations, saved = {}, nil
service.confirmAction = function(title, message) table.insert(confirmations, {title, message}); return true end
service.saveKeep = function(kept) saved = kept; return true end
local changed, published, page, worktrees = 0, 0, nil, nil
page, worktrees = Host.new("worktrees", "WorktreesPage", "pages/Worktrees", {model = model, service = service,
	rescan = function() changed = changed + 1 end, refresh = function() published = published + 1; page:update(page.state) end})
page:mount(ns.VStack {}, {query = ""})
local refs = page.refs
t.expect(worktrees.loaded and not worktrees.busy, "the scan completes")
local function listed()
	local count = 0
	for _, id in ipairs({"removeList", "reviewList", "missingList", "repositoryList"}) do count = count + refs[id].rowCount end
	return count
end
t.assertEqual(listed(), 7, "every worktree is listed, once each")
-- #100/#102: removable linked worktrees lead, then those needing review; the
-- repository they came from is collapsed context, never first.
t.assertEqual(refs.removeList.rowCount, 2, "the removable worktrees have their own list")
t.assertEqual(refs.reviewList.rowCount, 3, "the ones needing a person follow")
t.assertEqual(refs.missingList.rowCount, 1, "missing registrations are apart")
t.assertEqual(refs.repositoryList.rowCount, 1, "the repository is context")
t.expect(refs.repositories.subviews[2].hidden, "and starts collapsed")
local order = {}
for index, view in ipairs(refs.pageContent.subviews) do order[view] = index end
t.expect(order[refs.decisionHost] < order[refs.removeSection] and order[refs.removeSection] < order[refs.reviewSection]
	and order[refs.reviewSection] < order[refs.repositories], "decision, removable, review, then repositories")
for _, row in ipairs(worktrees.lists.removeList) do t.assertEqual(row.roleLabel, "Ready", "a removable worktree reads Ready") end
local byName = {}
for _, row in ipairs(worktrees.rows) do byName[row.name] = row end
t.assertEqual(byName.MockProject.state, "primary", "the primary checkout is protected")
t.assertEqual(byName["coin-quest"].state, "candidate", "a clean, merged Claude worktree is a candidate")
t.assertEqual(byName.navigation.state, "candidate", "a published, unmerged one is too")
t.assertEqual(byName.MockProject.manager, nil, "the primary has no manager")
local codexDirty, codexDetached
for _, row in ipairs(worktrees.rows) do
	if row.name == "3f2a/MockProject" then codexDirty = row elseif row.name == "9bd1/MockProject" then codexDetached = row end
end
t.assertEqual(byName["3f2a/MockProject"] ~= nil and byName["9bd1/MockProject"] ~= nil, true, "worktrees named after their repository are told apart by their own folder")
t.assertEqual(codexDirty.state, "recent", "a Codex worktree touched in the last hours waits for review, whatever else is true of it")
t.assertEqual(codexDirty.roleLabel, "Recent", "and says only that it was recently touched")
t.expect(not codexDirty.lastUse:find("[Uu]sed"), "its column is Last change, with a compact date: " .. codexDirty.lastUse)
t.assertEqual(codexDetached.state, "unpublished", "a detached worktree with commits nowhere else is held back")
t.assertEqual(byName["mockproject-spike"].state, "locked", "a locked worktree is protected")
t.assertEqual(byName["mockproject-gone"].state, "missing", "a missing registration is listed")
t.expect(published > 0 and model.worktreePlan and model.worktreePlan.removalCount == 2, "the plan is published for Clean Up")
t.assertEqual(model.worktreePlan.pruneCount, 1, "with its missing registration counted apart")
local decision = page.refs
t.expect(decision.decisionAction.enabled and decision.decisionAction.title:find("2 Worktrees", 1, true), "the review button counts the removal set")
t.assertEqual(decision.decisionAmount.stringValue, Model.size(model.worktreePlan.removalBytes), "beside the amount the removal could recover")
t.assertEqual(decision.decisionCaption.stringValue, "could recover", "which says what it is")
t.expect(refs.prune.enabled, "missing registrations can be pruned")
t.expect(refs.removeDetail.text:find("Source", 1, true) and refs.removeDetail.text:find("Git", 1, true), "storage is shown split: " .. refs.removeDetail.text)

-- Selecting a row explains it; Keep protects it everywhere.
local function select(name)
	for id, rows in pairs(worktrees.lists) do
		for index, row in ipairs(rows) do
			if row.name == name then page.refs[id]:selectRow(index - 1); return row end
		end
	end
end
select("coin-quest")
t.expect(refs.selectedDetail.text:find("merged", 1, true) and refs.selectedDetail.text:find("Source", 1, true), "the details give the evidence and the storage split: " .. refs.selectedDetail.text)
t.expect(refs.openOwner.enabled and refs.openOwner.title == "Open Claude…", "a managed worktree offers its owner's archive flow")
t.expect(refs.keep.enabled, "Keep is available")
page.actions.keep()
t.expect(saved and saved["worktree:" .. byName["coin-quest"].path], "Keep is saved with the other Keep choices")
refs = page.refs
t.assertEqual(model.worktreePlan.removalCount, 1, "a kept worktree leaves the plan")
select("MockProject")
t.expect(not refs.keep.enabled, "the primary cannot be kept or removed")

-- Clean Up carries the same plan and does not count the tool's folder again.
local data = Recommendations.presentation(model, "", {})
local candidate
for _, row in ipairs(data.decisions) do if row.id == "worktrees" then candidate = row end end
t.expect(candidate and candidate.page == "worktrees", "Clean Up offers the worktree review")
t.assertEqual(candidate.eligibleBytes, model.worktreePlan.removalBytes, "with the plan's removal bytes as its eligible bytes")
model.measurements["codex-worktrees"] = {status = "complete", bytes = 2e9}
for _, value in ipairs(Cleanup.suggestions(model)) do t.expect(value.id ~= "codex-worktrees", "the tool's worktree folder is not suggested beside the per-worktree review") end

-- Review: one confirmation, each worktree rechecked, nothing forced, results reported.
select("coin-quest")
page.actions.keep()
t.assertEqual(model.worktreePlan.removalCount, 2, "removing Keep puts the worktree back in the plan")
local removedPaths = {}
local realCommand = service.command
service.command = function(argv, done)
	table.insert(removedPaths, argv)
	realCommand(argv, done)
end
-- Between the review and the removal, one worktree gains an uncommitted change.
local store = service.worktreeStore
local realState = service.worktreeState
service.worktreeState = function(row, done)
	if row.name == "navigation" then
		realState(row, function(entry, facts) facts.changes = 2; done(entry, facts) end)
	else realState(row, done) end
end
local ran = page.actions.review()
t.expect(ran, "review runs")
t.assertEqual(#confirmations, 1, "one confirmation covers the whole set")
t.expect(confirmations[1][2]:find("Remove 2 worktrees", 1, true) and confirmations[1][2]:find("Claude keep their own session lists", 1, true), "it lists the set and names the owning app")
t.assertEqual(#removedPaths, 1, "the worktree that gained a change was never removed")
for _, argument in ipairs(removedPaths[1]) do t.expect(argument ~= "--force", "removal is never forced") end
t.expect(worktrees.result:find("Removed 1 worktree", 1, true) and worktrees.result:find("Skipped navigation", 1, true), "the result separates removed from skipped: " .. tostring(worktrees.result))
t.expect(worktrees.result:find("Free space", 1, true) and worktrees.result:find("not moved to the Trash", 1, true), "the result reports measured free space and that nothing went to the Trash: " .. tostring(worktrees.result))
t.expect(changed > 0, "the root remeasures")
t.assertEqual(#worktrees.rows, 6, "the removed worktree is gone from the next listing")
t.assertEqual(byName.MockProject ~= nil and worktrees.rows[1] ~= nil, true, "the rest are still listed")

-- Prune: its own review; forgets the registration, never a checkout.
local confirmationsBefore = #confirmations
t.expect(page.actions.prune(), "prune runs")
t.assertEqual(#confirmations, confirmationsBefore + 1, "prune has its own confirmation")
t.expect(confirmations[#confirmations][2]:find("No checkout is deleted", 1, true), "which says nothing is deleted")
t.assertEqual(#worktrees.rows, 5, "only the missing registration disappears")
for _, row in ipairs(worktrees.rows) do t.expect(row.state ~= "missing", "no missing registration remains") end
t.expect(worktrees.result:find("No checkout was deleted", 1, true), "and the result says so")

-- A failing removal is reported and the rest continue.
local failing = Mock.new()
local failModel = Model.new(failing.home)
failing.confirmAction = function() return true end
local failedPage, failed = Host.new("worktrees", "WorktreesPage", "pages/Worktrees", {model = failModel, service = failing})
failedPage:mount(ns.VStack {}, {query = ""})
local realFailing = failing.command
local attempts = 0
failing.command = function(argv, done)
	attempts = attempts + 1
	if attempts == 1 then done(false, "fatal: could not remove\nmore detail"); return end
	realFailing(argv, done)
end
t.expect(failedPage.actions.review(), "review runs when a removal will fail")
t.assertEqual(attempts, 2, "the second removal is still attempted after the first fails")
t.expect(failed.result:find("Failed", 1, true) and failed.result:find("Removed 1 worktree", 1, true), "failures and successes are both reported: " .. tostring(failed.result))

-- Empty and search states.
page:update({query = "no-such-worktree"})
refs = page.refs
t.assertEqual(listed(), 0, "a search with no match shows no rows")
page:update({query = ""})
local empty = Mock.new()
empty.worktreeScan = function(_, done) done({}, {}) end
local routed
local emptyPage, emptyWorktrees = Host.new("worktrees", "WorktreesPage", "pages/Worktrees", {model = Model.new(empty.home), service = empty,
	show = function(id) routed = id end})
emptyPage:mount(ns.VStack {}, {query = ""})
t.expect(not emptyPage.refs.worktreesEmpty.hidden and emptyPage.refs.removeSection.hidden and emptyPage.refs.reviewSection.hidden, "no worktrees shows its own empty state")
t.assertEqual(emptyWorktrees.storage.worktreePlan.removalCount, 0, "and an empty plan")
t.assertEqual(emptyPage.refs.decisionAction.title, "Open Clean Up", "a page with nothing to remove routes to other cleanup")
ns._invokeAction(emptyPage.refs.decisionAction)
t.assertEqual(routed, "cleanup", "and the route opens Clean Up")

-- #100 P1: the root starts the inventory when a scan finishes, often before
-- the page is mounted. Delayed replies must finish the load whichever visit
-- of the page is current, and navigation away and back while it is pending
-- must not strand the page in loading.
local delayed = Mock.new()
local pending = {}
local realScan = delayed.worktreeScan
delayed.worktreeScan = function(self, roots, done, progress)
	table.insert(pending, function() realScan(self, roots, done, progress) end)
end
local lifecycle, lifecycleWorktrees = Host.new("worktrees", "WorktreesPage", "pages/Worktrees", {model = Model.new(delayed.home), service = delayed})
lifecycleWorktrees:load()
t.expect(lifecycleWorktrees.busy and not lifecycleWorktrees.loaded, "a background load is pending before the page mounts")
lifecycle:mount(ns.VStack {}, {query = ""})
t.assertEqual(#pending, 1, "mounting during a load does not start a second one")
t.assertEqual(lifecycle.refs.computingStatus.stringValue, "Looking for Git worktrees…", "the page shows one progress state while it loads")
t.expect(lifecycle.refs.removeList == nil and lifecycle.refs.decisionAction == nil, "and no empty lists")
lifecycle:dispose()
lifecycle:mount(ns.VStack {}, {query = ""})
pending[1]()
t.expect(not lifecycleWorktrees.busy and lifecycleWorktrees.loaded, "the pending load finishes after navigating away and back")
t.assertEqual(lifecycle.refs.removeList.rowCount, 2, "and the mounted page shows its result")
t.expect(lifecycle.refs.decisionAction.enabled, "with its review action ready")
local unmounted, unmountedWorktrees = Host.new("worktrees", "WorktreesPage", "pages/Worktrees", {model = Model.new(delayed.home), service = delayed})
unmountedWorktrees:load(); unmounted:mount(ns.VStack {}, {query = ""}); unmounted:dispose()
pending[#pending]()
t.expect(unmountedWorktrees.loaded and not unmountedWorktrees.busy and unmountedWorktrees.storage.worktreePlan ~= nil, "a load that finishes while the page is closed still publishes the plan")
os.exit(t.summary() and 0 or 1)
