local History = {}

-- Opt-in record of category totals per completed scan, a few hundred bytes
-- each. No paths or file names are kept. Only complete category totals are
-- recorded, so partial scans never look like shrinkage.
History.keep = 60

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

return History
