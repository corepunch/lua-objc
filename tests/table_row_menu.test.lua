_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local bridge = require("AppKitNative")

-- A row menu is built from the row the user clicked, each time it opens, and
-- the same description backs the row's "More" button.
local performed = {}
local list = xml.render([[
<List rowMenu="menu">
  <Column id="name" />
  <Column id="more" width="40" buttonSymbol="ellipsis.circle" buttonMenu="true" />
</List>]], {actions = {
	menu = function(_, index, row)
		return {
			{title = "Open " .. row.name, action = function() table.insert(performed, "open:" .. row.id) end},
			{separator = true},
			{title = "Move to Trash", disabled = row.locked == true, action = function() table.insert(performed, "trash:" .. row.id) end},
			{title = "Row " .. tostring(index)},
		}
	end,
}}, ns)
list:replaceRows({{id = "a", name = "Alpha"}, {id = "b", name = "Beta", locked = true}})

t.expect(list.documentView.menu ~= nil, "rowMenu installs the table's contextual menu")
local first = bridge._tableRowMenu(list, 1)
t.assertEqual(#first, 4, "every record becomes one menu item")
t.assertEqual(first[1].title, "Open Alpha", "items describe the clicked row")
t.expect(first[2].separator == true, "separator records become separator items")
t.assertEqual(first[3].disabled, false, "items are enabled unless marked disabled")
t.assertEqual(first[4].title, "Row 0", "the builder receives the zero-based row index like onSelect")

local second = bridge._tableRowMenu(list, 2)
t.assertEqual(second[1].title, "Open Beta", "the second row builds its own menu")
t.assertEqual(second[3].disabled, true, "disabled records stay visible but unavailable")

bridge._tableRowMenu(list, 1, 1)
bridge._tableRowMenu(list, 1, 3)
t.assertEqual(table.concat(performed, ","), "open:a,trash:a", "performing an item calls its action with the row it was built for")
t.expect(not pcall(bridge._tableRowMenu, list, 2, 3), "a disabled item cannot be performed")

list:replaceRows({{id = "c", name = "Gamma"}})
t.assertEqual(bridge._tableRowMenu(list, 1)[1].title, "Open Gamma", "menus follow replaced rows")
t.assertEqual(#bridge._tableRowMenu(list, 5), 0, "a row outside the data has no menu")

local plain = xml.render('<List><Column id="name" /></List>', {}, ns)
t.expect(plain.documentView.menu == nil, "tables without rowMenu keep no contextual menu")

os.exit(t.summary() and 0 or 1)
