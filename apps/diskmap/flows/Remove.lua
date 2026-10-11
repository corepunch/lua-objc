local Model = require("data.model")
local Flow = require("data.flow")
local Batch = require("apps.diskmap.helpers.Batch")
local Verify = require("apps.diskmap.helpers.Verify")
local Format = require("apps.diskmap.helpers.Format")
local Simulators = require("apps.diskmap.helpers.Simulators")
local Worktrees = require("apps.diskmap.helpers.Worktrees")
local Paths = require("apps.diskmap.helpers.Paths")
local Verdict = require("apps.diskmap.helpers.Verdict")
local Keeps = require("apps.diskmap.models.Keeps")
local Remove = Flow:extend()

-- Removing: one confirmation that names every item and what happens to
-- it, then each item is checked again just before it goes
-- (helpers/Verify.lua): a folder to the Trash, a simulator through simctl,
-- a worktree through git. Every action is logged (Action History), the
-- model is updated without measuring again, and the result is said on the
-- page. A flow (lua/data/flow.lua) over a page: `self:flow("Remove"):rows({row})`.

Remove.verbs = {trash = "Move to Trash", erase = "Erase", delete = "Delete", runtimeDelete = "Delete Runtime",
	worktreeRemove = "Remove Worktree", worktreePrune = "Prune"}

-- Whether Diskmap can act on a row, and why not.
function Remove.allowed(row)
	if not row or not row.path then return false, "Nothing selected." end
	if row.state ~= "measured" and row.action ~= "worktreePrune" then return false, "It was not measured." end
	if Keeps:contains(row.id) then return false, "It is marked Keep." end
	if not Verdict.removable(row.verdict) then return false, Verdict.styles[row.verdict].label .. ": " .. (row.reason or "") end
	if (row.action or "none") == "none" then return false, row.admin and "Finder needs an administrator to move it; use Show in Finder." or (row.reason or "Its owner removes it.") end
	if row.action == "trash" then
		local ok, why = Paths.validate(row.path, Model.db.home)
		if not ok then return false, why end
	end
	return true
end

-- The confirmation for `rows`: each with its verb and size, then what the
-- verbs mean.
function Remove.confirmation(rows)
	local lines, counts, bytes = {}, {}, 0
	for index, row in ipairs(rows) do
		local action = row.action or "trash"
		counts[action] = (counts[action] or 0) + 1
		bytes = bytes + (row.bytes or 0)
		if index <= 12 then table.insert(lines, "· " .. row.name .. " (" .. Format.size(row.bytes) .. ") · " .. Remove.verbs[action]) end
	end
	if #rows > 12 then table.insert(lines, "· and " .. (#rows - 12) .. " more") end
	local notes = {}
	if counts.trash then table.insert(notes, "Folders move to the Trash; you can put them back in Finder until you empty it.") end
	if counts.erase or counts.delete or counts.runtimeDelete then table.insert(notes, "Simulator changes go through simctl and cannot be undone.") end
	if counts.worktreeRemove or counts.worktreePrune then table.insert(notes, "Worktrees are removed with git worktree remove; the repository and its history stay.") end
	local title = #rows == 1 and Remove.verbs[rows[1].action or "trash"] or ("Remove " .. Format.plural(#rows, "Item"))
	return title, table.concat(lines, "\n") .. "\n\n" .. Format.size(bytes) .. " in all. Each item is checked again just before it goes. " .. table.concat(notes, " ")
end

-- Checks and performs one row; `done(ok, message, skipped, kept)`.
function Remove:perform(row, probes, done)
	local service = self.app.service
	local action = row.action or "trash"
	if action == "trash" then
		local allowed, why = Verify.check(row, Model.db.home, probes)
		if not allowed then done(false, why.reason, true); return end
		local ok, moved, detail = pcall(service.trash, row.path)
		done(ok and moved == true, ok and detail or tostring(moved))
		return
	end
	if action == "erase" or action == "delete" then
		service.simulatorDevices(function(listed)
			local fresh = listed and Simulators.refresh(row, listed)
			if listed and not fresh and action == "delete" then fresh = row end
			if not fresh then done(false, "simctl no longer lists it", true); return end
			local argv, refusal = Simulators.command(action, fresh)
			if not argv then done(false, refusal.message, true); return end
			service.command(argv, function(ok, output) done(ok, output, false, action == "erase") end)
		end)
		return
	end
	if action == "runtimeDelete" then
		local argv, refusal = Simulators.command(action, row)
		if not argv then done(false, refusal.message, true); return end
		service.command(argv, done)
		return
	end
	if action == "worktreeRemove" or action == "worktreePrune" then
		service.worktreeState(row, function(entry, facts)
			if action == "worktreePrune" then
				if not entry then done(false, "Git no longer lists it", true); return end
				service.command(Worktrees.pruneCommand({prune = true, repository = row.repository}), done)
				return
			end
			local fresh = {state = "candidate", repository = row.repository, path = row.path}
			local ok, refusal = Worktrees.revalidate(fresh, entry, facts, {now = os.time()})
			if not ok then done(false, refusal.message, true); return end
			service.command(Worktrees.removeCommand(fresh), done)
		end)
		return
	end
	done(false, "its owner must remove it", true)
end

-- Removes `rows` after one confirmation. Returns whether anything ran; the
-- result is left in `Model.db.notice` for the page to show.
function Remove:rows(rows)
	local list, refused = {}, {}
	for _, row in ipairs(rows) do
		local ok, why = Remove.allowed(row)
		if ok then table.insert(list, row) else table.insert(refused, (row.name or row.path or "?") .. ": " .. tostring(why)) end
	end
	if #list == 0 then
		if #refused > 0 then self.app.service.showError("Nothing to remove", table.concat(refused, "\n")) end
		return false
	end
	local title, message = Remove.confirmation(list)
	if not self.app.service.confirmAction(title, message) then return false end
	local service, home = self.app.service, Model.db.home
	local before = service.diskSpace(home)
	local probes = service.cleanupProbes()
	local result = {moved = 0, movedBytes = 0, skipped = {}}
	Batch.run(list, {
		label = function(row) return row.name end, bytes = function(row) return row.bytes or 0 end,
		validate = function() return true end,
		execute = function(row, nextItem)
			self:perform(row, probes, function(ok, detail, skipped, kept)
				local verb = Remove.verbs[row.action or "trash"]
				self.app.log(verb, ok, row.bytes, row.path, detail)
				if ok then
					result.moved, result.movedBytes = result.moved + 1, result.movedBytes + (row.bytes or 0)
					if kept then self.app.resized(row.path, 0) else self.app.removed(row.path, row.bytes) end
				elseif skipped then
					table.insert(result.skipped, detail)
				else
					table.insert(result.skipped, "it could not be removed (" .. tostring(detail or "unknown error"):gsub("\n.*", "") .. ")")
				end
				nextItem(true)
			end)
		end,
	}, function() end)
	local after = service.diskSpace(home)
	result.freeBefore = before and before.freeKb and before.freeKb * 1024 or nil
	result.freeNow = after and after.freeKb and after.freeKb * 1024 or nil
	Model.db.notice = Verify.summary(result)
	self.app.refresh()
	return true
end

return Remove
