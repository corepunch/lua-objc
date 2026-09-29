_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local bridge = require("AppKitNative")
local Model = require("apps.diskmap.Model")
local Categories = require("apps.diskmap.controllers.CategoriesController")
local function render(name, data)
	return xml.renderFile("apps/diskmap/views/" .. name .. ".etlua", data, ns)
end
local model = Model.new("/Users/test")
local categories = Categories.new(model)
model.scan.errors = 3
local coverage = categories:coverage({totalKb = 1000000, freeKb = 500000})
t.expect(coverage:find("At least ", 1, true) == 1, "partial inventories mark the measured total as a lower bound")
t.expect(coverage:find("3 filesystem read issues", 1, true) ~= nil, "coverage reports read issues without calling them inaccessible locations")
t.expect(coverage:find("not attributed", 1, true) ~= nil, "capacity difference uses a plain-language label")
model.scan.errors = 0
for id, bytes in pairs({["apps-system-other"] = 30e9, derived = 20e9, ["codex-cache"] = 10e9,
	downloads = 5e9, ["user-caches"] = 4e9}) do
	model.measurements[id] = {bytes = bytes, status = "complete"}
end
local Overview = require("apps.diskmap.models.Overview")
local disk = {totalKb = 200e9 / 1024, freeKb = 100e9 / 1024}
local chart = Overview.chart(model, disk)
t.assertEqual(chart.legend[1].id, "applications", "largest category leads the legend")
t.assertEqual(chart.legend[2].id, "developer", "next largest category follows")
t.assertEqual(chart.legend[3].id, "ai-agents", "AI agents have their own storage segment")
t.assertEqual(chart.marks[#chart.marks].label, "Free", "free space closes the ring")
local hero, heroRefs = render("Hero", {summary = Overview.summary(model, disk), chart = chart,
	reclaim = Overview.reclaim(model), volumeName = "Startup Disk", actions = {},
	hidden = Overview.hidden(disk, {important = 110e9}, 2, 3)})
t.expect(heroRefs.hiddenSpace ~= nil, "the hero explains space no file scan can attribute")
t.assertEqual(#heroRefs.hiddenSpace.subviews, 3, "purgeable space, snapshots and unreadable locations are listed")
t.assertEqual(heroRefs.heroCard.className, "NSBox", "the hero uses the native rounded group")
t.assertEqual(heroRefs.usedTotal.text, "100.0 GB", "the chart hole shows used capacity")
t.expect(heroRefs.cleanUp.bezelColor ~= nil, "the cleanup call to action is the prominent button")
hero.size = ns.Size(760, 320); hero:layout(760)
-- The total fits the chart's hole once laid out.
t.expect(heroRefs.usedTotal.font.pointSize > heroRefs.freeSpace.font.pointSize + 4, "used capacity is the page's largest number")
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
t.expect(heroRefs.chart.frame.size.width == heroRefs.chart.frame.size.height, "the donut keeps a square frame")
local _, emptyRefs = render("Hero", {summary = Overview.summary(model, {totalKb = 1, freeKb = 0}),
	chart = Overview.chart(model, {totalKb = 1, freeKb = 0}), reclaim = Overview.reclaim(model), volumeName = "Startup Disk", actions = {}, hidden = {}})
t.expect(emptyRefs.legendExplanation ~= nil, "an overcounted inventory explains why no partition is drawn")
t.expect(emptyRefs.lowSpace ~= nil and heroRefs.lowSpace == nil, "only a nearly full disk shows the low-space warning")
t.assertEqual(#emptyRefs.chart.subviews, 2, "an empty chart keeps its track ring and centered total")
local _, refs = render("Overview", {status = "Calculating…", actions = {select = function() end, open = function() end,
	largestMenu = function() return {} end, openLargest = function() end, showLargest = function() end, access = function() end}})
t.assertEqual(refs.categoriesPanel.className, "NSBox", "category rows share a native rounded section")
t.assertEqual(refs.opportunities, nil, "the overview does not repeat reclaim content")
t.expect(not refs.results.drawsBackground, "the category list lets its native group background show through")
refs.results:replaceRows({{id = "apps", name = "Applications", size = "Calculating…", calculating = true}})
local nameCell = bridge._tableCell(refs.results, 0, 0)
local sizeCell = bridge._tableCell(refs.results, 1, 0)
t.assertEqual(nameCell.textField.font.pointSize, 13, "category title uses the regular system font")
t.assertEqual(sizeCell.valueField.font.pointSize, 13, "size and loading text use the regular system font")
local unmeasured = bridge._tableCell(refs.results, 1, 0).levelIndicator
t.expect(not unmeasured.hidden and not unmeasured.enabled and unmeasured.doubleValue == 0,
	"an unmeasured category keeps an empty, disabled bar under its state")

local settings, settingsRefs = render("Settings", {monitoring = true, mediaEnabled = false, historyEnabled = false,
	actions = {monitor = function() end, media = function() end, history = function() end, reminder = function() end, sentinel = function() end, storage = function() end, privacy = function() end, done = function() end}})
t.assertEqual(settingsRefs.history.state, 0, "storage history starts off")
t.expect(settingsRefs ~= nil and settings ~= nil, "settings reorganized into concise groups still render")
t.assertEqual(settingsRefs.monitor.className, "NSSwitch", "background checks use a switch")
t.assertEqual(settingsRefs.monitor.state, 1, "background checks start enabled")
t.assertEqual(settingsRefs.media.className, "NSSwitch", "media libraries use a switch")
t.assertEqual(settingsRefs.media.state, 0, "media libraries start off")

refs.results.fixedHeight = 44
refs.page.size = ns.Size(400, 500); refs.page:layout(400)
t.expect(refs.results.frame.size.height < 80, "category rows keep their height instead of filling the window")
t.expect(refs.results.frame.size.width <= 400, "category list stays within the page width")
t.expect(not bridge._tableCell(refs.results, 1, 0).loadingIndicator.hidden, "section background preserves per-row loading")
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
local Status = require("apps.diskmap.models.Status")
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
local bar = bridge._tableCell(statuses, 2, 0)
bar:layout()
t.expect(bar.levelIndicator.frame.origin.x <= 8, "the meter bar starts at the column edge")
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
	Model.sizeLabel({id = "mail", name = "Mail", shareText = "", color = "systemBlue", icon = "envelope"}, "denied"),
	Model.sizeLabel({id = "docs", name = "Documents", relative = 1, shareText = "", color = "systemBlue", icon = "doc"}, "complete", 2e9),
})
sizes.size = ns.Size(560, 200); sizes:layout(560)
local denied, measured = bridge._tableCell(sizes, 1, 0), bridge._tableCell(sizes, 1, 1)
denied:layout()
t.assertEqual(denied.valueField.stringValue, "No access", "the state is spelled out")
t.expect(denied.imageView.image ~= nil, "a state leads with its symbol")
t.expect(denied.imageView.frame.origin.x + denied.imageView.frame.size.width <= denied.valueField.frame.origin.x, "the symbol comes before the word")
t.assertEqual(denied.imageView.frame.size.width, 16, "the symbol fills the spinner's square")
t.assertEqual(tostring(denied.valueField.textColor), tostring(denied.imageView.contentTintColor), "the word takes its symbol's colour")
t.expect(not denied.levelIndicator.hidden and not denied.levelIndicator.enabled, "a state keeps an empty, disabled bar")
t.expect(measured.imageView.image == nil and measured.levelIndicator.enabled, "a measured size has no symbol and an enabled bar")
t.assertEqual(measured.valueField.stringValue, "2.0 GB", "the measured size is text")
for status, state in pairs(Model.sizeStates) do
	local row = Model.sizeLabel({}, status)
	t.assertEqual(row.size, state.text, status .. " reads as its word")
	t.expect(row.sizeIcon == state.icon and row.sizeColor == state.color, status .. " carries its symbol and colour")
	t.expect(#state.text <= 14, status .. " is a short word")
end
t.assertEqual(Model.sizeStates.unsupported.text, "System Managed", "system-managed storage says so")
t.assertEqual(Model.sizeStates.denied.color, "systemOrange", "no access is a warning")
t.assertEqual(Model.sizeStates.failed.color, "systemRed", "a failed measurement is an error")
t.expect(Model.sizeLabel({}, "complete", 1e9).sizeIcon == nil, "a measured size has no state symbol")
local annotated = require("apps.diskmap.controllers.ActionsController").new({}, {}, {}, nil):annotate({
	{id = "big", bytes = 4e9}, {id = "empty", bytes = 0}, Model.sizeLabel({id = "locked"}, "denied")})
t.assertEqual(annotated[1].relative, 1, "the largest row fills its bar")
t.assertEqual(annotated[2].relative, 0, "a measured zero is an empty bar")
t.assertEqual(annotated[3].relative, nil, "an unmeasured row has no fraction, so its bar is disabled")
local pending = Model.sizeLabel({}, "calculating")
t.expect(pending.calculating and pending.size == "Calculating…", "calculating keeps its spinner and word")
local partial = Model.sizeLabel({}, "partial", 2e9)
t.assertEqual(partial.size, "≥ 2.0 GB", "a partial size reads as a lower bound")
t.expect(partial.partial, "a partial size is flagged")
sizes:replaceRows({Model.sizeLabel({id = "dev", name = "Developer", relative = 1, shareText = "", color = "systemBlue", icon = "hammer"}, "partial", 15.8e9)})
local lower = bridge._tableCell(sizes, 1, 0)
t.assertEqual(lower.valueField.stringValue, "≥ 15.8 GB", "the lower bound reads ≥ before its number")
t.expect(lower.imageView.image == nil, "a lower bound is a sign, not a symbol")
t.assertEqual(Status.apply({detail = "Under 5.0 GB"}, "Within").statusColor, "systemGreen", "a location within limits is green")
t.assertEqual(Status.apply({detail = "Review"}).statusColor, "systemOrange", "review is orange")
t.assertEqual(Status.apply({detail = "Keep"}).statusColor, "systemRed", "required data is red")
local XcodeController = require("apps.diskmap.controllers.XcodeController")
for _, status in ipairs({"Newest · keep", "Older", "Missing", "Present", "Unknown"}) do
	t.expect(Status.styles[XcodeController.statuses[status]] ~= nil, "Xcode status " .. status .. " has a symbol")
end
t.assertEqual(Status.styles[XcodeController.statuses.Missing].color, "systemGreen", "build data of a missing project is safe to remove")

for _, name in ipairs({"Largest", "Files", "Cleanup", "Applications", "Disks"}) do
	local data = {summary = "", filters = {"All"}, threshold = "50 MB", health = {}, actions = setmetatable({}, {__index = function() return function() return {} end end})}
	local page, pageRefs = render(name, data)
	t.expect(page ~= nil and pageRefs.page ~= nil, name .. " renders as one scrolling page")
end
os.exit(t.summary() and 0 or 1)
