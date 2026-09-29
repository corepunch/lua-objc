local Model = require("apps.studio.models.Chat")
local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({model = Model}, Controller)
end

function Controller:presentation(conversation)
	return self.model.presentation(conversation)
end

return Controller
