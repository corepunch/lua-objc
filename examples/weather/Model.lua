local ns = require("AppKit")

local Model = {}

local ICONS = {
	sunny = "examples/weather/assets/sunny.svg",
	cloudy = "examples/weather/assets/cloudy.svg",
	rain = "examples/weather/assets/rain.svg",
	snow = "examples/weather/assets/snow.svg",
}

local function iconForCondition(condition)
	local value = tostring(condition or ""):lower()
	if value:find("snow", 1, true) or value:find("ice", 1, true) then
		return ICONS.snow
	elseif value:find("rain", 1, true) or value:find("drizzle", 1, true)
		or value:find("shower", 1, true) then
		return ICONS.rain
	elseif value:find("cloud", 1, true) or value:find("overcast", 1, true)
		or value:find("mist", 1, true) or value:find("haze", 1, true) then
		return ICONS.cloudy
	end
	return ICONS.sunny
end

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
	if not cc or not cc.weatherDesc or not cc.weatherDesc[1] then
		return nil
	end

	local forecast = {}
	if data.weather then
		for _, day in ipairs(data.weather) do
			local f = { date = day.date or "" }
			if day.hourly and #day.hourly > 0 then
				local mid = day.hourly[math.max(1, math.floor(#day.hourly / 2))]
				f.tempMax = day.maxtempC or "--"
				f.tempMin = day.mintempC or "--"
				f.desc = mid.weatherDesc and mid.weatherDesc[1] and mid.weatherDesc[1].value or "--"
				f.icon = iconForCondition(f.desc)
			end
			forecast[#forecast + 1] = f
		end
	end

	return {
		city = city.name,
		temp = cc.temp_C or "--",
		cond = cc.weatherDesc[1].value or "Unknown",
		icon = iconForCondition(cc.weatherDesc[1].value),
		humid = cc.humidity or "--",
		wind = cc.windspeedKmph or "--",
		feelsLike = cc.FeelsLikeC or "--",
		visibility = cc.visibility or "--",
		pressure = cc.pressure or "--",
		uvIndex = cc.uvIndex or "--",
		cloudCover = cc.cloudcover or "--",
		precip = cc.precipMM or "--",
		windDir = cc.winddir16Point or "--",
		windDegree = cc.winddirDegree or "--",
		observationTime = cc.observation_time or "--",
		localObsDate = cc.localObsDateTime or "--",
		areaName = cc.areaName and cc.areaName[1] and cc.areaName[1].value or city.name,
		region = cc.region and cc.region[1] and cc.region[1].value or "",
		country = cc.country and cc.country[1] and cc.country[1].value or "",
		latitude = cc.latitude or "--",
		longitude = cc.longitude or "--",
		forecast = forecast,
	}
end

return Model
