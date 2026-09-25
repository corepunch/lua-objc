local ns = require("ns")
local xml = require("ui.xml")
local Model = require("test.parity_batch.Model")
local Batch = require("test.parity_batch.services.Batch")
local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({ model = Model.new(Batch) }, Controller)
end

function Controller:createWindow()
	self.model:run()
	local content = xml.renderFile("test/parity_batch/views/Content.etlua", self.model:presentation(), ns)
	return ns.Window { title = "Parity Batch", content = content }
end

return Controller
