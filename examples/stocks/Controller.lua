local ns = require("AppKit")
local xml = require("ui.xml")
local Model = require("examples.stocks.Model")

local VIEWS = "examples/stocks/views/"
local LAYOUT = {
	chartWidth = 600,
	chartHeight = 118,
	chartLineWidth = 2,
	chartPadding = 3,
	searchHeight = 36,
	rowHeight = 58,
	symbolMinWidth = 96,
	sidebarChartWidth = 68,
	quoteWidth = 96,
	searchPaddingHorizontal = 8,
	sidebarPaddingVertical = 4,
	sidebarSpacing = 8,
	sidebarWidth = 342,
	gainColor = {0.16, 0.68, 0.32},
	lossColor = {0.86, 0.24, 0.25},
}

local Controller = {}
Controller.__index = Controller

local function money(value)
	if value == nil then return "--" end
	return string.format("$%.2f", value)
end

local function compactNumber(value)
	if value == nil then return "--" end
	if value >= 1e12 then return string.format("%.2fT", value / 1e12) end
	if value >= 1e9 then return string.format("%.2fB", value / 1e9) end
	if value >= 1e6 then return string.format("%.2fM", value / 1e6) end
	return string.format("%.0f", value)
end

local function precomputeMetrics(stock)
	return {
		{
			{"Open", stock.openStr},
			{"High", stock.dailyHighStr},
			{"Low", stock.dailyLowStr},
		},
		{
			{"Vol", stock.volumeStr},
			{"P/E", "--"},
			{"Mkt Cap", stock.marketCapStr},
		},
		{
			{"52W H", stock.fiftyTwoWeekHighStr},
			{"52W L", stock.fiftyTwoWeekLowStr},
			{"Avg Vol", stock.volumeStr},
		},
		{
			{"Yield", "--"},
			{"Beta", "--"},
			{"EPS", "--"},
		},
	}
end

local function precomputeNewsColumns(articles)
	local columns = {{}, {}}
	for index, article in ipairs(articles or {}) do
		columns[(index - 1) % 2 + 1][#columns[(index - 1) % 2 + 1] + 1] = article
	end
	return columns
end

local function decorate(data)
	local stock = {}
	for key, value in pairs(data) do stock[key] = value end
	stock.priceStr = money(stock.price)
	stock.openStr = money(stock.open)
	stock.prevCloseStr = money(stock.prevClose)
	stock.volumeStr = compactNumber(stock.volume)
	stock.dailyHighStr = money(stock.dailyHigh)
	stock.dailyLowStr = money(stock.dailyLow)
	stock.marketCapStr = compactNumber(stock.marketCap)
	stock.dayRangeStr = money(stock.dailyLow) .. " – " .. money(stock.dailyHigh)
	stock.yearRangeStr = money(stock.fiftyTwoWeekLow) .. " – " .. money(stock.fiftyTwoWeekHigh)
	stock.fiftyTwoWeekHighStr = money(stock.fiftyTwoWeekHigh)
	stock.fiftyTwoWeekLowStr = money(stock.fiftyTwoWeekLow)
	local gain = (stock.changePct or 0) >= 0
	stock.changeStr = string.format("%+.2f%% Today", stock.changePct or 0)
	stock.changeColor = gain and "systemGreen" or "systemRed"
	return stock
end

function Controller.new()
	return setmetatable({
		stockList = nil,
		searchField = nil,
		sidebar = nil,
		detailPane = nil,
		stockData = {},
		selectedSymbol = "^IXIC",
		query = "",
		window = nil,
		chart = nil,
		generalNews = nil,
	}, Controller)
end

function Controller:visibleRows()
	local rows = {{
		_id = "news",
		symbol = "Business News",
		name = "Latest market stories",
		price = "",
		change = "",
		chartData = {},
	}}
	local query = self.query:lower()
	for _, symbol in ipairs(Model.symbols) do
		local data = self.stockData[symbol] or Model.sampleStock(symbol)
		if query == "" or symbol:lower():find(query, 1, true)
			or data.name:lower():find(query, 1, true) then
			local gain = (data.changePct or 0) >= 0
			rows[#rows + 1] = {
				_id = symbol,
				symbol = symbol,
				name = data.name,
				price = money(data.price),
				change = string.format("%+.2f%%", data.changePct or 0),
				changeColor = gain and "systemGreen" or "systemRed",
				chartData = data.chartData or {},
			}
		end
	end
	return rows
end

function Controller:updateSidebar()
	self.stockList:replaceRows(self:visibleRows())
end

function Controller:showNews()
	local articles = self.generalNews
	if not articles or #articles == 0 then
		articles = Model.sampleNews(nil, 8)
	end
	local view = xml.renderFile(VIEWS .. "NewsPage.etlua", {
		newsColumns = precomputeNewsColumns(articles),
	})
	self.detailPane:clearContainer()
	self.detailPane:add(view)
	self.detailPane:layout()
end

function Controller:showDetail(data)
	if not data then return end
	local stock = decorate(data)
	local gain = (stock.changePct or 0) >= 0
	self.chart = ns.Curve {
		data = stock.chartData,
		width = LAYOUT.chartWidth,
		height = LAYOUT.chartHeight,
		fixedHeight = LAYOUT.chartHeight,
		fillWidth = true,
		strokeColor = gain and LAYOUT.gainColor or LAYOUT.lossColor,
		lineWidth = LAYOUT.chartLineWidth,
		chartPadding = LAYOUT.chartPadding,
		fillArea = false,
	}
	stock.metricColumns = precomputeMetrics(stock)
	stock.newsColumns = precomputeNewsColumns(stock.news)
	local view = xml.renderFile(VIEWS .. "StockDetail.etlua", {
		stock = stock,
		chart = self.chart,
	})
	self.detailPane:clearContainer()
	self.detailPane:add(view)
	self.detailPane:layout()
end

function Controller:refresh()
	self.stockList:showLoading()
	local function load()
		local generalNews = Model.fetchNews("^IXIC", 10)
		if generalNews and #generalNews > 0 then
			self.generalNews = generalNews
		end
		for _, symbol in ipairs(Model.symbols) do
			local data
			if not _G.__headless then data = Model.fetchStock(symbol) end
			self.stockData[symbol] = data or self.stockData[symbol]
				or Model.sampleStock(symbol)
		end
		self:updateSidebar()
		if self.detailPane then
			if self.selectedSymbol == "news" then
				self:showNews()
			else
				self:showDetail(self.stockData[self.selectedSymbol])
			end
		end
		self.stockList:hideLoading()
	end
	if _G.__headless then load() else ns.async(load) end
end

function Controller:createWindow()
	local cfg = xml.renderFile(VIEWS .. "Window.etlua")
	for _, item in ipairs(cfg.toolbar or {}) do
		if item.id == "refresh" then
			item.action = function() self:refresh() end
		end
	end

	self.searchField = ns.SearchField {
		placeholder = "Search",
		accessibilityLabel = "Search stocks",
		controlSize = "extraLarge",
		fixedHeight = LAYOUT.searchHeight,
		fillWidth = true,
		onChange = function(query)
			self.query = query
			self:updateSidebar()
		end,
	}
	self.stockList = ns.List {
		flexGrow = 1,
		fillWidth = true,
		style = "sourceList",
		header = false,
		alternatingRows = false,
		rowHeight = LAYOUT.rowHeight,
		columns = {
			{ id = "symbol", title = "Symbol", minWidth = LAYOUT.symbolMinWidth,
				cell = { secondary = "name", weight = "semibold" } },
			{ id = "chartData", title = "Day", width = LAYOUT.sidebarChartWidth,
				cell = { curve = "chartData", curveColor = "changeColor" } },
			{ id = "price", title = "Quote", width = LAYOUT.quoteWidth,
				alignment = "right",
				cell = { secondary = "change",
					secondaryColor = "changeColor", weight = "semibold" } },
		},
	}
	self.searchContainer = ns.VStack {
		fillWidth = true,
		fixedHeight = LAYOUT.searchHeight,
		flexShrink = 0,
		paddingHorizontal = LAYOUT.searchPaddingHorizontal,
		self.searchField,
	}
	self.sidebar = ns.VStack {
		flexGrow = 1,
		paddingVertical = LAYOUT.sidebarPaddingVertical,
		spacing = LAYOUT.sidebarSpacing,
		self.searchContainer,
		self.stockList,
	}
	self.detailPane = ns.VStack { flexGrow = 1 }
	cfg.sidebar = self.sidebar
	cfg.content = self.detailPane
	cfg.sidebarWidth = LAYOUT.sidebarWidth

	self.stockList:onRowSelect(function(_, _, row)
		if not row or not row._id then return end
		self.selectedSymbol = row._id
		if row._id == "news" then
			self:showNews()
		else
			self:showDetail(self.stockData[row._id] or Model.sampleStock(row._id))
		end
	end)

	for _, symbol in ipairs(Model.symbols) do
		self.stockData[symbol] = Model.sampleStock(symbol)
	end
	self:updateSidebar()
	self:showDetail(self.stockData[self.selectedSymbol])
	self.window = ns.Window(cfg)
	self:refresh()
	return self.window
end

return Controller
