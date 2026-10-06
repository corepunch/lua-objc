_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")

-- Writing a view's size lands on the settled layout. Layout pending above
-- the view used to run on the next geometry read and give the view its
-- container's size again, so a first pass at a new size differed from
-- every later one (the Diskmap maps at 724 points).
local root, refs = xml.render([[<VStack id="outer" width="874" height="656">
	<Label id="note" text="Short" />
	<VStack id="page" maxWidth="infinity" maxHeight="infinity">
		<HStack id="body" maxWidth="infinity"><Label text="Content" maxWidth="infinity" /></HStack>
	</VStack>
</VStack>]], {}, ns)
root.size = ns.Size(874, 656)
root:layout(874)
t.assertEqual(refs.page.frame.size.width, 874, "the page first fills its container")

-- A change outside the page leaves its container's layout pending.
refs.note.text = "A longer note above the page"
local widths = {}
for pass = 1, 3 do
	refs.page.size = ns.Size(724, 580)
	refs.page:layout(724)
	table.insert(widths, refs.page.frame.size.width)
	t.assertEqual(refs.body.frame.size.width, 724, "pass " .. pass .. " lays the content out at the written width")
end
t.assertEqual(widths[1], 724, "the first pass keeps the written width")
t.assertEqual(widths[1], widths[2], "and matches the second")
t.assertEqual(widths[2], widths[3], "layout is idempotent")
t.assertEqual(refs.note.text, "A longer note above the page", "the pending change itself was applied")

os.exit(t.summary() and 0 or 1)
