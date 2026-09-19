local Model = {}

function Model.humanKb(kb)
	if kb >= 1024 * 1024 then
		return string.format("%.1f GB", kb / 1024 / 1024)
	elseif kb >= 1024 then
		return string.format("%.0f MB", kb / 1024)
	else
		return string.format("%d KB", kb)
	end
end

-- Start a background du scan. Returns a scan handle with outFile/doneFile.
function Model.startScan(rootPath, maxDepth)
	local stamp = tostring(os.time())
	local outFile = "/tmp/diskmap_" .. stamp .. ".txt"
	local doneFile = "/tmp/diskmap_" .. stamp .. ".done"
	local cmd = string.format(
		"sh -c 'du -d %d -k -- %s > %s 2>/dev/null; touch %s' &",
		maxDepth,
		string.format("%q", rootPath),
		string.format("%q", outFile),
		string.format("%q", doneFile)
	)
	local fh = io.popen(cmd)
	if fh then fh:close() end
	return { outFile = outFile, doneFile = doneFile, rootPath = rootPath }
end

-- Returns true when the background scan has finished.
function Model.isDone(handle)
	local f = io.open(handle.doneFile, "r")
	if f then f:close(); return true end
	return false
end

-- Parse results once scan is done. Returns a flat list of rows sorted for display.
-- Each row: {depth, name, path, kb, rootKb}
function Model.parseResults(handle, maxChildrenPerDepth)
	local rootPath = handle.rootPath:gsub("/$", "")
	local limits = maxChildrenPerDepth or { 999, 12, 10, 8, 6 }

	-- Read all sizes into a path→kb map
	local sizes = {}
	local f = io.open(handle.outFile, "r")
	if not f then return {} end
	for line in f:lines() do
		local kbStr, p = line:match("^(%d+)%s+(.+)")
		if kbStr then
			p = p:gsub("/$", "")
			sizes[p] = tonumber(kbStr)
		end
	end
	f:close()

	-- Build parent→children map
	local children = {}
	for p in pairs(sizes) do
		local parent = p:match("^(.+)/[^/]+$")
		if parent and sizes[parent] then
			if not children[parent] then children[parent] = {} end
			children[parent][#children[parent] + 1] = p
		end
	end

	-- Sort children of each node by size descending
	for p, kids in pairs(children) do
		table.sort(kids, function(a, b)
			return (sizes[a] or 0) > (sizes[b] or 0)
		end)
	end

	local rootKb = sizes[rootPath] or 0
	local rows = {}

	-- DFS traversal
	local function visit(path, depth)
		if depth > #limits then return end
		local limit = limits[depth + 1] or 6
		local kids = children[path] or {}
		local count = 0
		for _, child in ipairs(kids) do
			local name = child:match("([^/]+)$") or child
			if name:sub(1, 1) ~= "." then
				count = count + 1
				if count > limit then break end
				rows[#rows + 1] = {
					depth  = depth + 1,
					name   = name,
					path   = child,
					kb     = sizes[child] or 0,
					rootKb = rootKb,
				}
				visit(child, depth + 1)
			end
		end
	end

	-- Root row
	local rootName = rootPath:match("([^/]+)$") or rootPath
	rows[#rows + 1] = {
		depth  = 0,
		name   = rootName,
		path   = rootPath,
		kb     = rootKb,
		rootKb = rootKb,
	}
	visit(rootPath, 0)

	-- Cleanup temp files
	os.remove(handle.outFile)
	os.remove(handle.doneFile)

	return rows
end

return Model
