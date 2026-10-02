local Locations = require("apps.diskmap.models.Locations")
local Model = require("data.model")
local Format = require("apps.diskmap.helpers.Format")
local Catalog = require("apps.diskmap.Catalog")
local Worktrees = require("apps.diskmap.helpers.Worktrees")
local Selection = require("apps.diskmap.helpers.Selection")
local Outcome = require("apps.diskmap.helpers.Outcome")
local Batch = require("apps.diskmap.helpers.Batch")

-- The Worktrees page: linked Git worktrees found under the project folders and
-- the tools' own worktree roots, one review flow for removing them and one for
-- pruning missing registrations. The page outlives a visit: the root starts
-- the inventory when a scan finishes, often before the page opens, and a read
-- that ends later asks the app to draw again with `app.refresh()`.
local Page = {view = "pages/Worktrees"}
-- What only reads or leaves the page; every other action changes what it shows.
Page.queries = {reveal = true, cleanup = true}

function Page:init()
	self.service = self.app.service
	self.entries, self.facts, self.rows = {}, {}, {}
end

function Page:activate()
	if not self.loaded then self:load() end
end

local function keepKey(path) return "worktree:" .. path end
function Page:isKept(path) return Model.db.kept[keepKey(path)] == true end

-- Artifacts the scan discovered inside a worktree are its generated output;
-- the checkout total includes them, so they are split out, never added.
function Page:generatedBytes(path)
	local total = 0
	for _, row in ipairs(Locations:leaves()) do
		if row.artifact and row.path and row.path:sub(1, #path + 1) == path .. "/" then
			local m = Model.db.measurements[row.id]
			total = total + (m and m.bytes or 0)
		end
	end
	return total
end

-- The rows for what was read, and the plan published for Clean Up.
function Page:rebuild()
	for path, facts in pairs(self.facts) do facts.generatedBytes = math.max(facts.generatedBytes or 0, self:generatedBytes(path)) end
	self.rows = Worktrees.rows(self.entries, self.facts, {now = os.time(), kept = function(path) return self:isKept(path) end})
	local plan = Worktrees.plan(self.rows)
	Model.db.worktreePlan = {removalBytes = plan.removalBytes, removalCount = #plan.removal, reviewBytes = plan.reviewBytes,
		reviewCount = #plan.review, pruneCount = #plan.prune}
end

local function detail(row)
	local parts = {row.name .. " · " .. (row.branch or "Detached HEAD"), row.path, table.concat(row.reasons, " ")}
	for _, warning in ipairs(row.warnings or {}) do table.insert(parts, warning) end
	if row.worktreeBytes then
		table.insert(parts, "Source " .. Format.size(row.sourceBytes) .. " · generated output " .. Format.size(row.generatedBytes or 0)
			.. " · Git record " .. Format.size(row.gitBytes or 0) .. ". The repository's shared history is not counted here.")
	end
	if row.manager then table.insert(parts, row.manager .. " manages this location; archiving it there keeps its session list tidy.") end
	return table.concat(parts, " ")
end

-- The leading decision: what Git can remove now and what it could recover,
-- or, when nothing is removable, why, with a route to other cleanup.
local function decision(self, plan)
	local data = {id = "decision", icon = "arrow.triangle.branch", color = "systemPurple", amountCaption = "could recover",
		actionTitle = "Review…", action = "review", disabled = true}
	local linked = #plan.removal + #plan.review + #plan.prune
	if #plan.removal > 0 then
		data.title = "Remove " .. Format.plural(#plan.removal, "leftover worktree")
		data.detail = "Clean, published and unchanged for " .. Format.plural(Worktrees.recentDays, "day") .. "; each is checked again just before removal."
			.. (#plan.review > 0 and (" " .. Format.plural(#plan.review, "more worktree") .. " " .. (#plan.review == 1 and "needs" or "need") .. " your review below.") or "")
		data.amount = Format.size(plan.removalBytes)
		data.actionTitle = "Review " .. Format.plural(#plan.removal, "Worktree") .. "…"
		data.disabled = self.busy
	elseif #plan.review > 0 then
		data.title = Format.plural(#plan.review, "worktree") .. " " .. (#plan.review == 1 and "needs" or "need") .. " your review"
		data.detail = "Select a worktree below to read its evidence and open the app that manages it."
		data.amount, data.amountCaption = Format.size(plan.reviewBytes), "to review"
		data.actionTitle, data.action = nil, nil
	else
		data.title = linked > 0 and "No worktree to remove" or "No leftover worktrees"
		data.detail = (#plan.prune > 0 and (Format.plural(#plan.prune, "missing registration") .. " can be pruned below; that deletes no checkout. ") or "")
			.. "Clean Up lists the other places worth reviewing."
		data.amount, data.amountCaption = Format.size(0), "could recover"
		data.actionTitle, data.action, data.disabled = "Open Clean Up", "cleanup", false
	end
	return data
end

function Page:data(state)
	if not self.loaded then
		self.lists = {}
		return {computing = self.progress or "Looking for Git worktrees…", hidden = {selectionSection = true}, disabled = {retry = true}}
	end
	local needle = (state.query or ""):lower()
	local plan = Worktrees.plan(self.rows)
	local function only(rows)
		local found = {}
		for _, row in ipairs(rows) do
			if needle == "" or (row.name .. " " .. row.path .. " " .. row.subtitle):lower():find(needle, 1, true) then table.insert(found, row) end
		end
		return found
	end
	-- Locked and kept worktrees are decisions already made: they join the
	-- review list, after the ones that still need a person.
	local review, primary, linked, stored = {table.unpack(plan.review)}, {}, 0, 0
	for _, row in ipairs(plan.protected) do
		if row.state == "primary" then table.insert(primary, row) else table.insert(review, row) end
	end
	review = only(review)
	for _, row in ipairs(self.rows) do
		if row.state ~= "primary" then linked, stored = linked + 1, stored + row.bytes end
	end
	local lists = {removeList = only(plan.removal), reviewList = review, missingList = only(plan.prune), repositoryList = only(primary)}
	self.lists = lists
	local selected
	for _, rows in pairs(lists) do
		for _, row in ipairs(rows) do if self.selected and row.id == self.selected.id then selected = row end end
	end
	self.selected = selected
	local idle = not self.busy
	return {
		summary = (self.busy and "Working · " or "") .. Format.plural(linked, "linked worktree") .. " in "
			.. Format.plural(self.repositories or 0, "repository") .. " · " .. Format.size(stored) .. " stored", decision = decision(self, plan), status = self.result or "",
		removeDetail = "Clean, every commit published, and unchanged for " .. Format.plural(Worktrees.recentDays, "day")
			.. ". Source " .. Format.size(plan.sourceBytes) .. ", generated output " .. Format.size(plan.generatedBytes) .. ", Git record " .. Format.size(plan.gitBytes) .. ".",
		selection = selected and {title = selected.name .. " · " .. (selected.branch or "Detached HEAD"),
			summary = table.concat(selected.reasons, " "), detail = detail(selected)},
		lists = lists,
		hidden = {worktreesEmpty = linked > 0, removeSection = #lists.removeList == 0,
			reviewSection = #review == 0, missingSection = #lists.missingList == 0, repositories = #lists.repositoryList == 0,
			selectionSection = selected == nil},
		texts = {keep = selected and self:isKept(selected.path) and "Remove Keep" or "Keep",
			openOwner = selected and selected.manager and ("Open " .. selected.manager .. "…") or "Open Owner…"},
		disabled = {prune = not (idle and #plan.prune > 0), retry = not idle,
			reveal = not (idle and selected and selected.state ~= "missing"),
			keep = not (idle and selected and selected.state ~= "primary"),
			openOwner = not (idle and selected and selected.manager)},
	}
end

-- After a draw the native selection follows the selected row.
function Page:rendered(refs)
	for id, rows in pairs(self.lists) do Selection.show(refs[id], rows, self.selected and self.selected.id) end
end

function Page:select(_, _, row) self.selected = row end
function Page:cleanup() self.app.show("cleanup") end
function Page:retry() self.result = nil; self:load() end

function Page:reveal()
	if self.selected then self.service.reveal(self.selected.path) end
end

function Page:openOwner()
	if not self.selected or not self.selected.manager then return false end
	local ok, message = self.service.openOwner(self.selected.manager:lower())
	if ok == false then self.result = message end
	return ok
end

function Page:keep()
	local row = self.selected
	if not row or row.state == "primary" then return end
	local key = keepKey(row.path)
	Model.db.kept[key] = not Model.db.kept[key] or nil
	if self.service.saveKeep then self.service.saveKeep(Model.db.kept) end
	self:rebuild()
end

-- A load belongs to the inventory, not to one visit of the page: it may end
-- after the page was left or opened again, and the page shows the result
-- whenever it is open.
function Page:load()
	if self.busy then return end
	self.busy, self.progress = true, nil
	if type(self.service.worktreeScan) ~= "function" then
		self.busy, self.loaded = false, true
		self:rebuild()
		return
	end
	local roots = Catalog.projectRoots(Model.db.home, Model.db.projectRoots, false)
	self.service.worktreeScan(roots, function(entries, facts)
		self.busy, self.loaded, self.progress = false, true, nil
		self.entries, self.facts = entries or {}, facts or {}
		local repositories, count = {}, 0
		for _, entry in ipairs(self.entries) do
			if entry.commonDir and not repositories[entry.commonDir] then repositories[entry.commonDir] = true; count = count + 1 end
		end
		self.repositories = count
		self:rebuild()
		self.app.refresh()
	end, function(done, total)
		-- Discovery reads several facts per worktree; say how far it is.
		self.progress = total == 0 and "No linked worktrees found yet." or ("Reading the evidence for " .. Format.plural(total, "worktree") .. ": " .. done .. " done.")
		if not self.loaded then self.app.refresh() end
	end)
end

-- One confirmation for the whole removal set, then each worktree is read
-- again from Git and revalidated just before its own removal. A refused or
-- failed worktree is reported and the rest continue; nothing is forced.
function Page:review()
	if self.busy then return false end
	local plan = Worktrees.plan(self.rows)
	if not plan.ready then return false end
	if not self.service.confirmAction("Remove leftover worktrees", Worktrees.confirmation(plan)) then return false end
	self.busy, self.result = true, "Removing…"
	local freeBefore = Outcome.free(self.service, Model.db.home)
	Batch.run(plan.removal, {
		label = function(row) return row.name end,
		bytes = function(row) return row.bytes end,
		refresh = function(row, done)
			self.service.worktreeState(row, function(entry, facts) done({entry = entry, facts = facts}) end)
		end,
		validate = function(row, fresh)
			return Worktrees.revalidate(row, fresh.entry, fresh.facts, {now = os.time(), kept = self:isKept(row.path)})
		end,
		execute = function(row, done)
			self.service.command(Worktrees.removeCommand(row), function(success, output)
				self.app.log("git worktree remove " .. row.path, success, row.bytes, row.name, not success and output or nil)
				done(success, output)
			end)
		end,
	}, function(result)
		self.busy = false
		self.result = Batch.report(result, "Removed", "worktree")
			.. ". The repositories and every other worktree were left as they were; removed worktrees are deleted at once, not moved to the Trash. "
			.. Outcome.freeText(freeBefore, Outcome.free(self.service, Model.db.home), result.removed > 0) .. "."
		self.app.rescan()
		self:load()
	end)
	return true
end

-- Missing registrations are forgotten in their own review: pruning removes
-- Git's record only, never a checkout.
function Page:prune()
	if self.busy then return false end
	local plan = Worktrees.plan(self.rows)
	if #plan.prune == 0 then return false end
	local names, repositories = {}, {}
	for _, row in ipairs(plan.prune) do
		table.insert(names, row.name .. " · " .. row.path)
		repositories[row.repository] = Worktrees.pruneCommand(row)
	end
	if not self.service.confirmAction("Prune missing worktrees", "Forget " .. Format.plural(#plan.prune, "registration") .. " whose directory no longer exists?\n\n"
		.. table.concat(names, "\n") .. "\n\nThis removes Git's record only. No checkout is deleted.") then return false end
	self.busy, self.result = true, "Pruning…"
	local commands, failed = {}, 0
	for _, command in pairs(repositories) do table.insert(commands, command) end
	local function step(index)
		if index > #commands then
			self.busy = false
			self.result = failed == 0 and ("Pruned " .. Format.plural(#plan.prune, "registration") .. ". No checkout was deleted.") or ("Prune failed for " .. failed .. " repositories.")
			self:load(); return
		end
		self.service.command(commands[index], function(ok) if not ok then failed = failed + 1 end; step(index + 1) end)
	end
	step(1)
	return true
end

return {worktrees = Page}
