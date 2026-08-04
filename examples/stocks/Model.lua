local ns = require("AppKit")

local Model = {}

Model.symbols = {
	"^IXIC", "AAPL", "GOOGL", "MSFT", "AMZN", "META",
	"TSLA", "NVDA", "JPM", "V",  "WMT",
}

local STOCKS = {
	["^IXIC"] = { name = "NASDAQ Composite", price = 21178.58 },
	AAPL = { name = "Apple Inc.", price = 229.35 },
	GOOGL = { name = "Alphabet Inc.", price = 196.52 },
	MSFT = { name = "Microsoft Corporation", price = 527.75 },
	AMZN = { name = "Amazon.com, Inc.", price = 230.19 },
	META = { name = "Meta Platforms, Inc.", price = 769.30 },
	TSLA = { name = "Tesla, Inc.", price = 309.26 },
	NVDA = { name = "NVIDIA Corporation", price = 180.00 },
	JPM = { name = "JPMorgan Chase & Co.", price = 295.77 },
	V = { name = "Visa Inc.", price = 337.54 },
	WMT = { name = "Walmart Inc.", price = 102.74 },
}

Model.news = {
	{ title = "Markets rise as technology shares lead a broad afternoon rally", source = "Reuters", time = "12m", symbols = {"^IXIC", "MSFT", "NVDA"} },
	{ title = "Apple suppliers prepare for the next wave of device upgrades", source = "Bloomberg", time = "28m", symbols = {"AAPL"} },
	{ title = "Chip demand remains strong as data-center investment accelerates", source = "CNBC", time = "44m", symbols = {"NVDA", "MSFT", "GOOGL"} },
	{ title = "Amazon expands same-day delivery to more regional markets", source = "The Wall Street Journal", time = "1h", symbols = {"AMZN"} },
	{ title = "Banks gain as investors assess the path for interest rates", source = "Financial Times", time = "2h", symbols = {"JPM", "V"} },
	{ title = "Meta outlines new tools for businesses and creators", source = "The Verge", time = "2h", symbols = {"META"} },
	{ title = "Electric-vehicle makers report steadier demand into the quarter", source = "Associated Press", time = "3h", symbols = {"TSLA"} },
	{ title = "Retail spending holds firm ahead of the back-to-school season", source = "MarketWatch", time = "4h", symbols = {"WMT", "AMZN", "V"} },
}

local function contains(values, needle)
	for _, value in ipairs(values or {}) do
		if value == needle then return true end
	end
	return false
end

function Model.newsFor(symbol, limit)
	local result = {}
	local included = {}
	for _, article in ipairs(Model.news) do
		if not symbol or contains(article.symbols, symbol) or symbol == "^IXIC" then
			result[#result + 1] = article
			included[article] = true
			if limit and #result >= limit then break end
		end
	end
	-- A company page should never collapse to one sparse story merely because
	-- the remaining market coverage is broader than that ticker.
	if limit and #result < limit then
		for _, article in ipairs(Model.news) do
			if not included[article] then
				result[#result + 1] = article
				if #result >= limit then break end
			end
		end
	end
	return result
end

function Model.sampleStock(symbol)
	local info = STOCKS[symbol] or { name = symbol, price = 100 }
	local seed = 0
	for i = 1, #symbol do seed = seed + symbol:byte(i) end
	local previous = info.price * (0.994 + (seed % 9) / 1000)
	local chartData = {}
	for point = 1, 79 do
		local progress = (point - 1) / 78
		local drift = (info.price - previous) * progress
		local wave = math.sin(point * 0.31 + seed) * info.price * 0.0018
		chartData[point] = previous + drift + wave
	end
	chartData[#chartData] = info.price
	return {
		symbol = symbol,
		name = info.name,
		price = info.price,
		prevClose = previous,
		changePct = ((info.price - previous) / previous) * 100,
		dailyHigh = info.price * 1.006,
		dailyLow = info.price * 0.991,
		volume = 48219300 + seed * 1000,
		open = previous * 1.001,
		marketCap = symbol == "^IXIC" and nil or info.price * 15200000000,
		fiftyTwoWeekHigh = info.price * 1.18,
		fiftyTwoWeekLow = info.price * 0.71,
		chartData = chartData,
		news = Model.newsFor(symbol, 4),
	}
end

function Model.fetchStock(symbol)
	local url = "https://query1.finance.yahoo.com/v8/finance/chart/"
		.. symbol .. "?interval=5m&range=1d"

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

	local chartData = nil
	if entry.indicators then
		local quote = entry.indicators.quote
		if quote and #quote > 0 and quote[1].close then
			local raw = quote[1].close
			chartData = {}
			local count = entry.timestamp and #entry.timestamp or 0
			if count == 0 then
				for key in pairs(raw) do
					if type(key) == "number" and key > count then count = key end
				end
			end
			for index = 1, count do
				local v = raw[index]
				if v ~= nil then
					chartData[#chartData + 1] = v
				end
			end
		end
	end

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
		chartData = chartData,
		news = Model.newsFor(symbol, 4),
	}
end

return Model
