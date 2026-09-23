local Model = require("demo.navigation-path.Model")
local Navigation = require("ui.navigation")
local xml = require("ui.xml")
local ns = require("ns")

local Controller = {}
Controller.__index = Controller

function Controller.new()
	local model = Model.new()
	local path = Navigation.Path.new()
	path:registerDestination("message", function(value)
		return xml.renderFile("demo/navigation-path/views/Message.etlua", {
			message = value,
		}, ns)
	end)
	return setmetatable({ model = model, path = path }, Controller)
end

function Controller:openMessage()
	self.path:push(self.model.message)
end

function Controller:createWindow()
	local config, refs = xml.renderFile("demo/navigation-path/views/Window.etlua", {
		path = self.path,
		destinations = {},
		actions = { openMessage = function() self:openMessage() end },
	}, ns)
	self.refs = refs
	self.window = ns.Window(config)
	return self.window
end

return Controller
