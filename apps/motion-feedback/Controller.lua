local Model = require("apps.motion-feedback.Model")
local haptics = require("ui.haptics")
local xml = require("ui.xml")
local ns = require("ns")

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({ model = Model.new() }, Controller)
end

function Controller:addItem()
	local item = self.model:addItem()
	self.refs.items:addRow(item)
	haptics.impact("light")
end

function Controller:createWindow()
	local config, refs = xml.renderFile("apps/motion-feedback/views/Window.etlua", {
		items = self.model.items,
		actions = { addItem = function() self:addItem() end },
	}, ns)
	self.refs = refs
	return ns.Window(config)
end

return Controller
