_G.__headless = true
-- Rows that make a vertical scroller appear narrow the visible width after
-- the columns were sized. The columns must be sized again, or the last one
-- sits under the scroller (seen in Diskmap's "Changes Since" sheet).
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local xml = require("ui.xml")

for _, style in ipairs({"inset", "fullWidth", "plain"}) do
	local window = ns.Window { visible = false, width = 680, height = 300 }
	local root, refs = xml.render([[
<VStack maxWidth="infinity" maxHeight="infinity">
  <List id="list" style="]] .. style .. [[" header="true" rowHeight="44" flexGrow="1" flexBasis="0" maxWidth="infinity" maxHeight="infinity">
    <Column id="name" title="Location" minWidth="220" />
    <Column id="change" title="Change" width="90" minWidth="90" alignment="trailing" />
    <Column id="bar" title="" width="110" minWidth="110" />
    <Column id="before" title="Before" width="90" minWidth="90" alignment="trailing" />
    <Column id="now" title="Now" width="90" minWidth="90" alignment="trailing" />
  </List>
</VStack>]], {}, ns)
	window:add(root)
	window:layout()
	local list = refs.list
	local emptyClip = list.contentView.bounds.size.width
	local rows = {}
	for index = 1, 40 do table.insert(rows, {name = "Location " .. index, change = "+1.0 GB", before = "1.0 GB", now = "2.0 GB"}) end
	list:replaceRows(rows)
	local clip = list.contentView.bounds.size.width
	local table_ = list.documentView
	t.expect(clip <= emptyClip, style .. ": rows that scroll never widen the visible area")
	t.expect(table_.frame.size.width <= clip + 0.5, style .. ": the table fits the visible width once rows need a scroller")
	t.assertEqual(list.hasHorizontalScroller, false, style .. ": no horizontal scroller appears")
end

os.exit(t.summary() and 0 or 1)
