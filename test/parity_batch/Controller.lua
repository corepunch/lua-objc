local ns = require("ns")
local Model = require("test.parity_batch.Model")
local Content = require("test.parity_batch.views.Content")
local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({ model = Model.new() }, Controller)
end

function Controller:createWindow()
	self.model:run()
	return ns.Window { title = "Parity Batch", content = Content(self.model) }
end

return Controller
