local ns    = require("AppKit")
local xml   = require("ui.xml")
local Model = require("examples.weather.Model")

local VIEWS = "examples/weather/views/"

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
	local layout, refs = xml.renderFile(VIEWS .. "WeatherLayout.xml")

	self.weatherList = refs.weatherList

	self:refresh()

	self.window = ns.Window {
		title  = Model.title,
		width  = Model.windowWidth,
		height = Model.windowHeight,
		toolbar = {
			{
				id      = "refresh",
				label   = "Refresh",
				icon    = "arrow.clockwise",
				tooltip = "Refresh weather",
				action  = function() self:refresh() end,
			},
		},
		layout,
	}
	return self.window
end

return Controller
