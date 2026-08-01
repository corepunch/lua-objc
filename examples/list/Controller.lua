local ns    = require("AppKit")
local xml   = require("ui.xml")
local Model = require("examples.list.Model")

local VIEWS = "examples/list/views/"

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({
		employeeList = nil,
		window       = nil,
	}, Controller)
end

function Controller:createWindow()
	local layout, refs = xml.renderFile(VIEWS .. "ListView.xml")

	self.employeeList = refs.employeeList
	self.employeeList:replaceRows(Model.employees)

	self.window = ns.Window {
		title  = Model.title,
		width  = Model.windowWidth,
		height = Model.windowHeight,
		layout,
	}
	return self.window
end

return Controller
