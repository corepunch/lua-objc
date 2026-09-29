local ns = require("ns")
local xml = require("ui.xml")
local Model = require("demo.playground.Model")

local Controller = {}
Controller.__index = Controller

local VIEW = "demo/playground/views/Window.etlua"

function Controller.new()
	return setmetatable({ model = Model.new(ns.LocalStorage) }, Controller)
end

function Controller:actions()
	return setmetatable({
		reminders = function(value) self.model:setReminders(value) end,
	}, { __index = function(_, name)
		local id = name:match("^toggle_(%w+)$")
		if id then return function() self:toggle(id) end end
	end })
end

function Controller:render()
	local data = self.model:presentation()
	data.actions = self:actions()
	self.refs.todayProgress.progress = data.progress.fraction
	self.refs.todayCount.text = data.progress.done .. " of " .. data.progress.total .. " complete"
	self.refs.todayGreeting.text = data.greeting
end

function Controller:toggle(id)
	self.model:toggle(id)
	self:render()
end

function Controller:createWindow()
	local data = self.model:presentation()
	data.actions = self:actions()
	local config, refs = xml.renderFile(VIEW, data, ns)
	self.refs = refs
	return ns.Window(config)
end

return Controller
