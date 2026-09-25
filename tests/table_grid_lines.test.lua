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
os.exit(t.summary() and 0 or 1)
