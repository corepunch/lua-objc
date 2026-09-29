-- apps/weather --showcase: offline sample weather in fetchCity's shape and
-- weekday forecast labels, so reel captures never need the network.
_G.__headless = true

local t = require("TestKit")
local Model = require("apps.weather.Model")

t.assertEqual(Model.weekday("2026-09-29"), "Tue", "dates read as weekdays")
t.assertEqual(Model.weekday("soon"), "soon", "an unparsable date passes through")
for _, city in ipairs(Model.cities) do
	local data = Model.showcaseCity(city)
	t.assertEqual(data.city, city.name, city.name .. " has a showcase reading")
	t.assertEqual(#data.forecast, 7, city.name .. " has a seven-day forecast")
	t.expect(data.forecast[1].day ~= nil and data.icon ~= nil, city.name .. " has weekdays and an icon")
end
t.assertEqual(Model.showcaseCity({name = "Tokyo"}).cond, "Clear", "cities keep their own weather")

os.exit(t.summary() and 0 or 1)
