_G.__headless = true
local Categories = require("apps.diskmap.models.Categories")
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local bridge = require("AppKitNative")
local Format = require("apps.diskmap.helpers.Format")
local Store = require("apps.diskmap.Store")
local FOLDERS = {Hero = "sections", Overview = "pages", Settings = "sheets", ResourceList = "components", Page = "pages"}
local function render(name, data)
	return xml.renderFile("apps/diskmap/views/" .. FOLDERS[name] .. "/" .. name .. ".etlua", data, ns)
end
local model = Store.new("/Users/test")
model.scan.errors = 3
local coverage = Categories:coverage({totalKb = 1000000, freeKb = 500000})
t.expect(coverage:find("At least ", 1, true) == 1, "partial inventories mark the measured total as a lower bound")
t.expect(coverage:find("3 filesystem read issues", 1, true) ~= nil, "coverage reports read issues without calling them inaccessible locations")
t.expect(coverage:find("not attributed", 1, true) ~= nil, "capacity difference uses a plain-language label")
model.scan.errors = 0
for id, bytes in pairs({["apps-system-other"] = 30e9, derived = 20e9, ["codex-cache"] = 10e9,
	downloads = 5e9, ["user-caches"] = 4e9}) do
	model.measurements[id] = {bytes = bytes, status = "complete"}
end
local Overview = require("apps.diskmap.helpers.Overview")
local Scans = require("apps.diskmap.models.Scans")
local Suggestions = require("apps.diskmap.models.Suggestions")
local disk = {totalKb = 200e9 / 1024, freeKb = 100e9 / 1024}
local chart = Categories:chart(disk)
t.assertEqual(chart.legend[1].id, "applications", "largest category leads the legend")
t.assertEqual(chart.legend[2].id, "developer", "next largest category follows")
t.assertEqual(chart.legend[3].id, "ai-agents", "AI agents have their own storage segment")
t.assertEqual(chart.marks[#chart.marks].label, "Free", "free space closes the ring")
local chartActions = {chartSelect = function() end, chartHover = function() end, chartCenter = function() end}
local hero, heroRefs = render("Hero", {summary = Scans:summary(disk), center = Overview.center(Scans:summary(disk)), chart = chart,
	reclaim = Suggestions:reclaim(), volumeName = "Startup Disk", actions = chartActions,
	hiddenSpace = Overview.hidden(disk, {important = 110e9}, 2, 3)})
t.assertEqual(chart.marks[1].id, chart.legend[1].id, "a mark carries its category, so its sector can open it")
t.expect(heroRefs.hiddenSpace ~= nil, "the hero explains space no file scan can attribute")
t.assertEqual(#heroRefs.hiddenSpace.subviews, 3, "purgeable space, snapshots and unreadable locations are listed")
t.assertEqual(heroRefs.heroCard.className, "NSBox", "the hero uses the native rounded group")
t.assertEqual(heroRefs.usedTotal.text, "100.0 GB", "the chart hole shows used capacity")
t.expect(heroRefs.cleanUp.bezelColor ~= nil, "the cleanup call to action is the prominent button")
hero.size = ns.Size(760, 320); hero:layout(760)
-- The total fits the chart's hole once laid out.
t.expect(heroRefs.usedTotal.font.pointSize >= heroRefs.freeSpace.font.pointSize, "capacity stays readable beneath the cleanup action")
local buttons = {}
local function collect(view)
	if view.className == "NSButton" and not view.bordered then table.insert(buttons, view) end
	for _, child in ipairs(view.subviews or {}) do collect(child) end
end
collect(heroRefs.legend)
t.assertEqual(#buttons, #chart.legend, "every measured legend category is a native link")
for _, button in ipairs(buttons) do
	t.expect(button.enabled, "legend keeps native link interaction")
	t.expect(button.toolTip ~= nil and button.toolTip:find("Show ", 1, true) == 1, "legend links explain where they go")
end
-- The chart fills the room the card gives it (its rings stay circular inside
-- the view, see sector_chart.test.lua), so it is taller than the old fixed 144.
hero.size = ns.Size(900, 400)
hero:layout(900)
t.expect(heroRefs.chart.frame.size.height > 150, "the donut takes the height of the card: " .. heroRefs.chart.frame.size.height)
local _, emptyRefs = render("Hero", {summary = Scans:summary({totalKb = 1, freeKb = 0}), center = Overview.center(Scans:summary({totalKb = 1, freeKb = 0})),
	chart = Categories:chart({totalKb = 1, freeKb = 0}), reclaim = Suggestions:reclaim(), volumeName = "Startup Disk", actions = chartActions})
model.measurements.downloads = {status = "calculating"}
-- While the scan runs the page draws its empty state: an empty ring, no legend, no cleanup offer.
local _, busyRefs = render("Hero", {summary = Scans:summary(disk), center = Overview.center(Scans:summary(disk)), chart = {marks = {}, legend = {}, explanation = "Measuring"},
	volumeName = "Startup Disk", actions = chartActions})
t.expect(busyRefs.cleanUp == nil and heroRefs.cleanUp ~= nil, "cleanup is offered only once every size is known")
t.expect(busyRefs.legend == nil and busyRefs.legendExplanation ~= nil, "a running scan draws no legend")
model.measurements.downloads = {bytes = 5e9, status = "complete"}
t.expect(emptyRefs.legendExplanation ~= nil, "an overcounted inventory explains why no partition is drawn")
t.expect(emptyRefs.lowSpace ~= nil and heroRefs.lowSpace == nil, "only a nearly full disk shows the low-space warning")
t.assertEqual(#emptyRefs.chart.subviews, 3, "an empty chart keeps its track ring and centered total under the pointer view")
local _, refs = render("Overview", {status = "Measured", measured = true, coverage = "", largestHidden = false, accessTitle = "Scan access…", accessHidden = false,
	unmeasured = {items = {}}, hero = {summary = Scans:summary(disk), center = Overview.center(Scans:summary(disk)), chart = chart, volumeName = "Startup Disk"}, actions = {chartSelect = function() end, chartHover = function() end, chartCenter = function() end, reclaim = function() end, select = function() end, open = function() end,
	largestMenu = function() return {} end, openLargest = function() end, showLargest = function() end, access = function() end}})
t.assertEqual(refs.categoriesPanel.className, "NSBox", "category rows share a native rounded section")
t.assertEqual(refs.opportunities, nil, "the overview does not repeat reclaim content")
t.expect(not refs.results.drawsBackground, "the category list lets its native group background show through")
refs.results:replaceRows({{id = "apps", name = "Applications", size = "Calculating…", calculating = true}})
local nameCell = bridge._tableCell(refs.results, 0, 0)
local meterOf = dofile("tests/fixtures/meter.lua")
local sizeCell = meterOf(bridge._tableCell(refs.results, 1, 0))
t.assertEqual(nameCell.textField.font.pointSize, 13, "category title uses the regular system font")
t.assertEqual(sizeCell.value.font.pointSize, 13, "size and loading text use the regular system font")
local unmeasured = sizeCell.bar
t.expect(not unmeasured.hidden and not unmeasured.enabled and unmeasured.doubleValue == 0,
	"an unmeasured category keeps an empty, disabled bar under its state")

local settings, settingsRefs = render("Settings", {monitoring = true, mediaEnabled = false, historyEnabled = false,
	actions = {toggleMonitor = function() end, toggleMedia = function() end, toggleHistory = function() end, toggleReminder = function() end, toggleSentinel = function() end, openStorage = function() end, openPrivacy = function() end, close = function() end}})
t.expect(settingsRefs ~= nil and settings ~= nil, "settings reorganized into concise groups still render")
t.assertEqual(settingsRefs.monitor.className, "NSSwitch", "background checks use a switch")
t.assertEqual(settingsRefs.media.className, "NSSwitch", "media libraries use a switch")
-- Which way each switch starts is the model's `sync` (tests/diskmap_sheets.test.lua).

refs.results.fixedHeight = 44
refs.page.size = ns.Size(400, 500); refs.page:layout(400)
t.expect(refs.results.frame.size.height < 80, "category rows keep their height instead of filling the window")
t.expect(refs.results.frame.size.width <= 400, "category list stays within the page width")
t.expect(not dofile("tests/fixtures/meter.lua")(bridge._tableCell(refs.results, 1, 0)).spinner.hidden, "section background preserves per-row loading")
-- Every ranking page shares one list: a non-scrolling table whose actions live
-- in a row menu, so the page itself scrolls and no buttons sit under lists.
local menuRows = 0
local _, listRefs = render("ResourceList", {id = "items", menu = "rowMenu", activate = "open", detailColumn = true, actions = {
	rowMenu = function(_, _, row) menuRows = menuRows + 1; return {{title = "Show " .. row.name, action = function() end}} end,
	open = function() end}})
local items = listRefs.items
t.expect(items.scrollDisabled, "shared lists never scroll inside a page")
items:replaceRows({{id = "derived", name = "Xcode DerivedData", subtitle = "Developer › Xcode", detail = "Rebuildable", size = "4.9 GB", relative = 1, shareText = "", color = "systemBlue", icon = "hammer.fill"}})
t.assertEqual(bridge._tableRowMenu(items, 1)[1].title, "Show Xcode DerivedData", "the row menu describes its row")
t.assertEqual(menuRows, 1, "row menus are built when opened")
local more = bridge._tableCell(items, 3, 0)
t.expect(more.actionButton ~= nil and more.actionButton.accessibilityLabel == "More", "each row has a More button")
-- 595 points is the list width in Diskmap's narrowest window (880 points).
items.size = ns.Size(595, 200); items:layout(595)
local widths = bridge._tableColumnWidths(items)
local total, named = 0, 0
for _, column in ipairs(widths) do total = total + column.width; if column.id == "name" then named = column.width end end
t.expect(total <= 595 + 1, "shared list columns fit the narrowest window")
t.expect(named >= 170, "the name keeps 170 points in the narrowest window")
-- Status lists show one colour-coded symbol per row; the status word stays
-- available as tooltip and accessibility label instead of truncated text.
local Status = require("apps.diskmap.helpers.Status")
local _, statusRefs = render("ResourceList", {id = "statuses", menu = "rowMenu", status = true, actions = {rowMenu = function() return {} end}})
local statuses = statusRefs.statuses
statuses:replaceRows({Status.apply({id = "derived", name = "Xcode DerivedData", detail = "Rebuildable", size = "≥ 999.9 MB", relative = 1, shareText = "", color = "systemBlue", icon = "hammer.fill"}),
	Status.apply({id = "group", name = "Simulator runtimes", detail = "Group", size = "8.5 GB", relative = 0.5, shareText = "", color = "systemBlue", icon = "hammer.fill"})})
local statusCell = bridge._tableCell(statuses, 1, 0)
t.expect(statusCell.textField.hidden, "an icon-only status hides its word")
t.expect(statusCell.imageView.image ~= nil, "a status is drawn as a symbol")
t.assertEqual(statusCell.imageView.toolTip, "Rebuildable", "the status word is the symbol's tooltip")
t.assertEqual(statusCell.imageView.accessibilityLabel, "Rebuildable", "VoiceOver reads the status word")
t.expect(bridge._tableCell(statuses, 1, 1).imageView.image == nil, "a rolled-up group has no status symbol")
local bar = meterOf(bridge._tableCell(statuses, 2, 0))
t.expect(bar.bar.frameInWindow.origin.x - bar.cell.frameInWindow.origin.x <= 8, "the meter bar starts at the column edge")
statuses.size = ns.Size(560, 200); statuses:layout(560)
local statusWidths = {}
for _, column in ipairs(bridge._tableColumnWidths(statuses)) do statusWidths[column.id] = column.width end
t.expect(statusWidths.detail <= 48, "the status column is one symbol wide")
t.expect(statusWidths.shareText >= 180, "the meter fits a lower-bound size such as ≥ 999.9 MB beside its share")
for status, style in pairs(Status.styles) do
	t.expect(style.icon:find("%.fill$") ~= nil and style.color ~= nil, status .. " has a filled, coloured symbol")
end

-- A size that is a state is a short coloured word led by its symbol, in the
-- spinner's place; measured rows in the same meter keep plain numbers.
local _, sizeRefs = render("ResourceList", {id = "sizes", menu = "rowMenu", actions = {rowMenu = function() return {} end}})
local sizes = sizeRefs.sizes
sizes:replaceRows({
	Format.sizeLabel({id = "mail", name = "Mail", shareText = "", color = "systemBlue", icon = "envelope"}, "denied"),
	Format.sizeLabel({id = "docs", name = "Documents", relative = 1, shareText = "", color = "systemBlue", icon = "doc"}, "complete", 2e9),
})
sizes.size = ns.Size(560, 200); sizes:layout(560)
local denied, measured = meterOf(bridge._tableCell(sizes, 1, 0)), meterOf(bridge._tableCell(sizes, 1, 1))
t.assertEqual(denied.value.stringValue, "No access", "the state is spelled out")
t.expect(denied.symbol.image ~= nil, "a state leads with its symbol")
t.expect(denied.symbol.frameInWindow.origin.x + denied.symbol.frameInWindow.size.width <= denied.value.frameInWindow.origin.x, "the symbol comes before the word")
t.assertEqual(denied.symbol.frame.size.width, 16, "the symbol fills the spinner's square")
t.assertEqual(tostring(denied.value.textColor), tostring(denied.symbol.contentTintColor), "the word takes its symbol's colour")
t.expect(not denied.bar.hidden and not denied.bar.enabled, "a state keeps an empty, disabled bar")
t.expect(measured.symbol.image == nil and measured.bar.enabled, "a measured size has no symbol and an enabled bar")
t.assertEqual(measured.value.stringValue, "2.0 GB", "the measured size is text")
for status, state in pairs(Format.sizeStates) do
	local row = Format.sizeLabel({}, status)
	t.assertEqual(row.size, state.text, status .. " reads as its word")
	t.expect(row.sizeIcon == state.icon and row.sizeColor == state.color, status .. " carries its symbol and colour")
	t.expect(#state.text <= 14, status .. " is a short word")
end
t.assertEqual(Format.sizeStates.unsupported.text, "System Managed", "system-managed storage says so")
t.assertEqual(Format.sizeStates.denied.color, "systemOrange", "no access is a warning")
t.assertEqual(Format.sizeStates.failed.color, "systemRed", "a failed measurement is an error")
t.expect(Format.sizeLabel({}, "complete", 1e9).sizeIcon == nil, "a measured size has no state symbol")
local annotated = require("apps.diskmap.flows.Rows")({app = {}}):annotate({
	{id = "big", bytes = 4e9}, {id = "empty", bytes = 0}, Format.sizeLabel({id = "locked"}, "denied")})
t.assertEqual(annotated[1].relative, 1, "the largest row fills its bar")
t.assertEqual(annotated[2].relative, 0, "a measured zero is an empty bar")
t.assertEqual(annotated[3].relative, nil, "an unmeasured row has no fraction, so its bar is disabled")
local pending = Format.sizeLabel({}, "calculating")
t.expect(pending.calculating and pending.size == "Calculating…", "calculating keeps its spinner and word")
local partial = Format.sizeLabel({}, "partial", 2e9)
t.assertEqual(partial.size, "≥ 2.0 GB", "a partial size reads as a lower bound")
t.expect(partial.partial, "a partial size is flagged")
sizes:replaceRows({Format.sizeLabel({id = "dev", name = "Developer", relative = 1, shareText = "", color = "systemBlue", icon = "hammer"}, "partial", 15.8e9)})
local lower = meterOf(bridge._tableCell(sizes, 1, 0))
t.assertEqual(lower.value.stringValue, "≥ 15.8 GB", "the lower bound reads ≥ before its number")
t.expect(lower.symbol.image == nil, "a lower bound is a sign, not a symbol")
t.assertEqual(Status.apply({detail = "Under 5.0 GB"}, "Within").statusColor, "systemGreen", "a location within limits is green")
t.assertEqual(Status.apply({detail = "Review"}).statusColor, "systemOrange", "review is orange")
t.assertEqual(Status.apply({detail = "Keep"}).statusColor, "systemRed", "required data is red")
local XcodeController = require("apps.diskmap.routes").xcode
for _, status in ipairs({"Newest · keep", "Older", "Missing", "Present", "Unknown"}) do
	t.expect(Status.styles[XcodeController.statuses[status]] ~= nil, "Xcode status " .. status .. " has a symbol")
end
t.assertEqual(Status.styles[XcodeController.statuses.Missing].color, "systemGreen", "build data of a missing project is safe to remove")

-- A list page is Page.etlua and a layout table: whatever the table leaves
-- out is left out of the page, and what it names gets a ref.
local anyAction = setmetatable({}, {__index = function() return function() return {} end end})
local header = {icon = "doc.fill", color = "systemTeal", title = "Example"}
local bare, bareRefs = render("Page", {header = header, layout = {}, actions = anyAction})
t.expect(bare ~= nil and bareRefs.page ~= nil and bareRefs.pageContent ~= nil, "an empty layout renders as one scrolling page")
t.assertEqual(bareRefs.pageTitle.text, "Example", "the header shows the page's title")
t.expect(bareRefs.stats == nil, "a layout without tiles has no tile row")
local _, fullRefs = render("Page", {header = header, actions = anyAction, layout = {
	summary = "Summary", summaryId = "exampleSummary",
	buttons = {{id = "add", title = "Add…", action = "add"}},
	tiles = {{id = "oneTile", icon = "doc.fill", color = "systemTeal", title = "One", value = "—", detail = "Detail"}},
	sections = {
		{id = "firstSection", title = "First", detail = "Detail", detailId = "firstDetail", titleId = "firstTitle", sizeId = "firstSize",
			links = {{id = "clear", title = "Clear", style = "link", action = "clear", hidden = true}},
			filters = {id = "filter", options = {"All", "Some"}},
			buttons = {{id = "bulk", title = "Mark", action = "bulk", disabled = true}},
			empties = {{id = "firstEmpty", hidden = true, title = "Nothing", systemImage = "doc", description = "Nothing here."}},
			panelId = "firstPanel", list = {id = "first", menu = "rowMenu", activate = "open", status = true}},
		{list = {id = "second", menu = "rowMenu", detailColumn = true}},
	},
	slots = {"extra"},
	footnote = {text = "Footnote"},
}})
t.assertEqual(fullRefs.exampleSummary.text, "Summary", "the summary takes the ref the layout names")
for _, id in ipairs({"add", "stats", "oneTileValue", "firstSection", "firstTitle", "firstDetail", "firstSize", "clear", "bulk",
	"firstEmpty", "firstPanel", "first", "second", "extra"}) do
	t.expect(fullRefs[id] ~= nil, "the layout's " .. id .. " is on the page")
end
t.assertEqual(fullRefs.filter.className, "NSSegmentedControl", "filters are a segmented control")
t.expect(fullRefs.clear.hidden and fullRefs.firstEmpty.hidden and not fullRefs.bulk.enabled, "hidden and disabled come from the layout")
-- Filters and actions take separate rows under the heading, so neither
-- the heading's detail nor the controls get squeezed in a narrow window.
fullRefs.page.size = ns.Size(620, 600); fullRefs.page:layout(620)
local filterRow, titleRow = fullRefs.filter.superview, fullRefs.firstTitle.superview.superview
t.expect(filterRow ~= titleRow, "the filter is not on the heading's row")
t.assertEqual(fullRefs.bulk.superview.superview, filterRow, "section buttons share the filter's controls block")
t.expect(fullRefs.bulk.superview ~= titleRow, "section actions stay below the heading")
t.expect(fullRefs.firstDetail.frame.size.width > 400, "the heading's detail keeps the section's width beside no controls")
t.assertEqual(fullRefs.firstDetail.frame.size.height, fullRefs.firstDetail.intrinsicContentSize.height, "the detail stays on one line")
-- The meter is no wider than its widest value and share, "≥ 999.9 MB" and
-- "could recover", so the name and its subtitle keep the rest.
local columns = {}
for _, column in ipairs(bridge._tableColumnWidths(fullRefs.second)) do columns[column.id] = column end
t.assertEqual(columns.shareText.minWidth, 200, "the meter column fits its widest value and share, no more")
local probe = xml.render('<Label text="≥ 999.9 MB" />', {}, ns)
local shareProbe = xml.render('<Label text="could recover" />', {}, ns)
t.expect(probe.fittingSize.width + shareProbe.fittingSize.width + 8 <= 200 - 16, "the meter's widest value and share fit inside the cell's insets")
local _, plainRefs = render("Page", {header = header, actions = anyAction, layout = {sections = {
	{title = "Plain", titleId = "plainTitle", buttons = {{id = "open", title = "Open", action = "open"}}, list = {id = "plain", menu = "rowMenu"}}}}})
t.expect(plainRefs.open.superview ~= plainRefs.plainTitle.superview.superview, "section actions keep their own row without a filter")
os.exit(t.summary() and 0 or 1)
