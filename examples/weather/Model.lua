local ns = require("AppKit")

local Model = {}

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

function Model.fetchCity(city)
	local url = "https://wttr.in/" .. city.query .. "?format=j1"

	local ok, data = pcall(ns.fetch_json, url)
	if not ok or not data or not data.current_condition then
		return nil
	end

	local cc = data.current_condition[1]
	if not cc or not cc.weatherDesc then
		return nil
	end

	local forecast = {}
	if data.weather then
		for _, day in ipairs(data.weather) do
			local f = { date = day.date or "" }
			if day.hourly and #day.hourly > 0 then
				local mid = day.hourly[math.max(1, math.floor(#day.hourly / 2))]
				f.tempMax = day.maxtempC
				f.tempMin = day.mintempC
				f.desc = mid.weatherDesc and mid.weatherDesc[1] and mid.weatherDesc[1].value or "--"
			end
			forecast[#forecast + 1] = f
		end
	end

	return {
		city = city.name,
		temp = cc.temp_C,
		cond = cc.weatherDesc[1].value,
		humid = cc.humidity,
		wind = cc.windspeedKmph,
		feelsLike = cc.FeelsLikeC,
		visibility = cc.visibility,
		pressure = cc.pressure,
		uvIndex = cc.uvIndex,
		forecast = forecast,
	}
end

return Model
