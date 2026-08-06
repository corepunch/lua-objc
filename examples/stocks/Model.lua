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

local SAMPLE_NEWS = {
	{ title = "Markets rise as technology shares lead a broad afternoon rally", source = "Reuters", time = "12m", symbols = {"^IXIC", "MSFT", "NVDA"},
		summary = "The S&P 500 and Nasdaq both climbed more than 1% as chipmakers and software names led gains. Investor sentiment improved after the latest inflation data came in below expectations." },
	{ title = "Apple suppliers prepare for the next wave of device upgrades", source = "Bloomberg", time = "28m", symbols = {"AAPL"},
		summary = "Key component manufacturers are ramping production ahead of Apple's fall product launches. Analysts expect a strong upgrade cycle driven by new AI features across the iPhone and Mac lineups." },
	{ title = "Chip demand remains strong as data-center investment accelerates", source = "CNBC", time = "44m", symbols = {"NVDA", "MSFT", "GOOGL"},
		summary = "Cloud providers continue to expand their infrastructure, fueling demand for high-performance processors. Orders for next-generation AI accelerators remain well above supply through mid-year." },
	{ title = "Amazon expands same-day delivery to more regional markets", source = "The Wall Street Journal", time = "1h", symbols = {"AMZN"},
		summary = "The e-commerce giant is adding dozens of metro areas to its same-day delivery network. The move puts pressure on traditional retailers already struggling with logistics costs." },
	{ title = "Banks gain as investors assess the path for interest rates", source = "Financial Times", time = "2h", symbols = {"JPM", "V"},
		summary = "Financial shares rose broadly after Fed officials signaled a measured approach to future rate adjustments. Higher-for-longer rates continue to support net interest margins across the sector." },
	{ title = "Meta outlines new tools for businesses and creators", source = "The Verge", time = "2h", symbols = {"META"},
		summary = "The company announced a suite of AI-powered advertising and content tools at its annual developer event. Early testing shows improved click-through rates for targeted campaigns." },
	{ title = "Electric-vehicle makers report steadier demand into the quarter", source = "Associated Press", time = "3h", symbols = {"TSLA"},
		summary = "Several automakers posted delivery numbers that topped lowered expectations, signaling that demand may be stabilizing. Price cuts earlier in the year helped clear inventory across key markets." },
	{ title = "Retail spending holds firm ahead of the back-to-school season", source = "MarketWatch", time = "4h", symbols = {"WMT", "AMZN", "V"},
		summary = "Consumer spending data showed resilience as households began early back-to-school shopping. Discount retailers and online platforms reported stronger-than-expected foot traffic and order volumes." },
}

local function contains(values, needle)
	for _, value in ipairs(values or {}) do
		if value == needle then return true end
	end
	return false
end

local function sampleNews(symbol, limit)
	local result = {}
	local included = {}
	for _, article in ipairs(SAMPLE_NEWS) do
		if not symbol or contains(article.symbols, symbol) or symbol == "^IXIC" then
			result[#result + 1] = article
			included[article] = true
			if limit and #result >= limit then break end
		end
	end
	if limit and #result < limit then
		for _, article in ipairs(SAMPLE_NEWS) do
			if not included[article] then
				result[#result + 1] = article
				if #result >= limit then break end
			end
		end
	end
	return result
end

Model.sampleNews = sampleNews

-- Yahoo Finance news API with crumb-based auth.
-- NSURLSession.sharedSession cookies are shared across calls within the same
-- coroutine, so the fc.yahoo.com → getcrumb → quoteSummary flow works
-- transparently.

local CRUMB_URL = "https://query2.finance.yahoo.com/v1/test/getcrumb"
local COOKIE_URL = "https://fc.yahoo.com/"
local NEWS_URL_FMT = "https://query2.finance.yahoo.com/v10/finance/quoteSummary/%s?modules=news"
local CHART_URL_FMT = "https://query1.finance.yahoo.com/v8/finance/chart/%s?interval=5m&range=1d"

local crumbCache = nil

local function getCrumb()
	if crumbCache then return crumbCache end
	pcall(ns.fetch, COOKIE_URL)
	local ok, raw = pcall(ns.fetch, CRUMB_URL)
	if not ok or not raw then return nil end
	raw = raw:match("^%s*(.-)%s*$") or ""
	if #raw == 0 then return nil end
	crumbCache = raw
	return raw
end

local function relativeTime(unixTime)
	local now = os.time()
	local diff = math.max(0, now - unixTime)
	if diff < 60 then return "Just now" end
	if diff < 3600 then return math.floor(diff / 60) .. "m" end
	if diff < 86400 then return math.floor(diff / 3600) .. "h" end
	return math.floor(diff / 86400) .. "d"
end

function Model.fetchNews(symbol, count)
	if _G.__headless then return nil end
	local crumb = getCrumb()
	if not crumb then return nil end
	local url = string.format(NEWS_URL_FMT, symbol) .. "&crumb=" .. crumb
	local ok, data = pcall(ns.fetch_json, url)
	if not ok or not data then
		crumbCache = nil
		return nil
	end
	local result = data.quoteSummary and data.quoteSummary.result
	if not result or #result == 0 then return nil end
	local newsItems = result[1].news
	if not newsItems then return nil end
	local articles = {}
	for i, n in ipairs(newsItems) do
		if count and i > count then break end
		articles[#articles + 1] = {
			title = n.title or "",
			source = n.publisher or "",
			summary = n.description or "",
			time = n.providerPublishTime and relativeTime(n.providerPublishTime) or "",
			symbols = n.relatedTickers or {},
		}
	end
	return #articles > 0 and articles or nil
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
		news = sampleNews(symbol, 4),
	}
end

function Model.fetchStock(symbol)
	local url = string.format(CHART_URL_FMT, symbol)

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

	local news = Model.fetchNews(symbol, 4)
	if not news or #news == 0 then
		news = sampleNews(symbol, 4)
	end

	return {
		symbol = symbol,
		name = name,
		price = price,
		prevClose = prev,
		changePct = change,
		dailyHigh = meta.regularMarketDayHigh,
		dailyLow = meta.regularMarketDayLow,
		volume = meta.regularMarketVolume,
		open = meta.regularMarketOpen,
		marketCap = meta.marketCap,
		fiftyTwoWeekHigh = meta.fiftyTwoWeekHigh,
		fiftyTwoWeekLow = meta.fiftyTwoWeekLow,
		chartData = chartData,
		news = news,
	}
end

return Model
