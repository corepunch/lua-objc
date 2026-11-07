_G.__headless = true
local ns = require("AppKit")
local t = require("TestKit")
local xml = require("ui.xml")
local Template = require("ui.template")

-- A list's rows are a binding: the template names them (`data="rows"`) and
-- the controller passes different rows on each draw. Reconciliation must
-- carry the new rows into the native list while the list keeps its view.
local path = os.tmpname() .. ".etlua"
local file = assert(io.open(path, "w"))
file:write([[<VStack maxWidth="infinity">
	<Label text="<%= title %>" />
	<List id="list" data="rows" style="plain" header="false" maxWidth="infinity" height="200">
		<Column id="name" title="" />
	</List>
</VStack>]])
file:close()
local config, host = xml.render('<Window width="600" height="400"><VStack id="host" maxWidth="infinity" /></Window>', {}, ns)
local window = ns.Window(config)
local template = Template.new(host.host, path, ns)
local _, refs = template:update({ title = "Files", rows = { { name = "a" }, { name = "b" }, { name = "c" } } })
local list = refs.list
t.assertEqual(list.rowCount, 3, "the list starts with the rows it was drawn with")
_, refs = template:update({ title = "Files", rows = { { name = "x" } } })
t.assertEqual(refs.list, list, "new rows keep the list's view")
t.assertEqual(refs.list.rowCount, 1, "and replace its rows")
_, refs = template:update({ title = "Other", rows = { { name = "x" } } })
t.assertEqual(refs.list.rowCount, 1, "a draw with the same rows leaves them")
_, refs = template:update({ title = "Other", rows = {} })
t.assertEqual(refs.list.rowCount, 0, "no rows empties the list")
_, refs = template:update({ title = "Other", rows = { { name = "p" }, { name = "q" } } })
t.assertEqual(refs.list.rowCount, 2, "rows come back")
t.assertEqual(refs.list, list, "in the same view throughout")
os.remove(path)
os.exit(t.summary() and 0 or 1)
