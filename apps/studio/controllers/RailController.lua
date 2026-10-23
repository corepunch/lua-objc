local Model = require("apps.studio.models.Rail")
local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({model = Model}, Controller)
end

function Controller:presentation(selected, badges)
	return self.model.presentation(selected, badges)
end

return Controller
