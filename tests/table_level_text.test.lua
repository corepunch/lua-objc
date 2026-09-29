_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local xml = require("ui.xml")

-- Diskmap's size meter is a column content template (views/cells/Meter):
-- the size (with its spinner while measuring) leads and the share trails on
-- a line above a full-width capacity bar.
local window = ns.Window { visible = false, width = 400, height = 240 }
local root, refs = xml.renderFile("tests/fixtures/meter_list.etlua", {}, ns)
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
local function frame(_, view) return view.frameInWindow end

local bars = {}
for row = 0, 3 do
	local m = meter(row)
	local value, share, bar = m.value, m.share, m.bar
	t.assertEqual(m.cell.className, "LuaTemplateCellView", "a column with content renders its template")
	t.expect(value ~= nil, "a meter has a value label")
	local valueFrame, barFrame = frame(m.cell, value), frame(m.cell, bar)
	t.expect(valueFrame.size.width >= value.fittingSize.width, "the value " .. value.text .. " fits without truncating")
	t.expect(not bar.hidden, "every row draws its bar")
	t.expect(barFrame.size.height >= 18, "the bar keeps the height its capsule draws in")
	t.expect(valueFrame.origin.y > barFrame.origin.y + barFrame.size.height - 1, "the labels sit above the bar")
	if bar.enabled then
		table.insert(bars, barFrame)
		local shareFrame = frame(m.cell, share)
		t.expect(shareFrame.size.width >= share.fittingSize.width, "the share " .. share.text .. " fits without truncating")
		t.expect(math.abs(shareFrame.origin.y - valueFrame.origin.y) < 1, "value and share share one line")
		t.expect(shareFrame.origin.x + shareFrame.size.width >= barFrame.origin.x + barFrame.size.width - 1,
			"the share ends where the bar ends")
		t.expect(valueFrame.origin.x <= barFrame.origin.x + 1, "the value starts where the bar starts")
	else
		t.expect(share == nil, "a row without a share shows no share label")
	end
end
t.assertEqual(#bars, 2, "rows with a fraction have an enabled bar")
t.expect(bars[1].origin.x == bars[2].origin.x and bars[1].size.width == bars[2].size.width, "bars in one column share their span")
t.expect(bars[1].size.width > 160 - 20, "the bar spans the column")
t.assertEqual(meter(0).bar.doubleValue, 0.1, "the bar shows the row's fraction")
t.assertEqual(meter(1).bar.doubleValue, 1, "a full row fills its bar")
t.assertEqual(meter(2).bar.doubleValue, 0, "a row without a fraction has an empty bar")

-- A measuring row puts its spinner before the value, on the value's line.
local pending = meter(2)
t.expect(not pending.spinner.hidden, "a measuring row shows its spinner")
t.expect(pending.symbol.hidden, "a measuring row shows no state symbol")
local spinnerFrame, valueFrame = frame(pending.cell, pending.spinner), frame(pending.cell, pending.value)
t.expect(spinnerFrame.origin.x + spinnerFrame.size.width <= valueFrame.origin.x, "the spinner comes before the value")
t.expect(spinnerFrame.origin.y < valueFrame.origin.y + valueFrame.size.height
	and valueFrame.origin.y < spinnerFrame.origin.y + spinnerFrame.size.height, "the spinner sits on the value's line")
t.assertEqual(pending.value.text, "Calculating…", "the value reads Calculating…")
t.expect(meter(0).spinner.hidden, "a measured row has no spinner")

-- A state symbol takes the spinner's square and tints its word.
local locked = meter(3)
t.expect(not locked.symbol.hidden and locked.spinner.hidden, "a state row shows its symbol, not the spinner")
t.assertEqual(locked.symbol.symbolName, "lock.fill", "the symbol is the row's")
local symbolFrame = frame(locked.cell, locked.symbol)
t.assertEqual(symbolFrame.size.width, spinnerFrame.size.width, "symbol and spinner share one square")
t.assertEqual(symbolFrame.origin.x, spinnerFrame.origin.x, "symbol and spinner start at one edge")
t.expect(frame(locked.cell, locked.value).origin.x >= symbolFrame.origin.x + symbolFrame.size.width, "the state word follows its symbol")
t.expect(meter(0).symbol.hidden, "a measured row has no state symbol")

-- A row that finishes measuring drops its spinner on reuse.
refs.list:replaceRows({{name = "Pending", shareText = "3%", size = "2.0 GB", relative = 0.3}})
local done = meter(0)
t.expect(done.spinner.hidden, "a measured row drops the spinner")
t.assertEqual(done.value.text, "2.0 GB", "the value shows the size")
t.assertEqual(done.share.text, "3%", "the share shows beside it")

-- VoiceOver reads the bar as its column's title, the size and the share.
t.assertEqual(done.bar.accessibilityLabel, "Size: 2.0 GB 3%", "the bar's label is its column's title, size and share")
t.assertEqual(done.cell.textField.text, "2.0 GB", "the cell's text is its size")

os.exit(t.summary() and 0 or 1)
