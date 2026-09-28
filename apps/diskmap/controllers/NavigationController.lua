local ns = require("AppKit")
local xml = require("ui.xml")
local Controller = {}; Controller.__index = Controller

-- Sidebar destinations in the order they matter: what uses storage, what to
-- do about it, the developer tools behind it, the disk and system-managed
-- storage, then how macOS lays it out and how to use Diskmap. Section rows
-- are native source-list group headers and cannot be selected. `key` is the
-- page's ⌘-digit shortcut in the Go menu.
Controller.destinations = {
	{section = true, title = "Storage"},
	{id = "overview", name = "Overview", icon = "chart.pie.fill", key = "1"},
	{id = "map", name = "Map", icon = "circle.circle.fill", key = "2"},
	{id = "folder", name = "Folder Map", icon = "folder.fill"},
	{id = "largest", name = "Largest Items", icon = "chart.bar.fill", key = "3"},
	{id = "files", name = "Large Files", icon = "doc.fill", key = "4"},
	{id = "kinds", name = "File Types", icon = "square.grid.2x2.fill", key = "5"},
	{id = "duplicates", name = "Duplicates", icon = "doc.on.doc.fill"},
	{section = true, title = "Clean Up"},
	{id = "cleanup", name = "Recommendations", icon = "sparkles", key = "6"},
	{id = "applications", name = "Applications", icon = "square.grid.3x3.fill", key = "7"},
	{section = true, title = "Developer"},
	{id = "developer", name = "Developer", icon = "hammer.fill", key = "8"},
	{id = "xcode", name = "Xcode", icon = "hammer.circle.fill", key = "9"},
	{id = "projects", name = "Projects", icon = "folder.fill.badge.gearshape"},
	{id = "simulators", name = "Simulators", icon = "iphone"},
	{section = true, title = "System"},
	{id = "disks", name = "Disks & Volumes", icon = "internaldrive.fill"},
	{id = "updates", name = "Updates & Snapshots", icon = "arrow.triangle.2.circlepath"},
	{section = true, title = "Learn"},
	{id = "guide", name = "Storage Guide", icon = "book.fill"},
	{id = "help", name = "Diskmap Help", icon = "questionmark.circle.fill"},
}

-- `show(id)` mounts the destination; the root controller owns page lifetime.
-- Back and forward follow destinations the way a browser follows pages.
function Controller.new(show)
	return setmetatable({show = show, history = {}, position = 0, badges = {}, watched = {}}, Controller)
end

-- Watched locations lead the sidebar, as Favorites lead Finder's: they are
-- what the person chose to come back to. The section appears only once
-- something is watched. Each row's badge is its current size.
function Controller:list()
	if #self.watched == 0 then return Controller.destinations end
	local list = {{section = true, title = "Watched"}}
	for _, row in ipairs(self.watched) do
		table.insert(list, {id = row.id, name = row.name, icon = row.icon, color = row.color,
			badge = not row.calculating and row.size or nil})
	end
	for _, row in ipairs(Controller.destinations) do table.insert(list, row) end
	return list
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
