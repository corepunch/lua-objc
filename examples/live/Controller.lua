local ns    = require("AppKit")
local xml   = require("ui.xml")
local Model = require("examples.live.Model")

local VIEWS = "examples/live/views/"

local ACTIONS = {
	refresh = function(self) self:refresh() end,
}

local function buildStockList()
	return ns.List {
		flexGrow = 1,
		style = "fullWidth",
		alternatingRows = false,
		columns = {
			{ id = "symbol", title = "Symbol", width = 100 },
			{ id = "name", title = "Name", width = 200 },
			{ id = "price", title = "Price", width = 120, alignment = "right" },
			{ id = "change", title = "Change", width = 140, alignment = "right" },
		},
	}
end

local function buildDetailPane()
	return ns.VStack {
		flexGrow = 1,
	}
end

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({
		stockList = nil,
		detailPane = nil,
		stockData = {},
		selectedSymbol = nil,
		window = nil,
	}, Controller)
end

function Controller:refresh()
	-- The table owns the native indeterminate spinner, just like SwiftUI's
	-- ProgressView or React Native's ActivityIndicator. Keep the table in place
	-- while the coroutine suspends for each HTTP request.
	self.stockList:showLoading()
	self.stockList:clearRows()

	ns.async(function()
		local ok, err = pcall(function()
			self.stockData = {}
			local rows = {}

			for _, symbol in ipairs(Model.symbols) do
				local data = Model.fetchStock(symbol)
				self.stockData[symbol] = data
				if data then
					local arrow = data.changePct >= 0 and "▲" or "▼"
					rows[#rows + 1] = {
						_id = symbol,
						symbol = symbol,
						name = data.name,
						price = string.format("$%.2f", data.price),
						change = arrow .. " " .. string.format("%.2f%%", math.abs(data.changePct)),
					}
				else
					rows[#rows + 1] = {
						_id = symbol,
						symbol = symbol,
						name = symbol,
						price = "--",
						change = "—",
					}
				end
			end

			self.stockList:replaceRows(rows)

			if self.selectedSymbol then
				self:showDetail(self.stockData[self.selectedSymbol])
			end
		end)

		-- Always stop the native spinner, including when a request or response
		-- parser fails. A failed refresh leaves the table empty and retryable.
		self.stockList:hideLoading()
		if not ok then
			io.stderr:write("refresh error: " .. tostring(err) .. "\n")
		end
	end)
end

local function fmt(val, dec)
	if val == nil then return "--" end
	return string.format("$%." .. (dec or 2) .. "f", val)
end

local function fmtVolume(val)
	if val == nil then return "--" end
	return string.format("%.0f", val)
end

function Controller:showLoading()
	self.detailPane:clearContainer()
	local spinner = ns.ProgressView { flexGrow = 1 }
	self.detailPane:add(ns.VStack {
		flexGrow = 1,
		alignment = "center",
		spinner,
	})
	self.detailPane:layout()
	spinner:start()
end

function Controller:showDetail(data)
	self.detailPane:clearContainer()
	if data then
		local stock = {}
		for k, v in pairs(data) do stock[k] = v end
		stock.priceStr = fmt(stock.price)
		stock.openStr = fmt(stock.open)
		stock.prevCloseStr = fmt(stock.prevClose)
		stock.dailyHighStr = fmt(stock.dailyHigh)
		stock.dailyLowStr = fmt(stock.dailyLow)
		stock.marketCapStr = stock.marketCap and fmtVolume(stock.marketCap) or "--"
		stock.fiftyTwoWeekHighStr = fmt(stock.fiftyTwoWeekHigh)
		stock.fiftyTwoWeekLowStr = fmt(stock.fiftyTwoWeekLow)
		stock.volumeStr = stock.volume and fmtVolume(stock.volume) or "--"
		local arrow = (stock.changePct or 0) >= 0 and "▲" or "▼"
		stock.changeStr = arrow .. " " .. string.format("%.2f%%", math.abs(stock.changePct or 0))
		stock.changeColor = (stock.changePct or 0) >= 0 and "systemGreen" or "systemRed"
		local view = xml.renderFile(VIEWS .. "StockDetail.etlua", { stock = stock })
		self.detailPane:add(view)
	else
		local view = xml.renderFile(VIEWS .. "StockDetail.etlua", { stock = nil })
		self.detailPane:add(view)
	end
	self.detailPane:layout()
end

function Controller:createWindow()
	local cfg, refs = xml.renderFile(VIEWS .. "Window.etlua")

	for _, item in ipairs(cfg.toolbar or {}) do
		if item.action and ACTIONS[item.action] then
			local fn = ACTIONS[item.action]
			item.action = function() fn(self) end
		end
	end

	self.stockList = buildStockList()
	self.detailPane = buildDetailPane()
	cfg.content = self.stockList
	cfg.detail = self.detailPane

	self.stockList:onRowSelect(function(_, _, row)
		if row and row._id then
			self.selectedSymbol = row._id
			local data = self.stockData[row._id]
			if data then
				self:showDetail(data)
			else
				self:showLoading()
			end
		end
	end)

	self:refresh()

	self.window = ns.Window(cfg)
	return self.window
end

return Controller
