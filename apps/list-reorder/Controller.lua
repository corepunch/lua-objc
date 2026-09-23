local ns = require("ns")
local xml = require("ui.xml")
local Model = require("apps.list-reorder.Model")

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({ model = Model.new() }, Controller)
end

function Controller:handleReorder(difference)
	self.model:applyReorder(difference)
end

function Controller:createWindow()
	local content, refs = xml.renderFile("apps/list-reorder/views/Window.etlua", {
		tasks = self.model.tasks,
		actions = {
			reorderTasks = function(difference)
				self:handleReorder(difference)
			end,
		},
	}, ns)
	self.refs = refs
	self.window = ns.Window {
		title = "Reorderable Tasks",
		width = 640,
		height = 420,
		content = content,
	}
	return self.window
end

return Controller
