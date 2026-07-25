local ns = require("AppKit")

local symbols = {
	"AAPL", "GOOGL", "MSFT", "AMZN", "META",
	"TSLA", "NVDA", "JPM", "V",  "WMT",
}

local function fetch_stock(list, symbol)
	local url = "https://query1.finance.yahoo.com/v8/finance/chart/"
		.. symbol .. "?interval=1d&range=1d"

	local ok, data = pcall(ns.fetch_json, url)
	if not ok or not data then
		list:addRow{ symbol = symbol, name = symbol,
			price = "--", change = "\226\128\148" }
		return
	end

	local results = data.chart and data.chart.result
	if not results or #results == 0 then
		list:addRow{ symbol = symbol, name = symbol,
			price = "--", change = "\226\128\148" }
		return
	end

	local meta = results[1].meta
	if not meta then
		list:addRow{ symbol = symbol, name = symbol,
			price = "--", change = "\226\128\148" }
		return
	end

	local price = meta.regularMarketPrice
	local prev = meta.chartPreviousClose
	local name = meta.shortName or meta.longName or symbol

	if not price or not prev or prev == 0 then
		list:addRow{ symbol = symbol, name = name,
			price = "--", change = "\226\128\148" }
		return
	end

	local change = ((price - prev) / prev) * 100
	local arrow = change >= 0 and "\226\150\178" or "\226\150\188"

	list:addRow{
		symbol = symbol,
		name = name,
		price = string.format("$%.2f", price),
		change = arrow .. " " .. string.format("%.2f%%", math.abs(change)),
	}
end

local list = ns.List {
	width = 600,
	height = 390,
	columns = {
		{ id = "symbol", title = "Symbol", width = 100 },
		{ id = "name",   title = "Name",   width = 220 },
		{ id = "price",  title = "Price",  width = 120, alignment = "trailing" },
		{ id = "change", title = "Change", width = 140, alignment = "trailing" },
	},
	refresh = function(l)
		for _, sym in ipairs(symbols) do
			fetch_stock(l, sym)
		end
	end,
}

ns.Window {
	title = "Live Stock Ticker",
	width = 620,
	height = 480,
	toolbar = {
		{
			id = "refresh",
			label = "Refresh",
			icon = "arrow.clockwise",
			tooltip = "Refresh market data",
			action = function()
				list:refresh()
			end,
		},
	},
	list,
}

list:refresh()
