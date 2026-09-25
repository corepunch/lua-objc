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
local categories = Categories.new(model, function() end)
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
local bar = categories:bar({totalKb = 200e9 / 1024, freeKb = 100e9 / 1024})
local summary, summaryRefs = render("StorageBar", bar)
t.assertEqual(summaryRefs.storageSummary.className, "NSBox", "storage summary uses the native rounded group")
summary.size = ns.Size(788, 100); summary:layout(788)
local buttons = {}
local function collect(view)
	if view.className == "NSButton" then table.insert(buttons, view) end
	for _, child in ipairs(view.subviews or {}) do collect(child) end
end
collect(summary)
t.assertEqual(#buttons, 5, "legend contains measured categories with storage")
t.assertEqual(bar.legend[1].id, "applications", "largest category leads the legend")
t.assertEqual(bar.legend[2].id, "developer", "next largest category follows")
t.assertEqual(bar.legend[3].id, "ai-agents", "AI agents have their own storage segment")
for _, button in ipairs(buttons) do
	t.assertEqual(button.font.pointSize, 11, "legend uses the smaller font")
	t.expect(not button.bordered and button.enabled, "legend keeps native link interaction")
	t.expect(button.frame.size.width >= button.intrinsicContentSize.width, "legend title fits without truncation")
end
-- A single row keeps complete leading items and restores hidden ones on resize.
local legend = summaryRefs.legend
local itemCount = #legend.subviews
local function visibleCount()
	local count = 0
	for _, item in ipairs(legend.subviews) do
		if not item.hidden then
			count = count + 1
			t.expect(item.frame.origin.x + item.size.width <= legend.size.width, "visible legend item fits completely")
		end
	end
	return count
end
summary.size = ns.Size(1300, 100); summary:layout(1300)
t.assertEqual(visibleCount(), itemCount, "wide legend shows all measured categories")
t.assertEqual(#legend.subviews, itemCount, "wide legend preserves every destination")
summary.size = ns.Size(360, 100); summary:layout(360)
t.expect(visibleCount() < itemCount, "narrow legend omits trailing categories instead of wrapping")
t.expect(not legend.subviews[1].hidden and legend.subviews[itemCount].hidden, "largest categories remain visible first")
t.assertEqual(legend.size.height, legend.subviews[1].size.height, "legend remains one row high")
summary.size = ns.Size(1300, 100); summary:layout(1300)
t.assertEqual(visibleCount(), itemCount, "widening restores all category links")
local _, refs = render("Dashboard", {title = "Storage categories", subtitle = "Current inventory",
	icon = "chart.pie.fill", color = "systemBlue", coverage = "Measuring", status = "Calculating…", actions = {}})
t.assertEqual(refs.categoriesPanel.className, "NSBox", "category rows share a native rounded section")
t.assertEqual(refs.opportunities, nil, "category pages do not repeat reclaim content")
t.expect(not refs.openCategory.enabled, "category management waits for a selection")
t.assertEqual(refs.inspector, nil, "category detail does not displace dashboard suggestions")
t.expect(not refs.results.drawsBackground, "outline lets its native group background show through")
refs.results:replaceRows({{id = "apps", name = "Applications", size = "Calculating…", calculating = true}})
local nameCell = bridge._tableCell(refs.results, 0, 0)
local sizeCell = bridge._tableCell(refs.results, 1, 0)
t.assertEqual(nameCell.textField.font.pointSize, 13, "category title uses the regular system font")
t.assertEqual(sizeCell.textField.font.pointSize, 13, "size and loading text use the regular system font")
t.assertEqual(refs.heading, nil, "storage list omits its redundant heading")
t.expect(nameCell.textField.font.pointSize > buttons[1].font.pointSize, "only legend text uses the smaller primary font")

local settings, settingsRefs = render("Settings", {monitoring = true, mediaEnabled = false, actions = {}})
t.expect(settingsRefs ~= nil and settings ~= nil, "settings reorganized into concise groups still render")

for _, height in ipairs({220, 500}) do
	refs.categoriesPanel.size = ns.Size(400, height); refs.categoriesPanel:layout(400)
	t.expect(refs.results.frame.size.height >= height - 20, "category list consumes group content height after resize")
	t.expect(refs.results.frame.size.width <= 400, "category list stays within native group margins")
	t.expect(not bridge._tableCell(refs.results, 1, 0).loadingIndicator.hidden, "section background preserves per-row loading")
end
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
t.expect(reclaimRefs.opportunities ~= nil and reclaimRefs.tips ~= nil, "Reclaim page provides dedicated content mounts")
local suggestions = render("Opportunities", {groups = {{name = "Safe/rebuildable", size = "4.9 GB", index = 1, rows = {{id = "derived", name = "Xcode DerivedData",
	subtitle = "Build products can be recreated.", size = "4.9 GB", icon = "hammer", color = "systemBlue"}}}}, actions = {}})
suggestions.size = ns.Size(292, 300); suggestions:layout(292)
for _, child in ipairs(suggestions.subviews) do t.expect(child.frame.size.width <= 292, "recommendation fits a narrow inspector") end
os.exit(t.summary() and 0 or 1)
