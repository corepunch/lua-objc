local ns = require("AppKit")
local xml = require("ui.xml")
local Model = require("examples.stocks.Model")
local Views = require("examples.stocks.views.StockDetail")

local VIEWS = "examples/stocks/views/"
local LAYOUT = {
	chartWidth = 600,
	chartHeight = 118,
	chartLineWidth = 2,
	chartPadding = 3,
	searchHeight = 28,
	rowHeight = 32,
	symbolMinWidth = 72,
	priceWidth = 80,
	priceMinWidth = 72,
	changeWidth = 70,
	changeMinWidth = 64,
	sidebarPaddingHorizontal = 8,
	sidebarPaddingVertical = 10,
	sidebarSpacing = 8,
	sidebarWidth = 324,
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

local function decorate(data)
	local stock = {}
	for key, value in pairs(data) do stock[key] = value end
	stock.priceStr = money(stock.price)
	stock.openStr = money(stock.open)
	stock.prevCloseStr = money(stock.prevClose)
	stock.volumeStr = compactNumber(stock.volume)
	stock.dayRangeStr = money(stock.dailyLow) .. " – " .. money(stock.dailyHigh)
	stock.yearRangeStr = money(stock.fiftyTwoWeekLow) .. " – " .. money(stock.fiftyTwoWeekHigh)
	local gain = (stock.changePct or 0) >= 0
	stock.changeStr = (gain and "▲ " or "▼ ")
		.. string.format("%.2f%% Today", math.abs(stock.changePct or 0))
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
	}, Controller)
end

function Controller:visibleRows()
	local rows = {{
		_id = "news",
		symbol = "Business News",
		price = "",
		change = "",
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
				price = money(data.price),
				change = (gain and "▲ " or "▼ ")
					.. string.format("%.2f%%", math.abs(data.changePct or 0)),
			}
		end
	end
	return rows
end

function Controller:updateSidebar()
	self.stockList:replaceRows(self:visibleRows())
end

function Controller:showNews()
	self.detailPane:clearContainer()
	self.detailPane:add(Views.newsPage(Model.news))
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
	self.detailPane:clearContainer()
	self.detailPane:add(Views.stock(stock, self.chart))
	self.detailPane:layout()
end

function Controller:refresh()
	self.stockList:showLoading()
	local function load()
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
			{ id = "symbol", title = "Symbol", minWidth = LAYOUT.symbolMinWidth },
			{ id = "price", title = "Price", width = LAYOUT.priceWidth,
				minWidth = LAYOUT.priceMinWidth, alignment = "right" },
			{ id = "change", title = "Change", width = LAYOUT.changeWidth,
				minWidth = LAYOUT.changeMinWidth, alignment = "right" },
		},
	}
	self.sidebar = ns.VStack {
		flexGrow = 1,
		paddingHorizontal = LAYOUT.sidebarPaddingHorizontal,
		paddingVertical = LAYOUT.sidebarPaddingVertical,
		spacing = LAYOUT.sidebarSpacing,
		self.searchField,
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
