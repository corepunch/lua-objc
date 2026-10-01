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
		openOwner = function() if self.selected and self.selected.manager then self.service.openOwner(self.selected.manager:lower()) end end,
		review = function() self:review() end,
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
	local parts = {table.concat(row.reasons, " ")}
	for _, warning in ipairs(row.warnings or {}) do table.insert(parts, warning) end
	if row.worktreeBytes then
		table.insert(parts, "Source " .. Model.size(row.sourceBytes) .. " · generated output " .. Model.size(row.generatedBytes or 0)
			.. " · Git record " .. Model.size(row.gitBytes or 0) .. ". The repository's shared history is not counted here.")
	end
	if row.manager then table.insert(parts, row.manager .. " manages this location; archiving it there keeps its session list tidy.") end
	return table.concat(parts, " ")
end

function Controller:show()
	local refs = self.refs
	if not refs then return end
	self:publish()
	local plan = Worktrees.plan(self.rows)
	local rows = self:visibleRows()
	refs.worktrees:replaceRows(rows)
	local none = self.loaded == true and #self.rows == 0
	refs.worktreesPanel.hidden = none
	refs.worktreesEmpty.hidden = not none
	if self.loading then
		for _, tile in ipairs({"removeTile", "reviewTile", "pruneTile"}) do refs[tile .. "Value"].text = "—"; refs[tile .. "Detail"].text = "Reading…" end
		refs.summary.text = "Looking for Git worktrees…"
	else
		refs.removeTileValue.text = Model.size(plan.removalBytes)
		refs.removeTileDetail.text = Model.plural(#plan.removal, "worktree") .. " · source " .. Model.size(plan.sourceBytes)
			.. ", generated " .. Model.size(plan.generatedBytes) .. ", Git " .. Model.size(plan.gitBytes)
		refs.reviewTileValue.text = Model.size(plan.reviewBytes)
		refs.reviewTileDetail.text = Model.plural(#plan.review, "worktree") .. " with changes, unpublished commits, submodules or recent use"
		refs.pruneTileValue.text = tostring(#plan.prune)
		refs.pruneTileDetail.text = #plan.prune == 0 and "No missing registrations" or "Registered, but the directory is gone"
		refs.summary.text = self.error or ((self.busy and "Working · " or "") .. Model.plural(#self.rows, "worktree") .. " in "
			.. Model.plural(self.repositories or 0, "repository") .. " · " .. Model.size(plan.removalBytes) .. " can be removed")
	end
	refs.worktreesDetail.text = Model.plural(#rows, "worktree") .. (self.query ~= "" and " matching the search" or "")
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
	local idle = not self.busy and not self.loading
	refs.review.enabled = idle and plan.ready
	refs.review.title = plan.ready and ("Review and Remove " .. Model.plural(#plan.removal, "Worktree") .. "…") or "Review and Remove…"
	refs.prune.enabled = idle and #plan.prune > 0
	refs.reveal.enabled = idle and row ~= nil and row.state ~= "missing"
	refs.keep.enabled = idle and row ~= nil and row.state ~= "primary"
	refs.keep.title = row and self:isKept(row.path) and "Remove Keep" or "Keep"
	refs.openOwner.enabled = idle and row ~= nil and row.manager ~= nil
	refs.openOwner.title = row and row.manager and ("Open " .. row.manager .. "…") or "Open Owner…"
	refs.retry.enabled = idle
	if refs.selectedDetail then refs.selectedDetail.text = self:detail(row) end
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

function Controller:load()
	if self.busy or self.loading then return end
	self.loading, self.error = not self.loaded, nil
	self.busy = true
	self:show()
	local generation = self.generation
	if type(self.service.worktreeScan) ~= "function" then
		self.busy, self.loading, self.loaded = false, false, true
		self.rows = {}; self:show(); return
	end
	local roots = Catalog.projectRoots(self.model.home, self.model.projectRoots, false)
	self.service.worktreeScan(roots, function(entries, facts)
		if generation ~= self.generation and self.refs then return end
		self.busy, self.loading, self.loaded = false, false, true
		self.entries, self.facts = entries or {}, facts or {}
		local repositories = {}
		for _, entry in ipairs(self.entries) do if entry.commonDir then repositories[entry.commonDir] = true end end
		local count = 0
		for _ in pairs(repositories) do count = count + 1 end
		self.repositories = count
		self.rows = self:buildRows()
		self:show()
		if self.published then self.published() end
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
	local generation = self.generation
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
		if generation == self.generation or not self.refs then self.loaded = true; self:load() end
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

function Controller:dispose()
	self.busy, self.selected = false, nil
	Page.dispose(self)
end

return Controller
