local ns    = require("AppKit")
local xml   = require("ui.xml")
local Model = require("examples.hello.Model")

local VIEWS = "examples/hello/views/"

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({}, Controller)
end

function Controller:createWindow()
	local layout = xml.renderFile(VIEWS .. "HelloLayout.xml")

	return ns.Window {
		title  = Model.title,
		width  = Model.windowWidth,
		height = Model.windowHeight,
		layout,
	}
end

return Controller
