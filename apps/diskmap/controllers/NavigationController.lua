local ns = require("AppKit")
local xml = require("ui.xml")
local Manifest = require("data.manifest")
local Workflows = require("apps.diskmap.models.Workflows")
local Controller = {}; Controller.__index = Controller

-- Sidebar destinations come from the app manifest (apps/diskmap/app.xml): the
-- pages that lead the sidebar without a header (Overview, Clean Up), then the
-- pages that each end in a cleanup decision, the tools for browsing storage,
-- the disk and system-managed storage, the kinds of work this Mac does, and
-- how macOS lays it out. A row with `workflow` appears only on a Mac that does
-- that work (knowledge/Workflows.lua, #52), and a section with no rows to show
-- is left out. Section rows are native source-list group headers and cannot be
-- selected. `key` is the page's ⌘-digit shortcut in the Go menu. A row is also
-- its page's header: `icon` in a `color` badge beside `title` (the row's `name`
-- unless it differs), so the sidebar, the Go menu and the page never disagree.
local function destinations()
	local list = {}
	for _, section in ipairs(Manifest.load("apps/diskmap/app.xml").sections) do
		if section.title then table.insert(list, {section = true, title = section.title}) end
		for _, page in ipairs(section.pages) do
			local sidebar = page.attrs.sidebar
			table.insert(list, {id = page.id, name = sidebar or page.title, title = sidebar and page.title or nil,
				icon = page.icon, color = page.color, key = page.key, workflow = page.attrs.workflow})
		end
	end
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
-- Back and forward follow locations the way a browser follows URLs
-- (lua/data/location.lua): `/folder//Users/me` and `/folder//Users/me/Music`
-- are two visits, and `go(location)` shows one again.
function Controller.new(show, go)
	return setmetatable({show = show, go = go, history = {}, position = 0, badges = {}, workflows = {}}, Controller)
end

function Controller:list()
	local list = {}
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
	for _, workflow in ipairs(Workflows:all()) do
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
	local view, refs = xml.renderFile("apps/diskmap/views/layouts/Sidebar.etlua", {actions = {
		-- The selected row is the page being shown: selecting it again, or the
		-- list showing where navigation went, asks for nothing.
		navigate = function(_, _, row) if row and row.id and row.id ~= self.current then self.show(row.id) end end,
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

-- Records where the window is. A new location is a visit, and drops the
-- visits Forward would have returned to, as in a browser; a location reached
-- by Back or Forward (`restoring`) takes its entry's place.
function Controller:visit(location, restoring)
	if self.history[self.position] == location then return end
	if restoring and self.position > 0 then self.history[self.position] = location; return end
	for index = #self.history, self.position + 1, -1 do table.remove(self.history, index) end
	table.insert(self.history, location)
	self.position = #self.history
end

-- The sidebar shows the current page as its selected row, wherever the
-- navigation started (a row, "Show All" on the overview, Back).
function Controller:select(id)
	self.current = id
	-- A page without a row (Search) leaves no row selected.
	local index = self:index(id)
	if self.refs and self.refs.sidebar.documentView.selectedRow ~= (index or -1) then self.refs.sidebar:selectRow(index) end
end

function Controller:canGoBack() return self.position > 1 end
function Controller:canGoForward() return self.position < #self.history end

function Controller:back()
	if not self:canGoBack() then return false end
	self.position = self.position - 1
	self.go(self.history[self.position], true)
	return true
end

function Controller:forward()
	if not self:canGoForward() then return false end
	self.position = self.position + 1
	self.go(self.history[self.position], true)
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

function Controller:reload()
	if not self.refs then return end
	-- Replacing rows drops the native selection; the current page restores it.
	self.refs.sidebar:replaceRows(self:rows())
	local index = self.current and self:index(self.current)
	if self.refs.sidebar.documentView.selectedRow ~= (index or -1) then self.refs.sidebar:selectRow(index) end
end

return Controller
