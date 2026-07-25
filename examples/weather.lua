local ns = require("AppKit")

local cities = {
	{ name = "London",           query = "London" },
	{ name = "Tokyo",            query = "Tokyo" },
	{ name = "San Francisco",    query = "San+Francisco" },
	{ name = "Sydney",           query = "Sydney" },
	{ name = "Berlin",           query = "Berlin" },
	{ name = "Mumbai",           query = "Mumbai" },
	{ name = "Cape Town",        query = "Cape+Town" },
	{ name = "Rio de Janeiro",   query = "Rio+de+Janeiro" },
	{ name = "Reykjavik",        query = "Reykjavik" },
	{ name = "Singapore",        query = "Singapore" },
}

local function fetch_city(list, city)
	local url = "https://wttr.in/" .. city.query .. "?format=j1"

	local ok, data = pcall(ns.fetch_json, url)
	if not ok or not data or not data.current_condition then
		list:addRow{
			city = city.name, temp = "\226\154\160",
			cond = "unreachable", humid = "-", wind = "-",
		}
		return
	end

	local cc = data.current_condition[1]
	if not cc or not cc.weatherDesc then
		list:addRow{
			city = city.name, temp = "\226\154\160",
			cond = "no data", humid = "-", wind = "-",
		}
		return
	end

	list:addRow{
		city = city.name,
		temp = cc.temp_C .. "\194\176C",
		cond = cc.weatherDesc[1].value,
		humid = cc.humidity .. "%",
		wind = cc.windspeedKmph .. " km/h",
	}
end

local list = ns.List {
	width = 660,
	height = 430,
	columns = {
		{ id = "city",  title = "City",        width = 130 },
		{ id = "temp",  title = "Temperature", width = 110, alignment = "trailing" },
		{ id = "cond",  title = "Conditions",  width = 180 },
		{ id = "humid", title = "Humidity",    width = 100, alignment = "trailing" },
		{ id = "wind",  title = "Wind",        width = 120, alignment = "trailing" },
	},
	refresh = function(l)
		for _, city in ipairs(cities) do
			fetch_city(l, city)
		end
	end,
}

list:refresh()

return ns.Window {
	title = "World Weather",
	width = 680,
	height = 500,
	toolbar = {
		{
			id = "refresh",
			label = "Refresh",
			icon = "arrow.clockwise",
			tooltip = "Refresh weather",
			action = function()
				list:refresh()
			end,
		},
	},
	list,
}
