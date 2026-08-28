local ns    = require("AppKit")
local xml   = require("ui.xml")
local Model = require("examples.weather.Model")

local VIEWS = "examples/weather/views/"

local ACTIONS = {
	refresh = function(self) self:refresh() end,
}

local function buildWeatherList()
	return ns.List {
		flexGrow = 1,
		style = "sourceList",
		header = false,
		alternatingRows = false,
		rowHeight = 48,
		columns = {
			{ id = "city", title = "Location", width = 270,
				cell = { secondary = "summary" } },
		},
	}
end

local function buildDetailPane()
	return ns.VStack {
		flexGrow = 1,
	}
end

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({
		weatherList = nil,
		detailPane = nil,
		weatherData = {},
		selectedCity = Model.cities[1].name,
		window = nil,
	}, Controller)
end

function Controller:refresh()
	-- Keep the native table visible while the coroutine suspends for HTTP.
	-- List:showLoading owns the indeterminate AppKit spinner.
	self.weatherList:showLoading()
	self.weatherList:clearRows()

	ns.async(function()
		local ok, err = pcall(function()
			self.weatherData = {}
			local rows = {}

			for _, city in ipairs(Model.cities) do
				local data = Model.fetchCity(city)
				self.weatherData[city.name] = data
				rows[#rows + 1] = {
					_id = city.name,
					city = city.name,
					summary = data and (data.temp .. "°C  ·  " .. data.cond) or "Unavailable",
					temp = data and (tonumber(data.temp) and string.format("%.0f", data.temp) .. "°C" or "--") or "--",
					cond = data and data.cond or "unreachable",
			}
			end

			self.weatherList:replaceRows(rows)

			if self.selectedCity and self.detailPane then
				self:showDetail(self.weatherData[self.selectedCity], self.selectedCity)
			end
		end)

		self.weatherList:hideLoading()
		if not ok then
			io.stderr:write("weather refresh error: " .. tostring(err) .. "\n")
		end
	end)
end

function Controller:showDetail(data, cityName)
	self.detailPane:clearContainer()
	if data then
		local view = xml.renderFile(VIEWS .. "CityDetail.etlua", { city = data })
		self.detailPane:add(view)
	elseif cityName then
		local view = xml.renderFile(VIEWS .. "CityDetail.etlua", { city = nil })
		self.detailPane:add(view)
	end
	self.detailPane:layout()
end

function Controller:createWindow()
	local cfg, refs = xml.renderFile(VIEWS .. "Window.etlua")

	for _, item in ipairs(cfg.toolbar or {}) do
		if item.action and ACTIONS[item.action] then
			local fn = ACTIONS[item.action]
			item.action = function() fn(self) end
		end
	end

	self.weatherList = buildWeatherList()
	self.detailPane = buildDetailPane()
	cfg.sidebar = self.weatherList
	cfg.content = self.detailPane

	self.weatherList:onRowSelect(function(_, _, row)
		if row and row._id then
			self.selectedCity = row._id
			self:showDetail(self.weatherData[row._id], row._id)
		end
	end)

	self.window = ns.Window(cfg)
	self:refresh()
	return self.window
end

return Controller
