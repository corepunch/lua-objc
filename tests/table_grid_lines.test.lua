_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")

for _, tag in ipairs({"List", "OutlineView"}) do
	for _, config in ipairs({{name = "horizontal", mask = 2}, {name = "vertical", mask = 1}, {name = "both", mask = 3}}) do
		local list = xml.render('<' .. tag .. ' gridLines="' .. config.name .. '"><Column id="name" /></' .. tag .. '>', {}, ns)
		t.assertEqual(list.documentView.gridStyleMask, config.mask, tag .. " maps " .. config.name .. " to AppKit's named axis")
		list:replaceRows({{id = "first", name = "First"}, {id = "second", name = "Second"}})
		list:selectRow(1)
		t.assertEqual(list.documentView.gridStyleMask, config.mask, tag .. " keeps grid style after loading and selection")
		list:replaceRows({})
		t.assertEqual(list.documentView.gridStyleMask, config.mask, tag .. " keeps grid style when emptied")
	end
	local list = xml.render('<' .. tag .. '><Column id="name" /></' .. tag .. '>', {}, ns)
	t.assertEqual(list.documentView.gridStyleMask, 0, tag .. " leaves grid lines off unless requested")
end

-- Rules separate rows; the last row draws none, matching SwiftUI's List
-- inside a bounded container.
local bridge = require("AppKitNative")
for _, tag in ipairs({"List", "OutlineView"}) do
	local list = xml.render('<' .. tag .. ' gridLines="horizontal" header="false" rowHeight="44" height="400" maxWidth="infinity"><Column id="name" /></' .. tag .. '>', {}, ns)
	local window = ns.Window { visible = false, width = 300, height = 400 }
	window:add(list)
	window:layout()
	t.assertEqual(#bridge._tableSeparatorRows(list), 0, tag .. " draws no rule without rows")
	list:replaceRows({{id = "one", name = "One"}})
	t.assertEqual(#bridge._tableSeparatorRows(list), 0, tag .. " draws no rule under a single row")
	list:replaceRows({{id = "a", name = "A"}, {id = "b", name = "B"}, {id = "c", name = "C"}})
	t.assertEqual(table.concat(bridge._tableSeparatorRows(list), ","), "1,2", tag .. " rules only between its three rows")
	list:replaceRows({{id = "a", name = "A"}, {id = "b", name = "B"}})
	t.assertEqual(table.concat(bridge._tableSeparatorRows(list), ","), "1", tag .. " moves the omitted rule to the new last row")
	local plain = xml.render('<' .. tag .. ' header="false"><Column id="name" /></' .. tag .. '>', {}, ns)
	plain:replaceRows({{id = "a", name = "A"}, {id = "b", name = "B"}})
	t.assertEqual(#bridge._tableSeparatorRows(plain), 0, tag .. " without grid lines draws no rules")
end
os.exit(t.summary() and 0 or 1)
