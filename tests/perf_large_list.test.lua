_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")

local function rows(count)
	local result = {}
	for i = 1, count do result[i] = { id = i, title = "Item " .. i } end
	return result
end

local items = rows(1000)
local eagerTemplate = [[<VStack><% for _, item in ipairs(items) do %><Label text="<%= item.title %>"/><% end %></VStack>]]
local eager = xml.render(eagerTemplate, { items = items }, ns)
t.expect(eager ~= nil, "bounded eager construction remains supported for small groups")

local list = ns.List {
	columns = { { id = "title", title = "Title" } },
	data = items,
}
t.assertEqual(list.rowCount, 1000, "native List accepts 1,000 rows")

local larger = ns.List {
	columns = { { id = "title", title = "Title" } },
	data = rows(5000),
}
t.assertEqual(larger.rowCount, 5000, "native List accepts 5,000 rows without eager view creation")

os.exit(t.summary() and 0 or 1)
