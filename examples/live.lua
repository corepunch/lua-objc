local stocks = {
	{ symbol = "AAPL",  name = "Apple Inc.",         price = 193.82, change = "+2.34" },
	{ symbol = "GOOGL", name = "Alphabet Inc.",      price = 141.15, change = "-0.81" },
	{ symbol = "MSFT",  name = "Microsoft Corp.",    price = 378.91, change = "+4.12" },
	{ symbol = "AMZN",  name = "Amazon.com Inc.",    price = 183.66, change = "+1.03" },
	{ symbol = "META",  name = "Meta Platforms Inc.", price = 476.09, change = "+7.55" },
	{ symbol = "TSLA",  name = "Tesla Inc.",         price = 248.50, change = "-3.21" },
	{ symbol = "NVDA",  name = "NVIDIA Corp.",       price = 821.44, change = "+12.36" },
	{ symbol = "JPM",   name = "JPMorgan Chase",     price = 198.73, change = "+0.44" },
	{ symbol = "V",     name = "Visa Inc.",           price = 279.20, change = "-1.10" },
	{ symbol = "WMT",   name = "Walmart Inc.",       price = 67.82,  change = "+0.27" },
}

local spinner = Spinner()
local status_text = Text "Starting up..."
local list = List {
	width = 600,
	height = 390,
	columns = {
		{ id = "symbol", title = "Sym" },
		{ id = "name",   title = "Name" },
		{ id = "price",  title = "Price" },
		{ id = "change", title = "Change" },
	},
}

local function fetch_stock(i)
	local s = stocks[i]
	local delay = 0.2 + math.random() * 0.6
	sleep(delay)

	local green = s.change:sub(1, 1) == "+"
	local arrow = green and "\226\150\178" or "\226\150\188"
	local change_str = arrow .. " " .. s.change .. "%"

	list:add_row{
		symbol = s.symbol,
		name = s.name,
		price = string.format("$%.2f", s.price),
		change = change_str,
	}
	status_text:set_text(
		string.format("Loaded %d/%d  (%s in %.2fs)",
			i, #stocks, s.symbol, delay))
end

local function run_ticker()
	status_text:set_text("Connecting to market data...")
	sleep(0.8)

	for i = 1, #stocks do
		fetch_stock(i)
	end

	status_text:set_text(
		string.format("\226\151\143  %d stocks  |  Last update: just now",
			#stocks))
	SpinnerStop(spinner)
end

Window {
	title = "Live Stock Ticker",
	width = 620,
	height = 480,
	VStack {
		HStack {
			spinner,
			Text "Market Data",
			Spacer(),
			status_text,
		},
		list,
	}
}

SpinnerStart(spinner)
async(run_ticker)
