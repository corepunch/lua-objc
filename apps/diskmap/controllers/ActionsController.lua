local Model = require("apps.diskmap.Model")
local Inspector = require("apps.diskmap.models.Inspector")
local Files = require("apps.diskmap.models.Files")
local InspectorController = require("apps.diskmap.controllers.InspectorController")
local Controller = {}; Controller.__index = Controller

-- Row menus for every list in Diskmap. A row's actions live in its "More"
-- button and its contextual menu instead of buttons under the list, so a
-- page can scroll as one surface and every list offers the same verbs in the
-- same order: the primary action, Finder, the owning category, Keep, Copy.
-- `handlers.open(id)` opens a category, `handlers.show(page)` a sidebar page,
-- `handlers.keep(id)` toggles Keep and `handlers.refresh()` remeasures.
-- `review` is the cleanup basket (ReviewController): "Mark for Cleanup"
-- adds a row to it, and nothing touches the disk until its review sheet.
function Controller.new(model, service, handlers, review)
	return setmetatable({model = model, service = service, handlers = handlers, review = review}, Controller)
end

function Controller:isMarked(path) return self.review ~= nil and self.review:isMarked(path) end

-- The Mark/Unmark item for an item {path, name, bytes, source, consequence,
-- resourceId}. A refusal (a system folder, a parent already marked) is
-- shown as an alert rather than failing silently.
function Controller:mark(item)
	if not self.review or not item or not item.path then return nil end
	local marked = self.review:isMarked(item.path)
	return {title = marked and "Unmark" or "Mark for Cleanup", systemImage = marked and "minus.circle" or "plus.circle",
		action = function()
			local _, reason = self.review:toggle(item)
			if reason and not marked then self.service.showError("Cannot mark for cleanup", reason) end
		end}
end

-- Marks every item in `items` that is not marked yet; returns how many.
function Controller:markAll(items)
	local count = 0
	for _, item in ipairs(items) do
		if self.review and not self.review:isMarked(item.path) and self.review:toggle(item) then count = count + 1 end
	end
	return count
end

-- Prepares rows for ResourceList: share bars relative to the largest row,
-- the row's own icon and color, and a checkmark for rows in the basket so
-- marked items are recognisable in every list.
function Controller:annotate(rows, icon, color)
	local largest = 0
	for _, row in ipairs(rows) do largest = math.max(largest, row.bytes or 0) end
	for _, row in ipairs(rows) do
		row.relative = largest > 0 and (row.bytes or 0) / largest or 0
		row.shareText = row.shareText or ""
		row.color = row.color or color
		row.icon = row.icon or icon
		if self:isMarked(row.path) then
			row.icon, row.color = "checkmark.circle.fill", "systemBlue"
			row.subtitle = "Marked for cleanup · " .. (row.subtitle or "")
		end
	end
	return rows
end

-- Only resources Diskmap has a verified Move to Trash recipe for can be
-- marked from a list; everything else is reviewed in its category.
function Controller:markableResource(row)
	return row ~= nil and row:isLeaf() and row.action == "trash" and row.path ~= nil and (row:validateTrash()) == true
end

local function separator() return {separator = true} end

function Controller:reveal(path)
	return {title = "Show in Finder", systemImage = "folder", action = function() self.service.reveal(path) end}
end

function Controller:copyPath(path)
	return {title = "Copy Path", systemImage = "doc.on.doc", action = function() self.service.copy(path) end}
end

-- A catalog resource (leaf or group).
function Controller:resource(id)
	local row = self.model.resources:find(id)
	if not row then return {} end
	local items = {}
	if not row:isLeaf() then
		table.insert(items, {title = "Open " .. row.name .. "…", systemImage = "list.bullet", action = function() self.handlers.open(id) end})
	else
		local detail = Inspector.details(self.model, id)
		if row.action ~= "finder" and detail then
			table.insert(items, {title = detail.manageTitle, disabled = not detail.canManage,
				action = function()
					if row.action == "simulators" or row.action == "sdks" then self.handlers.open(id); return end
					local inspector = InspectorController.new(self.model, self.service, self.handlers.refresh)
					inspector:select(id); inspector:manage()
				end})
		end
		if self:markableResource(row) then
			local measured = self.model.measurements[id]
			table.insert(items, self:mark({path = row.path, name = row.name, bytes = measured and measured.bytes, resourceId = id,
				source = (row:getParent() or row).name, consequence = row.consequence}))
		end
		if row.path then table.insert(items, self:reveal(row.path)) end
		local parent = row:getParent()
		if parent then
			table.insert(items, {title = "Open " .. parent.name .. "…", systemImage = "list.bullet", action = function() self.handlers.open(parent.id) end})
		end
	end
	table.insert(items, separator())
	table.insert(items, {title = self.model.kept[id] and "Stop Keeping" or "Keep", systemImage = "checkmark.shield",
		action = function() self.handlers.keep(id) end})
	if row.path then table.insert(items, self:copyPath(row.path)) end
	return items
end

-- An individual file from Large Files. Trash is offered only for ordinary
-- documents in the home folder; the menu says why otherwise.
function Controller:file(row)
	local ok, reason = Files.validateTrash(self.model, row.path)
	local items = {
		{title = ok and "Move to Trash…" or ("Move to Trash — " .. (reason and reason.message or "unavailable")), systemImage = "trash", disabled = not ok,
			action = function() self:trashFile(row) end},
	}
	if ok then table.insert(items, self:mark({path = row.path, name = row.name, bytes = row.bytes, source = "Large Files"})) end
	table.insert(items, self:reveal(row.path))
	if row.ownerId then
		local owner = self.model.resources:find(row.ownerId)
		table.insert(items, {title = "Open " .. (owner and owner.name or "Category") .. "…", systemImage = "list.bullet",
			action = function() self.handlers.open(row.ownerId) end})
	end
	table.insert(items, separator())
	table.insert(items, self:copyPath(row.path))
	return items
end

function Controller:trashFile(row)
	local ok, reason = Files.validateTrash(self.model, row.path)
	if not ok then self.service.showError("Cannot move to Trash", reason.message); return end
	if not self.service.confirmTrashPath("Move " .. row.name .. " to Trash?", row.path,
		Model.size(row.bytes) .. " · last used " .. (row.lastUse or "unknown"):lower() .. ". Moving to Trash does not free space until you empty it.") then return end
	local moved, message = self.service.trash(row.path)
	if not moved then self.service.showError("Could not move to Trash", message or "Check permissions."); return end
	self.handlers.refresh()
end

-- A folder that is not itself a catalog resource: an app's container, a
-- possible leftover, Xcode data or a project's build folder. `trash(row)`
-- performs a validated move when given; `mark` is the basket item for it.
function Controller:folder(row, trash, mark)
	local items = {}
	if trash then
		table.insert(items, {title = "Move to Trash…", systemImage = "trash", action = function() trash(row) end})
	end
	if mark then table.insert(items, self:mark(mark)) end
	table.insert(items, self:reveal(row.path))
	table.insert(items, separator())
	table.insert(items, self:copyPath(row.path))
	return items
end

-- An installed application: its bundle and the data folders it owns.
function Controller:application(row)
	local items = {self:reveal(row.path)}
	for index, folder in ipairs(row.folders or {}) do
		if index > 4 then break end
		table.insert(items, {title = "Show " .. folder.label .. " (" .. Model.size(folder.bytes) .. ")", systemImage = "folder",
			action = function() self.service.reveal(folder.path) end})
	end
	table.insert(items, separator())
	table.insert(items, {title = self.model.kept[row.resourceId] and "Stop Keeping" or "Keep", systemImage = "checkmark.shield",
		action = function() self.handlers.keep(row.resourceId) end})
	if row.bundleId then
		table.insert(items, {title = "Copy Bundle Identifier", systemImage = "doc.on.doc", action = function() self.service.copy(row.bundleId) end})
	end
	table.insert(items, self:copyPath(row.path))
	return items
end

return Controller
