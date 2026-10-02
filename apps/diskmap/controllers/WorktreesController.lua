local Page = require("apps.diskmap.controllers.PageController")
local Model = require("apps.diskmap.Model")
local Catalog = require("apps.diskmap.Catalog")
local Worktrees = require("apps.diskmap.models.Worktrees")
local Outcome = require("apps.diskmap.models.Outcome")
local Batch = require("apps.diskmap.models.Batch")
local Controller = Page.extend("worktrees", "Worktrees")

-- The Worktrees page: linked Git worktrees found under the project folders
-- and the tools' own worktree roots, one review flow for removing them and
-- one for pruning missing registrations. `changed` asks the root to
-- remeasure after an action; `published` tells Clean Up the plan changed.
function Controller.new(model, service, changed)
	return setmetatable({model = model, service = service, changed = changed, entries = {}, facts = {}, rows = {}}, Controller)
end

local function keepKey(path) return "worktree:" .. path end

function Controller:isKept(path) return self.model.kept[keepKey(path)] == true end

function Controller:mount(host, state)
	self.query, self.selected = state.query or "", nil
	local refs = self:attach(host, {actions = {
		select = function(_, _, row) self.selected = row; self:buttons() end,
		reveal = function() if self.selected then self.service.reveal(self.selected.path) end end,
		keep = function() self:toggleKeep() end,
		openOwner = function() self:openOwner() end,
		review = function() self:review() end,
		cleanup = function() if self.showPage then self.showPage("cleanup") end end,
		prune = function() self:prune() end,
		retry = function() self.result = nil; self:load() end,
	}})
	if self.loaded then self:show() else self:load() end
	return refs
end

function Controller:update(state)
	if self.query == (state.query or "") then return end
	self.query = state.query or ""
	self:show()
end

-- Artifacts the scan discovered inside a worktree are its generated output;
-- the checkout total includes them, so they are split out, never added.
function Controller:generatedBytes(path)
	local total = 0
	for _, row in ipairs(self.model.resources:leaves()) do
		if row.artifact and row.path and row.path:sub(1, #path + 1) == path .. "/" then
			local m = self.model.measurements[row.id]
			total = total + (m and m.bytes or 0)
		end
	end
	return total
end

function Controller:buildRows()
	for path, facts in pairs(self.facts) do facts.generatedBytes = math.max(facts.generatedBytes or 0, self:generatedBytes(path)) end
	return Worktrees.rows(self.entries, self.facts, {now = os.time(), kept = function(path) return self:isKept(path) end})
end

function Controller:publish()
	if not self.loaded then self.model.worktreePlan = nil; return end
	local plan = Worktrees.plan(self.rows)
	self.model.worktreePlan = {removalBytes = plan.removalBytes, removalCount = #plan.removal, reviewBytes = plan.reviewBytes,
		reviewCount = #plan.review, pruneCount = #plan.prune}
end

function Controller:visibleRows()
	local needle, rows = (self.query or ""):lower(), {}
	for _, row in ipairs(self.rows) do
		if needle == "" or (row.name .. " " .. row.path .. " " .. row.subtitle):lower():find(needle, 1, true) then table.insert(rows, row) end
	end
	return rows
end

function Controller:detail(row)
	if not row then return "Select a worktree to see why it is or is not offered." end
	local parts = {row.name .. " · " .. (row.branch or "Detached HEAD"), row.path, table.concat(row.reasons, " ")}
	for _, warning in ipairs(row.warnings or {}) do table.insert(parts, warning) end
	if row.worktreeBytes then
		table.insert(parts, "Source " .. Model.size(row.sourceBytes) .. " · generated output " .. Model.size(row.generatedBytes or 0)
			.. " · Git record " .. Model.size(row.gitBytes or 0) .. ". The repository's shared history is not counted here.")
	end
	if row.manager then table.insert(parts, row.manager .. " manages this location; archiving it there keeps its session list tidy.") end
	return table.concat(parts, " ")
end

-- The leading decision: what Git can remove now and what it could recover,
-- or, when nothing is removable, why, with a route to other cleanup.
function Controller:decisionData(plan)
	local data = {id = "decision", icon = "arrow.triangle.branch", color = "systemPurple", amountCaption = "could recover",
		actionTitle = "Review…", action = "review", disabled = true, actions = self.decisionActions}
	if self.loading then
		data.title = "Looking for leftover worktrees…"
		data.detail = self.progress or "Finding repositories in your project folders."
		data.amount = "—"
		return data
	end
	local linked = #plan.removal + #plan.review + #plan.prune
	if #plan.removal > 0 then
		data.title = "Remove " .. Model.plural(#plan.removal, "leftover worktree")
		data.detail = "Clean, published and unchanged for " .. Model.plural(Worktrees.recentDays, "day") .. "; each is checked again just before removal."
			.. (#plan.review > 0 and (" " .. Model.plural(#plan.review, "more worktree") .. " " .. (#plan.review == 1 and "needs" or "need") .. " your review below.") or "")
		data.amount = Model.size(plan.removalBytes)
		data.actionTitle = "Review " .. Model.plural(#plan.removal, "Worktree") .. "…"
		data.disabled = self.busy
	elseif #plan.review > 0 then
		data.title = Model.plural(#plan.review, "worktree") .. " " .. (#plan.review == 1 and "needs" or "need") .. " your review"
		data.detail = "Select a worktree below to read its evidence and open the app that manages it."
		data.amount, data.amountCaption = Model.size(plan.reviewBytes), "to review"
		data.actionTitle, data.action, data.disabled = nil, nil, true
	else
		data.title = linked > 0 and "No worktree to remove" or "No leftover worktrees"
		data.detail = (#plan.prune > 0 and (Model.plural(#plan.prune, "missing registration") .. " can be pruned below; that deletes no checkout. ") or "")
			.. "Clean Up lists the other places worth reviewing."
		data.amount, data.amountCaption = Model.size(0), "could recover"
		data.actionTitle, data.action, data.disabled = "Open Clean Up", "cleanup", false
	end
	return data
end

function Controller:show()
	local refs = self.refs
	if not refs then return end
	self:publish()
	local plan = Worktrees.plan(self.rows)
	local visible = {}
	for _, row in ipairs(self:visibleRows()) do visible[row.id] = true end
	local function only(rows)
		local result = {}
		for _, row in ipairs(rows) do if visible[row.id] then table.insert(result, row) end end
		return result
	end
	-- Locked and kept worktrees are decisions already made: they join the
	-- review list, after the ones that still need a person.
	local review = only(plan.review)
	local repositories = {}
	for _, row in ipairs(plan.protected) do
		if row.state == "primary" then table.insert(repositories, row) elseif visible[row.id] then table.insert(review, row) end
	end
	repositories = only(repositories)
	local remove, missing = only(plan.removal), only(plan.prune)
	self.lists = {removeList = remove, reviewList = review, missingList = missing, repositoryList = repositories}
	refs.removeList:replaceRows(remove)
	refs.reviewList:replaceRows(review)
	refs.missingList:replaceRows(missing)
	refs.repositoryList:replaceRows(repositories)
	local linked = #plan.removal + #plan.review + #plan.prune + #plan.protected - #repositories
	local none = self.loaded == true and linked == 0
	refs.worktreesEmpty.hidden = not none
	refs.removeSection.hidden = #remove == 0
	refs.reviewSection.hidden = #review == 0
	refs.missingSection.hidden = #missing == 0
	refs.repositories.hidden = #repositories == 0
	refs.selectionSection.hidden = self.selected == nil
	if self.loading then
		refs.summary.text = "Looking for Git worktrees…"
	else
		local stored = 0
		for _, row in ipairs(self.rows) do if row.state ~= "primary" then stored = stored + row.bytes end end
		refs.summary.text = self.error or ((self.busy and "Working · " or "") .. Model.plural(linked, "linked worktree") .. " in "
			.. Model.plural(self.repositories or 0, "repository") .. " · " .. Model.size(stored) .. " stored")
	end
	refs.removeDetail.text = "Clean, every commit published, and unchanged for " .. Model.plural(Worktrees.recentDays, "day")
		.. ". Source " .. Model.size(plan.sourceBytes) .. ", generated output " .. Model.size(plan.generatedBytes) .. ", Git record " .. Model.size(plan.gitBytes) .. "."
	refs.status.text = self.result or ""
	self.selected = nil
	refs.selectedDetail.text = self:detail(nil)
	self:buttons()
end

function Controller:buttons()
	local refs = self.refs
	if not refs then return end
	local plan = Worktrees.plan(self.rows)
	local row = self.selected
	refs.selectionSection.hidden = row == nil
	local idle = not self.busy and not self.loading
	self.decisionActions = self.decisionActions or {
		review = function() self:review() end,
		cleanup = function() if self.showPage then self.showPage("cleanup") end end,
	}
	self.decisionRefs = self:decision("decisionHost", self:decisionData(plan))
	refs.prune.enabled = idle and #plan.prune > 0
	refs.reveal.enabled = idle and row ~= nil and row.state ~= "missing"
	refs.keep.enabled = idle and row ~= nil and row.state ~= "primary"
	refs.keep.title = row and self:isKept(row.path) and "Remove Keep" or "Keep"
	refs.openOwner.enabled = idle and row ~= nil and row.manager ~= nil
	refs.openOwner.title = row and row.manager and ("Open " .. row.manager .. "…") or "Open Owner…"
	refs.retry.enabled = idle
	if refs.selectedDetail then
		refs.selectedTitle.text = row and (row.name .. " · " .. (row.branch or "Detached HEAD")) or ""
		refs.selectedTitle.toolTip = refs.selectedTitle.text
		refs.selectedSummary.text = row and table.concat(row.reasons, " ") or ""
		refs.selectedDetail.text = self:detail(row)
	end
end

function Controller:openOwner()
	if not self.selected or not self.selected.manager then return false end
	local ok, message = self.service.openOwner(self.selected.manager:lower())
	if ok == false and self.refs then self.refs.status.text = message end
	return ok
end

function Controller:toggleKeep()
	local row = self.selected
	if not row or row.state == "primary" then return end
	local key = keepKey(row.path)
	self.model.kept[key] = not self.model.kept[key] or nil
	if self.service.saveKeep then self.service.saveKeep(self.model.kept) end
	self.rows = self:buildRows()
	self:show()
end

-- A load belongs to the inventory, not to one visit of the page: the root
-- starts it when a scan finishes, often before the page mounts, and it may
-- finish after the page was left or mounted again. Only a newer load
-- supersedes it; the page shows the result whenever it is open.
function Controller:load()
	if self.busy or self.loading then self:show(); return end
	self.loading, self.error, self.progress = not self.loaded, nil, nil
	self.busy = true
	self.loadToken = (self.loadToken or 0) + 1
	local token = self.loadToken
	self:show()
	if type(self.service.worktreeScan) ~= "function" then
		self.busy, self.loading, self.loaded = false, false, true
		self.rows = {}; self:show(); return
	end
	local roots = Catalog.projectRoots(self.model.home, self.model.projectRoots, false)
	self.service.worktreeScan(roots, function(entries, facts)
		if token ~= self.loadToken then return end
		self.busy, self.loading, self.loaded, self.progress = false, false, true, nil
		self.entries, self.facts = entries or {}, facts or {}
		local repositories = {}
		for _, entry in ipairs(self.entries) do if entry.commonDir then repositories[entry.commonDir] = true end end
		local count = 0
		for _ in pairs(repositories) do count = count + 1 end
		self.repositories = count
		self.rows = self:buildRows()
		self:publish()
		self:show()
		if self.published then self.published() end
	end, function(done, total)
		-- Discovery reads several facts per worktree; say how far it is.
		if token ~= self.loadToken then return end
		self.progress = total == 0 and "No linked worktrees found yet." or ("Reading the evidence for " .. Model.plural(total, "worktree") .. ": " .. done .. " done.")
		if self.loading then self:buttons() end
	end)
end

-- One confirmation for the whole removal set, then each worktree is read
-- again from Git and revalidated just before its own removal. A refused or
-- failed worktree is reported and the rest continue; nothing is forced.
function Controller:review()
	if self.busy then return false end
	local plan = Worktrees.plan(self.rows)
	if not plan.ready then return false end
	if not self.service.confirmAction("Remove leftover worktrees", Worktrees.confirmation(plan)) then return false end
	self.busy, self.result = true, "Removing…"
	local freeBefore = Outcome.free(self.service, self.model.home)
	self:show()
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
				if self.log then self.log("git worktree remove " .. row.path, success, row.bytes, row.name, not success and output or nil) end
				done(success, output)
			end)
		end,
	}, function(result)
		self.busy = false
		self.result = Batch.report(result, "Removed", "worktree")
			.. ". The repositories and every other worktree were left as they were; removed worktrees are deleted at once, not moved to the Trash. "
			.. Outcome.freeText(freeBefore, Outcome.free(self.service, self.model.home), result.removed > 0) .. "."
		if self.changed then self.changed() end
		self:load()
	end)
	return true
end

-- Missing registrations are forgotten in their own review: pruning removes
-- Git's record only, never a checkout.
function Controller:prune()
	if self.busy then return false end
	local plan = Worktrees.plan(self.rows)
	if #plan.prune == 0 then return false end
	local names, repositories = {}, {}
	for _, row in ipairs(plan.prune) do
		table.insert(names, row.name .. " · " .. row.path)
		repositories[row.repository] = Worktrees.pruneCommand(row)
	end
	if not self.service.confirmAction("Prune missing worktrees", "Forget " .. Model.plural(#plan.prune, "registration") .. " whose directory no longer exists?\n\n"
		.. table.concat(names, "\n") .. "\n\nThis removes Git's record only. No checkout is deleted.") then return false end
	self.busy, self.result = true, "Pruning…"
	self:show()
	local commands = {}
	for _, command in pairs(repositories) do table.insert(commands, command) end
	local failed = 0
	local function step(index)
		if index > #commands then
			self.busy = false
			self.result = failed == 0 and ("Pruned " .. Model.plural(#plan.prune, "registration") .. ". No checkout was deleted.") or ("Prune failed for " .. failed .. " repositories.")
			self:load(); return
		end
		self.service.command(commands[index], function(ok) if not ok then failed = failed + 1 end; step(index + 1) end)
	end
	step(1)
	return true
end

-- Leaving the page never cancels a load or a removal in progress.
function Controller:dispose()
	self.selected = nil
	Page.dispose(self)
end

return Controller
