local Paths = require("apps.diskmap.helpers.Paths")
local FileKind = require("apps.diskmap.helpers.FileKind")
local Format = require("apps.diskmap.helpers.Format")
local Palette = require("apps.diskmap.helpers.Palette")
local Kinds = require("apps.diskmap.knowledge.FileKinds")
local FolderTree = {}; FolderTree.__index = FolderTree

-- Any folder or disk as DaisyDisk and GrandPerspective show it: every folder
-- and file under it, largest first, from one scan (the scanner's `treeDepth`
-- summary). Nodes are keyed by path. The scan lists `treeDepth` levels;
-- deeper folders are measured but unlisted (`deeper`), and are scanned on
-- their own when opened. Each folder keeps its largest children and sums
-- the rest as "smaller items", so the map never has more marks than it can
-- draw.
FolderTree.scanOptions = {treeDepth = 8, treeMinimumBytes = 1024 * 1024}
-- The chart shows three rings (or nested rectangles) below the focus, and
-- folds anything under 1.5% of the focus into "smaller items", as the Map
-- page does.
FolderTree.depth = 3
FolderTree.minimumShare = 0.015

-- How the map is colored: by top-level folder (each branch keeps its
-- color, as the Map's categories do), by kind of file, or by last use.
FolderTree.colorings = {
	{id = "folders", title = "Folders"},
	{id = "kinds", title = "Kinds"},
	{id = "age", title = "Last Used"},
}
-- Last-use bands, newest first. A folder's last use is the latest use of
-- anything inside it, so a folder is old only when all of it is.
FolderTree.ages = {
	{id = "month", name = "This month", days = 31, color = "systemGreen"},
	{id = "halfYear", name = "Last 6 months", days = 183, color = "systemTeal"},
	{id = "year", name = "Last year", days = 365, color = "systemYellow"},
	{id = "years", name = "1–3 years ago", days = 3 * 365, color = "systemOrange"},
	{id = "older", name = "Over 3 years ago", days = math.huge, color = "systemRed"},
}
-- Files too small to list have no kind of their own.
local UNKNOWN = {id = "smaller", name = "Smaller files", color = "systemGray"}

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
function FolderTree:contains(path) return self.index[path] ~= nil end

-- Whether opening `path` needs a scan of its own: a listed folder whose
-- contents lie below the first scan's depth.
function FolderTree:needsScan(path)
	local node = self:find(path)
	return node ~= nil and node.directory and node.children == nil and node.bytes > 0
end

-- Folder kinds are cached per node; a change below a folder clears its
-- cache and its ancestors'.
local function invalidate(node)
	while node do node.kinds = nil; node = node.parent end
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
	invalidate(node)
	local ancestor = node.parent
	while ancestor do
		ancestor.bytes = math.max(0, ancestor.bytes + delta)
		ancestor = ancestor.parent
	end
	return true
end

-- Removes an item that was moved away or to the Trash, so the map follows
-- at once without scanning again. Returns the bytes it held.
function FolderTree:remove(path)
	local node = self:find(path)
	if not node or node == self.root then return 0 end
	local parent = node.parent
	for index, child in ipairs(parent.children or {}) do
		if child == node then table.remove(parent.children, index); break end
	end
	unindex(self, node)
	invalidate(parent)
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

-- The kind of a file (FileKinds) by extension; a folder's is the kind that
-- fills most of it, from the files the scan listed inside it.
local OTHER_KIND = Kinds[#Kinds]
local function kindTotals(node)
	if node.kinds then return node.kinds end
	local totals = {}
	if not node.directory then
		totals[FileKind.of(node.name).id] = node.bytes
	else
		for _, child in ipairs(node.children or {}) do
			for id, bytes in pairs(kindTotals(child)) do totals[id] = (totals[id] or 0) + bytes end
		end
	end
	node.kinds = totals
	return totals
end
function FolderTree.kindOf(node)
	if not node.directory then return FileKind.of(node.name) end
	local best, bestBytes = nil, 0
	for id, bytes in pairs(kindTotals(node)) do
		if bytes > bestBytes or (bytes == bestBytes and best and id < best) then best, bestBytes = id, bytes end
	end
	return best and FileKind.byId(best) or OTHER_KIND
end

function FolderTree.ageOf(node, now)
	if not node.used or node.used <= 0 then return UNKNOWN end
	local days = ((now or os.time()) - node.used) / 86400
	for _, band in ipairs(FolderTree.ages) do
		if days < band.days then return band end
	end
	return FolderTree.ages[#FolderTree.ages]
end

-- A node's color under a coloring. "folders" keeps the color its top-level
-- branch was given (`inherited`); the others color every mark on its own.
local function colorFor(node, coloring, inherited, now)
	if coloring == "kinds" then return FolderTree.kindOf(node).color end
	if coloring == "age" then return FolderTree.ageOf(node, now).color end
	return inherited
end

-- Chart nodes {id, parent, value, color, label, detail, ring, leaf, other}
-- below the focus, as Categories:mapNodes draws them, and the focus's total.
function FolderTree:nodes(focus, coloring, now, depth)
	depth = depth or FolderTree.depth
	local root = self:find(focus) or self.root
	local total = root.bytes
	local nodes = {}
	local palette = Palette.new()
	local function visit(node, parentId, ring, inherited)
		local other, otherBytes, shown = node.otherCount, node.otherBytes, 0
		for _, child in ipairs(node.children or {}) do
			if child.bytes > 0 then
				if total > 0 and child.bytes / total < FolderTree.minimumShare then
					other, otherBytes = other + 1, otherBytes + child.bytes
				else
					shown = shown + 1
					local branch = inherited
					if ring == 1 then
						branch = palette:take(nil)
					end
					local leaf = not child.directory or not child.children or #child.children == 0
					table.insert(nodes, {id = child.path, parent = parentId, value = child.bytes,
						color = colorFor(child, coloring, branch, now), label = child.name, detail = Format.size(child.bytes),
						ring = ring, leaf = leaf, directory = child.directory})
					if child.children and ring < depth then visit(child, child.path, ring + 1, branch) end
				end
			end
		end
		-- Smaller items are more of their parent, so they keep its hue, as
		-- on the Map; an outer sliver is left out and the arc ends early.
		if other > 0 and otherBytes > 0 and (ring == 1 or (total > 0 and otherBytes / total >= FolderTree.minimumShare)) then
			table.insert(nodes, {id = (parentId or node.path) .. "#other", parent = parentId, value = otherBytes,
				color = ring == 1 and "systemGray" or inherited, label = Format.count(other) .. " smaller items",
				detail = Format.size(otherBytes), ring = ring, leaf = true, other = true})
		end
	end
	visit(root, nil, 1, nil)
	return nodes, total
end

-- A row's second line: what it is and when it was last used.
local function subtitle(node, now, owner)
	local parts = {}
	if owner then table.insert(parts, owner) end
	if node.directory then
		if node.deeper then table.insert(parts, "Folder")
		elseif node.children then
			local count = #node.children + node.otherCount
			table.insert(parts, count == 0 and "Empty folder" or Format.plural(Format.count(count), "item"))
		end
	else
		table.insert(parts, FileKind.of(node.name).name)
	end
	if node.used and node.used > 0 then table.insert(parts, "used " .. Format.age(node.used, now):lower()) end
	return table.concat(parts, " · ")
end

local function iconFor(node)
	if not node.directory then return FileKind.of(node.name).icon end
	if FileKind.isPackage(node.name) then return "shippingbox.fill" end
	return "folder.fill"
end

-- List rows for the focus's children, largest first, each with the color
-- its mark has on the chart. `describe(path)` may name the catalog location
-- a row is (such as Xcode's DerivedData) so a folder reads as what it is.
function FolderTree:rows(focus, coloring, now, describe)
	local root = self:find(focus) or self.root
	local nodes = self:nodes(focus, coloring, now, 1)
	local colors = {}
	for _, mark in ipairs(nodes) do colors[mark.id] = mark.color end
	local rows, largest = {}, 0
	for _, child in ipairs(root.children or {}) do largest = math.max(largest, child.bytes) end
	for _, child in ipairs(root.children or {}) do
		if child.bytes > 0 then
			table.insert(rows, {id = child.path, path = child.path, name = child.name, bytes = child.bytes,
				size = Format.size(child.bytes), directory = child.directory,
				subtitle = subtitle(child, now, describe and describe(child.path)),
				icon = iconFor(child), color = colors[child.path] or colorFor(child, coloring, "systemGray", now),
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

-- The coloring's legend for the focus: each kind or age band with the bytes
-- it covers, largest first for kinds and newest first for ages. Folders
-- need no legend: the list beside the chart is one.
function FolderTree:legend(focus, coloring, now)
	if coloring ~= "kinds" and coloring ~= "age" then return {} end
	local root = self:find(focus) or self.root
	local totals = {}
	local function add(band, bytes) totals[band.id] = {id = band.id, name = band.name, color = band.color, bytes = (totals[band.id] and totals[band.id].bytes or 0) + bytes} end
	local function walk(node)
		for _, child in ipairs(node.children or {}) do
			if child.directory and child.children and #child.children > 0 then walk(child)
			else add(coloring == "kinds" and (child.directory and FolderTree.kindOf(child) or FileKind.of(child.name)) or FolderTree.ageOf(child, now), child.bytes) end
		end
		if node.otherBytes > 0 then add(coloring == "age" and FolderTree.ageOf(node, now) or UNKNOWN, node.otherBytes) end
	end
	walk(root)
	local rows = {}
	for _, row in pairs(totals) do
		row.size, row.share = Format.size(row.bytes), Format.percent(row.bytes, root.bytes)
		table.insert(rows, row)
	end
	local order = {}
	for index, band in ipairs(FolderTree.ages) do order[band.id] = index end
	table.sort(rows, function(a, b)
		if coloring == "age" and order[a.id] and order[b.id] then return order[a.id] < order[b.id] end
		if a.bytes ~= b.bytes then return a.bytes > b.bytes end
		return a.name < b.name
	end)
	return rows
end

-- One line for the hover bar: the path below the root, size and share.
function FolderTree:describe(path)
	local node = self:find(path)
	if not node then
		local parent = path and path:match("^(.*)#other$")
		local owner = parent and self:find(parent)
		if not owner then return nil end
		return owner.name .. " › " .. Format.count(owner.otherCount) .. " smaller items · " .. Format.size(owner.otherBytes)
	end
	local names = {}
	for _, step in ipairs(self:trail(path)) do table.insert(names, step.name) end
	local share = self.root.bytes > 0 and string.format(" · %.1f%% of %s", node.bytes * 100 / self.root.bytes, self.root.name) or ""
	return table.concat(names, " › ") .. " · " .. Format.size(node.bytes) .. share
end

-- Whether Diskmap may move `path` to the Trash or to another folder:
-- only items in the home folder or on another disk, never a system
-- location, a standard folder or a mount point (the cleanup basket's
-- rules), never something inside a package, and never a location the
-- catalog marks Keep, Essential or system managed. `home` is the home
-- folder and `owner` the location that owns the path (Locations:owner).
function FolderTree.validateChange(path, home, owner)
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
	-- The catalog describes the startup disk; another disk has no owners.
	if inHome and owner then
		if owner:isKept() then return false, owner.name .. " is marked Keep." end
		if owner.policy == "Essential" or owner.policy == "System managed" then return false, owner.name .. " is managed by its owner." end
	end
	return true
end

-- The destination a move must not use: the item's own folder (nothing
-- would change) or a folder inside the item.
function FolderTree.validateDestination(path, folder)
	if type(folder) ~= "string" or folder:sub(1, 1) ~= "/" then return false, "Choose a folder to move it to." end
	if folder == parentOf(path) then return false, "It is already in that folder." end
	if folder == path or folder:sub(1, #path + 1) == path .. "/" then return false, "A folder cannot be moved into itself." end
	return true
end

return FolderTree
