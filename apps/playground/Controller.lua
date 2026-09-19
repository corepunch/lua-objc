local ns = require("ns")
local xml = require("ui.xml")
local Model = require("apps.playground.Model")
local Controller = {}
Controller.__index = Controller
function Controller.new()
	return setmetatable({ model = Model.new() }, Controller)
end
function Controller:createWindow()
	local config, refs = xml.renderFile("apps/playground/views/Window.etlua", {
		count = self.model.count,
		actions = { increment = function()
			self.model:increment()
			self.refs.count.text = tostring(self.model.count)
		end },
	}, ns)
	self.refs = refs
	return ns.Window(config)
end
return Controller
