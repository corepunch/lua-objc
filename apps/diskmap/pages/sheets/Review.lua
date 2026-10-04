local Model = require("data.model")
local Marks = require("apps.diskmap.models.Marks")
local Format = require("apps.diskmap.helpers.Format")
local Selection = require("apps.diskmap.helpers.Selection")
local SheetRoute = require("apps.diskmap.pages.SheetRoute")
local Batch = require("apps.diskmap.helpers.Batch")
local Verify = require("apps.diskmap.helpers.Verify")

-- Review presents the scan-owned basket; staging is flows/Basket.lua.
-- Nothing touches the disk until the sheet's Move to Trash, which
-- revalidates each item, moves it, logs it, and then offers to empty the
-- Trash so the freed space can be measured rather than assumed. The sheet is
-- drawn from `data()` (views/sheets/Review.etlua); the app hears of marks through
-- `app.basketChanged`; what moved or was emptied leaves the model through
-- `app.trashed` and `app.removed`, and the disk is not measured again.
local routes = {}

local Review = SheetRoute.extend({view = "sheets/Review", width = 620, height = 560})
routes.review = Review

function Review:init()
	self.service = self.app.service
	self.results, self.done = self.app.basket.results, self.app.basket.done
end

-- The sheet opens on `path`'s item, or on the first.
function Review:open(parent, path)
	self.app.basket.done = {}
	self.done, self.status, self.movedBytes = self.app.basket.done, nil, nil
	self.selectedPath = path or ((Marks:all()[1] or {}).path)
	SheetRoute.open(self, parent)
end

function Review:data()
	local rows, bytes = Marks:rows()
	for _, row in ipairs(rows) do row.result = self.results[row.path] or "" end
	for path, result in pairs(self.done) do
		table.insert(rows, {id = path, path = path, name = path:match("([^/]+)$"), subtitle = path, size = "", result = result})
	end
	self.rows, self.selected = rows, nil
	for _, row in ipairs(rows) do
		if row.path == self.selectedPath then self.selected = row end
	end
	if not self.selected then self.selectedPath = nil end
	local selected, pending, busy = self.selected, Marks:count(), self.busy == true
	return {
		-- Measuring again shows one progress state in place of the list.
		lists = {items = busy and {} or rows}, loading = {items = busy},
		texts = {
			reviewSummary = self.status or (pending == 0 and "Nothing marked. Use Mark for Cleanup on any page."
				or (pending .. (pending == 1 and " item · " or " items · ") .. Format.size(bytes) .. " on disk")),
			selectedPath = selected and selected.path or "",
			consequence = selected and (selected.consequence or "This item has already left the cleanup basket.") or "",
			selectedResult = selected and selected.result or "",
		},
		hidden = {selectedDetails = selected == nil, emptyTrash = (self.movedBytes or 0) <= 0},
		disabled = {remove = busy or not (selected and Marks:contains(selected.path)),
			trash = busy or pending == 0, clear = busy or pending == 0},
	}
end

-- After a draw the native selection follows the selected row.
function Review:sync(refs)
	Selection.show(refs.items, self.rows, self.selectedPath)
end

function Review:select(_, _, row) self.selectedPath = row and row.path end

function Review:remove()
	if self.selected then Marks:remove(self.selected.path) end
	self.app.basketChanged()
end

function Review:clear()
	self.app.basket.done = {}
	self.done, self.selectedPath = self.app.basket.done, nil
	Marks:clear()
	self.app.basketChanged()
end

function Review:history()
	self:close()
	self.app.openHistory()
end

-- Moves every marked item to the Trash. Nothing is measured again: an
-- item leaves the model with the size it was marked with. Each item is
-- checked again just before it moves (helpers/Verify.lua): an item whose app
-- is running, whose proof is gone or that was replaced is skipped with its
-- reason. Results are reported per item and summarised; nothing is rolled
-- back or retried.
function Review:trash()
	if Marks:count() == 0 or self.busy then return false end
	local paths = {}
	for _, mark in ipairs(Marks:all()) do table.insert(paths, mark.path) end
	return self:moveAll(paths)
end

function Review:probes()
	local probes = self.service.cleanupProbes
	return probes()
end

function Review:moveAll(paths)
	local rows, bytes = Marks:rows()
	if #rows == 0 then return false end
	local names = {}
	for index, row in ipairs(rows) do if index <= 12 then table.insert(names, "· " .. row.name .. " (" .. row.size .. ")") end end
	if #rows > 12 then table.insert(names, "· and " .. (#rows - 12) .. " more") end
	if not self.service.confirmAction("Move to Trash", table.concat(names, "\n") .. "\n\n" .. Format.size(bytes)
		.. " moves to the Trash. You can put items back from the Trash in Finder until you empty it.") then self:draw(); return false end
	self.busy = true
	local home = Model.db.home
	local before = self.service.diskSpace(home)
	local probes = self:probes()
	local result = {moved = 0, movedBytes = 0, skipped = {}}
	Batch.run(paths, {
		label = function(path) return path end, bytes = function() return 0 end,
		validate = function(path) return Marks:find(path) ~= nil end,
		execute = function(path, nextItem)
		local item = Marks:find(path)
		if item then
			local resource = item:location()
			local ok, message
			local allowed, why = Verify.check(item, resource, home, probes)
			if not allowed then
				ok, message = false, "Skipped: " .. why.reason
				table.insert(result.skipped, why.reason)
			elseif item.resourceId then
				local done, err = self:flow("Manage"):moveToTrash(item.resourceId)
				ok, message = done, err and err.message
			else
				local pcallOk, moved, detail = pcall(self.service.trash, path)
				ok, message = pcallOk and moved == true, pcallOk and detail or tostring(moved)
			end
			if not (allowed and item.resourceId) then self.app.log("Move to Trash", ok, item.bytes, path, message) end
			if ok then
				result.moved, result.movedBytes = result.moved + 1, result.movedBytes + (item.bytes or 0)
				self.done[path] = "Moved to Trash"
				Marks:remove(path)
				self.app.trashed(path, item.bytes)
			else
				if allowed then table.insert(result.skipped, "it could not be moved (" .. tostring(message or "unknown error") .. ")") end
				self.results[path] = allowed and ("Failed: " .. tostring(message or "unknown error")) or "Skipped"
			end
		end
			nextItem(true)
		end,
	}, function() end)
	local after = self.service.diskSpace(home)
	result.freeBefore = before and before.freeKb and before.freeKb * 1024 or nil
	result.freeNow = after and after.freeKb and after.freeKb * 1024 or nil
	self.busy = false
	self.movedBytes = (self.movedBytes or 0) + result.movedBytes
	self.lastResult = result
	self.status = Verify.summary(result)
	self.app.basketChanged()
	self:draw()
	return true
end

-- Empties the Trash through Finder and reports the change in free space
-- macOS observes, which can differ from the moved size (snapshots keep
-- blocks; other apps write meanwhile).
function Review:emptyTrash()
	local ok, status = self:flow("EmptyTrash"):run()
	if status then
		if ok then self.movedBytes = nil end
		self.status = status
		self:draw()
	end
	return ok
end

return routes
