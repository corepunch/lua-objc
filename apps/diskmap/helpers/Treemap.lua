-- The height of a rectangles map, from the cells it must show. A page that
-- scrolls cannot hand the map "the rest of the window", so the map is as
-- tall as its cells need: a squarified treemap (Bruls, Huizing and van Wijk)
-- lays out cells close to square, so the area needed is the number of cells
-- times the area one readable cell takes (its name and its size on two
-- lines), plus what gaps and slivers waste. DaisyDisk and GrandPerspective
-- scale a map with its window; a document-like page scales it with its
-- content instead, as a chart in a scrolling report does.
local Treemap = {}

local CELL = {width = 120, height = 48, fill = 0.7}
-- The readable column of PageFrame.lua; the map is as wide as the page.
local PAGE = {width = 960}
local LIMITS = {minimum = 320, maximum = 720}

-- Leaves are the nodes no other node names as its parent.
function Treemap.leaves(nodes)
	local parents, leaves = {}, 0
	for _, node in ipairs(nodes) do
		if node.parent and node.parent ~= "" then parents[node.parent] = true end
	end
	for _, node in ipairs(nodes) do
		if not parents[node.id] then leaves = leaves + 1 end
	end
	return leaves
end

function Treemap.height(nodes, width)
	local area = Treemap.leaves(nodes) * CELL.width * CELL.height / CELL.fill
	local height = math.floor(area / (width or PAGE.width) + 0.5)
	return math.max(LIMITS.minimum, math.min(LIMITS.maximum, height))
end

return Treemap
