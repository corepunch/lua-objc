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
	local refs
	data.actions = {
		activate = function()
			self.activationCount = self.activationCount + 1
			if refs and refs.counter then
				refs.counter.text = "Count: " .. self.activationCount
				refs.counter:sizeToFit()
			end
		end,
	}
	local cfg, renderedRefs = xml.renderFile(
		"examples/swiftui_parity/views/Window.etlua", data, ns)
	refs = renderedRefs
	cfg.title = "SwiftUI parity — " .. caseId
	return ns.Window(cfg)
end

return Controller
