_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
for _, constructor in ipairs({ns.List, ns.OutlineView}) do
	local table = constructor {columns = {{id = "name", title = "Name"}}}
	local selected, activated
	table:onRowSelect(function(_, _, row) selected = row end)
	table:onRowActivate(function(_, _, row) activated = row end)
	table:replaceRows({{id = "a", name = "Device", running = false, available = true, bytes = 12345, metadata = {runtime = "iOS"}}})
	table:selectRow(0)
	t.assertEqual(selected.running, false, "false remains false through native selection")
	t.assertEqual(selected.available, true, "true remains true through native selection")
	t.assertEqual(selected.bytes, 12345, "byte count remains numeric")
	t.assertEqual(selected.metadata.runtime, "iOS", "nested metadata remains structured")
	table:activateRow(0)
	t.assertEqual(activated.running, false, "activation preserves booleans")
	t.assertEqual(activated.bytes, 12345, "activation preserves numbers")
end
os.exit(t.summary() and 0 or 1)
