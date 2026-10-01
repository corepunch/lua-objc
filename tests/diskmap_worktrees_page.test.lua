_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local Model = require("apps.diskmap.Model")
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.controllers.WorktreesController")
local Recommendations = require("apps.diskmap.models.Recommendations")
local Cleanup = require("apps.diskmap.models.Cleanup")

-- With the mock fixture: the page lists every worktree, offers the clean ones and holds the rest back.
local service = Mock.new()
local model = Model.new(service.home)
local confirmations, saved = {}, nil
service.confirmAction = function(title, message) table.insert(confirmations, {title, message}); return true end
service.saveKeep = function(kept) saved = kept; return true end
local changed = 0
local page = Controller.new(model, service, function() changed = changed + 1 end)
local published = 0
page.published = function() published = published + 1 end
page:mount(ns.VStack {}, {query = ""})
local refs = page.refs
t.expect(page.loaded and not page.busy, "the scan completes")
t.assertEqual(refs.worktrees.rowCount, 7, "every worktree is listed, once each")
local byName = {}
for _, row in ipairs(page.rows) do byName[row.name] = row end
t.assertEqual(byName.MockProject.state, "primary", "the primary checkout is protected")
t.assertEqual(byName["coin-quest"].state, "candidate", "a clean, merged Claude worktree is a candidate")
t.assertEqual(byName.navigation.state, "candidate", "a published, unmerged one is too")
t.assertEqual(byName.MockProject.manager, nil, "the primary has no manager")
local codexDirty, codexDetached
for _, row in ipairs(page.rows) do
	if row.name == "3f2a/MockProject" then codexDirty = row elseif row.name == "9bd1/MockProject" then codexDetached = row end
end
t.assertEqual(byName["3f2a/MockProject"] ~= nil and byName["9bd1/MockProject"] ~= nil, true, "worktrees named after their repository are told apart by their own folder")
t.assertEqual(codexDirty.state, "active", "a Codex worktree touched in the last hours is in use, whatever else is true of it")
t.assertEqual(codexDetached.state, "unpublished", "a detached worktree with commits nowhere else is held back")
t.assertEqual(byName["mockproject-spike"].state, "locked", "a locked worktree is protected")
t.assertEqual(byName["mockproject-gone"].state, "missing", "a missing registration is listed")
t.expect(published > 0 and model.worktreePlan and model.worktreePlan.removalCount == 2, "the plan is published for Clean Up")
t.assertEqual(model.worktreePlan.pruneCount, 1, "with its missing registration counted apart")
t.expect(refs.review.enabled and refs.review.title:find("2 Worktrees", 1, true), "the review button counts the removal set")
t.expect(refs.prune.enabled, "missing registrations can be pruned")
t.expect(refs.removeTileDetail.text:find("source", 1, true) and refs.removeTileDetail.text:find("Git", 1, true), "storage is shown split: " .. refs.removeTileDetail.text)

-- Selecting a row explains it; Keep protects it everywhere.
local function select(name)
	for index, row in ipairs(page.visibleRows and page:visibleRows() or {}) do
		if row.name == name then refs.worktrees:selectRow(index - 1); return row end
	end
end
select("coin-quest")
t.expect(refs.selectedDetail.text:find("merged", 1, true) and refs.selectedDetail.text:find("Source", 1, true), "the details give the evidence and the storage split: " .. refs.selectedDetail.text)
t.expect(refs.openOwner.enabled and refs.openOwner.title == "Open Claude…", "a managed worktree offers its owner's archive flow")
t.expect(refs.keep.enabled, "Keep is available")
page:toggleKeep()
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
page:toggleKeep()
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
local before = page.model.worktreePlan.removalCount
local ran = page:review()
t.expect(ran, "review runs")
t.assertEqual(#confirmations, 1, "one confirmation covers the whole set")
t.expect(confirmations[1][2]:find("Remove 2 worktrees", 1, true) and confirmations[1][2]:find("Claude keep their own session lists", 1, true), "it lists the set and names the owning app")
t.assertEqual(#removedPaths, 1, "the worktree that gained a change was never removed")
for _, argument in ipairs(removedPaths[1]) do t.expect(argument ~= "--force", "removal is never forced") end
t.expect(page.result:find("Removed 1 worktree", 1, true) and page.result:find("Skipped navigation", 1, true), "the result separates removed from skipped: " .. tostring(page.result))
t.expect(page.result:find("Free space", 1, true) and page.result:find("not moved to the Trash", 1, true), "the result reports measured free space and that nothing went to the Trash: " .. tostring(page.result))
t.expect(changed > 0, "the root remeasures")
t.assertEqual(#page.rows, 6, "the removed worktree is gone from the next listing")
t.assertEqual(byName.MockProject ~= nil and page.rows[1] ~= nil, true, "the rest are still listed")

-- Prune: its own review; forgets the registration, never a checkout.
local confirmationsBefore = #confirmations
t.expect(page:prune(), "prune runs")
t.assertEqual(#confirmations, confirmationsBefore + 1, "prune has its own confirmation")
t.expect(confirmations[#confirmations][2]:find("No checkout is deleted", 1, true), "which says nothing is deleted")
t.assertEqual(#page.rows, 5, "only the missing registration disappears")
for _, row in ipairs(page.rows) do t.expect(row.state ~= "missing", "no missing registration remains") end
t.expect(page.result:find("No checkout was deleted", 1, true), "and the result says so")

-- A failing removal is reported and the rest continue.
local failing = Mock.new()
local failModel = Model.new(failing.home)
failing.confirmAction = function() return true end
local failedPage = Controller.new(failModel, failing, function() end)
failedPage:mount(ns.VStack {}, {query = ""})
local realFailing = failing.command
local attempts = 0
failing.command = function(argv, done)
	attempts = attempts + 1
	if attempts == 1 then done(false, "fatal: could not remove\nmore detail"); return end
	realFailing(argv, done)
end
t.expect(failedPage:review(), "review runs when a removal will fail")
t.assertEqual(attempts, 2, "the second removal is still attempted after the first fails")
t.expect(failedPage.result:find("Failed", 1, true) and failedPage.result:find("Removed 1 worktree", 1, true), "failures and successes are both reported: " .. tostring(failedPage.result))

-- Empty and search states.
page:update({query = "no-such-worktree"})
t.assertEqual(page.refs.worktrees.rowCount, 0, "a search with no match shows no rows")
page:update({query = ""})
local empty = Mock.new()
empty.worktreeScan = function(_, done) done({}, {}) end
local emptyPage = Controller.new(Model.new(empty.home), empty, function() end)
emptyPage:mount(ns.VStack {}, {query = ""})
t.expect(not emptyPage.refs.worktreesEmpty.hidden and emptyPage.refs.worktreesPanel.hidden, "no worktrees shows its own empty state")
t.assertEqual(emptyPage.model.worktreePlan.removalCount, 0, "and an empty plan")
os.exit(t.summary() and 0 or 1)
