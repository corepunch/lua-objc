local Model = require("apps.studio.models.Sidebar")
local Controller = {}
Controller.__index = Controller

function Controller.new(metrics)
	return setmetatable({model = Model, metrics = assert(metrics, "sidebar metrics are required")}, Controller)
end

function Controller:presentation()
	local presentation = self.model.presentation()
	presentation.metrics = self.metrics
	presentation.collapsed = false
	return presentation
end

return Controller
