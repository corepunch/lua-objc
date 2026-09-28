_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local xml = require("ui.xml")

-- A level column's labels take the width of the widest one, so a size such
-- as "7.2 GB" is never truncated, and every bar starts at the same x.
local window = ns.Window { visible = false, width = 400, height = 240 }
local root, refs = xml.render([[<VStack>
	<List id="list" style="fullWidth" header="false" rowHeight="40" maxWidth="infinity" height="200">
		<Column id="name" title="Item" minWidth="140" />
		<Column id="size" title="Size" width="110" minWidth="80" levelKey="relative" />
	</List>
</VStack>]], {}, ns)
refs.list:replaceRows({
	{name = "Short", size = "12%", relative = 0.1},
	{name = "Installer", size = "7.2 GB", relative = 1},
	{name = "Archive", size = "180.0 MB", relative = 0.4},
})
window:add(root)
window:layout()
bridge._appkitLayout(window)
local bars = {}
for row = 0, 2 do
	local cell = bridge._tableCell(refs.list, 1, row)
	local label = cell.textField
	t.expect(label.frame.size.width >= label.fittingSize.width,
		"the label " .. label.stringValue .. " fits without truncating")
	for _, view in ipairs(cell.subviews) do
		if view.className == "LuaLevelIndicator" then table.insert(bars, view.frame.origin.x) end
	end
end
t.assertEqual(#bars, 3, "every row has a bar")
t.expect(bars[1] == bars[2] and bars[2] == bars[3], "bars in one column start at the same x")

os.exit(t.summary() and 0 or 1)
