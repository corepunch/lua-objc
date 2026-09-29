local ns = require("AppKit")

local Model = {}

local ICONS = {
	sunny = "apps/weather/assets/sunny.svg",
	cloudy = "apps/weather/assets/cloudy.svg",
	rain = "apps/weather/assets/rain.svg",
	snow = "apps/weather/assets/snow.svg",
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
		table.insert(forecast, {
			date = date,
			tempMax = daily.temperature_2m_max and daily.temperature_2m_max[index] or "--",
			tempMin = daily.temperature_2m_min and daily.temperature_2m_min[index] or "--",
			desc = condition,
			icon = iconForCondition(condition),
			precipProbability = daily.precipitation_probability_max and daily.precipitation_probability_max[index] or "--",
			rain = daily.rain_sum and daily.rain_sum[index] or "--",
			wind = daily.windspeed_10m_max and daily.windspeed_10m_max[index] or "--",
			uvIndex = daily.uv_index_max and daily.uv_index_max[index] or "--",
		})
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

-- "2026-09-29" -> "Tue": forecast columns read by weekday.
function Model.weekday(date)
	local y, m, d = tostring(date or ""):match("^(%d+)-(%d+)-(%d+)$")
	if not y then return tostring(date or "") end
	return os.date("%a", os.time({year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12}))
end

local function withWeekdays(forecast)
	for _, day in ipairs(forecast or {}) do day.day = Model.weekday(day.date) end
	return forecast
end

-- Offline sample weather for `--showcase` (the promo reel captures it), so
-- captures are the same on every run and need no network.
local SHOWCASE = {
	London = {temp = 18, cond = "Partly cloudy", feels = 17, humid = 64, wind = 14, dir = "WSW", uv = 3, cloud = 40,
		area = "Westminster", region = "Greater London",
		days = {{21, 13, "Partly cloudy", 10}, {19, 12, "Rain", 70}, {17, 11, "Showers", 55}, {20, 12, "Clear", 5},
			{22, 14, "Clear", 0}, {21, 14, "Partly cloudy", 15}, {18, 12, "Rain", 60}}},
	Tokyo = {temp = 26, cond = "Clear", feels = 27, humid = 58, wind = 9, dir = "SE", uv = 6, cloud = 10,
		area = "Chiyoda", region = "Tokyo",
		days = {{28, 21, "Clear", 0}, {27, 21, "Partly cloudy", 10}, {25, 20, "Rain", 80}, {24, 19, "Showers", 45},
			{27, 20, "Clear", 5}, {28, 21, "Clear", 0}, {26, 20, "Partly cloudy", 20}}},
	["San Francisco"] = {temp = 17, cond = "Foggy", feels = 16, humid = 82, wind = 19, dir = "W", uv = 4, cloud = 75,
		area = "Mission District", region = "California",
		days = {{19, 13, "Foggy", 5}, {21, 13, "Partly cloudy", 0}, {23, 14, "Clear", 0}, {22, 14, "Clear", 0},
			{20, 13, "Foggy", 5}, {19, 12, "Partly cloudy", 10}, {18, 12, "Foggy", 10}}},
	Sydney = {temp = 21, cond = "Clear", feels = 21, humid = 55, wind = 17, dir = "NE", uv = 7, cloud = 5,
		area = "Surry Hills", region = "New South Wales",
		days = {{23, 15, "Clear", 0}, {24, 16, "Clear", 0}, {22, 15, "Partly cloudy", 10}, {19, 14, "Showers", 60},
			{20, 13, "Partly cloudy", 20}, {22, 14, "Clear", 0}, {24, 16, "Clear", 0}}},
	Berlin = {temp = 15, cond = "Cloudy", feels = 14, humid = 71, wind = 12, dir = "NW", uv = 2, cloud = 90,
		area = "Mitte", region = "Berlin",
		days = {{16, 9, "Cloudy", 20}, {14, 8, "Rain", 75}, {13, 7, "Showers", 50}, {15, 8, "Partly cloudy", 15},
			{17, 9, "Clear", 0}, {16, 10, "Partly cloudy", 10}, {14, 9, "Rain", 65}}},
	Reykjavik = {temp = 7, cond = "Snow", feels = 3, humid = 88, wind = 28, dir = "N", uv = 1, cloud = 95,
		area = "Miðborg", region = "Capital Region",
		days = {{8, 3, "Snow", 70}, {7, 2, "Snow", 60}, {9, 4, "Cloudy", 30}, {10, 5, "Rain", 55},
			{8, 3, "Cloudy", 20}, {6, 1, "Snow", 65}, {7, 2, "Cloudy", 25}}},
}

-- The showcase reading for `city`, in the shape fetchCity returns; the
-- cities without one reuse London's, renamed.
function Model.showcaseCity(city)
	local s = SHOWCASE[city.name] or SHOWCASE.London
	local forecast = {}
	for index, day in ipairs(s.days) do
		table.insert(forecast, {date = string.format("2026-09-%02d", 28 + index), tempMax = day[1], tempMin = day[2],
			desc = day[3], icon = iconForCondition(day[3]), precipProbability = day[4]})
	end
	return {
		city = city.name, temp = s.temp, cond = s.cond, icon = iconForCondition(s.cond), humid = s.humid,
		wind = s.wind, feelsLike = s.feels, visibility = 10, pressure = 1016, uvIndex = s.uv, cloudCover = s.cloud,
		precip = "0.0", windDir = s.dir, observationTime = "09:41 AM", areaName = s.area, region = s.region,
		forecast = withWeekdays(forecast),
	}
end

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
			table.insert(forecast, f)
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
	result.forecast = withWeekdays(openMeteoForecast(result.latitude, result.longitude) or forecast)
	return result
end

return Model
