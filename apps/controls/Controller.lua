local ns = require("AppKit")
local xml = require("ui.xml")
local Model = require("apps.controls.Model")

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({}, Controller)
end

function Controller:createWindow()
	local config = xml.renderFile("apps/controls/views/Window.etlua", Model)
	return ns.Window(config)
end

return Controller