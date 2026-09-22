local Model = require("apps.studio.models.Chat")
local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({model = Model}, Controller)
end

function Controller:presentation()
	return self.model.presentation()
end

return Controller
