_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local root, refs = xml.render([[
<VStack spacing="0" fillWidth="true">
  <FlowStack ref="flow" fillWidth="true" spacing="10">
    <VStack ref="a" fixedWidth="60" fixedHeight="20" />
    <VStack ref="b" fixedWidth="80" fixedHeight="30" />
    <VStack ref="c" fixedWidth="40" fixedHeight="10" />
  </FlowStack>
  <Label ref="after" text="After the flow" />
</VStack>]], {}, ns)
local function resize(width)
	root.size = ns.Size(width, 200); root:layout(width)
end
local function top(view)
	return refs.flow.size.height - view.frame.origin.y - view.size.height
end
resize(150)
t.assertEqual(refs.flow.size.height, 50, "exact-fit row plus wrapped row determines height")
t.assertEqual(refs.b.frame.origin.x, 70, "second item fills the first row exactly")
t.assertEqual(top(refs.a), 5, "unequal-height items are vertically centered")
t.assertEqual(top(refs.b), 0, "tallest item defines row top")
t.assertEqual(top(refs.c), 40, "next row starts after spacing")
t.expect(refs.after.frame.origin.y + refs.after.size.height <= refs.flow.frame.origin.y, "following content stays below wrapped rows")
resize(149)
t.assertEqual(refs.flow.size.height, 60, "one-point shrink recomputes row breaks")
t.assertEqual(refs.b.frame.origin.x, 0, "item that no longer fits moves to next row")
t.assertEqual(refs.c.frame.origin.x, 90, "next item uses remaining width in second row")
resize(210)
t.assertEqual(refs.flow.size.height, 30, "wide layout fits all items on one row")
t.assertEqual(refs.c.frame.origin.x, 160, "widening repacks existing children")
t.assertEqual(refs.flow.subviews[2], refs.b, "resize preserves native child identity")
refs.b.hidden = true
resize(150)
t.assertEqual(refs.flow.size.height, 20, "hidden items consume no rows or spacing")
t.assertEqual(refs.c.frame.origin.x, 70, "visible siblings pack together after hiding")
refs.b.hidden = false
resize(150)
t.assertEqual(refs.flow.size.height, 50, "unhiding restores original packing")
resize(0)
t.expect(refs.flow.size.height >= 0 and refs.c.frame.origin.x == 0, "zero-width proposal remains finite and places each fixed item on a row")
resize(210)
t.assertEqual(refs.flow.size.height, 30, "zero-size round trip does not retain stale row breaks")
local empty = xml.render('<FlowStack padding="0" spacing="10"/>', {}, ns)
empty:layout(150)
t.assertEqual(empty.size.height, 0, "empty flow adds no row spacing")
local padded, p = xml.render('<VStack><FlowStack ref="flow" padding="5" spacing="10" fillWidth="true"><VStack fixedWidth="60" fixedHeight="20"/><VStack fixedWidth="80" fixedHeight="30"/></FlowStack></VStack>', {}, ns)
padded.size = ns.Size(160, 150); padded:layout(160)
t.assertEqual(p.flow.size.height, 40, "padding is applied once around an exact-fit row")
t.assertEqual(p.flow.subviews[1].frame.origin.x, 5, "flow respects leading padding")
os.exit(t.summary() and 0 or 1)
