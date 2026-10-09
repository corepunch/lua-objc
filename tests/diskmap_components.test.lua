_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Inventory = require("apps.diskmap.components.InventoryList")
for _, kind in ipairs({"devices", "runtimes", "plan", "worktrees"}) do
	local data = Inventory.data({kind = kind})
	t.assertEqual(data.columns.date, 160, kind .. " uses the same date column, wide enough for \"Last change unknown\"")
	t.assertEqual(data.columns.size, 110, kind .. " uses the same size column")
	t.expect(type(data.role) == "string" and type(data.subtitle) == "string", kind .. " names native row fields")
end
local base = {__baseDir = "apps/diskmap/views/pages/", actions = {open = function() end, close = function() end, markRow = function() end}}
for _, source in ipairs({
	'<Breadcrumb><Crumb name="Storage" action="open"/><Crumb name="Developer" current="true"/></Breadcrumb>',
	'<SymbolRow name="clock"><Label text="History"/></SymbolRow>',
	'<Disclosure label="Details" expanded="true"><Label text="Evidence"/></Disclosure>',
	'<InventoryList kind="devices"/>',
	'<SettingRow title="History" detail="Store category totals" toggleId="history" action="open"/>',
	'<LegendRow label="Apps" color="systemBlue" sizeText="3 GB" share="50%" linked="true" action="open"/>',
	'<LegendRow label="Folders" color="systemBlue" sizeText="3 GB" share="50%" linked="false"/>',
}) do t.expect(xml.render(source, base, ns) ~= nil, "component renders: " .. source:match("<(%w+)")) end
os.exit(t.summary() and 0 or 1)
