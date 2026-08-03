_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local Controller = require("examples.live.Controller")

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

-- Run the app coroutine inline so the test can verify its lifecycle without
-- opening a window or making network requests.
ns.async = function(fn) fn() end
ns.fetch_json = function()
	return {
		chart = { result = { { meta = {
			regularMarketPrice = 101,
			chartPreviousClose = 100,
			shortName = "Example Corp",
		} } } },
	}
end

controller:refresh()

t.assertEqual(table.concat(loadingCalls, ","), "show,hide",
	"refresh starts and stops the native loading indicator")
t.assertEqual(#rows, 10, "refresh replaces rows after the coroutine completes")
t.assertEqual(rows[1].price, "$101.00", "refresh formats fetched prices")

ns.async = originalAsync
ns.fetch_json = originalFetchJSON

os.exit(t.summary() and 0 or 1)
