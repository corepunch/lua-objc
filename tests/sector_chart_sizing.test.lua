_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")

-- A scroll view proposes a width and no height. A scalable chart answers
-- with its ideal square constrained to the space left by sibling minimums.
local root, refs = xml.render([[
<ScrollView maxWidth="infinity" maxHeight="infinity">
 <VStack>
  <HStack id="row" spacing="20" alignment="center" flexGrow="0">
   <SectorChart id="chart" scalable="true" diameter="360" flexGrow="0" flexShrink="1" innerRadius="0.6">
    <SectorMark value="1" color="systemBlue" />
    <Label text="Total" size="24" minimumScaleFactor="0.5" />
   </SectorChart>
   <VStack id="legend" minWidth="300" flexGrow="1" flexBasis="0">
    <Label text="Measured storage" />
   </VStack>
  </HStack>
 </VStack>
</ScrollView>]], {}, ns)
for _, width in ipairs({1000, 550, 420, 1000}) do
	root.size = ns.Size(width, 500)
	root:layout(width)
	local side = math.min(360, width - 320)
	t.assertSize(refs.chart, side, side, "the ring is a square at width " .. width)
	t.assertEqual(refs.legend.frame.size.width, width - side - 20, "the legend takes the remainder")
	t.assertEqual(refs.row.frame.size.height, side, "the row reserves no unused chart height")
	t.assertEqual(refs.chart.subviews[1].frame.size.width, side, "arcs fill their chart")
	t.assertEqual(refs.chart.subviews[1].frame.size.height, side, "arc height follows resize")
end

local empty, emptyRefs = xml.render('<VStack><HStack flexGrow="0"><SectorChart id="empty" scalable="true" diameter="240" flexGrow="0" /></HStack></VStack>', {}, ns)
empty.size = ns.Size(500, 500)
empty:layout(500)
t.assertSize(emptyRefs.empty, 240, 240, "empty data has the same ideal size")
os.exit(t.summary() and 0 or 1)
