local ns = require("ns")
local xml = require("ui.xml")
local Model = require("comparison.iphone_swiftui.Model")

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({}, Controller)
end

function Controller:createWindow()
	local data = Model.load(ns)
	data.actions = { noop = function() end }
	local config = xml.renderFile("comparison/iphone_swiftui/views/Window.etlua", data, ns)
	config.title = "UI Comparison — " .. data.id
	config.appearance = "light"
	return ns.Window(config)
end

return Controller
