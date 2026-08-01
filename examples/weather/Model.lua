local Model = {}

Model.title = "World Weather"
Model.windowWidth = 680
Model.windowHeight = 500

Model.cities = {
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

function Model.fetchCity(list, city)
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

return Model
