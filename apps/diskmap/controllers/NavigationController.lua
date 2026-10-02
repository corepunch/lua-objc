local ns = require("AppKit")
local xml = require("ui.xml")
local Workflows = require("apps.diskmap.knowledge.Workflows")
local Controller = {}; Controller.__index = Controller

-- Sidebar destinations in the order a person needs them: where storage
-- stands and what to do first (Overview, Clean Up) lead without a header,
-- then the pages that each end in a cleanup decision, then the tools for
-- browsing storage, the disk and system-managed storage, the kinds of work
-- this Mac does, and how macOS lays it out. A row with `workflow` appears
-- only on a Mac that does that work (knowledge/Workflows.lua, #52), and a
-- section with no rows to show is left out. Section rows are native
-- source-list group headers and cannot be selected. `key` is the page's
-- ⌘-digit shortcut in the Go menu. A row is also its page's header: `icon`
-- in a `color` badge beside `title` (the row's `name` unless it differs), so
-- the sidebar, the Go menu and the page never disagree.
local function destinations()
	local list = {
		{id = "overview", name = "Overview", icon = "chart.pie.fill", color = "systemBlue", key = "1"},
		{id = "cleanup", name = "Clean Up", icon = "sparkles", color = "systemIndigo", key = "2"},
		{section = true, title = "Free Up Space"},
		{id = "applications", name = "Applications", icon = "square.grid.3x3.fill", color = "systemBlue", key = "3"},
		{id = "files", name = "Large Files", icon = "doc.fill", color = "systemTeal", key = "4"},
		{id = "duplicates", name = "Duplicates", icon = "doc.on.doc.fill", color = "systemTeal"},
		{id = "simulators", name = "Simulators", icon = "iphone", color = "systemBlue", workflow = "developer"},
		{id = "worktrees", name = "Worktrees", icon = "arrow.triangle.branch", color = "systemPurple", workflow = "developer"},
		{id = "projects", name = "Projects", icon = "folder.fill.badge.gearshape", color = "systemOrange", workflow = "developer"},
		{section = true, title = "Explore"},
		{id = "map", name = "Storage Map", icon = "circle.circle.fill", color = "systemIndigo", key = "5"},
		{id = "folder", name = "Folder Map", icon = "folder.fill", color = "systemBlue"},
		{id = "largest", name = "Largest Locations", icon = "chart.bar.fill", color = "systemOrange", key = "6"},
		{id = "kinds", name = "File Types", icon = "square.grid.2x2.fill", color = "systemPink", key = "7"},
		{section = true, title = "System"},
		{id = "disks", name = "Disks & Volumes", icon = "internaldrive.fill", color = "systemGray"},
		{id = "updates", name = "Updates & Snapshots", icon = "arrow.triangle.2.circlepath", color = "systemGray"},
	}
	-- Pages that belong to one kind of work follow its own page.
	local companions = {developer = {
		{id = "xcode", name = "Xcode", icon = "hammer.circle.fill", color = "systemBlue", key = "9", workflow = "developer"},
	}}
	local section
	for _, workflow in ipairs(Workflows.list) do
		if workflow.section ~= section then
			section = workflow.section
			table.insert(list, {section = true, title = section})
		end
		table.insert(list, {id = workflow.id, name = workflow.sidebar or (workflow.id == "developer" and "Dev tools" or workflow.name), title = workflow.id == "developer" and "Developer tools" or workflow.name, icon = workflow.icon,
			color = workflow.color, key = workflow.key, workflow = workflow.id})
		for _, row in ipairs(companions[workflow.id] or {}) do table.insert(list, row) end
	end
	for _, row in ipairs({
		{section = true, title = "Learn"},
		{id = "guide", name = "Storage Guide", icon = "book.fill", color = "systemTeal"},
		{id = "filesystem", name = "macOS Folders", icon = "apple.logo", color = "systemGray"},
		{id = "help", name = "Diskmap Help", icon = "questionmark.circle.fill", color = "systemBlue"},
	}) do table.insert(list, row) end
	return list
end
Controller.destinations = destinations()

-- The destination `id`: what its page's header shows.
function Controller.page(id)
	for _, row in ipairs(Controller.destinations) do
		if row.id == id then return row end
	end
end

-- `show(id)` mounts the destination; the root controller owns page lifetime.
-- Back and forward follow destinations the way a browser follows pages.
function Controller.new(show)
	return setmetatable({show = show, history = {}, position = 0, badges = {}, watched = {}, workflows = {}}, Controller)
end

-- Watched locations lead the sidebar, as Favorites lead Finder's: they are
-- what the person chose to come back to. The section appears only once
-- something is watched. Each row's badge is its current size.
function Controller:list()
	local list = {}
	if #self.watched > 0 then
		table.insert(list, {section = true, title = "Watched"})
		for _, row in ipairs(self.watched) do
			table.insert(list, {id = row.id, name = row.name, icon = row.icon, color = row.color,
				badge = not row.calculating and row.size or nil})
		end
	end
	-- A section header is listed once one of its rows is.
	local header
	for _, row in ipairs(Controller.destinations) do
		if row.section then header = row
		elseif not row.workflow or self.workflows[row.workflow] then
			if header then table.insert(list, header); header = nil end
			table.insert(list, row)
		end
	end
	return list
end

-- Shows the pages of the kinds of work in `present` (a set of workflow ids)
-- and hides the others, such as Developer on a Mac without developer tools.
-- Returns whether the sidebar changed.
function Controller:setWorkflows(present)
	local changed = false
	for _, workflow in ipairs(Workflows.list) do
		local shown = present[workflow.id] == true
		if (self.workflows[workflow.id] == true) ~= shown then changed = true end
		self.workflows[workflow.id] = shown or nil
	end
	if changed then self:reload() end
	return changed
end

function Controller:rows()
	local rows = {}
	for _, row in ipairs(self:list()) do
		local copy = {}
		for key, value in pairs(row) do copy[key] = value end
		copy.badge = row.badge or row.id and self.badges[row.id] or nil
		table.insert(rows, copy)
	end
	return rows
end

function Controller:render()
	local view, refs = xml.renderFile("apps/diskmap/views/Sidebar.etlua", {actions = {
		navigate = function(_, _, row) if row and row.id then self.show(row.id) end end,
	}}, ns)
	self.refs = refs
	refs.sidebar:replaceRows(self:rows())
	return view
end

function Controller:index(id)
	for index, row in ipairs(self:list()) do
		if row.id == id then return index - 1 end
	end
end

-- Keeps the sidebar selection in step with navigation that starts elsewhere,
-- such as "Show All" on the overview, and records the visit.
function Controller:select(id, fromHistory)
	self.current = id
	if not fromHistory and self.history[self.position] ~= id then
		for index = #self.history, self.position + 1, -1 do table.remove(self.history, index) end
		table.insert(self.history, id)
		self.position = #self.history
	end
	local index = self:index(id)
	if self.refs and index and self.refs.sidebar.documentView.selectedRow ~= index then
		self.refs.sidebar:selectRow(index)
	end
end

function Controller:canGoBack() return self.position > 1 end
function Controller:canGoForward() return self.position < #self.history end

function Controller:back()
	if not self:canGoBack() then return false end
	self.position = self.position - 1
	self.show(self.history[self.position], true)
	return true
end

function Controller:forward()
	if not self:canGoForward() then return false end
	self.position = self.position + 1
	self.show(self.history[self.position], true)
	return true
end

-- Trailing sizes beside destinations (SwiftUI `.badge`). Rows are replaced
-- only when a badge changes; the selection stays where it is.
function Controller:setBadges(badges)
	local changed = false
	for _, row in ipairs(Controller.destinations) do
		if row.id and self.badges[row.id] ~= badges[row.id] then changed = true end
	end
	if not changed then return false end
	self.badges = badges
	self:reload()
	return true
end

-- Replaces the Watched section. Adding the section shifts every row below
-- it, so the selection follows the current destination, not its index.
-- A watch removed while its row is selected leaves nothing selected.
function Controller:setWatched(rows)
	rows = rows or {}
	local function signature(list)
		local parts = {}
		for _, row in ipairs(list) do table.insert(parts, row.id .. "\t" .. row.name .. "\t" .. tostring(not row.calculating and row.size or "")) end
		return table.concat(parts, "\n")
	end
	if signature(rows) == signature(self.watched) then return false end
	self.watched = rows
	self:reload()
	return true
end

function Controller:reload()
	if not self.refs then return end
	self.refs.sidebar:replaceRows(self:rows())
	local index = self.current and self:index(self.current)
	if index and self.refs.sidebar.documentView.selectedRow ~= index then self.refs.sidebar:selectRow(index) end
end

return Controller
