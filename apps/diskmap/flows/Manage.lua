local Model = require("data.model")
local Flow = require("data.flow")
local Locations = require("apps.diskmap.models.Locations")
local Format = require("apps.diskmap.helpers.Format")
-- Acting on the one location a person chose: move it to the Trash, empty the
-- Trash, run its owner's cleanup, open its owner or reveal it. A flow
-- (lua/data/flow.lua) over a page or the app: it asks the app's service,
-- `self.app.service`, and remeasures with `self.app.rescan()` after a change.
--
--   Manage(page):manage("derived")
local Manage = Flow:extend()

-- Moves the location `id` to the Trash once its constraints allow it.
-- Returns ok and, when refused or failed, {code, message}.
function Manage:moveToTrash(id)
	local row = Locations:find(id)
	if not row then return false, {code = "unknown_resource", message = "Resource is not registered."} end
	local valid, validation = row:validateTrash()
	if not valid then return false, validation end
	local service = self.app.service
	local ok, result, message = pcall(function() return service.trash(row.path) end)
	if not ok then return false, {code = "trash_service", message = tostring(result)} end
	if not result then return false, {code = "trash_service", message = message or "Check permissions."} end
	return true
end

-- Empties the Trash location `id` through the service, under the same rules.
function Manage:emptyTrash(id)
	local row = Locations:find(id)
	if not row then return false, {code = "unknown_resource", message = "Resource is not registered."} end
	local valid, validation = row:validateEmpty()
	if not valid then return false, validation end
	local service = self.app.service
	local ok, result, message = pcall(function() return service.emptyTrash() end)
	if not ok then return false, {code = "empty_service", message = tostring(result)} end
	if not result then return false, {code = "empty_service", message = message or "Check permissions."} end
	return true
end

function Manage:manage(id)
	local row = Locations:find(id)
	if not row or not row:isLeaf() then return false end
	if row.action == "trash" then
		local valid, validation = row:validateTrash()
		if not valid or not self.app.service.confirmTrash(row) then return false end
		local ok, err = self:moveToTrash(row.id)
		if not ok then self.app.service.showError("Could not move to Trash", err and err.message or "Check permissions."); return false end
		self.app.rescan()
	elseif row.action == "empty" then
		local valid, validation = row:validateEmpty()
		if not valid then self.app.service.showError("Trash is already empty", validation and validation.message or "Nothing to remove."); return false end
		local measured = Model.db.measurements[row.id]
		if not self.app.service.confirmEmptyTrash(row, Format.size(measured and measured.bytes)) then return false end
		local ok, err = self:emptyTrash(row.id)
		if not ok then self.app.service.showError("Could not empty Trash", err and err.message or "Check permissions."); return false end
		self.app.rescan()
	elseif row.action == "ownerCleanup" then
		local measured = Model.db.measurements[row.id]
		if not measured or measured.status ~= "complete" or (measured.bytes or 0) <= 0 then
			self.app.service.showError("Cache is not ready to clear", "Refresh Diskmap and review a complete, positive measurement first."); return false
		end
		if not self.app.service.confirmOwnerCleanup or not self.app.service.confirmOwnerCleanup(row, Format.size(measured.bytes)) then return false end
		self.app.service.runOwnerCleanup(row.commandId, Model.db.home, function(ok, output)
			if not ok then self.app.service.showError("Could not clear " .. row.name, output or "Check that the package manager is installed."); return end
			self.app.rescan()
		end)
	elseif row.action == "settings" then self.app.service.openSettings(row.settingsSection)
	elseif row.action == "xcode" or row.action == "docker" then
		local ok, message = self.app.service.openOwner(row.action)
		if ok == false then self.app.service.showError("Cannot open cleanup owner", message); return false end
	elseif row.path then self.app.service.reveal(row.path) end
	return true
end
return Manage
