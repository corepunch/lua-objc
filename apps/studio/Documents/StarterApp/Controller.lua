local ns = require("ns")
local xml = require("ui.xml")
local Template = require("ui.template")
local Model = require("data.model")
local Counters = require("demo.playground.Model")
local Controller = {}
Controller.__index = Controller
function Controller.new()
	return setmetatable({store = {starterCounters = {{id = "main", value = 0}}}}, Controller)
end
function Controller:data()
	return { count = Counters:find("main").value, actions = self.actions }
end
function Controller:createWindow()
	Model.bind(self.store)
	self.actions = { increment = Model.bound(self.store, function()
		Counters:find("main"):increment()
		self.template:update(self:data())
	end) }
	local path = "demo/playground/views/layouts/Window.etlua"
	local config, refs = xml.renderFile(path, {}, ns)
	self.template = Template.new(refs.content, "demo/playground/views/pages/Main.etlua", ns)
	self.template:update(self:data())
	return ns.Window(config)
end
return Controller
