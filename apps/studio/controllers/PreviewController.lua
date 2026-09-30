local Model = require("apps.studio.models.Preview")
local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({model = Model}, Controller)
end

function Controller:presentation(projects, iconChoices)
	return self.model.presentation(projects, iconChoices)
end

return Controller
