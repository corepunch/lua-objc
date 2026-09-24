_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")

local root, refs = xml.render([[
<VStack padding="10" spacing="8">
	<Image id="cover" symbol="photo" maxWidth="infinity" height="280" />
	<HStack id="row" maxWidth="infinity" height="40" spacing="0">
		<Label id="fixed" text="Fixed" width="80" height="20" />
		<TextField id="input" value="Unchanged" maxWidth="infinity" height="20" />
	</HStack>
</VStack>]], {}, ns)
local function resize(width)
	root.size = ns.Size(width, 400)
	root:layout(width)
end
resize(420)
t.assertSize(refs.cover, 400, 280, "cover expands horizontally and preserves explicit height")
t.assertSize(refs.fixed, 80, 20, "fixed dimensions preserve natural sibling contract")
t.assertSize(refs.input, 320, 20, "infinity consumes remaining horizontal space")
resize(220)
t.assertSize(refs.cover, 200, 280, "narrow parent reproposes cover width")
t.assertSize(refs.input, 120, 20, "input shrinks with its parent")
resize(620)
t.assertSize(refs.cover, 600, 280, "large parent expands cover without stretching height")
resize(420)
t.assertSize(refs.cover, 400, 280, "resize round trip restores dimensions")
t.assertEqual(refs.input.text, "Unchanged", "resizing preserves control state")
t.assertEqual(refs.row.spacing, 0, "sizing leaves sibling spacing unchanged")

local vertical, v = xml.render([[
<VStack spacing="0">
	<VStack id="space" width="30" maxHeight="infinity" />
	<VStack id="footer" width="30" height="20" />
</VStack>]], {}, ns)
vertical.size = ns.Size(100, 240)
vertical:layout(100)
t.assertSize(v.space, 30, 220, "maxHeight infinity expands only vertically")
t.assertSize(v.footer, 30, 20, "vertical expansion preserves fixed siblings")

local zero, z = xml.render('<VStack spacing="0"><VStack id="zero" width="0" height="0" /></VStack>', {}, ns)
zero.size = ns.Size(100, 100)
zero:layout(100)
t.assertSize(z.zero, 0, 0, "zero dimensions are explicit rather than missing")

local bounded, b = xml.render('<VStack><Label id="text" text="A long label to constrain" minWidth="30" maxWidth="60" minHeight="12" maxHeight="24" /></VStack>', {}, ns)
bounded.size = ns.Size(400, 200)
bounded:layout(400)
local w, h = b.text.size.width, b.text.size.height
t.expect(w >= 30 and w <= 60 and h >= 12 and h <= 24, "finite bounds remain constraints")

for _, attrs in ipairs({
	'width="infinity"', 'height="-1"', 'width="nonsense"',
	'minWidth="infinity"', 'maxHeight="-1"', 'maxWidth="1e999"',
	'minWidth="50" maxWidth="20"',
	'fillWidth="true"', 'fillHeight="true"', 'fixedWidth="80"', 'fixedHeight="20"',
}) do
	t.assertThrows(function() xml.render('<VStack ' .. attrs .. '/>', {}, ns) end,
		"invalid or removed dimensions fail: " .. attrs)
end

-- Verify the shared renderer's contract before either platform constructs a
-- native view. Infinity must never reach native geometry as an infinite float.
local captured
xml.render('<Image path="cover.jpg" maxWidth="infinity" height="280" />', {}, {
	Image = function(props) captured = props; return props end,
})
t.assertEqual(captured.fixedHeight, 280, "both platforms receive the same fixed-height proposal")
t.expect(captured.fillWidth and captured.maxWidth == nil, "infinity becomes an axis expansion proposal")

local desc = require("ui.viewdesc").fromString('<VStack maxWidth="infinity" height="280"><Label text="Hi" width="40" /></VStack>')
t.assertEqual(desc.props.maxWidth, "infinity", "descriptions retain declarative infinity")
t.assertEqual(desc.props.height, 280, "descriptions retain height")
t.assertEqual(desc.children[1].props.width, 40, "text descriptions retain sizing")
os.exit(t.summary() and 0 or 1)
