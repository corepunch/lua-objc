_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local Controller = require("examples.weather.Controller")

local originalAsync = ns.async
local originalFetchJSON = ns.fetch_json
local loadingCalls = {}
local rows
local controller = Controller.new()
controller.weatherList = {
	showLoading = function() loadingCalls[#loadingCalls + 1] = "show" end,
	hideLoading = function() loadingCalls[#loadingCalls + 1] = "hide" end,
	clearRows = function() rows = nil end,
	replaceRows = function(_, value) rows = value end,
}

ns.async = function(fn) fn() end
ns.fetch_json = function()
	return {
		current_condition = { {
			temp_C = "21",
			weatherDesc = { { value = "Sunny" } },
			humidity = "45",
			windspeedKmph = "12",
				latitude = "51.5",
				longitude = "-0.1",
		} },
		daily = {
			time = { "2026-08-28", "2026-08-29", "2026-08-30", "2026-08-31", "2026-09-01", "2026-09-02", "2026-09-03" },
			weather_code = { 1, 2, 61, 3, 0, 71, 80 },
			temperature_2m_max = { 21, 22, 20, 19, 23, 18, 20 },
			temperature_2m_min = { 12, 13, 11, 10, 14, 9, 12 },
			precipitation_probability_max = { 10, 20, 70, 35, 5, 60, 45 },
			rain_sum = { 0, 0, 4, 1, 0, 3, 2 },
			windspeed_10m_max = { 12, 14, 18, 10, 8, 16, 20 },
			uv_index_max = { 4, 5, 3, 4, 6, 2, 3 },
		},
		nearest_area = { {
			areaName = { { value = "London" } },
			latitude = { { value = "51.5" } },
			longitude = { { value = "-0.1" } },
		} },
	}
end

controller:refresh()

t.assertEqual(table.concat(loadingCalls, ","), "show,hide",
	"refresh starts and stops the native loading indicator")
t.assertEqual(#rows, 10, "refresh replaces rows after the coroutine completes")
t.assertEqual(rows[1].temp, "21°C", "refresh formats fetched temperatures")
t.assertEqual(#controller.weatherData.London.forecast, 7,
	"refresh loads a full seven-day forecast")

ns.async = originalAsync
ns.fetch_json = originalFetchJSON

os.exit(t.summary() and 0 or 1)
