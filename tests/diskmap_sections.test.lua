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
local summary, summaryRefs = render("StorageBar", categories:bar({totalKb = 1000000, freeKb = 500000}))
t.assertEqual(summaryRefs.storageSummary.className, "NSBox", "storage summary uses the native rounded group")
summary.size = ns.Size(788, 100); summary:layout(788)
local buttons = {}
local function collect(view)
	if view.className == "NSButton" then buttons[#buttons + 1] = view end
	for _, child in ipairs(view.subviews or {}) do collect(child) end
end
collect(summary)
t.assertEqual(#buttons, 11, "all storage legend destinations remain buttons")
for _, button in ipairs(buttons) do
	t.assertEqual(button.font.pointSize, 11, "legend uses the smaller font")
	t.expect(not button.bordered and button.enabled, "legend keeps native link interaction")
	t.expect(button.frame.size.width >= button.intrinsicContentSize.width, "legend title fits without truncation")
end
-- The same legend fills wider rows and wraps only when an item cannot fit.
local legend = summaryRefs.legend
local itemCount = #legend.subviews
local function rowCount()
	local rows = {}
	for _, item in ipairs(legend.subviews) do rows[item.frame.origin.y] = true end
	local count = 0; for _ in pairs(rows) do count = count + 1 end
	return count
end
summary.size = ns.Size(1300, 100); summary:layout(1300)
t.assertEqual(rowCount(), 1, "wide legend uses one row for all categories")
t.assertEqual(#legend.subviews, itemCount, "wide legend preserves every destination")
summary.size = ns.Size(788, 100); summary:layout(788)
t.expect(rowCount() > 1, "minimum window wraps the legend")
local firstRow = 0
for _, item in ipairs(legend.subviews) do
	if item.frame.origin.y == legend.subviews[1].frame.origin.y then firstRow = firstRow + 1 end
	t.expect(item.frame.origin.x + item.size.width <= legend.size.width, "legend item stays within available width")
end
t.expect(firstRow > 6, "legend uses the space beyond the former six-item limit")
local _, refs = render("Dashboard", {title = "Storage categories", subtitle = "Current inventory",
	icon = "chart.pie.fill", color = "systemBlue", coverage = "Measuring", status = "Calculating…", actions = {}})
t.assertEqual(refs.categoriesPanel.className, "NSBox", "category rows share a native rounded section")
t.assertEqual(refs.inspector.className, "NSBox", "inspector uses a native rounded section")
t.expect(refs.inspector.hidden, "unselected inspector leaves no empty card")
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
local suggestions = render("Opportunities", {groups = {{name = "Safe/rebuildable", size = "4.9 GB", index = 1, rows = {{id = "derived", name = "Xcode DerivedData",
	subtitle = "Build products can be recreated.", size = "4.9 GB", icon = "hammer", color = "systemBlue"}}}}, actions = {}})
suggestions.size = ns.Size(292, 300); suggestions:layout(292)
for _, child in ipairs(suggestions.subviews) do t.expect(child.frame.size.width <= 292, "recommendation fits a narrow inspector") end
os.exit(t.summary() and 0 or 1)
