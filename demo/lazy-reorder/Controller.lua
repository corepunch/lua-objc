local ns = require("ns")
local xml = require("ui.xml")
local Template = require("ui.template")
local Model = require("demo.lazy-reorder.Model")

local Controller = {}
Controller.__index = Controller

function Controller.new(config)
	config = config or {}
	local kind = config.kind or os.getenv("LUA_OBJC_LAZY_KIND") or "stack"
	assert(kind == "stack" or kind == "grid", "lazy kind must be stack or grid")
	return setmetatable({ model = Model.new(config.count or 1000), kind = kind }, Controller)
end

function Controller:render()
	self.content:update({
		items = self.model.items,
		actions = {
			reorderItems = function(difference)
				self.model:applyReorder(difference)
				self:render()
			end,
		},
	})
end

function Controller:createWindow()
	local root, refs = xml.renderFile("demo/lazy-reorder/views/Root.etlua",
		{ kind = self.kind }, ns)
	self.window = ns.Window { title = "Lazy Reorder", width = 600,
		height = 500, content = root }
	local file = self.kind == "grid" and "Grid.etlua" or "Stack.etlua"
	self.content = Template.new(refs.host, "demo/lazy-reorder/views/" .. file, ns)
	self:render()
	return self.window
end

return Controller
