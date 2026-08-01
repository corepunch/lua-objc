local xml   = require("ui.xml")
local Model = require("examples.preview.Model")

local VIEWS = "examples/preview/views/"

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({}, Controller)
end

function Controller:render()
	return xml.renderFile(VIEWS .. "PreviewView.xml")
end

return Controller
