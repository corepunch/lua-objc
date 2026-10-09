local Selection = {}

-- One selection token per page: the id of the resource that a chart sector,
-- a map cell and a list row all stand for. Selecting a row or clicking a
-- sector keeps it; hovering keeps nothing and leaves the list alone.
-- The list paints it as its native selected row; the chart highlights only
-- what the pointer is over. See MOTION.md.

-- Sectors that are volume geometry, not a resource a list row can select.
local TRACKS = {free = true, unreconciled = true}

function Selection.isResource(id)
	if type(id) ~= "string" or id == "" then return false end
	if TRACKS[id] then return false end
	-- A folded remainder ("developer#other", the Overview's "#other") has no
	-- row of its own.
	if id:find("#other", 1, true) then return false end
	return true
end

-- The zero-based row that owns `id`, as `List:selectRow` counts them. Rows of
-- a kind list match their own id; extension rows belong to their `kindId`.
function Selection.index(rows, id)
	if not Selection.isResource(id) then return nil end
	for index, row in ipairs(rows or {}) do
		if row.id == id then return index - 1 end
	end
	return nil
end

-- Extensions that belong to the selected File Types kind. No token, or a
-- kind none of the ranked extensions belongs to, leaves the full ranking.
function Selection.extensions(rows, kindId)
	if not Selection.isResource(kindId) then return rows end
	local matched = {}
	for _, row in ipairs(rows or {}) do
		if row.kindId == kindId then table.insert(matched, row) end
	end
	return #matched > 0 and matched or rows
end

-- Points `list` at the token's row without scrolling the page under the
-- pointer, or clears its selection when the token has no row in `rows`.
function Selection.show(list, rows, id)
	if not list then return end
	local index = Selection.index(rows, id)
	if index then list:selectRow(index, false) else list:selectRow(nil) end
end

return Selection
