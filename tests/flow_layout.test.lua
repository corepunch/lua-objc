_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local root, refs = xml.render([[
<VStack spacing="0" maxWidth="infinity">
  <FlowStack id="flow" maxWidth="infinity" spacing="10">
    <VStack id="a" width="60" height="20" />
    <VStack id="b" width="80" height="30" />
    <VStack id="c" width="40" height="10" />
  </FlowStack>
  <Label id="after" text="After the flow" />
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
local padded, p = xml.render('<VStack><FlowStack id="flow" padding="5" spacing="10" maxWidth="infinity"><VStack width="60" height="20"/><VStack width="80" height="30"/></FlowStack></VStack>', {}, ns)
padded.size = ns.Size(160, 150); padded:layout(160)
t.assertEqual(p.flow.size.height, 40, "padding is applied once around an exact-fit row")
t.assertEqual(p.flow.subviews[1].frame.origin.x, 5, "flow respects leading padding")
local limited, items = xml.render([[
<VStack spacing="0" maxWidth="infinity">
  <FlowStack id="flow" maxRows="1" maxWidth="infinity" spacing="10">
    <VStack id="first" width="60" height="20" />
    <VStack id="second" width="80" height="20" />
    <VStack id="third" width="40" height="20" />
  </FlowStack>
</VStack>]], {}, ns)
limited.size = ns.Size(150, 80); limited:layout(150)
t.assertEqual(items.flow.size.height, 20, "limited flow keeps one row")
t.expect(not items.first.hidden and not items.second.hidden and items.third.hidden, "limited flow hides items that do not fit completely")
limited.size = ns.Size(210, 80); limited:layout(210)
t.expect(not items.third.hidden, "widening restores an overflow item")
limited.size = ns.Size(100, 80); limited:layout(100)
t.expect(items.second.hidden and items.third.hidden, "shrinking hides lower-priority trailing items")
limited.size = ns.Size(50, 80); limited:layout(50)
t.expect(items.first.hidden and items.second.hidden, "a row narrower than its first item shows no clipped item")
os.exit(t.summary() and 0 or 1)
