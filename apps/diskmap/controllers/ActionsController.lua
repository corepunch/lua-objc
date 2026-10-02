local Model = require("apps.diskmap.Model")
local Destinations = require("apps.diskmap.models.Destinations")
local Inspector = require("apps.diskmap.models.Inspector")
local Files = require("apps.diskmap.models.Files")
local FolderTree = require("apps.diskmap.models.FolderTree")
local Manage = require("apps.diskmap.models.Manage")
local Controller = {}; Controller.__index = Controller

-- Row menus for every list in Diskmap. A row's actions live in its "More"
-- button and its contextual menu instead of buttons under the list, so a
-- page can scroll as one surface and every list offers the same verbs in the
-- same order: the primary action, Finder, the owning category, Keep, Copy.
-- `handlers.open(id)` opens a resource or category where Destinations sends
-- it, `handlers.show(page)` a sidebar page,
-- `handlers.keep(id)` toggles Keep, `handlers.watch(entry)` returns the
-- Watch/Stop Watching item for a resource or folder entry, and
-- `handlers.refresh()` remeasures.
-- `review` is the cleanup basket (models/Review.lua), set by the app once built: "Mark for Cleanup"
-- adds a row to it, and nothing touches the disk until its review sheet.
function Controller.new(model, service, handlers)
	return setmetatable({model = model, service = service, handlers = handlers}, Controller)
end

function Controller:isMarked(path) return self.review ~= nil and self.review:isMarked(path) end
function Controller:covering(path)
	if self.review then return self.review:covering(path) end
end
function Controller:isIncluded(path) return self:covering(path) ~= nil end

-- The Mark/Unmark item for an item {path, name, bytes, source, consequence,
-- resourceId}. A refusal (a system folder, a parent already marked) is
-- shown as an alert rather than failing silently.
function Controller:mark(item)
	if not self.review or not item or not item.path then return nil end
	local marked = self.review:isMarked(item.path)
	local parent, exact = self:covering(item.path)
	if parent and not exact then
		return {title = "Included through Marked Folder — Review…", systemImage = "folder.badge.checkmark",
			action = function() self.handlers.review(parent.path) end}
	end
	return {title = marked and "Unmark" or "Mark for Cleanup", systemImage = marked and "minus.circle" or "plus.circle",
		action = function()
			local _, reason = self.review:toggle(item)
			if reason and not marked then self.service.showError("Cannot mark for cleanup", reason) end
		end}
end

-- Marks every item in `items` that is not marked yet; returns how many.
function Controller:markAll(items)
	return self.review and self.review:markAll(items) or 0
end

-- Prepares rows for ResourceList: share bars relative to the largest row,
-- the row's own icon and color, and a checkmark for rows in the basket so
-- marked items are recognisable in every list.
function Controller:annotate(rows, icon, color)
	local largest = 0
	for _, row in ipairs(rows) do largest = math.max(largest, row.bytes or 0) end
	local presented = {}
	for _, source in ipairs(rows) do
		local row = setmetatable({}, getmetatable(source))
		for key, value in pairs(source) do row[key] = value end
		-- An unmeasured row has no fraction: its meter draws an empty,
		-- disabled bar under its state rather than a measured zero.
		if row.bytes == nil then row.relative = nil
		else row.relative = largest > 0 and row.bytes / largest or 0 end
		row.shareText = row.shareText or ""
		row.color = row.color or color
		row.icon = row.icon or icon
		if self:isMarked(row.path) then
			row.icon, row.color = "checkmark.circle.fill", "systemBlue"
			row.subtitle = "Marked for cleanup · " .. (row.subtitle or "")
		elseif self:isIncluded(row.path) then
			local parent = self:covering(row.path)
			row.icon, row.color = "folder.badge.checkmark", "systemBlue"
			row.subtitle = "Included through marked folder " .. (parent.name or parent.path) .. " · " .. (row.subtitle or "")
		end
		table.insert(presented, row)
	end
	return presented
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

-- Watch/Stop Watching; nil when the page was built without a watchlist.
function Controller:watch(entry)
	return self.handlers.watch and self.handlers.watch(entry) or nil
end

function Controller:copyPath(path)
	return {title = "Copy Path", systemImage = "doc.on.doc", action = function() self.service.copy(path) end}
end

-- Quick Look, as the Finder's Space bar: `paths` are the neighbours the
-- panel's arrow keys step through, starting at `path`. A provider without
-- Quick Look offers none.
function Controller:quickLookItem(path, paths)
	if type(rawget(self.service, "quickLook")) ~= "function" then return nil end
	return {title = "Quick Look", systemImage = "eye", action = function() self:quickLook(path, paths) end}
end

function Controller:quickLook(path, paths)
	if type(rawget(self.service, "quickLook")) ~= "function" or not path then return false end
	paths = paths and #paths > 0 and paths or {path}
	local index = 1
	for position, candidate in ipairs(paths) do if candidate == path then index = position; break end end
	self.service.quickLook(paths, index)
	return true
end

-- "Move to…": offloads a file or folder to another folder or disk, as
-- Nektony's Disk Space Analyzer and the Finder do. `validate(path)` is the
-- page's own policy for what may leave its place; `moved(destination)`
-- updates the page once the move finished. Nothing is ever replaced.
function Controller:moveItem(row, validate, moved)
	if type(rawget(self.service, "moveItem")) ~= "function" then return nil end
	local ok, reason = validate(row.path)
	return {title = ok and "Move to…" or ("Move to… — " .. tostring(reason)), systemImage = "folder.badge.plus", disabled = not ok,
		action = function() self:move(row, validate, moved) end}
end

function Controller:move(row, validate, moved)
	local ok, reason = validate(row.path)
	if not ok then self.service.showError("Cannot move " .. (row.name or "this item"), reason); return end
	local folder = self.service.pickFolder("Move “" .. (row.name or row.path) .. "” to")
	if not folder then return end
	local allowed, why = FolderTree.validateDestination(row.path, folder)
	if not allowed then self.service.showError("Cannot move " .. (row.name or "this item"), why); return end
	self.service.moveItem(row.path, folder, function(done, message, destination)
		if self.review then self.review:log("Move", done, row.bytes, row.path, done and destination or message) end
		if not done then self.service.showError("Could not move " .. (row.name or "this item"), message or "Check permissions."); return end
		if moved then moved(destination) end
	end)
end

-- Move to Trash for an item outside the catalog, checked by `validate`
-- first; `trashed()` updates the page.
function Controller:trashItem(row, validate, trashed)
	local ok, reason = validate(row.path)
	if not ok then self.service.showError("Cannot move to Trash", reason); return end
	if not self.service.confirmTrashPath("Move " .. (row.name or row.path) .. " to Trash?", row.path,
		Model.size(row.bytes) .. ". Moving to Trash does not free space until you empty it.") then return end
	local moved, message = self.service.trash(row.path)
	if self.review then self.review:log("Move to Trash", moved, row.bytes, row.path, message) end
	if not moved then self.service.showError("Could not move to Trash", message or "Check permissions."); return end
	if trashed then trashed() end
end

-- A file or folder on the Folder page. `handlers.open(row)` looks inside a
-- folder, `handlers.changed(path)` follows a move or Trash, and
-- `handlers.siblings` are the paths Quick Look steps through.
function Controller:item(row, handlers)
	local items = {}
	if row.directory then
		table.insert(items, {title = "Open", systemImage = "arrow.right.circle", action = function() handlers.open(row) end})
	end
	table.insert(items, self:quickLookItem(row.path, handlers.siblings))
	table.insert(items, self:reveal(row.path))
	table.insert(items, separator())
	local validate = function(path) return FolderTree.validateChange(self.model, path) end
	table.insert(items, self:moveItem(row, validate, function() handlers.changed(row.path) end))
	local ok, reason = validate(row.path)
	table.insert(items, {title = ok and "Move to Trash…" or ("Move to Trash — " .. tostring(reason)), systemImage = "trash", disabled = not ok,
		action = function() self:trashItem(row, validate, function() handlers.changed(row.path) end) end})
	if ok then table.insert(items, self:mark({path = row.path, name = row.name, bytes = row.bytes, source = "Folder"})) end
	table.insert(items, separator())
	if row.directory then table.insert(items, self:watch({kind = "folder", path = row.path, name = row.name})) end
	table.insert(items, self:copyPath(row.path))
	return items
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
					if Destinations.elsewhere(self.model, id) then self.handlers.open(id); return end
					local inspector = Manage.new(self.model, self.service, self.handlers.refresh)
					inspector:select(id); inspector:manage()
				end})
		end
		if self:markableResource(row) then
			local measured = self.model.measurements[id]
			table.insert(items, self:mark({path = row.path, name = row.name, bytes = measured and measured.bytes, resourceId = id,
				source = (row:getParent() or row).name, consequence = row.consequence}))
		end
		if row.path then
			table.insert(items, self:quickLookItem(row.path))
			table.insert(items, self:reveal(row.path))
		end
		local parent = row:getParent()
		if parent then
			table.insert(items, {title = "Open " .. parent.name .. "…", systemImage = "list.bullet", action = function() self.handlers.open(parent.id) end})
		end
	end
	table.insert(items, separator())
	table.insert(items, {title = self.model.kept[id] and "Stop Keeping" or "Keep", systemImage = "checkmark.shield",
		action = function() self.handlers.keep(id) end})
	table.insert(items, self:watch({kind = "resource", id = id}))
	if row.path then table.insert(items, self:copyPath(row.path)) end
	return items
end

-- An individual file from Large Files. Trash is offered only for ordinary
-- documents in the home folder; the menu says why otherwise.
function Controller:file(row, handlers)
	local ok, reason = Files.validateTrash(self.model, row.path)
	local items = {
		{title = ok and "Move to Trash…" or ("Move to Trash — " .. (reason and reason.message or "unavailable")), systemImage = "trash", disabled = not ok,
			action = function() self:trashFile(row) end},
	}
	if ok then table.insert(items, self:mark({path = row.path, name = row.name, bytes = row.bytes, source = "Large Files"})) end
	table.insert(items, self:moveItem(row, function(path)
		local allowed, why = Files.validateTrash(self.model, path)
		return allowed, why and why.message
	end, function() self.handlers.refresh() end))
	table.insert(items, self:quickLookItem(row.path, handlers and handlers.siblings))
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
	table.insert(items, self:quickLookItem(row.path))
	table.insert(items, self:reveal(row.path))
	table.insert(items, separator())
	-- Folders only: a single file's size is not worth a sidebar row.
	if row.directory ~= false then table.insert(items, self:watch({kind = "folder", path = row.path, name = row.name})) end
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
