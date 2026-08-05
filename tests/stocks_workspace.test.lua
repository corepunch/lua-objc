_G.__headless = true

local t = require("TestKit")
local Controller = require("examples.stocks.Controller")
local Model = require("examples.stocks.Model")

local sample = Model.sampleStock("^IXIC")
t.assertEqual(sample.name, "NASDAQ Composite", "stocks fallback data names the selected index")
t.expect(#sample.chartData > 20, "stocks fallback data includes a useful chart series")

local controller = Controller.new()
local window = controller:createWindow()
local state = window:workspaceState()
t.assertEqual(state.itemCount, 2, "stocks window has semantic sidebar and content panes")
t.expect(state.nativeSidebar, "stocks uses AppKit's semantic sidebar")
t.expect(state.hasSidebarToggle, "stocks exposes the standard sidebar toggle")
t.expect(state.tracksSidebarDivider, "stocks sidebar toggle tracks the native divider")
t.expect(controller.sidebar ~= nil, "stocks sidebar includes a native container")
t.expect(controller.searchField ~= nil, "stocks sidebar includes a native search field")
t.assertEqual(controller.searchField.className, "NSSearchField",
	"stocks uses AppKit's native capsule search control")
t.assertEqual(controller.searchField.bezelStyle, 1,
	"stocks search uses NSTextFieldRoundedBezel")
t.assertEqual(controller.searchField.controlSize, 4,
	"stocks search field uses AppKit's macOS 26 extra-large control size")
t.assertEqual(controller.searchField.intrinsicContentSize.height, 36,
	"stocks search field receives native 36-point capsule geometry")
t.assertEqual(controller.searchField.size.height, 36,
	"stocks search field frame follows its extra-large intrinsic height")
t.expect(controller.searchField.size.width > 200, "stocks search field fills the sidebar width")
t.assertEqual(controller.selectedSymbol, "^IXIC", "stocks selects NASDAQ by default")
t.assertEqual(controller.stockList.rowCount, #Model.symbols + 1,
	"stocks includes Business News plus the watchlist rows")
t.expect(#Model.news >= 8, "Business News has a useful set of stories")
t.expect(#Model.newsFor("^IXIC", 4) >= 4,
	"stock details include several related stories")
t.assertEqual(#Model.newsFor("AAPL", 4), 4,
	"a company detail fills sparse ticker coverage with market news")
t.expect(controller.chart ~= nil and not controller.chart.closed,
	"stock chart is an open stroked path without a closing round trip")
t.expect(state.safeAreaPaneHosts, "stocks panes use native safe-area hosts")
t.expect(state.contentUsesSafeArea, "stocks content respects the native sidebar safe area")

-- Content / detail pane layout
local windowFrame = window.frame
local sidebarW = controller.sidebar.size.width
local detailW = controller.detailPane.size.width
local expectedDetailW = windowFrame.size.width - sidebarW
t.expect(detailW > 0, "stocks detail pane has non-zero width")
t.expect(math.abs(detailW - expectedDetailW) < 50,
	"stocks detail pane fills the space after the sidebar (" ..
	tostring(detailW) .. " ≈ " .. tostring(expectedDetailW) .. ")")
t.expect(detailW > sidebarW,
	"stocks detail pane is wider than the sidebar")

window:toggleSidebar()
window:layout()
local expandedDetailW = controller.detailPane.size.width
t.expect(expandedDetailW > detailW + sidebarW - 50,
	"collapsing the sidebar gives its width back to stock details")
window:toggleSidebar()
window:layout()
t.expect(math.abs(controller.detailPane.size.width - detailW) < 1,
	"restoring the sidebar restores the stock detail width")

-- Detail content should start after the sidebar (not at x=0)
t.expect(controller.detailPane.size.width > 0,
	"stocks detail content has measurable width")

-- Sidebar child frames should be within the sidebar's bounds
local searchW = controller.searchField.size.width
t.expect(searchW > 200, "stocks search field fills the sidebar width")
t.expect(searchW <= sidebarW + 8, "stocks search field does not overflow the sidebar")
t.expect(controller.stockList.size.width > searchW,
	"stocks list uses the sidebar edges beyond the inset search field")

os.exit(t.summary() and 0 or 1)
