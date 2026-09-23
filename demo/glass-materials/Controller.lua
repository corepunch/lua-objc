local ns = require("ns")
local xml = require("ui.xml")
local Model = require("demo.glass-materials.Model")

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({ model = Model.new() }, Controller)
end

function Controller:createWindow()
	local config = xml.renderFile("demo/glass-materials/views/Main.etlua", {
		materials = self.model.materials,
	}, ns)
	self.window = ns.Window(config)
	return self.window
end

return Controller
