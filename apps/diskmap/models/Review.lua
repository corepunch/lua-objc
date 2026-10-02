local SheetPage = require("apps.diskmap.SheetPage")
local Selection = require("apps.diskmap.models.Selection")
local Model = require("apps.diskmap.Model")
local Basket = require("apps.diskmap.models.Basket")
local Cleanup = require("apps.diskmap.models.Cleanup")
local OperationLog = require("apps.diskmap.models.OperationLog")
local Verify = require("apps.diskmap.models.Verify")

-- The cleanup basket and its review sheet. Pages mark items through
-- `toggle`; nothing touches the disk until the sheet's Move to Trash, which
-- revalidates each item, moves it, logs it, and then offers to empty the
-- Trash so the freed space can be measured rather than assumed. The sheet is
-- drawn from `data()` (views/Review.etlua); the app hears of marks through
-- `services.basketChanged`, of remeasuring through `services.rescan`.
local Review = SheetPage.define({id = "review", view = "Review", width = 620, height = 560})

function Review.new(_, services)
	return setmetatable({services = services, storage = services.model, service = services.service,
		basket = Basket.new(services.model.home), results = {}, done = {}}, Review)
end

function Review:log(action, ok, bytes, target, detail)
	if type(self.service.logOperation) ~= "function" then return end
	self.service.logOperation(OperationLog.format({action = action, ok = ok, bytes = bytes, target = target, detail = detail}))
end

function Review:isMarked(path) return path ~= nil and self.basket:contains(path) end
function Review:covering(path) return self.basket:covering(path) end
function Review:summary() return self.basket:summary() end
function Review:count() return self.basket:count() end

-- Identity and basket validation are identical for individual and bulk
-- staging. Only the caller publishes, so a bulk click refreshes UI once.
local function add(self, item)
	local valid, why = Basket.validate(item.path, self.storage.home)
	if not valid then return false, why end
	local identity = rawget(self.service, "fileIdentity")
	if type(identity) == "function" and not item.identity then item.identity = identity(item.path) end
	local ok, reason = self.basket:add(item)
	if ok then
		self.results[item.path] = nil
		self.done[item.path] = nil
	end
	return ok, reason
end

-- Marks or unmarks an item {path, name, bytes, consequence, source,
-- resourceId}. Returns marked state and a refusal message.
function Review:toggle(item)
	if type(item) ~= "table" or not item.path then return false, "Nothing selected." end
	if self.basket:contains(item.path) then
		self.basket:remove(item.path)
		self.services.basketChanged()
		return false
	end
	local ok, reason = add(self, item)
	self.services.basketChanged()
	return ok, reason
end

function Review:markAll(items)
	local count = 0
	for _, item in ipairs(items) do
		if type(item) == "table" and item.path and not self:covering(item.path) and add(self, item) then count = count + 1 end
	end
	if count > 0 then self.services.basketChanged() end
	return count
end

-- The sheet opens on `path`'s item, or on the first.
function Review:open(parent, path)
	self.done, self.status, self.movedBytes = {}, nil, nil
	self.selectedPath = path or (self.basket.order[1])
	SheetPage.open(self, parent)
end

function Review:data()
	local rows, bytes = self.basket:rows()
	for _, row in ipairs(rows) do row.result = self.results[row.path] or "" end
	for path, result in pairs(self.done) do
		table.insert(rows, {id = path, path = path, name = path:match("([^/]+)$"), subtitle = path, size = "", result = result})
	end
	self.rows, self.selected = rows, nil
	for _, row in ipairs(rows) do
		if row.path == self.selectedPath then self.selected = row end
	end
	if not self.selected then self.selectedPath = nil end
	local selected, pending, busy = self.selected, self.basket:count(), self.busy == true
	return {
		-- Measuring again shows one progress state in place of the list.
		lists = {items = busy and {} or rows}, loading = {items = busy},
		texts = {
			reviewSummary = self.status or (pending == 0 and "Nothing marked. Use Mark for Cleanup on any page."
				or (pending .. (pending == 1 and " item · " or " items · ") .. Model.size(bytes) .. " on disk")),
			selectedPath = selected and selected.path or "",
			consequence = selected and (selected.consequence or "This item has already left the cleanup basket.") or "",
			selectedResult = selected and selected.result or "",
		},
		hidden = {selectedDetails = selected == nil, emptyTrash = (self.movedBytes or 0) <= 0},
		disabled = {remove = busy or not (selected and self.basket:contains(selected.path)),
			trash = busy or pending == 0, clear = busy or pending == 0},
	}
end

-- After a draw the native selection follows the selected row.
function Review:sync(refs)
	Selection.show(refs.items, self.rows, self.selectedPath)
end

function Review:select(_, _, row) self.selectedPath = row and row.path end

function Review:remove()
	if self.selected then self.basket:remove(self.selected.path) end
	self.services.basketChanged()
end

function Review:clear()
	self.basket:clear()
	self.services.basketChanged()
end

function Review:history()
	self:close()
	self.services.openHistory()
end

-- Moves every marked item to the Trash. Sizes are measured again first,
-- because a mark can be hours old, and each item is checked again just
-- before it moves (models/Verify.lua): an item whose app is running, whose
-- proof is gone or that was replaced is skipped with its reason. Results
-- are reported per item and summarised; nothing is rolled back or retried.
function Review:trash()
	if self.basket:count() == 0 or self.busy then return false end
	local paths = {table.unpack(self.basket.order)}
	local measure = rawget(self.service, "measure")
	if type(measure) ~= "function" then return self:moveAll(paths) end
	self.busy = true
	self.status = "Measuring marked items again…"; self:draw()
	local finished
	measure(paths, function(sizes)
		self.busy = false
		for index, path in ipairs(paths) do
			local item = self.basket.items[path]
			if item and sizes and sizes[index] and sizes[index] > 0 then item.bytes = sizes[index] end
		end
		self.status = nil
		finished = self:moveAll(paths)
	end)
	return finished ~= false
end

function Review:probes()
	local probes = rawget(self.service, "cleanupProbes")
	return type(probes) == "function" and probes() or {}
end

function Review:moveAll(paths)
	local rows, bytes = self.basket:rows()
	if #rows == 0 then return false end
	local names = {}
	for index, row in ipairs(rows) do if index <= 12 then table.insert(names, "· " .. row.name .. " (" .. row.size .. ")") end end
	if #rows > 12 then table.insert(names, "· and " .. (#rows - 12) .. " more") end
	if not self.service.confirmAction("Move to Trash", table.concat(names, "\n") .. "\n\n" .. Model.size(bytes)
		.. " moves to the Trash. You can put items back from the Trash in Finder until you empty it.") then self:draw(); return false end
	self.busy = true
	local home = self.storage.home
	local before = self.service.diskSpace(home)
	local probes = self:probes()
	local result = {moved = 0, movedBytes = 0, skipped = {}}
	for _, path in ipairs(paths) do
		local item = self.basket.items[path]
		if item then
			local resource = item.resourceId and self.storage.resources:find(item.resourceId)
			local ok, message
			local allowed, why = Verify.check(item, resource, home, probes)
			if not allowed then
				ok, message = false, "Skipped: " .. why.reason
				table.insert(result.skipped, why.reason)
			elseif item.resourceId then
				local done, err = Cleanup.moveToTrash(self.storage, item.resourceId, self.service)
				ok, message = done, err and err.message
			else
				local pcallOk, moved, detail = pcall(self.service.trash, path)
				ok, message = pcallOk and moved == true, pcallOk and detail or tostring(moved)
			end
			self:log("Move to Trash", ok, item.bytes, path, message)
			if ok then
				result.moved, result.movedBytes = result.moved + 1, result.movedBytes + (item.bytes or 0)
				self.done[path] = "Moved to Trash"
				self.basket:remove(path)
			else
				if allowed then table.insert(result.skipped, "it could not be moved (" .. tostring(message or "unknown error") .. ")") end
				self.results[path] = allowed and ("Failed: " .. tostring(message or "unknown error")) or "Skipped"
			end
		end
	end
	local after = self.service.diskSpace(home)
	result.freeBefore = before and before.freeKb and before.freeKb * 1024 or nil
	result.freeNow = after and after.freeKb and after.freeKb * 1024 or nil
	self.busy = false
	self.movedBytes = (self.movedBytes or 0) + result.movedBytes
	self.lastResult = result
	self.status = Verify.summary(result)
	self.services.basketChanged()
	self.services.rescan()
	self:draw()
	return true
end

-- Empties the Trash through Finder and reports the change in free space
-- macOS observes, which can differ from the moved size (snapshots keep
-- blocks; other apps write meanwhile).
function Review:emptyTrash()
	if not self.service.emptyTrash or not self.service.confirmAction("Empty Trash",
		"Permanently removes everything in the Trash, including items you moved there before. This cannot be undone.") then return false end
	local home = self.storage.home
	local before = self.service.diskSpace(home)
	local ok = self.service.emptyTrash()
	local after = self.service.diskSpace(home)
	local freed = before and after and (after.freeKb - before.freeKb) * 1024 or nil
	self:log("Empty Trash", ok == true, freed and math.max(0, freed) or 0, "~/.Trash")
	self.movedBytes = nil
	if ok and freed and freed > 0 then
		self.status = "Emptied the Trash. macOS now reports " .. Model.size(freed) .. " more free space."
	elseif ok then
		self.status = "Emptied the Trash. Free space has not changed yet; local snapshots may still hold the blocks."
	else
		self.status = "The Trash could not be emptied."
	end
	self.services.rescan()
	self:draw()
	return ok
end

return Review
