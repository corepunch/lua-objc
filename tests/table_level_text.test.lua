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
		<Column id="shareText" title="Size" width="160" minWidth="120" levelKey="relative" levelColorKey="color" valueKey="size" loadingKey="calculating" imageKey="sizeIcon" imageColorKey="sizeColor" />
	</List>
</VStack>]], {}, ns)
refs.list:replaceRows({
	{name = "Short", shareText = "12%", size = "180.0 MB", relative = 0.1, color = "systemBlue"},
	{name = "Installer", shareText = "100%", size = "≥ 7.2 GB", relative = 1},
	{name = "Pending", shareText = "", size = "Calculating…", calculating = true},
	{name = "Locked", shareText = "", size = "No access", sizeIcon = "lock.fill", sizeColor = "systemOrange"},
})
window:add(root)
window:layout()
bridge._appkitLayout(window)

local meterOf = dofile("tests/fixtures/meter.lua")
local function meter(row) return meterOf(bridge._tableCell(refs.list, 1, row)) end

local bars = {}
for row = 0, 3 do
	local m = meter(row)
	local value, share, bar = m.value, m.share, m.bar
	t.assertEqual(m.cell.className, "LuaTableCellView", "a level column is the table's own native cell")
	t.expect(value.frame.size.width >= value.fittingSize.width, "the value " .. value.stringValue .. " fits without truncating")
	t.expect(not bar.hidden, "every row draws its bar")
	t.assertEqual(bar.frame.size.height, 9, "the bar is a capsule half the height of AppKit's capacity cell")
	t.assertEqual(bar.thickness, 9, "and draws at that thickness, so nothing is cropped")
	t.expect(value.frame.origin.y > bar.frame.origin.y + bar.frame.size.height - 1, "the labels sit above the bar")
	if bar.enabled then
		table.insert(bars, bar.frame)
		t.expect(share.frame.size.width >= share.fittingSize.width, "the share " .. share.stringValue .. " fits without truncating")
		t.expect(math.abs(share.frame.origin.y - value.frame.origin.y) < 1, "value and share share one line")
		t.expect(share.frame.origin.x + share.frame.size.width >= bar.frame.origin.x + bar.frame.size.width - 1,
			"the share ends where the bar ends")
		t.expect(value.frame.origin.x <= bar.frame.origin.x + 1, "the value starts where the bar starts")
	else
		t.assertEqual(share.stringValue, "", "a row without a share shows no share text")
	end
end
t.assertEqual(#bars, 2, "rows with a fraction have an enabled bar")
t.expect(bars[1].origin.x == bars[2].origin.x and bars[1].size.width == bars[2].size.width, "bars in one column share their span")
t.expect(bars[1].size.width > 160 - 20, "the bar spans the column")
t.expect(tostring(meter(0).bar.fillColor) ~= tostring(meter(1).bar.fillColor), "a row's colour tints its bar")
t.assertEqual(meter(0).bar.doubleValue, 0.1, "the bar shows the row's fraction")
t.assertEqual(meter(1).bar.doubleValue, 1, "a full row fills its bar")
t.assertEqual(meter(2).bar.doubleValue, 0, "a row without a fraction has an empty bar")

-- A measuring row puts its spinner before the value, on the value's line.
local pending = meter(2)
t.expect(not pending.spinner.hidden, "a measuring row shows its spinner")
t.expect(pending.symbol.image == nil, "a measuring row shows no state symbol")
local spinnerFrame, valueFrame = pending.spinner.frame, pending.value.frame
t.expect(spinnerFrame.origin.x + spinnerFrame.size.width <= valueFrame.origin.x, "the spinner comes before the value")
t.expect(spinnerFrame.origin.y < valueFrame.origin.y + valueFrame.size.height
	and valueFrame.origin.y < spinnerFrame.origin.y + spinnerFrame.size.height, "the spinner sits on the value's line")
t.assertEqual(pending.value.stringValue, "Calculating…", "the value reads Calculating…")
t.expect(meter(0).spinner.hidden, "a measured row has no spinner")

-- A state symbol takes the spinner's square and tints its word.
local locked = meter(3)
t.expect(locked.symbol.image ~= nil and locked.spinner.hidden, "a state row shows its symbol, not the spinner")
local symbolFrame = locked.symbol.frame
t.assertEqual(symbolFrame.size.width, spinnerFrame.size.width, "symbol and spinner share one square")
t.assertEqual(symbolFrame.origin.x, spinnerFrame.origin.x, "symbol and spinner start at one edge")
t.expect(locked.value.frame.origin.x >= symbolFrame.origin.x + symbolFrame.size.width, "the state word follows its symbol")
t.expect(meter(0).symbol.image == nil, "a measured row has no state symbol")

-- A row that finishes measuring drops its spinner on reuse.
refs.list:replaceRows({{name = "Pending", shareText = "3%", size = "2.0 GB", relative = 0.3}})
local done = meter(0)
t.expect(done.spinner.hidden, "a measured row drops the spinner")
t.assertEqual(done.value.stringValue, "2.0 GB", "the value shows the size")
t.assertEqual(done.share.stringValue, "3%", "the share shows beside it")

-- VoiceOver reads the column's title, the size and its share together.
t.assertEqual(done.bar.accessibilityLabel, "Size: 2.0 GB, 3%", "the bar's label is its column's title, size and share")

-- A column describes its cell with key attributes; rows are data, not views.
local ok, err = pcall(xml.render, '<List><Column id="a"><Label text="x" /></Column></List>', {}, ns)
t.expect(not ok and tostring(err):find("takes no content", 1, true) ~= nil, "a Column with child views is rejected")
local plain = xml.render('<Label text="$a {b}" />', {}, ns)
t.assertEqual(plain.text, "$a {b}", "attributes are literal text: there is no binding syntax")

-- `lines` lets a text column wrap before it truncates.
local wrapRoot, wrapRefs = xml.render([[<VStack>
	<List id="list" style="fullWidth" header="false" rowHeight="44" maxWidth="infinity" height="100">
		<Column id="detail" title="Detail" width="120" lines="2" />
		<Column id="plain" title="Plain" width="120" />
	</List>
</VStack>]], {}, ns)
wrapRefs.list:replaceRows({{detail = "main · 4 uncommitted changes in the tree", plain = "main · 4 uncommitted changes in the tree"}, {detail = "main", plain = "main"}})
local wrapWindow = ns.Window { visible = false, width = 300, height = 140 }
wrapWindow:add(wrapRoot)
wrapWindow:layout()
bridge._appkitLayout(wrapWindow)
local function textOf(column, row)
	local cell = bridge._tableCell(wrapRefs.list, column, row)
	cell:layout()
	return cell.textField
end
local single = textOf(1, 0).frame.size.height
t.expect(textOf(0, 0).frame.size.height >= single * 2 - 1, "a long detail takes two lines")
t.assertEqual(textOf(0, 1).frame.size.height, textOf(1, 1).frame.size.height, "a short detail stays on one line")
t.expect(textOf(0, 0).frame.size.height <= 44, "and never outgrows its row")

os.exit(t.summary() and 0 or 1)
