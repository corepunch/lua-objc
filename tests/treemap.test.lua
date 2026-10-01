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
-- No two rectangles touch: siblings keep a margin on every side, and a child sits inside its parent's.
local margin = Treemap.metrics.margin
local big = {}
for index = 1, 12 do table.insert(big, {id = "n" .. index, value = 13 - index, label = "N" .. index}) end
for index = 1, 6 do table.insert(big, {id = "k" .. index, parent = "n1", value = 7 - index, label = "K" .. index}) end
local bigCells = Treemap.layout(big, 800, 500)
local parentOf = {}
for _, node in ipairs(big) do parentOf[node.id] = node.parent end
for i, a in ipairs(bigCells) do
	for j = i + 1, #bigCells do
		local b = bigCells[j]
		if parentOf[a.id] == parentOf[b.id] and a.w > 4 * margin and b.w > 4 * margin and a.h > 4 * margin and b.h > 4 * margin then
			local apartX = math.max(b.x - (a.x + a.w), a.x - (b.x + b.w))
			local apartY = math.max(b.y - (a.y + a.h), a.y - (b.y + b.h))
			t.expect(math.max(apartX, apartY) >= 2 * margin - 1e-6, a.id .. " and " .. b.id .. " do not touch")
		end
	end
end
local n1 = bigCells[1]
for _, cell in ipairs(bigCells) do
	if parentOf[cell.id] == "n1" then
		t.expect(cell.x >= n1.x + margin - 1e-6 and cell.x + cell.w <= n1.x + n1.w - margin + 1e-6, cell.id .. " keeps a margin inside its parent")
	end
end
for _, cell in ipairs(bigCells) do
	if cell.header then t.expect(cell.labelFrame.x + cell.labelFrame.w <= cell.x + cell.w, cell.id .. "'s header text stays inside its own rectangle") end
end
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

-- Labels never overlap: a group's header label sits in the band above its
-- children, and every label stays inside its own tile.
local function intersects(a, b)
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end
local function inside(frame, cell)
	return frame.x >= cell.x - 1e-9 and frame.y >= cell.y - 1e-9
		and frame.x + frame.w <= cell.x + cell.w + 1e-9 and frame.y + frame.h <= cell.y + cell.h + 1e-9
end
local nested = {
	{id = "dev", value = 45, label = "Developer", detail = "45.4 GB"},
	{id = "ios", value = 22, label = "iOS Files", detail = "21.8 GB"},
	{id = "xcode", parent = "dev", value = 30, label = "Xcode", detail = "28.3 GB"},
	{id = "pkg", parent = "dev", value = 15, label = "Package managers", detail = "3.6 GB"},
	{id = "support", parent = "xcode", value = 12, label = "Device support", detail = "11.5 GB"},
	{id = "derived", parent = "xcode", value = 8, label = "DerivedData", detail = "8.0 GB"},
	{id = "sims", parent = "xcode", value = 10, label = "Simulator devices", detail = "11.2 GB"},
	{id = "backups", parent = "ios", value = 16, label = "Backups", detail = "16.4 GB"},
	{id = "updates", parent = "ios", value = 5, label = "Updates", detail = "5.4 GB"},
	{id = "npm", parent = "pkg", value = 1, label = "npm", detail = "1.4 GB"},
}
local function checkLabels(width, height)
	local laid = Treemap.layout(nested, width, height)
	local cellById, parentOf = {}, {}
	for _, node in ipairs(nested) do parentOf[node.id] = node.parent end
	for _, cell in ipairs(laid) do cellById[cell.id] = cell end
	local headers = 0
	for _, cell in ipairs(laid) do
		for _, key in ipairs({"labelFrame", "detailFrame"}) do
			if cell[key] then
				t.expect(inside(cell[key], cell), cell.id .. " " .. key .. " stays inside its tile at " .. width .. "x" .. height)
			end
		end
		if cell.header then headers = headers + 1 end
		-- Walk every ancestor: no descendant label may cross a header label.
		local ancestor = cellById[parentOf[cell.id]]
		while ancestor do
			t.expect(ancestor.labelFrame == nil or ancestor.header, ancestor.id .. " draws a header, not leaf lines, above children")
			t.expect(intersects(cell, ancestor) and cell.y >= ancestor.y, cell.id .. " nests inside " .. ancestor.id)
			if ancestor.labelFrame then
				t.expect(not intersects(cell, ancestor.labelFrame),
					cell.id .. " tile stays below " .. ancestor.id .. " header at " .. width .. "x" .. height)
				for _, key in ipairs({"labelFrame", "detailFrame"}) do
					if cell[key] then
						t.expect(not intersects(cell[key], ancestor.labelFrame),
							cell.id .. " " .. key .. " clears " .. ancestor.id .. " header at " .. width .. "x" .. height)
					end
				end
			end
			ancestor = cellById[parentOf[ancestor.id]]
		end
	end
	return laid, cellById, headers
end
local _, big, headers = checkLabels(900, 540)
t.expect(headers >= 2, "large groups draw header labels")
t.expect(big.xcode.header and big.support.labelFrame, "nested headers and their children are both labelled")
t.expect(big.support.y >= big.xcode.labelFrame.y + big.xcode.labelFrame.h, "children start below the header band")
t.expect(big.support.detailFrame ~= nil, "roomy leaves show their detail line")
t.assertEqual(big.xcode.detailFrame, nil, "a header draws its detail on its own line, not below it")
checkLabels(400, 260)
checkLabels(160, 90)
local _, cramped = checkLabels(60, 60)
for _, cell in pairs(cramped) do
	if cell.depth > 0 then
		t.assertEqual(cell.labelFrame, nil, "children of an unbanded parent are too small to label")
	end
end
for _, cell in ipairs(Treemap.layout(nested, 50, 20)) do
	t.assertEqual(cell.labelFrame, nil, "tiles too small for a label line show none")
end

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
