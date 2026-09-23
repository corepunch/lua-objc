_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Difference = require("ui.reorder").Difference

local items = { "one", "two", "three" }
local actions = {
	move = function(diff)
		t.expect(getmetatable(diff) == Difference, "container sends a Difference")
		diff:apply(items)
	end,
}
local view, refs = xml.render([[
<VStack ref="stack" reorderable="true" reorderContainer="move">
	<Label text="One"/><Label text="Two"/><Label text="Three"/>
</VStack>]], { actions = actions }, ns)
t.expect(view == refs.stack, "reorderable stack preserves the native view ref")
ns._testReorderMove(view, 3, 1)
t.assertEqual(table.concat(items, ","), "three,one,two", "native move updates the model")
ns._testReorderMove(view, 1, 1)
t.assertEqual(table.concat(items, ","), "three,one,two", "no-op drop leaves the model alone")
local validIndex = pcall(function() ns._testReorderMove(view, 0, 2) end)
t.expect(not validIndex, "native helper rejects a zero source index")
t.assertEqual(table.concat(items, ","), "three,one,two", "invalid source leaves the model alone")

local grid = xml.render([[
<Grid reorderable="true" reorderContainer="move">
	<GridRow><Label text="One"/><Label text="Two"/></GridRow>
	<GridRow><Label text="Three"/></GridRow>
</Grid>]], { actions = actions }, ns)
ns._testReorderMove(grid, 2, 3)
t.assertEqual(table.concat(items, ","), "three,two,one",
	"grid items use the same difference callback")

local flow = xml.render([[
<FlowStack reorderable="true" reorderContainer="move">
	<Label text="One"/><Label text="Two"/><Label text="Three"/>
</FlowStack>]], { actions = actions }, ns)
ns._testReorderMove(flow, 3, 1)
t.assertEqual(table.concat(items, ","), "one,three,two",
	"flow layout items use the same difference callback")

local empty = xml.render('<VStack reorderable="true" reorderContainer="move"/>',
	{ actions = actions }, ns)
t.expect(empty ~= nil, "empty reorder containers render")

local ok = pcall(function()
	xml.render('<VStack reorderable="true" reorderContainer="missing"><Label text="A"/></VStack>',
		{ actions = actions }, ns)
end)
t.expect(not ok, "missing controller action is rejected")

local rows = {}
for index = 1, 1000 do rows[index] = { title = "Item " .. index } end
local lazy = xml.render([[
<LazyVStack rowHeight="36" reorderable="true" reorderContainer="move">
	<% for _, item in ipairs(rows) do %>
	<Label text="<%= item.title %>" />
	<% end %>
</LazyVStack>]], { rows = rows, actions = actions }, ns)
local count, created = ns._lazyCollectionStats(lazy)
t.assertEqual(count, 1000, "lazy stack retains all model positions")
t.assertEqual(created, 0, "lazy stack creates no offscreen native item views")

local lazyGrid = xml.render([[
<LazyVGrid columns="3" rowHeight="40" reorderable="true" reorderContainer="move">
	<% for _, item in ipairs(rows) do %>
	<Label text="<%= item.title %>" />
	<% end %>
</LazyVGrid>]], { rows = rows, actions = actions }, ns)
local gridCount, gridCreated = ns._lazyCollectionStats(lazyGrid)
t.assertEqual(gridCount, 1000, "lazy grid retains all model positions")
t.assertEqual(gridCreated, 0, "lazy grid creates no offscreen native item views")

local emptyLazy = xml.render('<LazyVStack/>', {}, ns)
local emptyCount, emptyCreated = ns._lazyCollectionStats(emptyLazy)
t.assertEqual(emptyCount, 0, "empty lazy collection has no items")
t.assertEqual(emptyCreated, 0, "empty lazy collection creates no item views")

for _, source in ipairs({ '<LazyVStack rowHeight="0"/>',
	'<LazyVGrid columns="0"><Label text="A"/></LazyVGrid>' }) do
	local valid = pcall(function() xml.render(source, {}, ns) end)
	t.expect(not valid, "invalid lazy dimensions are rejected")
end

os.exit(t.summary() and 0 or 1)
