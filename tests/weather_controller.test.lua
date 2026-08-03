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
		} },
	}
end

controller:refresh()

t.assertEqual(table.concat(loadingCalls, ","), "show,hide",
	"refresh starts and stops the native loading indicator")
t.assertEqual(#rows, 10, "refresh replaces rows after the coroutine completes")
t.assertEqual(rows[1].temp, "21°C", "refresh formats fetched temperatures")

ns.async = originalAsync
ns.fetch_json = originalFetchJSON

os.exit(t.summary() and 0 or 1)
