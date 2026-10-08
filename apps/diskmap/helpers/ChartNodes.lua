local Format = require("apps.diskmap.helpers.Format")

-- The marks of a sunburst or treemap over a tree of rows, the nodes the
-- Storage Map and every list page's Rings and Rectangles draw:
-- {id, parent, value, color, label, detail, ring, leaf, hatched, other}.
--
-- `top` are rows {id, name, bytes, size, color, children, leaf, hatched};
-- `hues` (id -> color) colors the inner ring, and a top row without a hue
-- folds into the gray "N smaller" node, as layout.md's chart colors ask.
-- Rows under `minimumShare` of the total (about 5 degrees of the rings at
-- 1.5%) fold into one "smaller" node per parent so every mark is big enough
-- to see and to point at. An outer "smaller" node that is itself a sliver is
-- left out: its parent's arc simply ends early. So is one that would be its
-- parent's only child, which would only repeat the parent in gray.
local ChartNodes = {}

local function measured(row)
	return row.bytes ~= nil and row.bytes > 0
end

function ChartNodes.build(top, hues, depth, minimumShare)
	local total = 0
	for _, row in ipairs(top) do if measured(row) then total = total + row.bytes end end
	local nodes = {}
	local function visit(rows, parent, ring, color)
		local other, otherBytes, shown = 0, 0, 0
		for _, row in ipairs(rows) do
			if measured(row) then
				if (total > 0 and row.bytes / total < minimumShare) or (ring == 1 and not hues[row.id]) then
					other, otherBytes = other + 1, otherBytes + row.bytes
				else
					shown = shown + 1
					local rowColor = ring == 1 and hues[row.id] or color
					local leaf = row.leaf
					if leaf == nil then leaf = row.children == nil end
					table.insert(nodes, {id = row.id, parent = parent, value = row.bytes, color = rowColor,
						label = row.name, detail = row.size, ring = ring, leaf = leaf, hatched = row.hatched or false})
					if row.children and ring < depth then visit(row.children, row.id, ring + 1, rowColor) end
				end
			end
		end
		if other > 0 and (ring == 1 or (shown > 0 and otherBytes / total >= minimumShare)) then
			-- Nested smaller items are more of their parent, so they keep its
			-- hue (the view fades them); only the top level has no family.
			table.insert(nodes, {id = (parent or "top") .. "#other", parent = parent, value = otherBytes, color = color or "systemGray",
				label = other .. " smaller", detail = Format.size(otherBytes), ring = ring, leaf = true, other = true})
		end
	end
	visit(top, nil, 1, nil)
	return nodes, total
end

return ChartNodes
