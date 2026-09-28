_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")

-- SwiftUI `.minimumScaleFactor`: `size` is the largest size, and a label
-- offered less width shrinks its font to fit, no smaller than the factor.
local function render(width, text)
	local root, refs = xml.render(([[<VStack alignment="center"><VStack id="box" maxWidth="%d" alignment="center">
	<Label id="total" text="%s" size="34" minimumScaleFactor="0.4" lines="1" />
	<Label id="plain" text="%s" size="34" lines="1" />
</VStack></VStack>]]):format(width, text, text), {}, ns)
	root.size = ns.Size(400, 200)
	root:layout(400)
	refs.root = root
	return refs
end

local wide = render(300, "12.1 GB")
t.assertEqual(wide.total.font.pointSize, 34, "with room, the label keeps its largest size")
local narrow = render(80, "166.7 GB")
t.expect(narrow.total.font.pointSize < 34 and narrow.total.font.pointSize >= 34 * 0.4, "offered less width, the font shrinks within its floor")
t.expect(narrow.total.frame.size.width <= 80 and narrow.total.fittingSize.width <= 80, "the shrunken text fits the proposal")
t.assertEqual(narrow.plain.font.pointSize, 34, "a label without a factor keeps its size and truncates")
local tiny = render(20, "166.7 GB")
t.expect(math.abs(tiny.total.font.pointSize - 34 * 0.4) < 0.01, "the font never goes below size times the factor")
-- The declared size returns once there is room again.
narrow.box.maxWidth = 400
narrow.root:layout(400)
t.assertEqual(narrow.total.font.pointSize, 34, "a wider proposal brings back the full size")

-- A donut offers its center content the square inscribed in its hole.
local chart, refs = xml.render([[<SectorChart width="200" height="200" innerRadius="0.5">
	<SectorMark value="1" color="systemBlue" />
	<VStack id="center" alignment="center"><Label id="value" text="640.0 GB" size="34" minimumScaleFactor="0.3" lines="1" /></VStack>
</SectorChart>]], {}, ns)
chart:layout(200)
t.expect(math.abs(refs.center.maxWidth - 100 / math.sqrt(2)) < 0.01, "the hole content is offered the inscribed square")
t.expect(refs.value.frame.size.width <= 100 / math.sqrt(2) + 0.5 and refs.value.font.pointSize < 34, "the total shrinks to the hole")

os.exit(t.summary() and 0 or 1)
