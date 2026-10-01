_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local xml = require("ui.xml")

-- Fitted tables inside scrolling pages cannot inherit a viewport height.
-- Their native loading overlay must contribute its own minimum body size.
for _, header in ipairs({"false", "true"}) do
	local root, refs = xml.render('<VStack spacing="0"><List id="list" header="' .. header .. '" scrollDisabled="true"><Column id="name" title="Name" /></List><Label id="next" text="After the table" /></VStack>', {}, ns)
	root.size = ns.Size(420, 240); root:layout(420)
	local emptyHeight = refs.list.frame.size.height
	refs.list:showLoading()
	root:layout(420)
	local spinner = bridge._tableSpinnerFrame(refs.list)
	t.expect(refs.list.frame.size.height > emptyHeight, "loading contributes height with header " .. header)
	t.expect(spinner.y >= 0 and spinner.y + spinner.height <= refs.list.frame.size.height, "spinner fits in the list with header " .. header)
	t.expect(math.abs(spinner.x + spinner.width / 2 - refs.list.frame.size.width / 2) < 1, "spinner stays centered")
	refs.list:showLoading(); root:layout(420)
	t.assertEqual(bridge._tableSpinnerFrame(refs.list).height, spinner.height, "repeated loading preserves native size")
	refs.list:hideLoading(); root:layout(420)
	t.assertEqual(refs.list.frame.size.height, emptyHeight, "hiding loading restores fitted empty size")
	refs.list:replaceRows({{name = "Measured"}}); root:layout(420)
	local rowHeight = refs.list.frame.size.height
	refs.list:showLoading(); root:layout(420)
	refs.list:hideLoading(); root:layout(420)
	t.assertEqual(refs.list.frame.size.height, rowHeight, "loading leaves measured rows unchanged")
	t.assertEqual(refs.list.rowCount, 1, "loading leaves row data unchanged")
end
os.exit(t.summary() and 0 or 1)
