local Model = require("apps.diskmap.Model")
local Categories = require("apps.diskmap.models.Categories")
local History = {}

-- Opt-in record of category totals per completed scan, a few hundred bytes
-- each. No paths or file names are kept. Only complete category totals are
-- recorded, so partial scans never look like shrinkage.
History.keep = 60

function History.snapshot(model, time)
	local totals = {}
	for _, row in ipairs(Categories.rows(model)) do
		if row.status == "complete" and row.bytes then totals[row.id] = row.bytes end
	end
	return {time = time or os.time(), totals = totals}
end

function History.append(entries, snapshot)
	entries = entries or {}
	table.insert(entries, snapshot)
	while #entries > History.keep do table.remove(entries, 1) end
	return entries
end

-- Serialized as one line per scan: time, then id=bytes pairs.
function History.encode(entries)
	local lines = {}
	for _, entry in ipairs(entries or {}) do
		local pairs_ = {}
		for id, bytes in pairs(entry.totals) do table.insert(pairs_, id .. "=" .. string.format("%.0f", bytes)) end
		table.sort(pairs_)
		table.insert(lines, tostring(entry.time) .. " " .. table.concat(pairs_, " "))
	end
	return table.concat(lines, "\n")
end

function History.decode(text)
	local entries = {}
	for line in (text or ""):gmatch("[^\n]+") do
		local time, rest = line:match("^(%d+)%s*(.*)$")
		if time then
			local totals = {}
			for id, bytes in rest:gmatch("([%w%-]+)=(%d+)") do totals[id] = tonumber(bytes) end
			table.insert(entries, {time = tonumber(time), totals = totals})
		end
	end
	return entries
end

-- The largest changes between the oldest entry within `days` and the newest
-- one, as rows for the overview. Categories missing from either end are
-- skipped rather than reported as appearing or vanishing.
function History.changes(model, entries, days, limit, now)
	if not entries or #entries < 2 then return nil end
	local latest = entries[#entries]
	local since = (now or latest.time) - (days or 30) * 86400
	local base
	for _, entry in ipairs(entries) do
		if entry ~= latest and entry.time >= since then base = entry; break end
	end
	base = base or entries[#entries - 1]
	local rows = {}
	for id, bytes in pairs(latest.totals) do
		local before = base.totals[id]
		local resource = model.resources:find(id)
		if before and resource and bytes ~= before then
			local delta = bytes - before
			table.insert(rows, {id = id, name = resource.name, color = resource.color, icon = resource.icon, delta = delta,
				text = (delta > 0 and "+" or "−") .. Model.size(math.abs(delta)), grew = delta > 0})
		end
	end
	table.sort(rows, function(a, b)
		if math.abs(a.delta) ~= math.abs(b.delta) then return math.abs(a.delta) > math.abs(b.delta) end
		return a.id < b.id
	end)
	while #rows > (limit or 4) do table.remove(rows) end
	if #rows == 0 then return nil end
	local since = (os.date("%b %e", base.time):gsub("  ", " "))
	return {rows = rows, since = since, scans = #entries, detail = "Since " .. since .. " · " .. #entries .. " scans recorded"}
end

return History
