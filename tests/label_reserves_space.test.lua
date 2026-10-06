_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")

-- SwiftUI `.lineLimit(2, reservesSpace: true)`: the label is two lines tall
-- whatever its text, so a flexible sibling keeps its size as the text wraps.
local function render(text, reserves)
	local root, refs = xml.render(([[<VStack id="pane" maxHeight="infinity" spacing="12" alignment="center">
	<VStack id="chart" flexGrow="1" maxWidth="infinity" maxHeight="infinity" />
	<Label id="caption" text="%s" size="12" maxWidth="infinity" alignment="center" lines="2" reservesSpace="%s" truncation="tail" />
</VStack>]]):format(text, reserves and "true" or "false"), {}, ns)
	root.size = ns.Size(200, 300)
	root:layout(200)
	return refs
end

local short = "Docs · 4.7 GB"
local long = "System Data › Logs & diagnostics › com.apple.something.long › 4.7 GB · 12.2%"
local endless = long .. " " .. long .. " " .. long
local one, two, many = render(short, true), render(long, true), render(endless, true)
local _, oneHeight = one.caption.frame.size.width, one.caption.frame.size.height
local lineHeight = math.ceil(one.caption.font.ascender - one.caption.font.descender + one.caption.font.leading)
t.assertEqual(oneHeight, lineHeight * 2, "one line of text still takes two lines")
t.assertEqual(two.caption.frame.size.height, oneHeight, "two lines of text take the same two lines")
t.assertEqual(many.caption.frame.size.height, oneHeight, "longer text truncates within the two lines")
t.assertEqual(one.chart.frame.size.height, two.chart.frame.size.height, "the flexible sibling keeps its height as the text wraps")
t.assertEqual(one.chart.frame.size.height, many.chart.frame.size.height, "and when the text overflows")

-- Without it the label is as tall as its text, which is what moved the chart.
local plainShort, plainLong = render(short, false), render(long, false)
t.assertEqual(plainShort.caption.frame.size.height, lineHeight, "a plain label takes the lines its text needs")
t.expect(plainLong.chart.frame.size.height < plainShort.chart.frame.size.height, "so wrapping text squeezes its sibling")

-- Changing the text of the retained label keeps the reserved height.
one.caption.text = long
one.pane:layout(200)
t.assertEqual(one.caption.frame.size.height, oneHeight, "a new text keeps the reserved height")

os.exit(t.summary() and 0 or 1)
