local Model = require("data.model")
local Flow = require("data.flow")
local Provider = require("apps.diskmap.services.Provider")
local Locations = require("apps.diskmap.models.Locations")
local Format = require("apps.diskmap.helpers.Format")
local Files = require("apps.diskmap.models.Files")
local FolderTree = require("apps.diskmap.helpers.FolderTree")
local Manage = require("apps.diskmap.flows.Manage")
local Rows = Flow:extend()

-- Row menus for every list in Diskmap. A row's actions live in its "More"
-- button and its contextual menu instead of buttons under the list, so a
-- page can scroll as one surface and every list offers the same verbs in the
-- same order: the primary action, Finder, the owning category, Keep, Copy.
--
-- A flow (lua/data/flow.lua) over a page: `self:flow("Rows"):resource(id)`.
-- It acts through the app's services, `self.app`: `open(id)` opens a
-- resource where its location sends it, `keep(id)` toggles Keep,
-- `watchlist` watches, `rescan()` remeasures, `openReview(path)` shows the
-- marked items, and `review` is the review sheet: "Mark for Cleanup" adds a
-- row to the marks (models/Marks.lua), and nothing touches the disk until
-- that sheet.

function Rows:isMarked(path) return self.app.review ~= nil and self.app.review:isMarked(path) end
function Rows:covering(path)
	if self.app.review then return self.app.review:covering(path) end
end
function Rows:isIncluded(path) return self:covering(path) ~= nil end

-- The Mark/Unmark item for an item {path, name, bytes, source, consequence,
-- resourceId}. A refusal (a system folder, a parent already marked) is
-- shown as an alert rather than failing silently.
function Rows:mark(item)
	if not self.app.review or not item or not item.path then return nil end
	local marked = self.app.review:isMarked(item.path)
	local parent, exact = self:covering(item.path)
	if parent and not exact then
		return {title = "Included through Marked Folder — Review…", systemImage = "folder.badge.checkmark",
			action = function() self.app.openReview(parent.path) end}
	end
	return {title = marked and "Unmark" or "Mark for Cleanup", systemImage = marked and "minus.circle" or "plus.circle",
		action = function()
			local _, reason = self.app.review:toggle(item)
			if reason and not marked then self.app.service.showError("Cannot mark for cleanup", reason) end
		end}
end

-- Marks every item in `items` that is not marked yet; returns how many.
function Rows:markAll(items)
	return self.app.review and self.app.review:markAll(items) or 0
end

-- Prepares rows for ResourceList: share bars relative to the largest row,
-- the row's own icon and color, and a checkmark for rows in the basket so
-- marked items are recognisable in every list.
function Rows:annotate(rows, icon, color)
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
function Rows:markableResource(row)
	return row ~= nil and row:isLeaf() and row.action == "trash" and row.path ~= nil and (row:validateTrash()) == true
end

local function separator() return {separator = true} end

function Rows:reveal(path)
	return {title = "Show in Finder", systemImage = "folder", action = function() self.app.service.reveal(path) end}
end

-- Watch/Stop Watching; nil when the app keeps no watchlist.
function Rows:watch(entry)
	return self.app.watchlist and self.app.watchlist:menuItem(entry) or nil
end

function Rows:copyPath(path)
	return {title = "Copy Path", systemImage = "doc.on.doc", action = function() self.app.service.copy(path) end}
end

-- Quick Look, as the Finder's Space bar: `paths` are the neighbours the
-- panel's arrow keys step through, starting at `path`. A provider without
-- Quick Look offers none.
function Rows:quickLookItem(path, paths)
	if type(Provider.offers(self.app.service, "quickLook")) ~= "function" then return nil end
	return {title = "Quick Look", systemImage = "eye", action = function() self:quickLook(path, paths) end}
end

function Rows:quickLook(path, paths)
	if type(Provider.offers(self.app.service, "quickLook")) ~= "function" or not path then return false end
	paths = paths and #paths > 0 and paths or {path}
	local index = 1
	for position, candidate in ipairs(paths) do if candidate == path then index = position; break end end
	self.app.service.quickLook(paths, index)
	return true
end

-- "Move to…": offloads a file or folder to another folder or disk, as
-- Nektony's Disk Space Analyzer and the Finder do. `validate(path)` is the
-- page's own policy for what may leave its place; `moved(destination)`
-- updates the page once the move finished. Nothing is ever replaced.
function Rows:moveItem(row, validate, moved)
	if type(Provider.offers(self.app.service, "moveItem")) ~= "function" then return nil end
	local ok, reason = validate(row.path)
	return {title = ok and "Move to…" or ("Move to… — " .. tostring(reason)), systemImage = "folder.badge.plus", disabled = not ok,
		action = function() self:move(row, validate, moved) end}
end

function Rows:move(row, validate, moved)
	local ok, reason = validate(row.path)
	if not ok then self.app.service.showError("Cannot move " .. (row.name or "this item"), reason); return end
	local folder = self.app.service.pickFolder("Move “" .. (row.name or row.path) .. "” to")
	if not folder then return end
	local allowed, why = FolderTree.validateDestination(row.path, folder)
	if not allowed then self.app.service.showError("Cannot move " .. (row.name or "this item"), why); return end
	self.app.service.moveItem(row.path, folder, function(done, message, destination)
		if self.app.review then self.app.review:log("Move", done, row.bytes, row.path, done and destination or message) end
		if not done then self.app.service.showError("Could not move " .. (row.name or "this item"), message or "Check permissions."); return end
		if moved then moved(destination) end
	end)
end

-- Move to Trash for an item outside the catalog, checked by `validate`
-- first; `trashed()` updates the page.
function Rows:trashItem(row, validate, trashed)
	local ok, reason = validate(row.path)
	if not ok then self.app.service.showError("Cannot move to Trash", reason); return end
	if not self.app.service.confirmTrashPath("Move " .. (row.name or row.path) .. " to Trash?", row.path,
		Format.size(row.bytes) .. ". Moving to Trash does not free space until you empty it.") then return end
	local moved, message = self.app.service.trash(row.path)
	if self.app.review then self.app.review:log("Move to Trash", moved, row.bytes, row.path, message) end
	if not moved then self.app.service.showError("Could not move to Trash", message or "Check permissions."); return end
	if trashed then trashed() end
end

-- A file or folder on the Folder page. `handlers.open(row)` looks inside a
-- folder, `handlers.changed(path)` follows a move or Trash, and
-- `handlers.siblings` are the paths Quick Look steps through.
function Rows:item(row, handlers)
	local items = {}
	if row.directory then
		table.insert(items, {title = "Open", systemImage = "arrow.right.circle", action = function() handlers.open(row) end})
	end
	table.insert(items, self:quickLookItem(row.path, handlers.siblings))
	table.insert(items, self:reveal(row.path))
	table.insert(items, separator())
	local validate = function(path) return FolderTree.validateChange(path, Model.db.home, Locations:owner(path)) end
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
function Rows:resource(id)
	local row = Locations:find(id)
	if not row then return {} end
	local items = {}
	if not row:isLeaf() then
		table.insert(items, {title = "Open " .. row.name .. "…", systemImage = "list.bullet", action = function() self.app.open(id) end})
	else
		local detail = Locations:details(id)
		if row.action ~= "finder" and detail then
			table.insert(items, {title = detail.manageTitle, disabled = not detail.canManage,
				action = function()
					if Locations:opensElsewhere(id) then self.app.open(id); return end
					Manage(self):manage(id)
				end})
		end
		if self:markableResource(row) then
			local measured = Model.db.measurements[id]
			table.insert(items, self:mark({path = row.path, name = row.name, bytes = measured and measured.bytes, resourceId = id,
				source = (row:parent() or row).name, consequence = row.consequence}))
		end
		if row.path then
			table.insert(items, self:quickLookItem(row.path))
			table.insert(items, self:reveal(row.path))
		end
		local parent = row:parent()
		if parent then
			table.insert(items, {title = "Open " .. parent.name .. "…", systemImage = "list.bullet", action = function() self.app.open(parent.id) end})
		end
	end
	table.insert(items, separator())
	table.insert(items, {title = Model.db.kept[id] and "Stop Keeping" or "Keep", systemImage = "checkmark.shield",
		action = function() self.app.keep(id) end})
	table.insert(items, self:watch({kind = "resource", id = id}))
	if row.path then table.insert(items, self:copyPath(row.path)) end
	return items
end

-- An individual file from Large Files. Trash is offered only for ordinary
-- documents in the home folder; the menu says why otherwise.
function Rows:file(row, handlers)
	local ok, reason = Files:validateTrash(row.path)
	local items = {
		{title = ok and "Move to Trash…" or ("Move to Trash — " .. (reason and reason.message or "unavailable")), systemImage = "trash", disabled = not ok,
			action = function() self:trashFile(row) end},
	}
	if ok then table.insert(items, self:mark({path = row.path, name = row.name, bytes = row.bytes, source = "Large Files"})) end
	table.insert(items, self:moveItem(row, function(path)
		local allowed, why = Files:validateTrash(path)
		return allowed, why and why.message
	end, function() self.app.rescan() end))
	table.insert(items, self:quickLookItem(row.path, handlers and handlers.siblings))
	table.insert(items, self:reveal(row.path))
	if row.ownerId then
		local owner = Locations:find(row.ownerId)
		table.insert(items, {title = "Open " .. (owner and owner.name or "Category") .. "…", systemImage = "list.bullet",
			action = function() self.app.open(row.ownerId) end})
	end
	table.insert(items, separator())
	table.insert(items, self:copyPath(row.path))
	return items
end

function Rows:trashFile(row)
	local ok, reason = Files:validateTrash(row.path)
	if not ok then self.app.service.showError("Cannot move to Trash", reason.message); return end
	if not self.app.service.confirmTrashPath("Move " .. row.name .. " to Trash?", row.path,
		Format.size(row.bytes) .. " · last used " .. (row.lastUse or "unknown"):lower() .. ". Moving to Trash does not free space until you empty it.") then return end
	local moved, message = self.app.service.trash(row.path)
	if not moved then self.app.service.showError("Could not move to Trash", message or "Check permissions."); return end
	self.app.rescan()
end

-- A folder that is not itself a catalog resource: an app's container, a
-- possible leftover, Xcode data or a project's build folder. `trash(row)`
-- performs a validated move when given; `mark` is the basket item for it.
function Rows:folder(row, trash, mark)
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
function Rows:application(row)
	local items = {self:reveal(row.path)}
	for index, folder in ipairs(row.folders or {}) do
		if index > 4 then break end
		table.insert(items, {title = "Show " .. folder.label .. " (" .. Format.size(folder.bytes) .. ")", systemImage = "folder",
			action = function() self.app.service.reveal(folder.path) end})
	end
	table.insert(items, separator())
	table.insert(items, {title = Model.db.kept[row.resourceId] and "Stop Keeping" or "Keep", systemImage = "checkmark.shield",
		action = function() self.app.keep(row.resourceId) end})
	if row.bundleId then
		table.insert(items, {title = "Copy Bundle Identifier", systemImage = "doc.on.doc", action = function() self.app.service.copy(row.bundleId) end})
	end
	table.insert(items, self:copyPath(row.path))
	return items
end

return Rows
