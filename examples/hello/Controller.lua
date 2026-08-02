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
	local cfg, refs = xml.renderFile(VIEWS .. "Window.etlua")
	return ns.Window(cfg)
end

return Controller
