-- The text match of the Search page (pages/Search.lua): a row is found when
-- the query occurs, ignoring case, in any of the fields named for its kind.
-- Each model's `search(needle)` asks this of its own rows; nothing else in
-- Diskmap filters by text, since every page shows all it lists and Search
-- shows what matches across the whole store.
local Search = {}

-- The lowered query, or nil when there is nothing to look for.
function Search.needle(text)
	local needle = (text or ""):lower():match("^%s*(.-)%s*$")
	return needle ~= "" and needle or nil
end

-- Whether `needle` occurs in any of the values (nil values are skipped).
function Search.matches(needle, ...)
	for index = 1, select("#", ...) do
		local value = select(index, ...)
		if value ~= nil and tostring(value):lower():find(needle, 1, true) then return true end
	end
	return false
end

-- The rows whose `fields` contain `needle`, in their order.
function Search.filter(rows, needle, fields)
	local found = {}
	for _, row in ipairs(rows or {}) do
		local values = {}
		for index, field in ipairs(fields) do values[index] = row[field] or "" end
		if Search.matches(needle, table.unpack(values, 1, #fields)) then table.insert(found, row) end
	end
	return found
end

return Search
