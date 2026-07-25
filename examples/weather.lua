local ui = require("luaui")

local function fetch_json(url)
	local cmd = "curl -s --max-time 10 '" .. url .. "' 2>/dev/null"
	local handle = io.popen(cmd)
	if not handle then return nil, "popen failed" end
	local body = handle:read("*a")
	handle:close()
	if not body or body == "" then return nil, "empty response" end

	body = body:gsub("null", "nil")
	local fn, err = load("return " .. body)
	if not fn then return nil, "parse: " .. tostring(err) end

	local ok, result = pcall(fn)
	if not ok then return nil, "eval: " .. tostring(result) end
	return result
end

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

local list = ui.List {
	width = 660,
	height = 430,
	columns = {
		{ id = "city",  title = "City",        width = 130 },
		{ id = "temp",  title = "Temperature", width = 110, alignment = "trailing" },
		{ id = "cond",  title = "Conditions",  width = 180 },
		{ id = "humid", title = "Humidity",    width = 100, alignment = "trailing" },
		{ id = "wind",  title = "Wind",        width = 120, alignment = "trailing" },
	},
}

local window
local refresh_progress
local is_loading = false

local function fetch_city(city)
	local url = "https://wttr.in/" .. city.query .. "?format=j1"
	local data, err = fetch_json(url)
	if not data or not data.current_condition then
		list:add_row{
			city = city.name,
			temp = "\226\154\160",
			cond = err or "unreachable",
			humid = "-",
			wind = "-",
		}
		return
	end

	local cc = data.current_condition[1]
	local wd = cc.weatherDesc[1].value

	list:add_row{
		city = city.name,
		temp = cc.temp_C .. "\194\176C",
		cond = wd,
		humid = cc.humidity .. "%",
		wind = cc.windspeedKmph .. " km/h",
	}
end

local function run()
	ui.sleep(0.3)

	for _, city in ipairs(cities) do
		fetch_city(city)
		ui.sleep(0.15)
	end

	refresh_progress:stop("Refresh weather — last updated just now")
	is_loading = false
end

local function refresh()
	if is_loading then return end
	is_loading = true
	list:clear_rows()
	refresh_progress:start("Refreshing weather")
	ui.async(run)
end

window = ui.Window {
	title = "World Weather",
	width = 680,
	height = 500,
	toolbar = {
		{
			id = "refresh",
			label = "Refresh",
			icon = "arrow.clockwise",
			tooltip = "Refresh weather",
			action = refresh,
		},
	},
	list,
}

refresh_progress = ui.ToolbarProgress(window, "refresh")
refresh()
