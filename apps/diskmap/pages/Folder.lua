local Applications = require("apps.diskmap.models.Applications")
local Explain = require("apps.diskmap.helpers.Explain")
local Locations = require("apps.diskmap.models.Locations")
local Model = require("data.model")
local FolderTree = require("apps.diskmap.helpers.FolderTree")
local Format = require("apps.diskmap.helpers.Format")
local Breakdown = require("apps.diskmap.helpers.Breakdown")
local Selection = require("apps.diskmap.helpers.Selection")

-- Any folder or disk opens as a shared breakdown above its complete list.
-- Clicking a folder looks inside; the center and breadcrumb go back up.
-- Files preview with Quick Look. Moves update the measured tree directly.
local Folder = {view = "pages/Breakdown"}


-- Pointing, row menus and drags only read; a move redraws through `changed`.
Folder.queries = {chartHover = true, rowMenu = true, dragPath = true}

-- `/folder//Users/me?focus=/Users/me/Music`: the folder measured, and the
-- one looked inside. Returning to the folder measured already looks inside
-- again without measuring it again.
function Folder:focus(params)
	if params.path and (params.path ~= self.path or not self.tree) then self:open(params.path, params.focus)
	elseif params.path or params.focus then self:setFocus(params.focus or self.path) end
end
function Folder:location()
	return {path = self.path, focus = self.focusPath ~= self.path and self.focusPath or nil}
end

function Folder:init()
	self.service, self.rowActions = self.app.service, self:flow("Rows")
	self.coloring, self.generation = FolderTree.colorings[1].id, 0
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
	-- Which installed app owns a Library folder needs the apps Spotlight knows.
	if self.app.inventories then self.app.inventories:load("applications") end
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
	if self.refs and self.refs.computingStatus then self.refs.computingStatus.text = self:progressText() end
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
-- sample does, and the native tooltip gives its full path.
-- (WWDC23 10037, StylesDetailsChart; see lua/ui/sectors.lua.)
function Folder:describe(id)
	if not self.refs then return end
	local node = id and self.nodeById and self.nodeById[id]
	if self.refs.breakdownTotal then
		self.refs.breakdownTotal.text = node and node.label or self.center.title
		self.refs.breakdownCaption.text = node and node.detail or self.center.detail
	end
	local chart = self.refs.breakdownChart or self.refs.breakdownRectangles
	if chart then chart.toolTip = id and self.tree and self.tree:describe(id) or "" end
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
	else self.selected = node and id or self.selected; self:describe(id) end
end


function Folder:selection()
	local node = self.tree and self.tree:find(self.selected)
	local detail
	if node then
		detail = node.name .. " · " .. Format.size(node.bytes)
		local about = self:about(node.path)
		if about then detail = detail .. "\n" .. about end
	else
		-- Nothing selected: what the open folder is, when Diskmap knows.
		local about = self.focusPath and self:about(self.focusPath)
		detail = about and (self:displayName(self.focusPath) .. ": " .. about) or "Select an item to inspect its contents or preview it."
	end
	return {title = node and (node.directory and "Inspect Folder Contents" or "Preview File") or "Open Selection",
		detail = detail, enabled = node ~= nil}
end

-- What `path` is and whose, remembered until the installed apps change: a
-- folder named by a random identifier reads its container's metadata once.
function Folder:explain(path)
	local installed = Model.db.installedApplications
	if self.explainedFor ~= installed or not self.explained then
		self.explainedFor, self.explained = installed, {}
		self.installedIndex = Applications.index()
	end
	local cached = self.explained[path]
	if cached == nil then
		cached = Explain.path(path, {home = Model.db.home, apps = self.installedIndex,
			container = function(folder) return self.service.containerIdentifier(folder) end}) or false
		self.explained[path] = cached
	end
	return cached or nil
end

-- A row's owner: the catalog's name for the location, or whose it is.
function Folder:owner(path)
	local named = self:catalogName(path)
	if named then return named end
	local answer = self:explain(path)
	if not answer then return nil end
	if answer.owner then return answer.owner end
	return answer.unclaimed and "No installed app" or nil
end

-- The sentences under the map: what the item is, from the catalog's advice
-- or the knowledge of macOS, and the package that installed it when an
-- installer's receipt says so.
function Folder:about(path)
	local parts = {}
	local owner = Locations:owner(path)
	local answer = self:explain(path)
	if owner and owner.path == path and (owner.advice or owner.subtitle) and not (answer and answer.what) then
		table.insert(parts, owner.advice or owner.subtitle)
	elseif answer and answer.what then
		table.insert(parts, answer.what)
	end
	local package = self.packages and self.packages[path]
	if package then table.insert(parts, package) end
	return #parts > 0 and table.concat(parts, " ") or nil
end

-- An unexplained item in a shared folder may have come from an installer;
-- its receipt names the package. Asked once per item, when it is selected.
function Folder:askPackage(path)
	if not path or not (path:match("^/Library/") or path:match("^/usr/local/") or path:match("^/opt/")) then return end
	local answer = self:explain(path)
	if answer and answer.owner then return end
	self.packages = self.packages or {}
	if self.packages[path] ~= nil then return end
	self.packages[path] = false
	self.service.packageOwner(path, function(packages)
		if not self.packages then return end
		self.packages[path] = Explain.package(packages) or false
		if self.selected == path then self:showSelection() end
	end)
end

function Folder:showSelection() self.app.refresh() end

function Folder:chartHover(id) self:describe(id) end

function Folder:selectRow(_, _, row)
	if not row then return end
	if not row.other then self.selected = row.path; self:askPackage(row.path) end
	self:describe(row.id)
end

function Folder:markRow(_, _, row) self.rowActions:toggleReview(row) end

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
	-- The folder looked inside, where it is and what it holds; the count of
	-- items is the whole measurement's, so it shows at the folder measured.
	local focus = self.tree:find(self.focusPath) or self.tree.root
	local home, shown = Model.db.home or "", focus.path or self.path
	if home ~= "" and (shown == home or shown:sub(1, #home + 1) == home .. "/") then shown = "~" .. shown:sub(#home + 1) end
	local parts = {shown, Format.size(focus.bytes)}
	if focus == self.tree.root and self.stats and (self.stats.visited or 0) > 0 then table.insert(parts, Format.count(self.stats.visited) .. " items") end
	return table.concat(parts, " · ")
end

-- The sidebar badge: the open folder's size.
function Folder:badge()
	return self.tree and Format.size(self.tree.root.bytes) or nil
end

local EMPTY = {id = "folderEmpty", title = "Open a Folder", systemImage = "folder.badge.plus",
	description = "Drop a folder or disk onto this window, or choose File › Open Folder…"}

function Folder:data()
	local phase = self.failure and "failed" or self.tree and "loaded" or self.loading and "scanning" or "empty"
	local data = {title = self.tree and self.tree:find(self.focusPath) and self.tree:find(self.focusPath).name
		or self.path and self:displayName(self.path) or nil, subtitle = self:summary()}
	self.trail, self.rowsByPath = {}, {}
	if phase == "empty" then data.waiting = EMPTY; return data end
	if phase == "failed" then
		data.waiting = {id = "folderFailed", title = "Could Not Measure This Folder", systemImage = "exclamationmark.triangle", description = self.failure}
		return data
	end
	if phase == "scanning" then data.computing, data.stopAction = self:progressText(), "stop"; return data end
	local now = os.time()
	local nodes, total = self.tree:nodes(self.focusPath, self.coloring, now)
	local rows = self.tree:rows(self.focusPath, self.coloring, now, function(path) return self:owner(path) end)
	local trail = self.tree:trail(self.focusPath)
	self.rows, self.trail = rows, trail
	self.nodeById = {}
	for _, node in ipairs(nodes) do self.nodeById[node.id] = node end
	self.center = {title = Format.size(total), detail = #trail > 1 and "Click to go up" or "Measured"}
	for _, row in ipairs(rows) do self.rowActions:annotateReview(row); self.rowsByPath[row.id] = row end
	local options, colorIndex = {}, 0
	for index, coloring in ipairs(FolderTree.colorings) do
		table.insert(options, coloring.title)
		if coloring.id == self.coloring then colorIndex = index - 1 end
	end
	-- Colored by kind or by last use, the legend names the colors instead.
	local marks, legend = Breakdown.rows(rows)
	if self.coloring ~= "folders" then legend = self.tree:legend(self.focusPath, self.coloring, now) end
	-- The coloring is a view option of the page, in the toolbar like Finder's view buttons.
	data.picker = {id = "folderColoring", label = "Color By", value = colorIndex, action = "pickColoring", options = options,
		help = "Color the map by folder, by kind of file or by when files were last used"}
	data.breakdown = {style = self.app.chartStyle,
		marks = marks, rectangles = nodes, legend = legend, dragItem = "dragPath", center = self.center, centerAction = "up",
		accessibilityLabel = "Storage map of " .. trail[#trail].name .. ", " .. #nodes .. " areas"}
	data.lists = {folderList = rows}
	data.sections = {{id = "folderSection", title = "Contents", list = {id = "folderList", menu = "rowMenu", selectAction = "selectRow", activate = "drillRow", fileIcons = true}}}
	data.footnotes = {}
	if self.stats and (self.stats.errors or 0) > 0 then table.insert(data.footnotes, {text = "Some folders could not be read, so sizes are a lower bound."}) end
	local unreadable = self:unreadableBytes()
	if unreadable then
		table.insert(data.footnotes, {text = Format.size(unreadable) .. " of used space is in no folder Diskmap could read: the macOS system volume, snapshots, purgeable space and protected folders."})
	end
	return data
end

function Folder:rendered(refs)
	self.refs = refs
	Selection.show(refs.folderList, self.rows or {}, self.selected)
end

function Folder:deactivate() self.refs = nil end

return {folder = Folder}
