local ns = require("AppKit")
local Welcome = require("examples.IDEKit.Welcome")

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({}, Controller)
end

function Controller:createWindow()
	local welcomeView = Welcome {}

	return ns.Window {
		title  = "Welcome",
		width  = 820,
		height = 520,
		welcomeView,
	}
end

return Controller
