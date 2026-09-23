local ns = require("ns")
local xml = require("ui.xml")
local Template = require("ui.template")
local Model = require("demo.container-reorder.Model")

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({ model = Model.new() }, Controller)
end

function Controller:render()
	local actions = {}
	for _, group in ipairs({ "stack", "grid", "flow" }) do
		local name = group
		actions["reorder" .. name] = function(difference)
			self.model:applyReorder(name, difference)
			self:render()
		end
	end
	self.content:update({
		stack = self.model.stack,
		grid = self.model.grid,
		flow = self.model.flow,
		actions = actions,
	})
end

function Controller:createWindow()
	local root, refs = xml.renderFile("demo/container-reorder/views/Root.etlua", {}, ns)
	self.window = ns.Window { title = "Reorder Containers", width = 560,
		height = 640, content = root }
	self.content = Template.new(refs.host, "demo/container-reorder/views/Content.etlua", ns)
	self:render()
	return self.window
end

return Controller
