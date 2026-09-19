local xml   = require("ui.xml")
local Model = require("apps.preview.Model")

local VIEWS = "apps/preview/views/"

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({}, Controller)
end

function Controller:render()
	return xml.renderFile(VIEWS .. "PreviewView.etlua")
end

return Controller
