local Model = {}

Model.symbols = {
	"AAPL", "GOOGL", "MSFT", "AMZN", "META",
	"TSLA", "NVDA", "JPM", "V",  "WMT",
}

function Model.fetchStock(list, symbol)
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

return Model
