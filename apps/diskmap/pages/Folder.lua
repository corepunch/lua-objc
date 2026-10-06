local Locations = require("apps.diskmap.models.Locations")
local Model = require("data.model")
local FolderTree = require("apps.diskmap.helpers.FolderTree")
local Sectors = require("ui.sectors")
local Format = require("apps.diskmap.helpers.Format")
local Selection = require("apps.diskmap.helpers.Selection")

-- The Folder page: any folder or disk dropped on the window or the Dock icon,
-- or chosen with File › Open Folder…, measured in one scan and shown as
-- DaisyDisk and GrandPerspective show a disk: rings or rectangles beside a
-- list of the focused folder's contents, largest first. Clicking a folder
-- looks inside it, the center or the breadcrumb goes back up, and the map can
-- be colored by folder, by kind of file or by last use. Rows offer Quick Look,
-- Move to… and Move to Trash; a move or Trash updates the map at once.
-- Folders below the first scan's depth are measured when opened. The scan
-- counts its items on the line under the spinner, the one live thing here;
-- the rest is drawn when the scan has finished (`app.refresh()`).
local Folder = {view = "pages/Folder"}
-- The caption under the chart keeps two lines; this must fit them whole in
-- the narrowest pane (tests/diskmap_issue102.test.lua).
Folder.guidance = "Click a folder to look inside. Double-click a file to preview it."

local STYLES = {"rings", "rectangles"}

-- Pointing, row menus and drags only read; a move redraws through `changed`.
Folder.queries = {chartHover = true, selectRow = true, rowMenu = true, dragPath = true}

function Folder:focus(params)
	if params.path then self:open(params.path, params.focus)
	elseif params.focus then self:setFocus(params.focus) end
	if params.style then self.style = params.style end
end

function Folder:init()
	self.service, self.rowActions = self.app.service, self:flow("Rows")
	self.style, self.coloring, self.generation = STYLES[1], FolderTree.colorings[1].id, 0
end

-- The name a folder is shown by: its own, or the startup disk's for "/".
function Folder:displayName(path)
	if path == "/" then return self.app.volumeName() end
	return path:match("([^/]+)$") or path
end

function Folder:cancel()
	if self.job then self.service.cancelFolderScan(self.job) end
	self.job, self.loading = nil, nil
end

-- Measures `path` and shows it, looking inside `focus` when it is still
-- there. A file opens its folder with the file selected, as the Finder
-- reveals one.
function Folder:open(path, focus)
	if type(path) ~= "string" or path:sub(1, 1) ~= "/" then return false end
	if #path > 1 then path = path:gsub("/+$", "") end
	self:cancel()
	self.generation = self.generation + 1
	local generation = self.generation
	self.path, self.tree, self.focusPath, self.failure, self.stats = path, nil, path, nil, nil
	self.loading = {path = path, items = 0}
	self.app.refresh()
	local job = self.service.scanFolder(path, FolderTree.scanOptions, function(folder, failure, stats)
		if generation ~= self.generation then return end
		self.job, self.loading = nil, nil
		if folder and not folder.directory and folder.children == nil then
			local parent = FolderTree.parentOf(path)
			if parent then self.selectPath = path; self:open(parent); return end
		end
		if not folder then
			self.failure = failure or "The folder could not be read."
		else
			self.tree = FolderTree.new(path, folder)
			self.tree.root.name = self:displayName(path)
			self.stats = stats or {}
			local selected = self.selectPath and self.tree:find(self.selectPath)
			if selected then self.selected = selected.path end
			local kept = focus and self.tree:find(focus)
			self.focusPath = kept and kept.directory and focus or selected and selected.parent and selected.parent.path or path
			self.selectPath = nil
		end
		self.app.refresh()
	end, function(items) self:progress(generation, items) end)
	-- A provider may finish before returning; its job is then done.
	if generation == self.generation and self.loading then self.job = job end
	return true
end

function Folder:progress(generation, items)
	if generation ~= self.generation or not self.loading then return end
	self.loading.items = items
	if self.refs and self.refs.folderProgress then self.refs.folderProgress.text = self:progressText() end
end

function Folder:rescan()
	if self.path then self:open(self.path, self.focusPath) end
end

function Folder:stop()
	self:cancel()
	self.generation = self.generation + 1
	if not self.tree then self.path = nil end
end

function Folder:progressText()
	local loading = self.loading
	if not loading then return "" end
	local name = self:displayName(loading.path)
	if (loading.items or 0) == 0 then return "Measuring " .. name .. "…" end
	return "Measuring " .. name .. "… " .. Format.count(loading.items) .. " items"
end

-- Looks inside a folder. One below the first scan's depth is measured on
-- its own first, then joined to the tree.
function Folder:setFocus(path)
	if not self.tree then return end
	local node = self.tree:find(path)
	if not node or not node.directory then return end
	if self.tree:needsScan(path) then
		self:cancel()
		local generation = self.generation
		self.loading = {path = path, items = 0, deeper = true}
		local job = self.service.scanFolder(path, FolderTree.scanOptions, function(folder, failure)
			if generation ~= self.generation then return end
			self.job, self.loading = nil, nil
			if folder and self.tree:graft(path, folder) then self.focusPath = path
			elseif failure then self.service.showError("Could not measure " .. node.name, failure) end
			self.app.refresh()
		end, function(items) self:progress(generation, items) end)
		if generation == self.generation and self.loading then self.job = job end
		return
	end
	self.focusPath, self.selected = path, nil
end

function Folder:up()
	local node = self.tree and self.tree:find(self.focusPath)
	if node and node.parent then self:setFocus(node.parent.path) end
end

-- The hole names the pointed item and its size, as Apple's SectorMark
-- sample does, and the line under the map its path.
-- (WWDC23 10037, StylesDetailsChart; see lua/ui/sectors.lua.)
function Folder:describe(id)
	if not self.refs or not self.refs.folderHover then return end
	local node = id and self.nodeById and self.nodeById[id]
	if self.refs.folderCenterTitle then
		self.refs.folderCenterTitle.text = node and node.label or self.center.title
		self.refs.folderCenterDetail.text = node and node.detail or self.center.detail
	end
	self.refs.folderHover.text = id and self.tree and self.tree:describe(id) or self.hover or ""
end

-- Opens a folder, or previews a file with Quick Look.
function Folder:drill(id)
	local node = self.tree and self.tree:find(id)
	if not node then return end
	if node.directory then self:setFocus(id) else self:quickLook(id) end
end

function Folder:chartSelect(id, count)
	local node = self.tree and self.tree:find(id)
	if count and count > 1 then self:drill(id)
	elseif node and node.directory and (node.children == nil or #node.children > 0) then self:setFocus(id)
	else self.selected = node and id or self.selected; self:describe(id); self:showSelection() end
end

function Folder:openSelection() if self.selected then self:drill(self.selected) end end

function Folder:selection()
	local node = self.tree and self.tree:find(self.selected)
	return {title = node and (node.directory and "Inspect Folder Contents" or "Preview File") or "Open Selection",
		detail = node and (node.name .. " · " .. Format.size(node.bytes)) or "Select an item to inspect its contents or preview it.",
		enabled = node ~= nil}
end

function Folder:showSelection()
	if not self.refs or not self.refs.folderOpen then return end
	local selection = self:selection()
	self.refs.folderOpen.title, self.refs.folderOpen.enabled = selection.title, selection.enabled
	self.refs.folderSelection.text = selection.detail
end

function Folder:chartHover(id) self:describe(id) end

function Folder:selectRow(_, _, row)
	if not row then return end
	if not row.other then self.selected = row.path end
	self:describe(row.id)
	self:showSelection()
	if self.refs.folderSunburst then Sectors.highlight(self.refs.folderSunburst, row.id) end
end

function Folder:drillRow(_, _, row) if row and not row.other then self:drill(row.id) end end

function Folder:rowMenu(_, _, row)
	if not row or row.other then return {} end
	local app = self.app
	return self.rowActions:item(self.rowsByPath[row.id] or row, {
		open = function(item) self:setFocus(item.path); app.refresh() end,
		changed = function(path) self:changed(path) end,
		siblings = self:siblings(),
	})
end

-- A mark drags as its folder or file, like a Finder item.
function Folder:dragPath(id)
	local node = self.tree and self.tree:find(id)
	return node and node.path
end

function Folder:pickStyle(index)
	local style = STYLES[(index or 0) + 1]
	if not style then error("unknown map style " .. tostring(index), 2) end
	self.style = style
end

function Folder:pickColoring(index)
	local coloring = FolderTree.colorings[(index or 0) + 1]
	if coloring then self.coloring = coloring.id end
end

function Folder:openFolder()
	local path = self.service.pickFolder("Open Folder")
	if path then self:open(path) end
end

-- The focused folder's files and folders, the neighbours Quick Look's
-- arrow keys step through.
function Folder:siblings()
	local paths = {}
	local node = self.tree and self.tree:find(self.focusPath)
	for _, child in ipairs(node and node.children or {}) do table.insert(paths, child.path) end
	return paths
end

-- Quick Look for `path`, or for the selected row (File › Quick Look, ⌘Y).
function Folder:quickLook(path)
	path = path or self.selected
	if not path or not (self.tree and self.tree:find(path)) then return false end
	return self.rowActions:quickLook(path, self:siblings())
end

function Folder:canQuickLook()
	return self.selected ~= nil and self.tree ~= nil and self.tree:find(self.selected) ~= nil
end

-- A move or Trash removes the item from the map without scanning again.
function Folder:changed(path)
	if not self.tree then return end
	self.tree:remove(path)
	if self.selected == path then self.selected = nil end
	if not self.tree:find(self.focusPath) then self.focusPath = self.path end
end

-- The name the catalog gives a folder, such as Xcode's DerivedData, so a
-- scanned folder reads as what it is and how safe it is to remove.
function Folder:catalogName(path)
	local owner = Locations:owner(path)
	if not owner or owner.path ~= path then return nil end
	-- A build folder's group only repeats its kind ("CMake builds › CMake
	-- build output"), so an artifact is named by itself.
	local parent = not owner.artifact and owner:parent() or nil
	local name = (parent and parent.name ~= owner.name) and (parent.name .. " › " .. owner.name) or owner.name
	return owner.policy and (name .. " · " .. owner.policy) or name
end

-- Space the scan could not attribute on a whole disk: the sealed system
-- volume, snapshots, purgeable files and folders macOS protects.
function Folder:unreadableBytes()
	if not self.tree or not (self.path == "/" or self.path:match("^/Volumes/[^/]+$")) then return nil end
	local capacity = self.service.volumeCapacity(self.path)
	if not capacity or not capacity.total or not capacity.available then return nil end
	local used = capacity.total - capacity.available
	local unreadable = used - self.tree.root.bytes
	if unreadable <= used * 0.01 then return nil end
	return unreadable
end

function Folder:summary()
	if self.loading and not self.tree then return self:progressText() end
	if self.failure then return self.path end
	if not self.tree then return "See everything in any folder or disk, largest first." end
	local home, shown = Model.db.home or "", self.path
	if home ~= "" and (shown == home or shown:sub(1, #home + 1) == home .. "/") then shown = "~" .. shown:sub(#home + 1) end
	local parts = {shown, Format.size(self.tree.root.bytes)}
	if self.stats and (self.stats.visited or 0) > 0 then table.insert(parts, Format.count(self.stats.visited) .. " items") end
	return table.concat(parts, " · ")
end

-- The sidebar badge: the open folder's size.
function Folder:badge()
	return self.tree and Format.size(self.tree.root.bytes) or nil
end

function Folder:data()
	local phase = self.failure and "failed" or self.tree and "loaded" or self.loading and "scanning" or "empty"
	local data = {state = phase, style = self.style, summary = self:summary(), progress = self:progressText(),
		failure = self.failure or "", colorings = FolderTree.colorings, colorIndex = 0, nodes = {}, rows = {}, trail = {}, legend = {},
		title = self.tree and self.tree.root.name or (self.path and self:displayName(self.path)) or "Folder",
		hasPath = self.path ~= nil, measuring = self.loading ~= nil, loadingDeeper = self.loading ~= nil and self.loading.deeper == true}
	for index, coloring in ipairs(FolderTree.colorings) do if coloring.id == self.coloring then data.colorIndex = index - 1 end end
	self.trail, self.rowsByPath = data.trail, {}
	if phase ~= "loaded" then return data end
	local now = os.time()
	local nodes, total = self.tree:nodes(self.focusPath, self.coloring, now)
	data.nodes = nodes
	data.rows = self.tree:rows(self.focusPath, self.coloring, now, function(path) return self:catalogName(path) end)
	self.rows = data.rows
	data.trail = self.tree:trail(self.focusPath)
	self.nodeById = {}
	for _, node in ipairs(nodes) do self.nodeById[node.id] = node end
	self.center = {title = Format.size(total), detail = #data.trail > 1 and "Click to go up" or "Measured"}
	data.center = self.center
	data.selection = self:selection()
	data.legend = self.tree:legend(self.focusPath, self.coloring, now)
	data.lists = self.style ~= "rectangles" and {folderList = data.rows} or nil
	self.trail = data.trail
	for _, row in ipairs(data.rows) do self.rowsByPath[row.id] = row end
	self.hover = #nodes == 0 and "" or Folder.guidance
	data.hover = self.hover
	-- The breadcrumb buttons are named by position (`focus_2`).
	data.handlers = {}
	for index, step in ipairs(data.trail) do data.handlers["focus_" .. index] = function() self:setFocus(step.id) end end
	data.accessibilityLabel = "Storage map of " .. data.trail[#data.trail].name .. ", " .. #nodes .. " areas"
	data.incomplete = self.stats and (self.stats.errors or 0) > 0
	local unreadable = self:unreadableBytes()
	data.unreadable = unreadable and (Format.size(unreadable) .. " of used space is in no folder Diskmap could read: the macOS system volume, snapshots, purgeable space and protected folders.") or nil
	return data
end

function Folder:rendered(refs)
	self.refs = refs
	Selection.show(refs.folderList, self.rows or {}, self.selected)
	self:showSelection()
end

function Folder:deactivate() self.refs = nil end

return {folder = Folder}
