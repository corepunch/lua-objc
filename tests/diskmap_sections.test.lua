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
local _, refs = render("Dashboard", {title = "Storage categories", subtitle = "Current inventory",
	icon = "chart.pie.fill", color = "systemBlue", coverage = "Measuring", status = "Calculating…", actions = {}})
t.assertEqual(refs.categoriesPanel.className, "NSBox", "category rows share a native rounded section")
t.assertEqual(refs.inspector.className, "NSBox", "inspector uses a native rounded section")
t.expect(refs.inspector.hidden, "unselected inspector leaves no empty card")
t.expect(not refs.results.drawsBackground, "outline lets its native group background show through")
refs.results:replaceRows({{id = "apps", name = "Applications", size = "Calculating…", calculating = true}})
for _, height in ipairs({220, 500}) do
	refs.categoriesPanel.size = ns.Size(400, height); refs.categoriesPanel:layout(400)
	t.expect(refs.results.frame.size.height >= height - 20, "category list consumes group content height after resize")
	t.expect(refs.results.frame.size.width <= 400, "category list stays within native group margins")
	t.expect(not bridge._tableCell(refs.results, 1, 0).loadingIndicator.hidden, "section background preserves per-row loading")
end
local empty = render("Opportunities", {suggestions = {}, actions = {}})
t.assertEqual(empty.subviews[1].className, "NSBox", "empty recommendations remain a native section")
local suggestions = render("Opportunities", {suggestions = {{id = "derived", name = "Xcode DerivedData",
	subtitle = "Build products can be recreated.", size = "4.9 GB", icon = "hammer", color = "systemBlue"}}, actions = {}})
t.assertEqual(suggestions.subviews[1].className, "NSBox", "each recommendation has its own native card")
suggestions.size = ns.Size(292, 200); suggestions:layout(292)
t.expect(suggestions.subviews[1].frame.size.width <= 292, "recommendation card fits a narrow inspector")
os.exit(t.summary() and 0 or 1)
