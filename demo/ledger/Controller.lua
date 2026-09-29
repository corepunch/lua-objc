-- Opens the dashboard. On the Mac the sections sit in a sidebar; a phone
-- shows the overview by itself.
local ns = require("ns")
local xml = require("ui.xml")
local Template = require("ui.template")
local Model = require("demo.ledger.Model")

local VIEWS = "demo/ledger/views/"

local SECTIONS = {
	{id = "overview", name = "Overview", icon = "chart.bar.xaxis", color = "systemBlue"},
	{id = "accounts", name = "Accounts", icon = "building.columns.fill", color = "systemIndigo"},
	{id = "budgets", name = "Budgets", icon = "chart.pie.fill", color = "systemOrange"},
	{id = "goals", name = "Goals", icon = "target", color = "systemGreen"},
}

local Controller = {}
Controller.__index = Controller

function Controller.new(model)
	return setmetatable({model = model or Model.new()}, Controller)
end

function Controller:actions()
	return {
		selectSection = function() end,
		period = function(index) self:setPeriod(index == 0 and "weekly" or "monthly") end,
	}
end

function Controller:render()
	local data = self.model:presentation()
	data.period = self.model.period == "weekly" and 0 or 1
	data.actions = self:actions()
	self.content:update(data)
end

function Controller:setPeriod(period)
	self.model:setPeriod(period)
	self:render()
end

function Controller:createWindow()
	local config, refs = xml.renderFile(VIEWS .. "Window.etlua", {actions = self:actions()}, ns)
	self.content = Template.new(refs.content, VIEWS .. "Overview.etlua", ns)
	if ns.platform == "AppKit" then
		config.sidebar = xml.renderFile(VIEWS .. "Sidebar.etlua", {sections = SECTIONS, actions = self:actions()}, ns)
	end
	self:render()
	self.window = ns.Window(config)
	return self.window
end

return Controller
