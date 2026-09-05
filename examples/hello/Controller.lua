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
	local cfg, refs = xml.renderFile(VIEWS .. "Window.etlua", {
		title     = Model.title,
		subtitle  = Model.subtitle,
		version   = Model.version,
		timestamp = Model.timestamp,
		contacts  = Model.contacts,
	})
	return ns.Window(cfg)
end

return Controller
