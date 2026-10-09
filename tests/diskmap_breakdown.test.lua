_G.__headless = true
local t = require("TestKit")
local Breakdown = require("apps.diskmap.helpers.Breakdown")
local Component = require("apps.diskmap.components.Breakdown")
local marks, legend = Breakdown.rows({})
t.assertEqual(#marks, 0, "empty input has no chart sectors")
t.assertEqual(#legend, 0, "empty input has no legend rows")
marks, legend = Breakdown.rows({{id = "zero", bytes = 0}, {id = "unknown"}})
t.assertEqual(#marks, 0, "zero and unknown sizes cannot create sectors")
t.assertEqual(#legend, 0, "zero and unknown sizes add no filler to the concise legend")
marks, legend = Breakdown.rows({{id = "unnamed", bytes = 1}})
t.assertEqual(legend[1].name, "Item", "an unnamed item has a readable fallback")
t.assertEqual(legend[1].color, "systemGray", "missing colors use a system color")
local rows, total = {}, 0
for index = 1, 20 do
	local bytes = 21 - index
	table.insert(rows, {id = tostring(index), name = "Item " .. index, bytes = bytes})
	total = total + bytes
end
marks, legend = Breakdown.rows(rows)
t.assertEqual(#marks, Breakdown.limit + 1, "the chart folds its long tail once")
t.assertEqual(#legend, Breakdown.limit + 1, "the concise legend has the same tail")
local represented = 0
for _, mark in ipairs(marks) do represented = represented + mark.value end
t.assertEqual(represented, total, "folding preserves the full measured total")
t.assertEqual(legend[#legend].name, "12 more items", "the tail names its item count")
t.assertEqual(#rows, 20, "summarizing never drops rows from the full list")
local card = Component.data({}, {{tag = "BreakdownSector", id = "a"}, {tag = "BreakdownLegend", id = "a"},
	{tag = "BreakdownNote", title = "Purgeable"}, {tag = "BreakdownRectangle", id = "a"}})
for _, bucket in ipairs({"sectors", "legend", "notes", "rectangles"}) do
	t.assertEqual(#card[bucket], 1, "the card sorts its " .. bucket .. " records")
end
t.assertEqual(card.toggleSymbol, nil, "the chart style is the toolbar's, not the card's")
os.exit(t.summary() and 0 or 1)
