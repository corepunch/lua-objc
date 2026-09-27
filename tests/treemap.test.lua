_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local bridge = require("AppKitNative")
local Treemap = require("ui.treemap")

-- Squarified layout: every value gets its share of the area.
local rects = Treemap.squarify({6, 6, 4, 3, 2, 2, 1}, 0, 0, 600, 400)
t.assertEqual(#rects, 7, "each value gets a rectangle")
local area = 0
for index, rect in ipairs(rects) do
	area = area + rect.w * rect.h
	t.expect(rect.x >= -1e-9 and rect.y >= -1e-9 and rect.x + rect.w <= 600 + 1e-6 and rect.y + rect.h <= 400 + 1e-6,
		"rectangle " .. index .. " stays inside the canvas")
end
t.expect(math.abs(area - 600 * 400) < 1e-6, "rectangles fill the canvas")
t.expect(math.abs(rects[1].w * rects[1].h - 6 / 24 * 240000) < 1e-6, "areas are proportional to values")
local worstRatio = 0
for _, rect in ipairs(rects) do worstRatio = math.max(worstRatio, math.max(rect.w / rect.h, rect.h / rect.w)) end
t.expect(worstRatio < 3, "squarified rectangles stay close to square")
t.assertEqual(#Treemap.squarify({}, 0, 0, 10, 10), 0, "no values, no rectangles")
t.assertEqual(#Treemap.squarify({1}, 0, 0, 0, 10), 0, "an empty canvas has no rectangles")

-- Nested layout puts children inside their parent, below a label strip.
local nodes = {
	{id = "a", value = 60, color = "systemBlue", label = "A"},
	{id = "b", value = 40, color = "systemGreen", label = "B"},
	{id = "a1", parent = "a", value = 40, label = "A1", hatched = true},
	{id = "a2", parent = "a", value = 20, label = "A2"},
	{id = "zero", value = 0},
}
local cells = Treemap.layout(nodes, 400, 300)
local byId = {}
for _, cell in ipairs(cells) do byId[cell.id] = cell end
t.assertEqual(byId.zero, nil, "zero values are not drawn")
t.expect(byId.a and byId.a1, "parents and children are both drawn")
t.expect(byId.a1.x >= byId.a.x and byId.a1.y >= byId.a.y + Treemap.metrics.labelStrip - 1e-9, "children sit below their parent's label strip")
t.assertEqual(byId.a1.depth, 1, "children are one level deeper")
t.expect(byId.a1.hatched and not byId.a2.hatched, "hatching follows the node")
local parentIndex, childIndex
for index, cell in ipairs(cells) do
	if cell.id == "a" then parentIndex = index elseif cell.id == "a1" then childIndex = index end
end
t.expect(parentIndex < childIndex, "parents draw before their children")
t.assertEqual(Treemap.hit(cells, byId.a1.x + 2, byId.a1.y + 2).id, "a1", "hit testing finds the deepest cell")
t.assertEqual(Treemap.hit(cells, byId.a.x + 2, byId.a.y + 2).id, "a", "the label strip belongs to the parent")
t.assertEqual(Treemap.hit(cells, 1000, 1000), nil, "points outside hit nothing")
local tiny = Treemap.layout(nodes, 40, 30)
for _, cell in ipairs(tiny) do t.expect(cell.depth == 0, "small parents do not nest children") end

-- The native view lays out on resize and reports clicks and hovers.
local selected, hovered
local view, refs = xml.render([[<Treemap id="map" width="400" height="300">
  <TreemapNode id="a" value="60" color="systemBlue" label="A" detail="6 GB" />
  <TreemapNode id="b" value="40" color="systemGreen" label="B" detail="4 GB" hatched="true" />
</Treemap>]], {actions = {}}, ns)
view.frameSize = ns.Size(400, 300)
t.assertEqual(refs.map.className, "LuaTreemapView", "Treemap is a native drawing view")
t.assertEqual(#view.cells, 2, "the view computed its cells")
local interactive = ns.Treemap { fixedWidth = 400, fixedHeight = 300,
	{__treemapNode = true, id = "a", value = 3, color = "systemBlue"},
	{__treemapNode = true, id = "b", value = 1, color = "systemGreen"},
	onSelect = function(id, count) selected = {id, count} end,
	onHover = function(id) hovered = id end }
interactive.frameSize = ns.Size(400, 300)
local first = interactive.cells[1]
bridge._pointerSend(interactive, "click", first.x + 5, first.y + 5, 2)
t.expect(selected and selected[1] == first.id and selected[2] == 2, "clicks select the cell under the pointer")
t.assertEqual(interactive.selectedId, first.id, "the selected cell is outlined")
bridge._pointerSend(interactive, "hover", first.x + 5, first.y + 5)
t.assertEqual(hovered, first.id, "hover reports the cell under the pointer")
bridge._pointerSend(interactive, "hover")
t.assertEqual(hovered, nil, "leaving the view clears the hover")
t.assertEqual(interactive.highlightedId, nil, "leaving clears the outline")

os.exit(t.summary() and 0 or 1)
