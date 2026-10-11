local Paths = require("apps.diskmap.helpers.Paths")
local FileKind = require("apps.diskmap.helpers.FileKind")
local Format = require("apps.diskmap.helpers.Format")
local FolderTree = {}; FolderTree.__index = FolderTree

-- Any folder as one list to look inside: every folder and file under it,
-- largest first, from one scan (the scanner's `treeDepth` summary). Nodes
-- are keyed by path. The scan lists `treeDepth` levels; deeper folders are
-- measured but unlisted (`deeper`), and are scanned on their own when
-- opened. Each folder keeps its largest children and sums the rest as
-- "smaller items", so a list never has more rows than it can show.
FolderTree.scanOptions = {treeDepth = 8, treeMinimumBytes = 1024 * 1024}

local function parentOf(path)
	if path == "/" then return nil end
	local slash = path:match("^.*()/")
	return slash == 1 and "/" or slash and path:sub(1, slash - 1) or nil
end
FolderTree.parentOf = parentOf

local function join(folder, name)
	return folder == "/" and ("/" .. name) or (folder .. "/" .. name)
end

-- Converts a scanner node {name, kb, used, directory, children, otherKb,
-- otherCount, deeper} at `path` into the tree's own nodes, indexing each.
local function adopt(self, raw, path, parent)
	local node = {path = path, name = raw.name or path:match("([^/]+)$") or path, parent = parent,
		bytes = math.floor((raw.kb or 0) * 1024 + 0.5), used = raw.used or 0,
		directory = raw.directory == true, deeper = raw.deeper == true,
		otherBytes = math.floor((raw.otherKb or 0) * 1024 + 0.5), otherCount = raw.otherCount or 0}
	self.index[path] = node
	if raw.children then
		node.children = {}
		for _, child in ipairs(raw.children) do
			if child.name and child.name ~= "" then table.insert(node.children, adopt(self, child, join(path, child.name), node)) end
		end
		table.sort(node.children, function(a, b) if a.bytes ~= b.bytes then return a.bytes > b.bytes end return a.name < b.name end)
	end
	return node
end

-- A tree for the folder at `path` from the scanner's root node.
function FolderTree.new(path, raw)
	local self = setmetatable({path = path, index = {}}, FolderTree)
	self.root = adopt(self, raw or {}, path, nil)
	self.root.directory = true
	self.root.name = path == "/" and (raw and raw.name ~= "" and raw.name or "/") or self.root.name
	return self
end

function FolderTree:find(path) return path and self.index[path] or nil end

-- Whether opening `path` needs a scan of its own: a listed folder whose
-- contents lie below the first scan's depth.
function FolderTree:needsScan(path)
	local node = self:find(path)
	return node ~= nil and node.directory and node.children == nil and node.bytes > 0
end

local function unindex(self, node)
	self.index[node.path] = nil
	for _, child in ipairs(node.children or {}) do unindex(self, child) end
end

-- Replaces a deeper folder's contents with its own scan. Its measured size
-- may have changed since the first scan; ancestors follow the difference.
function FolderTree:graft(path, raw)
	local node = self:find(path)
	if not node or not raw then return false end
	for _, child in ipairs(node.children or {}) do unindex(self, child) end
	local fresh = adopt(self, raw, path, node.parent)
	fresh.name, fresh.directory = node.name, true
	local delta = fresh.bytes - node.bytes
	for key, value in pairs(fresh) do node[key] = value end
	for _, child in ipairs(node.children or {}) do child.parent = node end
	node.deeper = false
	self.index[path] = node
	local ancestor = node.parent
	while ancestor do
		ancestor.bytes = math.max(0, ancestor.bytes + delta)
		ancestor = ancestor.parent
	end
	return true
end

-- Removes an item that was moved to the Trash, so the list follows at once
-- without scanning again. Returns the bytes it held.
function FolderTree:remove(path)
	local node = self:find(path)
	if not node or node == self.root then return 0 end
	local parent = node.parent
	for index, child in ipairs(parent.children or {}) do
		if child == node then table.remove(parent.children, index); break end
	end
	unindex(self, node)
	local ancestor = parent
	while ancestor do
		ancestor.bytes = math.max(0, ancestor.bytes - node.bytes)
		ancestor = ancestor.parent
	end
	return node.bytes
end

-- The focus and its ancestors, root first, for the breadcrumb.
function FolderTree:trail(focus)
	local trail, node = {}, self:find(focus) or self.root
	while node do
		table.insert(trail, 1, {id = node.path, name = node.name})
		node = node.parent
	end
	return trail
end

-- A row's second line: what it is and when it was last written.
local function subtitle(node, now, note)
	local parts = {}
	if note then table.insert(parts, note) end
	if node.directory then
		if node.deeper then table.insert(parts, "Folder")
		elseif node.children then
			local count = #node.children + node.otherCount
			table.insert(parts, count == 0 and "Empty folder" or Format.plural(Format.count(count), "item"))
		end
	else
		table.insert(parts, FileKind.of(node.name).name)
	end
	if node.used and node.used > 0 then table.insert(parts, "written " .. Format.age(node.used, now):lower()) end
	return table.concat(parts, " · ")
end

local function iconFor(node)
	if not node.directory then return FileKind.of(node.name).icon end
	if FileKind.isPackage(node.name) then return "shippingbox.fill" end
	return "folder.fill"
end

-- List rows for the focus's children, largest first. `describe(path)` may
-- say what a folder is (helpers/Explain) so it reads as what it is.
function FolderTree:rows(focus, now, describe)
	local root = self:find(focus) or self.root
	local rows, largest = {}, 0
	for _, child in ipairs(root.children or {}) do largest = math.max(largest, child.bytes) end
	for _, child in ipairs(root.children or {}) do
		if child.bytes > 0 then
			table.insert(rows, {id = child.path, path = child.path, name = child.name, bytes = child.bytes,
				size = Format.size(child.bytes), directory = child.directory,
				subtitle = subtitle(child, now, describe and describe(child.path)),
				icon = iconFor(child), color = child.directory and "systemBlue" or FileKind.of(child.name).color,
				relative = largest > 0 and child.bytes / largest or 0, shareText = Format.percent(child.bytes, root.bytes)})
		end
	end
	if root.otherCount > 0 and root.otherBytes > 0 then
		table.insert(rows, {id = root.path .. "#other", name = Format.count(root.otherCount) .. " smaller items",
			bytes = root.otherBytes, size = Format.size(root.otherBytes), subtitle = "Each under " .. Format.size(FolderTree.scanOptions.treeMinimumBytes),
			icon = "ellipsis.circle.fill", color = "systemGray", other = true,
			relative = largest > 0 and root.otherBytes / largest or 0, shareText = Format.percent(root.otherBytes, root.bytes)})
	end
	return rows
end

-- Whether Diskmap may move `path` to the Trash: only items in the home
-- folder or on another disk, never a system location, a standard folder or
-- a mount point (helpers/Paths), and never something inside a package.
function FolderTree.validateChange(path, home)
	local ok, reason = Paths.validate(path, home)
	if not ok then return false, reason end
	home = home or ""
	local inHome = home ~= "" and path:sub(1, #home + 1) == home .. "/"
	if not inHome and not path:match("^/Volumes/[^/]+/.") then
		return false, "Diskmap changes only items in your home folder and on other disks."
	end
	local parent = parentOf(path)
	while parent and parent ~= "/" do
		local name = parent:match("([^/]+)$")
		if FileKind.isPackage(name) then return false, "This is inside " .. name .. ". Manage it in the app that owns it." end
		parent = parentOf(parent)
	end
	return true
end

return FolderTree
