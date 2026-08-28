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

local function conditionForCode(code)
	code = tonumber(code)
	if not code then return "Unknown" end
	if code == 0 then return "Clear" end
	if code <= 3 then return "Partly cloudy" end
	if code <= 48 then return "Foggy" end
	if code <= 57 then return "Drizzle" end
	if code <= 67 then return "Rain" end
	if code <= 77 then return "Snow" end
	if code <= 82 then return "Showers" end
	return "Stormy"
end

local function openMeteoForecast(latitude, longitude)
	if not latitude or not longitude then return nil end
	local url = string.format(
		"https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,rain_sum,windspeed_10m_max,uv_index_max&forecast_days=7&timezone=auto",
		tostring(latitude), tostring(longitude))
	local ok, data = pcall(ns.fetch_json, url)
	local daily = ok and data and data.daily
	if not daily or not daily.time then return nil end

	local forecast = {}
	for index, date in ipairs(daily.time) do
		local condition = conditionForCode(daily.weather_code and daily.weather_code[index])
		forecast[#forecast + 1] = {
			date = date,
			tempMax = daily.temperature_2m_max and daily.temperature_2m_max[index] or "--",
			tempMin = daily.temperature_2m_min and daily.temperature_2m_min[index] or "--",
			desc = condition,
			icon = iconForCondition(condition),
			precipProbability = daily.precipitation_probability_max and daily.precipitation_probability_max[index] or "--",
			rain = daily.rain_sum and daily.rain_sum[index] or "--",
			wind = daily.windspeed_10m_max and daily.windspeed_10m_max[index] or "--",
			uvIndex = daily.uv_index_max and daily.uv_index_max[index] or "--",
		}
	end
	return #forecast > 0 and forecast or nil
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
	local nearest = data.nearest_area and data.nearest_area[1] or {}
	local nearestValue = function(key, fallback)
		local values = nearest[key]
		if type(values) == "string" or type(values) == "number" then
			return values
		end
		return values and values[1] and (values[1].value or values[1]) or fallback
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

	local result = {
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
		areaName = cc.areaName and cc.areaName[1] and cc.areaName[1].value or nearestValue("areaName", city.name),
		region = cc.region and cc.region[1] and cc.region[1].value or nearestValue("region", ""),
		country = cc.country and cc.country[1] and cc.country[1].value or nearestValue("country", ""),
		latitude = cc.latitude or nearestValue("latitude", "--"),
		longitude = cc.longitude or nearestValue("longitude", "--"),
		forecast = forecast,
	}
	result.forecast = openMeteoForecast(result.latitude, result.longitude) or forecast
	return result
end

return Model
