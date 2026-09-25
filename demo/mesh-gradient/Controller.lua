local ns  = require("AppKit")
local xml = require("ui.xml")
local Model = require("demo.mesh-gradient.Model")

local VIEWS = "demo/mesh-gradient/views/"

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({}, Controller)
end

function Controller:createWindow()
	local cfg = xml.renderFile(VIEWS .. "Window.etlua", {
		title = Model.title,
		subtitle = Model.subtitle,
	})
	return ns.Window(cfg)
end

return Controller
