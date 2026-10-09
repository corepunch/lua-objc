local Format = require("apps.diskmap.helpers.Format")
local Breakdown = {limit = 8}
-- A concise, sorted summary is separate from the complete list below it.
-- Fold the tail once so the legend never becomes a second scrolling list.
function Breakdown.rows(rows)
	local legend, sectors, measured, total = {}, {}, {}, 0
	for _, row in ipairs(rows) do
		if (row.bytes or 0) > 0 then table.insert(measured, row); total = total + row.bytes end
	end
	local rest = 0
	for index, row in ipairs(measured) do
		local bytes = row.bytes or 0
		if index <= Breakdown.limit and bytes > 0 then table.insert(sectors, {id = row.id, value = bytes, color = row.color or "systemGray", label = row.name or row.path or "Item", detail = row.size or Format.size(bytes)}) end
		if index <= Breakdown.limit then
			table.insert(legend, {id = row.id, name = row.name or row.path or "Item", color = row.color or "systemGray", size = row.size or Format.size(bytes),
				share = total > 0 and string.format("%.0f%%", bytes / total * 100) or "0%"})
		else rest = rest + bytes end
	end
	if rest > 0 then table.insert(sectors, {id = "#other", value = rest, color = "systemGray", label = (#measured - Breakdown.limit) .. " more items", detail = Format.size(rest)}) end
	if #measured > Breakdown.limit then table.insert(legend, {id = "#other", name = (#measured - Breakdown.limit) .. " more items", color = "systemGray", size = Format.size(rest),
		share = total > 0 and string.format("%.0f%%", rest / total * 100) or "0%"}) end
	return sectors, legend
end
return Breakdown
