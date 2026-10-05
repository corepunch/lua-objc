_G.__headless = true
local ns = require("AppKit")
local t = require("TestKit")
local xml = require("ui.xml")
local bridge = require("AppKitNative")

-- A fixed column keeps its declared width. A viewport too narrow for every
-- declared width shrinks fixed columns toward their minimums only as far as
-- needed, and a later wider viewport gives the declared widths back: a
-- table first laid out narrow must not keep its columns at their minimums
-- (Diskmap's Worktrees list cut "Local commits" at every window size).
local _, refs = xml.render([[<List id="list" style="fullWidth" header="false">
	<Column id="name" title="Name" minWidth="180" />
	<Column id="role" title="Plan" width="110" minWidth="90" />
	<Column id="date" title="Date" width="150" minWidth="120" />
</List>]], {}, ns)
local list = refs.list
list:replaceRows({{id = "a", name = "coin-quest", role = "Local commits", date = "1 month ago"}})

local function widths(width)
	list.size = ns.Size(width, 200); list:layout(width)
	local result = {}
	for _, column in ipairs(bridge._tableColumnWidths(list)) do result[column.id] = column.width end
	return result
end

local narrow = widths(300)
t.assertEqual(narrow.name, 180, "too narrow: the flexible column takes its minimum")
t.assertEqual(narrow.role, 90, "too narrow for all minimums: fixed columns at their minimums")
t.assertEqual(narrow.date, 120, "too narrow for all minimums: every fixed column at its minimum")

local tight = widths(450)
t.assertEqual(tight.name, 180, "tight: the flexible column stays at its minimum")
t.expect(tight.role > 90 and tight.role < 110, "tight: a fixed column gives up only part of its width")
t.expect(tight.date > 120 and tight.date < 150, "tight: every fixed column shares the shortfall")

local wide = widths(900)
t.assertEqual(wide.role, 110, "wide again: the declared width comes back")
t.assertEqual(wide.date, 150, "wide again: every declared width comes back")
t.expect(wide.name > 180, "wide: the flexible column takes the rest")

os.exit(t.summary() and 0 or 1)
