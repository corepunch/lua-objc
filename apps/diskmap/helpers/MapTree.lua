local Model = require("data.model")
local Locations = require("apps.diskmap.models.Locations")
local Format = require("apps.diskmap.helpers.Format")
local Categories = require("apps.diskmap.helpers.Categories")
local MapTree = {}

-- The Map shows Diskmap's semantic tree from a focus node downwards: the
-- whole disk, a category, or a group. Rings and rectangles draw the same
-- nodes. Nodes under 1.5% of the map (about 5 degrees of the rings) fold into
-- one "Other" node per parent so every mark is big enough to see and to
-- point at. An outer-ring "Other" that is itself a sliver is left out: its
-- parent's arc simply ends early, which reads as "and a little more". So is
-- one that would be its parent's only child: a grey ring that repeats the
-- parent says nothing, so the parent ends the map there like a leaf.
MapTree.depth = 3
MapTree.minimumShare = 0.015

local function measured(row)
	return row.bytes ~= nil and row.bytes > 0
end

-- The focused row and its ancestors, root first, for the breadcrumb.
function MapTree.path(focus)
	local model = Model.db
	local trail = {}
	local resource = focus and Locations:find(focus)
	while resource do
		table.insert(trail, 1, {id = resource.id, name = resource.name})
		resource = resource:parent()
	end
	table.insert(trail, 1, {id = "", name = "All Storage"})
	return trail
end

-- Nodes {id, parent, value, color, label, detail, ring, hatched, leaf} for
-- the focus. The top level is the focus's children (or the categories).
function MapTree.nodes(focus, depth)
	local model = Model.db
	depth = depth or MapTree.depth
	local top = Categories.rows(focus ~= "" and focus or nil)
	local total = 0
	for _, row in ipairs(top) do if measured(row) then total = total + row.bytes end end
	local nodes = {}
	local function visit(rows, parent, ring, color)
		local other, otherBytes, shown = 0, 0, 0
		for _, row in ipairs(rows) do
			if measured(row) then
				if total > 0 and row.bytes / total < MapTree.minimumShare then
					other, otherBytes = other + 1, otherBytes + row.bytes
				else
					shown = shown + 1
					local resource = Locations:find(row.id)
					local leaf = resource and resource:isLeaf()
					local rowColor = ring == 1 and (row.color or "systemGray") or color
					table.insert(nodes, {id = row.id, parent = parent, value = row.bytes, color = rowColor,
						label = row.name, detail = row.size, ring = ring, leaf = leaf,
						hatched = leaf and resource.policy == "Rebuildable" or false})
					if row.children and ring < depth then visit(row.children, row.id, ring + 1, rowColor) end
				end
			end
		end
		if other > 0 and (ring == 1 or (shown > 0 and otherBytes / total >= MapTree.minimumShare)) then
			-- Nested smaller items are more of their parent, so they keep its
			-- hue (the view fades them); only the top level has no family.
			table.insert(nodes, {id = (parent or "top") .. "#other", parent = parent, value = otherBytes, color = color or "systemGray",
				label = other .. " smaller", detail = Format.size(otherBytes), ring = ring, leaf = true, other = true})
		end
	end
	visit(top, nil, 1, nil)
	return nodes, total
end

-- Largest rebuildable resources under the focus: the "Worth a look" list.
function MapTree.worthALook(focus, limit)
	local model = Model.db
	local rows = {}
	local root = focus ~= "" and focus and Locations:find(focus)
	local function within(resource)
		if not root then return true end
		while resource do
			if resource == root then return true end
			resource = resource:parent()
		end
		return false
	end
	for _, resource in ipairs(Locations:leaves()) do
		local m = model.measurements[resource.id]
		if resource.policy == "Rebuildable" and m and m.status == "complete" and (m.bytes or 0) > 0
			and within(resource) and not resource:isKept() then
			table.insert(rows, {id = resource.id, name = resource.name, path = resource.path, bytes = m.bytes,
				size = Format.size(m.bytes), action = resource.action})
		end
	end
	table.sort(rows, function(a, b) return a.bytes > b.bytes end)
	while #rows > (limit or 3) do table.remove(rows) end
	return rows
end

-- One line describing a node for the hover bar.
function MapTree.describe(id, total)
	local model = Model.db
	local row = id and Categories.row(id)
	if not row then return nil end
	local share = total and total > 0 and row.bytes and string.format(" · %.1f%%", row.bytes * 100 / total) or ""
	local trail = {}
	for _, step in ipairs(MapTree.path(id)) do if step.id ~= "" then table.insert(trail, step.name) end end
	return table.concat(trail, " › ") .. " · " .. row.size .. share
end

return MapTree
