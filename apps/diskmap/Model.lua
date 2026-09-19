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

-- Parse results into a tree. Each node: {name, path, kb, children}.
-- depthLimits is a list of max children per depth level (0-indexed depth → limits[depth+1]).
function Model.parseTree(handle, depthLimits)
	depthLimits = depthLimits or { 12, 10, 8, 6 }
	local rootPath = handle.rootPath:gsub("/$", "")

	local sizes = {}
	local f = io.open(handle.outFile, "r")
	if not f then return nil end
	for line in f:lines() do
		local kbStr, p = line:match("^(%d+)%s+(.+)")
		if kbStr then
			p = p:gsub("/$", "")
			sizes[p] = tonumber(kbStr)
		end
	end
	f:close()

	local childrenOf = {}
	for p in pairs(sizes) do
		local parent = p:match("^(.+)/[^/]+$")
		if parent and sizes[parent] then
			if not childrenOf[parent] then childrenOf[parent] = {} end
			childrenOf[parent][#childrenOf[parent]+1] = p
		end
	end

	for _, kids in pairs(childrenOf) do
		table.sort(kids, function(a, b) return (sizes[a] or 0) > (sizes[b] or 0) end)
	end

	local function buildNode(path, depth)
		local name = path:match("([^/]+)$") or path
		local node = { name = name, path = path, kb = sizes[path] or 0, children = {} }
		local limit = depthLimits[depth + 1] or 0
		if limit > 0 then
			local count = 0
			for _, child in ipairs(childrenOf[path] or {}) do
				local childName = child:match("([^/]+)$") or ""
				if childName:sub(1, 1) ~= "." then
					count = count + 1
					if count > limit then break end
					node.children[#node.children+1] = buildNode(child, depth + 1)
				end
			end
		end
		return node
	end

	os.remove(handle.outFile)
	os.remove(handle.doneFile)
	return buildNode(rootPath, 0)
end

return Model
