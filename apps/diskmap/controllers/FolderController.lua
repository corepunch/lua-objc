local ns = require("AppKit")
local Template = require("ui.template")
local FolderTree = require("apps.diskmap.models.FolderTree")
local Model = require("apps.diskmap.Model")
local Sectors = require("ui.sectors")
local Controller = {}; Controller.__index = Controller

local STYLES = {"rings", "rectangles"}

-- The Folder page: any folder or disk dropped on the window or the Dock
-- icon, or chosen with File › Open Folder…, measured in one scan and shown
-- as DaisyDisk and GrandPerspective show a disk: rings or rectangles beside
-- a list of the focused folder's contents, largest first. Clicking a folder
-- looks inside it, the center or the breadcrumb goes back up, and the map
-- can be colored by folder, by kind of file or by last use. Rows offer
-- Quick Look, Move to… and Move to Trash; a move or Trash updates the map
-- at once. Folders below the first scan's depth are measured when opened.
-- `handlers.volumeName()` names the startup disk, and `handlers.opened()`
-- tells the root controller a folder was opened so it can show this page.
function Controller.new(model, service, actions, handlers)
	return setmetatable({model = model, service = service, actions = actions, handlers = handlers or {},
		style = STYLES[1], coloring = FolderTree.colorings[1].id, generation = 0}, Controller)
end

local function call(service, name, ...)
	local fn = rawget(service, name)
	if type(fn) == "function" then return fn(...) end
end

function Controller:mount(host, state)
	self.template = Template.new(host, "apps/diskmap/views/Folder.etlua", ns)
	self:update(state)
	return self.refs
end

-- The name a folder is shown by: its own, or the startup disk's for "/".
function Controller:displayName(path)
	if path == "/" then return self.handlers.volumeName and self.handlers.volumeName() or "Startup Disk" end
	return path:match("([^/]+)$") or path
end

function Controller:cancel()
	if self.job then call(self.service, "cancelFolderScan", self.job) end
	self.job, self.loading = nil, nil
end

-- Measures `path` and shows it, looking inside `focus` when it is still
-- there. A file opens its folder with the file selected, as the Finder
-- reveals one.
function Controller:open(path, focus)
	if type(path) ~= "string" or path:sub(1, 1) ~= "/" then return false end
	if #path > 1 then path = path:gsub("/+$", "") end
	self:cancel()
	self.generation = self.generation + 1
	local generation = self.generation
	self.path, self.tree, self.focus, self.failure, self.stats = path, nil, path, nil, nil
	self.loading = {path = path, items = 0}
	self:refresh()
	local job = call(self.service, "scanFolder", path, FolderTree.scanOptions, function(folder, failure, stats)
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
			self.scannedAt = os.time()
			local selected = self.selectPath and self.tree:find(self.selectPath)
			if selected then self.selected = selected.path end
			local kept = focus and self.tree:find(focus)
			self.focus = kept and kept.directory and focus or selected and selected.parent and selected.parent.path or path
			self.selectPath = nil
		end
		self:refresh()
	end, function(items) self:progress(generation, items) end)
	-- A provider may finish before returning; its job is then done.
	if generation == self.generation and self.loading then self.job = job end
	return true
end

function Controller:progress(generation, items)
	if generation ~= self.generation or not self.loading then return end
	self.loading.items = items
	if self.refs and self.refs.folderProgress then self.refs.folderProgress.text = self:progressText() end
end

function Controller:rescan()
	if self.path then self:open(self.path, self.focus) end
end

function Controller:progressText()
	local loading = self.loading
	if not loading then return "" end
	local name = self:displayName(loading.path)
	if (loading.items or 0) == 0 then return "Measuring " .. name .. "…" end
	return "Measuring " .. name .. "… " .. Model.count(loading.items) .. " items"
end

-- Looks inside a folder. One below the first scan's depth is measured on
-- its own first, then joined to the tree.
function Controller:setFocus(path)
	if not self.tree then return end
	local node = self.tree:find(path)
	if not node or not node.directory then return end
	if self.tree:needsScan(path) then
		self:cancel()
		local generation = self.generation
		self.loading = {path = path, items = 0, deeper = true}
		self:refresh()
		local job = call(self.service, "scanFolder", path, FolderTree.scanOptions, function(folder, failure)
			if generation ~= self.generation then return end
			self.job, self.loading = nil, nil
			if folder and self.tree:graft(path, folder) then self.focus = path
			elseif failure then self.service.showError("Could not measure " .. node.name, failure) end
			self:refresh()
		end, function(items) self:progress(generation, items) end)
		if generation == self.generation and self.loading then self.job = job end
		return
	end
	self.focus = path
	self:refresh()
end

function Controller:up()
	local node = self.tree and self.tree:find(self.focus)
	if node and node.parent then self:setFocus(node.parent.path) end
end

function Controller:describe(id)
	if not self.refs or not self.refs.folderHover then return end
	self.refs.folderHover.text = id and self.tree and self.tree:describe(id) or self.defaultHover or ""
end

-- Opens a folder, or previews a file with Quick Look.
function Controller:activate(id)
	local node = self.tree and self.tree:find(id)
	if not node then return end
	if node.directory then self:setFocus(id) else self:quickLook(id) end
end

-- The focused folder's files and folders, the neighbours Quick Look's
-- arrow keys step through.
function Controller:siblings()
	local paths = {}
	local node = self.tree and self.tree:find(self.focus)
	for _, child in ipairs(node and node.children or {}) do table.insert(paths, child.path) end
	return paths
end

-- Quick Look for `path`, or for the selected row (File › Quick Look, ⌘Y).
function Controller:quickLook(path)
	path = path or self.selected
	if not path or not (self.tree and self.tree:find(path)) then return false end
	return self.actions:quickLook(path, self:siblings())
end

function Controller:canQuickLook()
	return self.selected ~= nil and self.tree ~= nil and self.tree:find(self.selected) ~= nil
end

-- A move or Trash removes the item from the map without scanning again.
function Controller:changed(path)
	if not self.tree then return end
	self.tree:remove(path)
	if self.selected == path then self.selected = nil end
	if not self.tree:find(self.focus) then self.focus = self.path end
	self:refresh()
end

-- The name the catalog gives a folder, such as Xcode's DerivedData, so a
-- scanned folder reads as what it is and how safe it is to remove.
function Controller:catalogName(path)
	local owner = self.model.resources:owner(path)
	if not owner or owner.path ~= path then return nil end
	local parent = owner:getParent()
	local name = (parent and parent.name ~= owner.name) and (parent.name .. " › " .. owner.name) or owner.name
	return owner.policy and (name .. " · " .. owner.policy) or name
end

-- Space the scan could not attribute on a whole disk: the sealed system
-- volume, snapshots, purgeable files and folders macOS protects.
function Controller:hidden()
	if not self.tree or not (self.path == "/" or self.path:match("^/Volumes/[^/]+$")) then return nil end
	local capacity = call(self.service, "volumeCapacity", self.path)
	if not capacity or not capacity.total or not capacity.available then return nil end
	local used = capacity.total - capacity.available
	local hidden = used - self.tree.root.bytes
	if hidden <= used * 0.01 then return nil end
	return hidden
end

function Controller:summary()
	if self.loading and not self.tree then return self:progressText() end
	if self.failure then return self.path end
	if not self.tree then return "See everything in any folder or disk, largest first." end
	local home, shown = self.model.home or "", self.path
	if home ~= "" and (shown == home or shown:sub(1, #home + 1) == home .. "/") then shown = "~" .. shown:sub(#home + 1) end
	local parts = {shown, Model.size(self.tree.root.bytes)}
	if self.stats and (self.stats.visited or 0) > 0 then table.insert(parts, Model.count(self.stats.visited) .. " items") end
	return table.concat(parts, " · ")
end

function Controller:phase()
	if self.failure then return "failed" end
	if self.tree then return "loaded" end
	if self.loading then return "scanning" end
	return "empty"
end

function Controller:presentation()
	local state = self:phase()
	local data = {state = state, style = self.style, title = self.tree and self.tree.root.name or (self.path and self:displayName(self.path)) or "Folder",
		summary = self:summary(), progress = self:progressText(), failure = self.failure or "",
		colorIndex = 0, colorings = FolderTree.colorings, nodes = {}, rows = {}, trail = {}, legend = {}, hover = "",
		loadingDeeper = self.loading ~= nil and self.loading.deeper == true,
		buttons = {{id = "openFolder", title = "Open Folder…", systemImage = "folder", action = "openFolder", help = "Choose a folder or disk to measure"}}}
	for index, coloring in ipairs(FolderTree.colorings) do if coloring.id == self.coloring then data.colorIndex = index - 1 end end
	if self.path then
		table.insert(data.buttons, self.loading and {id = "stop", title = "Stop", systemImage = "stop.circle", action = "stop", help = "Stop measuring"}
			or {id = "rescan", title = "Measure Again", systemImage = "arrow.clockwise", action = "rescan", help = "Measure this folder again"})
	end
	if state ~= "loaded" then return data end
	local now = os.time()
	local nodes, total = self.tree:nodes(self.focus, self.coloring, now)
	data.nodes, data.total = nodes, Model.size(total)
	data.rows = self.tree:rows(self.focus, self.coloring, now, function(path) return self:catalogName(path) end)
	data.trail = self.tree:trail(self.focus)
	data.legend = self.tree:legend(self.focus, self.coloring, now)
	self.defaultHover = #nodes == 0 and "" or "Hover over the map for details; click a folder to look inside."
	data.hover = self.defaultHover
	data.accessibilityLabel = "Storage map of " .. data.trail[#data.trail].name .. ", " .. #nodes .. " areas"
	data.incomplete = self.stats and (self.stats.errors or 0) > 0
	local hidden = self:hidden()
	data.hidden = hidden and (Model.size(hidden) .. " of used space is in no folder Diskmap could read: the macOS system volume, snapshots, purgeable space and protected folders.") or nil
	return data
end

function Controller:setStyle(style)
	for _, known in ipairs(STYLES) do
		if known == style then self.style = style; self:refresh(); return end
	end
	error("unknown map style " .. tostring(style), 2)
end

function Controller:setColoring(id)
	for _, coloring in ipairs(FolderTree.colorings) do
		if coloring.id == id then self.coloring = id; self:refresh(); return end
	end
	error("unknown coloring " .. tostring(id), 2)
end

function Controller:openFolder()
	local path = call(self.service, "pickFolder", "Open Folder")
	if path then self:open(path) end
end

function Controller:refresh()
	if self.template then self:update(self.state) end
end

function Controller:update(state)
	if not self.template then return end
	self.state = state
	local data = self:presentation()
	local rowsByPath = {}
	for _, row in ipairs(data.rows) do rowsByPath[row.id] = row end
	local handlers = {
		open = function(row) self:setFocus(row.path) end,
		changed = function(path) self:changed(path) end,
		siblings = self:siblings(),
	}
	local actions = {
		openFolder = function() self:openFolder() end,
		rescan = function() self:rescan() end,
		stop = function()
			self:cancel()
			self.generation = self.generation + 1
			if not self.tree then self.path = nil end
			self:refresh()
		end,
		style = function(index) self:setStyle(STYLES[(index or 0) + 1]) end,
		coloring = function(index)
			local coloring = FolderTree.colorings[(index or 0) + 1]
			if coloring then self:setColoring(coloring.id) end
		end,
		chartSelect = function(id, count)
			local node = self.tree and self.tree:find(id)
			if count and count > 1 then self:activate(id)
			elseif node and node.directory and (node.children == nil or #node.children > 0) then self:setFocus(id)
			else self.selected = node and id or self.selected; self:describe(id) end
		end,
		chartHover = function(id) self:describe(id) end,
		up = function() self:up() end,
		selectRow = function(_, _, row)
			if row and not row.other then self.selected = row.path end
			if not row then return end
			self:describe(row.id)
			if self.refs.folderSunburst then Sectors.highlight(self.refs.folderSunburst, row.id) end
		end,
		drillRow = function(_, _, row) if row and not row.other then self:activate(row.id) end end,
		rowMenu = function(_, _, row)
			if not row or row.other then return {} end
			return self.actions:item(rowsByPath[row.id] or row, handlers)
		end,
		-- A mark drags as its folder or file, like a Finder item.
		dragPath = function(id)
			local node = self.tree and self.tree:find(id)
			return node and node.path
		end,
	}
	for index, step in ipairs(data.trail) do
		actions["focus_" .. index] = function() self:setFocus(step.id) end
	end
	data.actions = actions
	local _, refs = self.template:update(data)
	self.refs = refs
	if refs.folderList then refs.folderList:replaceRows(data.rows) end
end

function Controller:marksChanged() self:refresh() end

-- The sidebar badge: the open folder's size.
function Controller:badge()
	return self.tree and Model.size(self.tree.root.bytes) or nil
end

function Controller:dispose()
	if self.template then self.template:dispose() end
	self.template, self.refs = nil, nil
end

return Controller
