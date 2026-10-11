local Model = require("data.model")
local Explain = require("apps.diskmap.helpers.Explain")
local Leftovers = require("apps.diskmap.helpers.Leftovers")
local FolderTree = require("apps.diskmap.helpers.FolderTree")
local Format = require("apps.diskmap.helpers.Format")

-- Any folder, as one list to look inside: its contents largest first, each
-- with what it is when Diskmap knows (helpers/Explain), when it was last
-- written and its share. Opening a folder looks inside; Up and Back return.
-- Files preview with Quick Look. A removal updates the measured tree.
local Folder = {view = "pages/Folder", queries = {rowMenu = true, dragPath = true}}

-- `/folder//Users/me?focus=/Users/me/Music`: the folder measured, and the
-- one looked inside. Returning to a folder measured already looks inside
-- again without measuring it again.
function Folder:focus(params)
	if params.path and (params.path ~= self.path or not self.tree) then self:open(params.path, params.focus)
	elseif params.path or params.focus then self:setFocus(params.focus or self.path) end
end
function Folder:location()
	return {path = self.path, focus = self.focusPath ~= self.path and self.focusPath or nil}
end

function Folder:init()
	self.service, self.rowActions, self.generation = self.app.service, self:flow("Rows"), 0
end

function Folder:displayName(path)
	if path == "/" then return self.app.volumeName() end
	return path:match("([^/]+)$") or path
end

function Folder:cancel()
	if self.job then self.service.cancelFolderScan(self.job) end
	self.job, self.loading = nil, nil
end

-- Measures `path` and shows it, looking inside `focus` when it is still
-- there. A file opens its folder with the file selected.
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
	if generation == self.generation and self.loading then self.job = job end
	return true
end

function Folder:progress(generation, items)
	if generation ~= self.generation or not self.loading then return end
	self.loading.items = items
	if self.refs and self.refs.measuringStatus then self.refs.measuringStatus.text = self:progressText() end
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

-- What `path` is and whose, remembered until the installed apps change.
function Folder:explain(path)
	local installed = Model.db.installedApplications
	if self.explainedFor ~= installed or not self.explained then
		self.explainedFor, self.explained = installed, {}
		self.facts = {home = Model.db.home, apps = installed and Leftovers.index(installed) or nil}
	end
	local cached = self.explained[path]
	if cached == nil then
		cached = Explain.path(path, self.facts) or false
		self.explained[path] = cached
	end
	return cached or nil
end

-- The few words under a row's name: what the folder is and whether it may
-- go, when the knowledge of macOS has a note for it; an item Diskmap
-- measured elsewhere reads as that item.
function Folder:note(path)
	local item = require("apps.diskmap.models.Items"):byPath(path)
	if item then return item.owner .. " · " .. require("apps.diskmap.helpers.Verdict").styles[item.verdict].label end
	local answer = self:explain(path)
	if answer and answer.note and answer.note ~= answer.kind then return answer.note end
	if not answer then return nil end
	return answer.note or answer.owner or (answer.unclaimed and "No installed app" or nil)
end

function Folder:drill(id)
	local node = self.tree and self.tree:find(id)
	if not node then return end
	if node.directory then self:setFocus(id) else self:quickLook(id) end
end

function Folder:selectRow(_, _, row) if row and not row.other then self.selected = row.path end end
function Folder:drillRow(_, _, row) if row and not row.other then self:drill(row.id) end end

-- A row of the list as something to remove: its path and size, for the
-- Trash, with what Diskmap knows about it as the consequence.
function Folder:item(row)
	local item = require("apps.diskmap.models.Items"):byPath(row.path)
	if item then return item end
	local answer = self:explain(row.path)
	return {id = row.path, path = row.path, name = row.name, bytes = row.bytes, state = "measured", action = "trash", verdict = "review", directory = row.directory,
		what = answer and answer.what or (row.directory and "The folder and everything in it move to the Trash." or "The file moves to the Trash."),
		bundleId = require("apps.diskmap.helpers.Verify").bundleId(row.path)}
end

-- Moves a row to the Trash after confirmation; only items in the home
-- folder or on another disk, never inside a package (helpers/FolderTree).
function Folder:removeRow(_, _, row)
	if not row or row.other then return end
	local ok, reason = FolderTree.validateChange(row.path, Model.db.home)
	if not ok then self.service.showError("Cannot remove this item", reason); return end
	return self:flow("Remove"):rows({self:item(row)})
end

function Folder:rowMenu(_, _, row)
	if not row or row.other then return {} end
	local service, app = self.service, self.app
	local items = {}
	if row.directory then table.insert(items, {title = "Look Inside", systemImage = "folder", action = function() self:setFocus(row.path); app.refresh() end})
	else table.insert(items, {title = "Quick Look", systemImage = "eye", action = function() self:quickLook(row.path) end}) end
	table.insert(items, {title = "Show in Finder", systemImage = "arrow.up.forward.square", action = function() service.reveal(row.path) end})
	table.insert(items, {separator = true})
	if FolderTree.validateChange(row.path, Model.db.home) then
		table.insert(items, {title = "Move to Trash…", systemImage = "trash", action = function() self:removeRow(nil, nil, row) end})
	end
	table.insert(items, {separator = true})
	table.insert(items, {title = "Copy Path", systemImage = "doc.on.doc", action = function() service.copy(row.path) end})
	return items
end

function Folder:dragPath(id)
	local node = self.tree and self.tree:find(id)
	return node and node.path
end

function Folder:siblings()
	local paths = {}
	local node = self.tree and self.tree:find(self.focusPath)
	for _, child in ipairs(node and node.children or {}) do table.insert(paths, child.path) end
	return paths
end

function Folder:quickLook(path)
	path = path or self.selected
	if not path or not (self.tree and self.tree:find(path)) then return false end
	local siblings, index = self:siblings(), 1
	for position, sibling in ipairs(siblings) do if sibling == path then index = position end end
	self.service.quickLook(#siblings > 0 and siblings or {path}, index)
	return true
end

function Folder:canQuickLook()
	return self.selected ~= nil and self.tree ~= nil and self.tree:find(self.selected) ~= nil
end

-- A removal takes the item out of the list without scanning again.
function Folder:changed(path)
	if not self.tree then return end
	self.tree:remove(path)
	if self.selected == path then self.selected = nil end
	if not self.tree:find(self.focusPath) then self.focusPath = self.path end
end

function Folder:summary()
	if self.loading and not self.tree then return self:progressText() end
	if self.failure then return self.path end
	if not self.tree then return "Look inside any folder, largest first." end
	local focus = self.tree:find(self.focusPath) or self.tree.root
	local parts = {Format.tilde(focus.path or self.path, Model.db.home), Format.size(focus.bytes)}
	if focus == self.tree.root and self.stats and (self.stats.visited or 0) > 0 then table.insert(parts, Format.count(self.stats.visited) .. " items") end
	return table.concat(parts, " · ")
end

function Folder:data()
	local phase = self.failure and "failed" or self.tree and "loaded" or self.loading and "measuring" or "empty"
	local focus = self.tree and self.tree:find(self.focusPath)
	local data = {title = focus and focus.name or self.path and self:displayName(self.path) or "Folder Map", subtitle = self:summary(), phase = phase,
		failure = self.failure or "", measuring = self:progressText(), notice = Model.db.notice or "", hidden = {notice = Model.db.notice == nil}}
	self.rowsByPath = {}
	if phase ~= "loaded" then return data end
	local now = os.time()
	local rows = self.tree:rows(self.focusPath, now, function(path) return self:note(path) end)
	local trail = self.tree:trail(self.focusPath)
	for _, row in ipairs(rows) do
		self.rowsByPath[row.id] = row
		row.removable = not row.other and FolderTree.validateChange(row.path, Model.db.home) == true
		row.removeHelp = row.removable and "Move to Trash…" or "Diskmap moves only items in your home folder or on other disks"
	end
	local crumbs = {}
	for _, step in ipairs(trail) do table.insert(crumbs, step.name) end
	data.lists = {folderList = rows}
	data.trail = table.concat(crumbs, " › ")
	data.hidden.up = #trail <= 1
	local notes = {}
	if self.stats and (self.stats.errors or 0) > 0 then table.insert(notes, "Some folders could not be read, so sizes are a lower bound.") end
	data.footnote = table.concat(notes, " ")
	data.hidden.footnote = data.footnote == ""
	return data
end

function Folder:rendered(refs) self.refs = refs end
function Folder:deactivate() self.refs = nil end

return {folder = Folder}
