local Changes = {}
local function lines(source)
	local result = {}
	if source == "" then return result end
	local terminated = source:sub(-1) == "\n" and source or (source .. "\n")
	for line in terminated:gmatch("(.-)\n") do table.insert(result, line) end
	return result
end

function Changes.between(before, after)
	local result = {}
	for path, source in pairs(after) do
		if source ~= before[path] then
			local old, new = lines(before[path] or ""), lines(source)
			local first, lastOld, lastNew = 1, #old, #new
			while first <= lastOld and first <= lastNew and old[first] == new[first] do first = first + 1 end
			while lastOld >= first and lastNew >= first and old[lastOld] == new[lastNew] do
				lastOld, lastNew = lastOld - 1, lastNew - 1
			end
			local diff = {}
			for index = first, lastOld do table.insert(diff, "- " .. old[index]) end
			for index = first, lastNew do table.insert(diff, "+ " .. new[index]) end
			table.insert(result, { path = path:gsub("^demo/playground/", ""),
				added = math.max(0, lastNew - first + 1), removed = math.max(0, lastOld - first + 1), lines = diff })
		end
	end
	table.sort(result, function(a, b) return a.path < b.path end)
	return result
end
return Changes
