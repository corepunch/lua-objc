local ns = require("AppKit")

local Model = {}

function Model.humanKb(kb)
	if kb >= 1024 * 1024 then
		return string.format("%.1f GB", kb / 1024 / 1024)
	elseif kb >= 1024 then
		return string.format("%.1f MB", kb / 1024)
	else
		return string.format("%d KB", kb)
	end
end

function Model.startScan(rootPath, maxDepth)
	local stamp = tostring(os.time()) .. tostring(math.random(1000, 9999))
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

function Model.isDone(handle)
	local f = io.open(handle.doneFile, "r")
	if f then f:close(); return true end
	return false
end

function Model.parseTree(handle)
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

	local function buildNode(path)
		local name = path:match("([^/]+)$") or path
		local node = { name = name, path = path, kb = sizes[path] or 0, children = {} }
		for _, child in ipairs(childrenOf[path] or {}) do
			node.children[#node.children+1] = buildNode(child)
		end
		return node
	end

	os.remove(handle.outFile)
	os.remove(handle.doneFile)
	return buildNode(rootPath)
end

function Model.diskSpace(path)
	return ns.diskSpace(path)
end

function Model.countItems(node)
	local count = #node.children
	for _, child in ipairs(node.children) do
		count = count + Model.countItems(child)
	end
	return count
end

return Model
