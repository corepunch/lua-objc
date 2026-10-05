_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Rings = require("apps.diskmap.components.StorageRings")
local Inventory = require("apps.diskmap.components.InventoryList")
local one = Rings.data({}, {{ring = 1, parent = "", value = 2}})
local three = Rings.data({}, {{ring = 3, parent = "p", other = true, value = 2}})
t.expect(math.abs(one.hole - (1 - 0.7 / 3)) < 1e-8, "one ring stays slim")
t.expect(math.abs(three.hole - 0.3) < 1e-8, "three rings preserve the minimum hole")
t.assertEqual(three.sectors[1].opacity, 0.5 * 0.55, "folded sectors keep their parent's faded hue")
for _, kind in ipairs({"devices", "runtimes", "plan", "worktrees"}) do
	local data = Inventory.data({kind = kind})
	t.assertEqual(data.columns.date, 160, kind .. " uses the same date column, wide enough for \"Last change unknown\"")
	t.assertEqual(data.columns.size, 110, kind .. " uses the same size column")
	t.expect(type(data.role) == "string" and type(data.subtitle) == "string", kind .. " names native row fields")
end
local base = {__baseDir = "apps/diskmap/views/pages/", actions = {open = function() end, close = function() end}}
for _, source in ipairs({
	'<StorageRings><StorageSector id="a" value="3" color="systemBlue" label="A" ring="1"/><ChartCenter total="3 GB" caption="Measured"/></StorageRings>',
	'<Breadcrumb><Crumb name="Storage" action="open"/><Crumb name="Developer" current="true"/></Breadcrumb>',
	'<SymbolRow name="clock"><Label text="History"/></SymbolRow>',
	'<Disclosure label="Details" expanded="true"><Label text="Evidence"/></Disclosure>',
	'<InventoryList kind="devices"/>',
	'<SheetHeader icon="tray.full.fill"><Label text="Cleanup"/></SheetHeader>',
	'<SheetFooter/>',
	'<SettingRow title="History" detail="Store category totals" toggleId="history" action="open"/>',
	'<LegendRow label="Apps" color="systemBlue" sizeText="3 GB" share="50%" linked="true" action="open"/>',
	'<LegendRow label="Folders" color="systemBlue" sizeText="3 GB" share="50%" linked="false"/>',
}) do t.expect(xml.render(source, base, ns) ~= nil, "component renders: " .. source:match("<(%w+)")) end
os.exit(t.summary() and 0 or 1)
