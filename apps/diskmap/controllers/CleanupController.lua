local Preferences = require("apps.diskmap.models.Preferences")
local Controller = {}; Controller.__index = Controller
-- Keep changes and their persistence. `changed(message)` reports a save
-- failure, or nil, after the model changes.
function Controller.new(model, service, changed)
	return setmetatable({model = model, service = service, changed = changed or function() end}, Controller)
end
function Controller:toggleKeep(id)
	if not Preferences.toggle(self.model, id) then return false end
	local saved = not self.service.saveKeep or self.service.saveKeep(self.model.kept)
	local message; if not saved then message = "Keep preference could not be saved." end
	self.changed(message)
	return saved
end
return Controller
