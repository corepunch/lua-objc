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
	reclaim = Overview.reclaim(model), volumeName = "Startup Disk", actions = {}})
t.assertEqual(heroRefs.heroCard.className, "NSBox", "the hero uses the native rounded group")
t.assertEqual(heroRefs.usedTotal.text, "100.0 GB", "the chart hole shows used capacity")
t.expect(heroRefs.usedTotal.font.pointSize > 20, "used capacity is the page's largest number")
t.expect(heroRefs.cleanUp.bezelColor ~= nil, "the cleanup call to action is the prominent button")
hero.size = ns.Size(760, 320); hero:layout(760)
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
	chart = Overview.chart(model, {totalKb = 1, freeKb = 0}), reclaim = Overview.reclaim(model), volumeName = "Startup Disk", actions = {}})
t.expect(emptyRefs.legendExplanation ~= nil, "an overcounted inventory explains why no partition is drawn")
t.expect(emptyRefs.lowSpace ~= nil and heroRefs.lowSpace == nil, "only a nearly full disk shows the low-space warning")
t.assertEqual(#emptyRefs.chart.subviews, 2, "an empty chart keeps its track ring and centered total")
local _, refs = render("Overview", {status = "Calculating…", actions = {select = function() end, open = function() end,
	selectLargest = function() end, openLargest = function() end, showLargest = function() end, access = function() end}})
t.assertEqual(refs.categoriesPanel.className, "NSBox", "category rows share a native rounded section")
t.assertEqual(refs.opportunities, nil, "the overview does not repeat reclaim content")
t.expect(not refs.results.drawsBackground, "the category list lets its native group background show through")
refs.results:replaceRows({{id = "apps", name = "Applications", size = "Calculating…", calculating = true}})
local nameCell = bridge._tableCell(refs.results, 0, 0)
local sizeCell = bridge._tableCell(refs.results, 2, 0)
t.assertEqual(nameCell.textField.font.pointSize, 13, "category title uses the regular system font")
t.assertEqual(sizeCell.textField.font.pointSize, 13, "size and loading text use the regular system font")
t.expect(bridge._tableCell(refs.results, 1, 0).levelIndicator.hidden, "unmeasured categories have no share bar")

local settings, settingsRefs = render("Settings", {monitoring = true, mediaEnabled = false, actions = {}})
t.expect(settingsRefs ~= nil and settings ~= nil, "settings reorganized into concise groups still render")
t.assertEqual(settingsRefs.monitor.className, "NSSwitch", "background checks use a switch")
t.assertEqual(settingsRefs.monitor.state, 1, "background checks start enabled")
t.assertEqual(settingsRefs.media.className, "NSSwitch", "media libraries use a switch")
t.assertEqual(settingsRefs.media.state, 0, "media libraries start off")

refs.results.fixedHeight = 44
refs.page.size = ns.Size(400, 500); refs.page:layout(400)
t.expect(refs.results.frame.size.height < 80, "category rows keep their height instead of filling the window")
t.expect(refs.results.frame.size.width <= 400, "category list stays within the page width")
t.expect(not bridge._tableCell(refs.results, 2, 0).loadingIndicator.hidden, "section background preserves per-row loading")
local empty = render("Opportunities", {groups = {{name = "Needs review", size = "0 KB", index = 1, rows = {}}}, actions = {}})
t.expect(empty ~= nil, "empty review group renders")
local overview, overviewRefs = render("Opportunities", {groups = {
	{name = "Safe/rebuildable", size = "6.2 GB", index = 1, rows = {}},
	{name = "Needs review", size = "49.0 GB", index = 2, rows = {}},
	{name = "Essential to keep", size = "0 KB", index = 3, rows = {}},
}, actions = {}})
for _, width in ipairs({490, 700}) do
	overview.size = ns.Size(width, 600); overview:layout(width)
	t.assertEqual(overviewRefs.group1.frame.origin.y, overviewRefs.group3.frame.origin.y, "impact summaries stay in one horizontal row")
	t.expect(overviewRefs.group3.frame.origin.x + overviewRefs.group3.size.width <= overviewRefs.impactSummary.size.width + 1,
		"impact summaries fit the available width")
	t.expect(overviewRefs.groupAction1.size.width < overviewRefs.group1.size.width / 2,
		"summary actions stay compact within their native groups")
end
local _, reclaimRefs = render("Reclaim", {})
t.expect(reclaimRefs.opportunities ~= nil and reclaimRefs.tips ~= nil, "cleanup sheet provides dedicated content mounts")
local suggestions = render("Opportunities", {groups = {{name = "Safe/rebuildable", size = "4.9 GB", index = 1, rows = {{id = "derived", name = "Xcode DerivedData",
	subtitle = "Build products can be recreated.", size = "4.9 GB", icon = "hammer", color = "systemBlue"}}}}, actions = {}})
suggestions.size = ns.Size(292, 300); suggestions:layout(292)
for _, child in ipairs(suggestions.subviews) do t.expect(child.frame.size.width <= 292, "recommendation fits a narrow inspector") end
os.exit(t.summary() and 0 or 1)
