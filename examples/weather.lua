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

local spinner = ui.Spinner()
local status_text = ui.Text "Initializing..."
local list = ui.List {
	width = 660,
	height = 430,
	columns = {
		{ id = "city",  title = "City" },
		{ id = "temp",  title = "Temp" },
		{ id = "cond",  title = "Conditions" },
		{ id = "humid", title = "Humidity" },
		{ id = "wind",  title = "Wind" },
	},
}

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
	status_text:set_text("Fetching weather data...")
	ui.sleep(0.3)

	for i, city in ipairs(cities) do
		fetch_city(city)
		status_text:set_text(
			string.format("Loading %d/%d  \226\154\128 %s",
				i, #cities, city.name))
		ui.sleep(0.15)
	end

	status_text:set_text(
		string.format("\226\154\136  %d cities  \226\128\162  live from wttr.in",
			#cities))
	ui.SpinnerStop(spinner)
end

ui.Window {
	title = "World Weather  \226\140\136",
	width = 680,
	height = 500,
	ui.VStack {
		ui.HStack {
			spinner,
			status_text,
			ui.Spacer(),
		},
		list,
	}
}

status_text:set_text("Connecting...")
ui.SpinnerStart(spinner)
ui.async(run)
