-- Opens the window, renders the task list and turns taps into model calls.
-- On the Mac the lists sit in a sidebar; a phone shows the day by itself.
local ns = require("ns")
local xml = require("ui.xml")
local Template = require("ui.template")
local Model = require("demo.todo.Model")

local VIEWS = "demo/todo/views/"

local Controller = {}
Controller.__index = Controller

function Controller.new(model)
	return setmetatable({model = model or Model.new()}, Controller)
end

-- Every checkbox dispatches `toggle_<id>`.
function Controller:actions()
	return setmetatable({
		filter = function(index) self:setFilter(index + 1) end,
		-- Every list shows today's tasks in this demo.
		selectList = function() end,
	}, {__index = function(_, name)
		local id = tonumber(name:match("^toggle_(%d+)$"))
		if id then return function() self:toggle(id) end end
	end})
end

function Controller:render()
	local data = self.model:presentation()
	data.actions = self:actions()
	self.content:update(data)
	if self.sidebar then self.sidebar:replaceRows(data.lists) end
end

function Controller:toggle(id)
	self.model:toggle(id)
	self:render()
end

function Controller:setFilter(index)
	self.model:setFilter(index)
	self:render()
end

function Controller:createWindow()
	local config, refs = xml.renderFile(VIEWS .. "Window.etlua", {actions = self:actions()}, ns)
	self.content = Template.new(refs.content, VIEWS .. "Content.etlua", ns)
	if ns.platform == "AppKit" then
		local sidebar, sidebarRefs = xml.renderFile(VIEWS .. "Sidebar.etlua",
			{lists = self.model:lists(), actions = self:actions()}, ns)
		config.sidebar, self.sidebar = sidebar, sidebarRefs.sidebar
	end
	self:render()
	self.window = ns.Window(config)
	return self.window
end

return Controller
