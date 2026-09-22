local Model = require("apps.diskmap.Model")
local Inspector = require("apps.diskmap.models.Inspector")
local Cleanup = require("apps.diskmap.models.Cleanup")
local Controller = {}; Controller.__index = Controller
function Controller.new(model, service, refresh)
	return setmetatable({model = model, service = service, refresh = refresh}, Controller)
end
function Controller:select(id)
	local data = Inspector.details(self.model, id)
	if data then self.selectedId = id end
	return data
end
function Controller:manage()
	local row = self.model.resources:find(self.selectedId)
	if not row or not row:isLeaf() then return false end
	if row.action == "trash" then
		local valid, validation = row:validateTrash()
		if not valid or not self.service.confirmTrash(row) then return false end
		local ok, err = Cleanup.moveToTrash(self.model, row.id, self.service)
		if not ok then self.service.showError("Could not move to Trash", err and err.message or "Check permissions."); return false end
		self.refresh()
	elseif row.action == "empty" then
		local valid, validation = row:validateEmpty()
		if not valid then self.service.showError("Trash is already empty", validation and validation.message or "Nothing to remove."); return false end
		local measured = self.model.measurements[row.id]
		if not self.service.confirmEmptyTrash(row, Model.size(measured and measured.bytes)) then return false end
		local ok, err = Cleanup.emptyTrash(self.model, row.id, self.service)
		if not ok then self.service.showError("Could not empty Trash", err and err.message or "Check permissions."); return false end
		self.refresh()
	elseif row.action == "ownerCleanup" then
		local measured = self.model.measurements[row.id]
		if not measured or measured.status ~= "complete" or (measured.bytes or 0) <= 0 then
			self.service.showError("Cache is not ready to clear", "Refresh Diskmap and review a complete, positive measurement first."); return false
		end
		if not self.service.confirmOwnerCleanup or not self.service.confirmOwnerCleanup(row, Model.size(measured.bytes)) then return false end
		self.service.runOwnerCleanup(row.commandId, self.model.home, function(ok, output)
			if not ok then self.service.showError("Could not clear " .. row.name, output or "Check that the package manager is installed."); return end
			self.refresh()
		end)
	elseif row.action == "settings" then self.service.openSettings(row.settingsSection)
	elseif row.action == "xcode" or row.action == "docker" then self.service.openOwner(row.action)
	elseif row.path then self.service.reveal(row.path) end
	return true
end
return Controller
