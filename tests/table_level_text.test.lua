_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local xml = require("ui.xml")

-- A level column is one meter: the value (with its spinner while measuring)
-- leads and the share trails on a line above a full-width capacity bar.
local window = ns.Window { visible = false, width = 400, height = 240 }
local root, refs = xml.render([[<VStack>
	<List id="list" style="fullWidth" header="false" rowHeight="44" maxWidth="infinity" height="200">
		<Column id="name" title="Item" minWidth="140" />
		<Column id="share" title="Size" width="160" minWidth="120" levelKey="relative" valueKey="size" loadingKey="calculating" />
	</List>
</VStack>]], {}, ns)
refs.list:replaceRows({
	{name = "Short", share = "12%", size = "180.0 MB", relative = 0.1},
	{name = "Installer", share = "100%", size = "≥ 7.2 GB", relative = 1},
	{name = "Pending", share = "", size = "Calculating…", calculating = true},
})
window:add(root)
window:layout()
bridge._appkitLayout(window)

local bars = {}
for row = 0, 2 do
	local cell = bridge._tableCell(refs.list, 1, row)
	cell:layout()
	local share, value, bar = cell.textField, cell.valueField, cell.levelIndicator
	t.expect(value ~= nil, "a meter has a value label")
	t.expect(value.frame.size.width >= value.fittingSize.width, "the value " .. value.stringValue .. " fits without truncating")
	t.expect(share.stringValue == "" or share.frame.size.width >= share.fittingSize.width, "the share " .. share.stringValue .. " fits without truncating")
	t.expect(not bar.hidden, "every row draws its bar")
	if bar.enabled then
		table.insert(bars, bar.frame)
		t.expect(value.frame.origin.y > bar.frame.origin.y + bar.frame.size.height - 1, "the labels sit above the bar")
		t.expect(math.abs(share.frame.origin.y - value.frame.origin.y) < 1, "value and share share one line")
		t.expect(share.frame.origin.x + share.frame.size.width >= bar.frame.origin.x + bar.frame.size.width - 1,
			"the share ends where the bar ends")
		t.expect(value.frame.origin.x <= bar.frame.origin.x + 1, "the value starts where the bar starts")
	end
end
t.assertEqual(#bars, 2, "rows with a fraction have an enabled bar")
t.expect(not bridge._tableCell(refs.list, 1, 2).levelIndicator.enabled, "a row without a fraction has an empty, disabled bar")
t.expect(bars[1].origin.x == bars[2].origin.x and bars[1].size.width == bars[2].size.width, "bars in one column share their span")
t.expect(bars[1].size.width > 160 - 20, "the bar spans the column")

-- A measuring row puts its spinner before the value, on the value's line.
local pending = bridge._tableCell(refs.list, 1, 2)
pending:layout()
t.expect(not pending.loadingIndicator.hidden, "a measuring row shows its spinner")
t.expect(pending.loadingIndicator.frame.origin.x + pending.loadingIndicator.frame.size.width <= pending.valueField.frame.origin.x,
	"the spinner comes before the value")
t.assertEqual(pending.valueField.stringValue, "Calculating…", "the value reads Calculating…")
t.expect(bridge._tableCell(refs.list, 1, 0).loadingIndicator.hidden, "a measured row has no spinner")

-- A row that finishes measuring drops its spinner on reuse.
refs.list:replaceRows({{name = "Pending", share = "3%", size = "2.0 GB", relative = 0.3}})
local done = bridge._tableCell(refs.list, 1, 0)
t.expect(done.loadingIndicator.hidden, "a measured row drops the spinner")
t.assertEqual(done.valueField.stringValue, "2.0 GB", "the value shows the size")

-- VoiceOver reads the share and the value together.
t.expect(done.levelIndicator.accessibilityLabel:find("3%%, 2.0 GB") ~= nil, "the bar's label names share and size")

os.exit(t.summary() and 0 or 1)
