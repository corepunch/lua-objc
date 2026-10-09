_G.__headless = true
local t = require("TestKit")
local Palette = require("apps.diskmap.helpers.Palette")

-- A sector keeps its own hue while it is free, else takes the next free one.
local palette = Palette.new()
t.assertEqual(palette:take("systemGreen"), "systemGreen", "the first green keeps its color")
local second = palette:take("systemGreen")
t.expect(second ~= "systemGreen", "a second green takes another hue")
t.assertEqual(palette:take("systemGray"), "systemGray", "neutral colors pass through")
t.assertEqual(palette:take("systemGray"), "systemGray", "and are never claimed")
t.assertEqual(palette:take("quaternaryLabel"), "quaternaryLabel", "free space stays the track")
local seen = {systemGreen = true, [second] = true}
-- Pink reads as red and cyan as teal, so twelve hues are ten choices.
local LOOK_ALIKE = {systemPink = "systemRed", systemCyan = "systemTeal"}
for _ = 1, #Palette.hues - 2 - 2 do
	local hue = palette:take(nil)
	t.expect(not seen[LOOK_ALIKE[hue] or hue], "no hue is handed out beside its look-alike: " .. hue)
	seen[LOOK_ALIKE[hue] or hue] = true
end
t.expect(palette:take(nil) ~= nil, "an exhausted palette starts over")

-- On the showcase disk no two colored sectors of one ring share a hue, and
-- the legend and the category rows use the colors of the ring.
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.Controller")
local Categories = require("apps.diskmap.models.Categories")
local app = Controller.new(Mock.new({showcase = true}))
local window = app:createWindow()
local NEUTRAL = {systemGray = true, secondary = true, tertiary = true, quaternaryLabel = true}
local function distinct(colors, what)
	local used = {}
	for _, color in ipairs(colors) do
		if not NEUTRAL[color] then
			local hue = LOOK_ALIKE[color] or color
			t.expect(not used[hue], what .. " uses " .. color .. " once, with no look-alike")
			used[hue] = true
		end
	end
end

app:show("overview")
local data = app.page.request
local chart = Categories:chart(app:state().disk)
local colors, byId = {}, {}
for _, mark in ipairs(chart.marks) do table.insert(colors, mark.color); byId[mark.id] = mark.color end
distinct(colors, "the Overview ring")
t.expect(#chart.legend >= 7, "the ring names seven categories, so most used space is in color")
for _, item in ipairs(chart.legend) do
	t.assertEqual(item.color, byId[item.id], item.name .. " has the color of its sector in the legend")
end
for _, row in ipairs(data.categoryRows) do
	if byId[row.id] then t.assertEqual(row.color, byId[row.id], row.name .. " has the color of its sector in the list") end
end

-- Every inner ring of the Map, at the top and inside each category.
local function ringOne(focus)
	local nodes = Categories:mapNodes(focus)
	local inner = {}
	for _, node in ipairs(nodes) do if node.ring == 1 then table.insert(inner, node.color) end end
	return inner
end
distinct(ringOne(""), "the Map")
for _, row in ipairs(Categories:rows()) do
	if row.children and #row.children > 1 then distinct(ringOne(row.id), "the Map inside " .. row.name) end
end
-- The Map's list has the colors of its ring.
app:show("map", {focus = "applications"})
local map = app.page.request
local mapData = map:data(app:state())
for _, row in ipairs(mapData.lists.mapList) do
	local node = map.nodeById[row.id]
	if node then t.assertEqual(row.color, node.color, row.name .. " has the color of its sector in the Map list") end
end
-- File Types: the ring, its legend and both lists share distinct hues.
app:show("kinds")
local kinds = app.page.request:data(app:state())
local kindColors = {}
for _, mark in ipairs(kinds.breakdown.marks) do table.insert(kindColors, mark.color) end
distinct(kindColors, "File Types")
t.assertEqual(LOOK_ALIKE.systemPink, "systemRed", "Videos (pink) and Music (red) never share the ring")
window:close()
os.exit(t.summary() and 0 or 1)
