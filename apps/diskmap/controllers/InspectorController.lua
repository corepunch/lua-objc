local Inspector = require("apps.diskmap.models.Inspector")
local Preferences = require("apps.diskmap.models.Preferences")
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
	local row = self.model.byId[self.selectedId]
	if not row or row.children then return false end
	if row.action == "trash" then
		if not Preferences.canTrash(self.model, row.id) or not self.service.confirmTrash(row) then return false end
		local ok, err = self.service.trash(row.path)
		if not ok then self.service.showError("Could not move to Trash", err or "Check permissions."); return false end
		self.refresh()
	elseif row.action == "settings" then self.service.openSettings()
	elseif row.action == "xcode" or row.action == "docker" then self.service.openOwner(row.action)
	elseif row.path then self.service.reveal(row.path) end
	return true
end
return Controller
