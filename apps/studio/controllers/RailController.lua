local Model = require("apps.studio.models.Rail")
local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({model = Model}, Controller)
end

function Controller:presentation(selected)
	return self.model.presentation(selected)
end

return Controller
