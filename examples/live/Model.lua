local ns = require("AppKit")

local Model = {}

Model.symbols = {
	"AAPL", "GOOGL", "MSFT", "AMZN", "META",
	"TSLA", "NVDA", "JPM", "V",  "WMT",
}

function Model.fetchStock(symbol)
	local url = "https://query1.finance.yahoo.com/v8/finance/chart/"
		.. symbol .. "?interval=1d&range=1d"

	local ok, data = pcall(ns.fetch_json, url)
	if not ok or not data then
		return nil
	end

	local results = data.chart and data.chart.result
	if not results or #results == 0 then
		return nil
	end

	local entry = results[1]
	local meta = entry.meta
	if not meta then
		return nil
	end

	local price = meta.regularMarketPrice
	local prev = meta.chartPreviousClose
	local name = meta.shortName or meta.longName or symbol

	if not price or not prev or prev == 0 then
		return nil
	end

	local change = ((price - prev) / prev) * 100
	local dailyHigh = meta.regularMarketDayHigh
	local dailyLow = meta.regularMarketDayLow
	local volume = meta.regularMarketVolume
	local previousClose = meta.chartPreviousClose
	local open = meta.regularMarketOpen
	local marketCap = meta.marketCap
	local fiftyTwoWeekHigh = meta.fiftyTwoWeekHigh
	local fiftyTwoWeekLow = meta.fiftyTwoWeekLow

	return {
		symbol = symbol,
		name = name,
		price = price,
		prevClose = prev,
		changePct = change,
		dailyHigh = dailyHigh,
		dailyLow = dailyLow,
		volume = volume,
		open = open,
		marketCap = marketCap,
		fiftyTwoWeekHigh = fiftyTwoWeekHigh,
		fiftyTwoWeekLow = fiftyTwoWeekLow,
	}
end

return Model
