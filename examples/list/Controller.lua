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
	local cfg, refs = xml.renderFile(VIEWS .. "Window.etlua")

	self.employeeList = refs.employeeList
	self.employeeList:replaceRows(Model.employees)

	self.window = ns.Window(cfg)
	return self.window
end

return Controller
