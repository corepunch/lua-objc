local ns = require("ns")
local xml = require("ui.xml")
local Model = require("apps.private-palettes.Model")

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({ model = Model.new() }, Controller)
end

function Controller:createWindow()
	local content = xml.renderFile("apps/private-palettes/views/Window.etlua", self.model, ns)
	self.window = ns.Window { title = self.model.title, content = content }
	return self.window
end

return Controller
