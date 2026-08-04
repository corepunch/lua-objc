_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local Controller = require("examples.stocks.Controller")

local originalAsync = ns.async
local originalFetchJSON = ns.fetch_json

local loadingCalls = {}
local rows
local controller = Controller.new()
controller.stockList = {
	showLoading = function() loadingCalls[#loadingCalls + 1] = "show" end,
	hideLoading = function() loadingCalls[#loadingCalls + 1] = "hide" end,
	clearRows = function() rows = nil end,
	replaceRows = function(_, value) rows = value end,
}
controller.selectedSymbol = "^IXIC"

-- Run the app coroutine inline so the test can verify its lifecycle without
-- opening a window or making network requests.
ns.async = function(fn) fn() end
ns.fetch_json = function()
	return {
		chart = { result = { { meta = {
			regularMarketPrice = 101,
			chartPreviousClose = 100,
			shortName = "Example Corp",
		}, timestamp = {1, 2, 3, 4}, indicators = { quote = {{
			close = {[1] = 100, [3] = 100.5, [4] = 101},
		}} } } } },
	}
end

_G.__headless = false
controller:refresh()
_G.__headless = true

t.assertEqual(table.concat(loadingCalls, ","), "show,hide",
	"refresh starts and stops the native loading indicator")
t.assertEqual(#rows, #require("examples.stocks.Model").symbols + 1,
	"refresh includes Business News and every watchlist row")
t.assertEqual(rows[2].price, "$101.00", "refresh formats fetched prices")
t.assertEqual(#controller.stockData["^IXIC"].chartData, 3,
	"intraday parsing continues after a missing close value")

ns.async = originalAsync
ns.fetch_json = originalFetchJSON

os.exit(t.summary() and 0 or 1)
