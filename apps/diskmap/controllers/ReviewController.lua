local ns = require("AppKit")
local Sheet = require("apps.diskmap.Sheet")
local xml = require("ui.xml")
local Model = require("apps.diskmap.Model")
local Basket = require("apps.diskmap.models.Basket")
local Cleanup = require("apps.diskmap.models.Cleanup")
local OperationLog = require("apps.diskmap.models.OperationLog")
local Controller = {}; Controller.__index = Controller

-- Owns the cleanup basket and its review sheet. Pages mark items through
-- `toggle`; nothing touches the disk until the sheet's Move to Trash, which
-- revalidates each item, moves it, logs it, and then offers to empty the
-- Trash so the freed space can be measured rather than assumed.
-- `changed()` refreshes pages after marks; `rescan()` remeasures after
-- actions; `history(parent)` opens the action log.
function Controller.new(model, service, handlers)
	return setmetatable({model = model, service = service, basket = Basket.new(model.home), handlers = handlers,
		results = {}}, Controller)
end

function Controller:log(action, ok, bytes, target, detail)
	if type(self.service.logOperation) ~= "function" then return end
	self.service.logOperation(OperationLog.format({action = action, ok = ok, bytes = bytes, target = target, detail = detail}))
end

function Controller:isMarked(path) return path ~= nil and self.basket:contains(path) end

-- Marks or unmarks an item {path, name, bytes, consequence, source,
-- resourceId}. Returns marked state and a refusal message.
function Controller:toggle(item)
	if not item or not item.path then return false, "Nothing selected." end
	if self.basket:contains(item.path) then
		self.basket:remove(item.path)
		self.handlers.changed()
		return false
	end
	local ok, reason = self.basket:add(item)
	if ok then self.results[item.path] = nil end
	self.handlers.changed()
	return ok, reason
end

function Controller:summary() return self.basket:summary() end
function Controller:count() return self.basket:count() end

function Controller:show()
	if not self.refs then return end
	local rows, bytes = self.basket:rows()
	for _, row in ipairs(rows) do row.result = self.results[row.path] or "" end
	for path, result in pairs(self.done or {}) do
		table.insert(rows, {id = path, path = path, name = path:match("([^/]+)$"), subtitle = path, size = "", result = result})
	end
	self.refs.items:replaceRows(rows)
	local pending = self.basket:count()
	self.refs.reviewSummary.text = self.status or (pending == 0 and "Nothing marked. Use Mark for Cleanup on any page."
		or (pending .. (pending == 1 and " item · " or " items · ") .. Model.size(bytes) .. " on disk"))
	self.refs.trash.enabled = pending > 0 and not self.busy
	self.refs.clear.enabled = pending > 0 and not self.busy
	self.refs.remove.enabled = false
	self.refs.emptyTrash.hidden = not self.movedBytes or self.movedBytes <= 0
	self.selected = nil
end

function Controller:open(parent)
	self:close()
	self.done, self.status, self.movedBytes = {}, nil, nil
	self.sheet, self.refs = Sheet.present(function()
		return xml.renderFile("apps/diskmap/views/Review.etlua", {summary = self:summary(), actions = {
			select = function(_, _, row) self.selected = row; if self.refs then self.refs.remove.enabled = row and self.basket:contains(row.path) or false end end,
			remove = function() if self.selected then self.basket:remove(self.selected.path); self.handlers.changed(); self:show() end end,
			clear = function() self.basket:clear(); self.handlers.changed(); self:show() end,
			trash = function() self:trash() end,
			emptyTrash = function() self:emptyTrash() end,
			history = function() self.handlers.history() end,
			close = function() self:close() end,
		}}, ns)
	end, parent)
	self:show()
end

function Controller:close()
	if self.sheet then ns.dismiss(self.sheet) end
	self.sheet, self.refs = nil, nil
end

-- Moves every marked item to the Trash, one at a time, checking each again
-- first: catalog resources through their cleanup constraints, discovered
-- folders through the basket's location rules and the service's symlink
-- check. Results are reported per item; nothing is rolled back or retried.
function Controller:trash()
	local rows, bytes = self.basket:rows()
	if #rows == 0 or self.busy then return false end
	local names = {}
	for index, row in ipairs(rows) do if index <= 12 then table.insert(names, "· " .. row.name .. " (" .. row.size .. ")") end end
	if #rows > 12 then table.insert(names, "· and " .. (#rows - 12) .. " more") end
	if not self.service.confirmAction("Move to Trash", table.concat(names, "\n") .. "\n\n" .. Model.size(bytes)
		.. " moves to the Trash. You can put items back from the Trash in Finder until you empty it.") then return false end
	self.busy = true
	local moved, failed = 0, 0
	for _, path in ipairs({table.unpack(self.basket.order)}) do
		local item = self.basket.items[path]
		local ok, message
		local valid, reason = Basket.validate(path, self.model.home)
		if not valid then
			ok, message = false, reason
		elseif item.resourceId then
			local done, err = Cleanup.moveToTrash(self.model, item.resourceId, self.service)
			ok, message = done, err and err.message
		else
			local pcallOk, result, detail = pcall(self.service.trash, path)
			ok, message = pcallOk and result == true, pcallOk and detail or tostring(result)
		end
		self:log("Move to Trash", ok, item.bytes, path, message)
		if ok then
			moved = moved + (item.bytes or 0)
			self.done[path] = "Moved to Trash"
			self.basket:remove(path)
		else
			failed = failed + 1
			self.results[path] = "Failed: " .. tostring(message or "unknown error")
		end
	end
	self.busy = false
	self.movedBytes = (self.movedBytes or 0) + moved
	self.status = "Moved " .. Model.size(moved) .. " to the Trash" .. (failed > 0 and (" · " .. failed .. " could not be moved") or "")
		.. ". Empty the Trash to free the space."
	self.handlers.changed()
	self.handlers.rescan()
	self:show()
	return true
end

-- Empties the Trash through Finder and reports the change in free space
-- macOS observes, which can differ from the moved size (snapshots keep
-- blocks; other apps write meanwhile).
function Controller:emptyTrash()
	if not self.service.emptyTrash or not self.service.confirmAction("Empty Trash",
		"Permanently removes everything in the Trash, including items you moved there before. This cannot be undone.") then return false end
	local before = self.service.diskSpace(self.model.home)
	local ok = self.service.emptyTrash()
	local after = self.service.diskSpace(self.model.home)
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
	self.handlers.rescan()
	self:show()
	return ok
end

return Controller
