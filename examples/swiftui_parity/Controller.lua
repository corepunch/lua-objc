local ns = require("AppKit")
local xml = require("ui.xml")
local Model = require("examples.swiftui_parity.Model")

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({ activationCount = 0 }, Controller)
end

function Controller:createWindow()
	local caseId = Model.caseId()
	local data = Model.data(caseId)
	data.caseId = caseId
	data.actions = {
		activate = function()
			self.activationCount = self.activationCount + 1
		end,
	}
	local cfg = xml.renderFile("examples/swiftui_parity/views/Window.etlua", data, ns)
	cfg.title = "SwiftUI parity — " .. caseId
	return ns.Window(cfg)
end

return Controller
