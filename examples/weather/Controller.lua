local ns    = require("AppKit")
local xml   = require("ui.xml")
local Model = require("examples.weather.Model")

local VIEWS = "examples/weather/views/"

local ACTIONS = {
	refresh = function(self) self:refresh() end,
}

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({
		weatherList = nil,
		window      = nil,
	}, Controller)
end

function Controller:refresh()
	for _, city in ipairs(Model.cities) do
		Model.fetchCity(self.weatherList, city)
	end
end

function Controller:createWindow()
	local cfg, refs = xml.renderFile(VIEWS .. "Window.xml")

	for _, item in ipairs(cfg.toolbar or {}) do
		if item.action and ACTIONS[item.action] then
			local fn = ACTIONS[item.action]
			item.action = function() fn(self) end
		end
	end

	self.weatherList = refs.weatherList

	self:refresh()

	self.window = ns.Window(cfg)
	return self.window
end

return Controller
