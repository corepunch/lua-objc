local ns    = require("ns")
local xml   = require("ui.xml")
local Model = require("demo.preview.Model")

local VIEWS = "demo/preview/views/"

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({}, Controller)
end

function Controller:render()
	return xml.renderFile(VIEWS .. "PreviewView.etlua", {}, ns)
end

function Controller:createWindow()
	self.window = ns.Window { title = "Preview", width = 480, height = 360, content = self:render() }
	return self.window
end

return Controller
