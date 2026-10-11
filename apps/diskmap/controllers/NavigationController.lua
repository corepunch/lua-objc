local ns = require("AppKit")
local xml = require("ui.xml")
local Manifest = require("data.manifest")
local Controller = {}; Controller.__index = Controller

-- Sidebar destinations come from the app manifest (apps/diskmap/app.xml):
-- Overview leads without a header, then the sources. Section
-- rows are native source-list group headers and cannot be selected. `key`
-- is the page's ⌘-digit shortcut in the Go menu.
local function destinations()
	local list = {}
	for _, section in ipairs(Manifest.load("apps/diskmap/app.xml").sections) do
		if section.title then table.insert(list, {section = true, title = section.title}) end
		for _, page in ipairs(section.pages) do
			local sidebar = page.attrs.sidebar
			table.insert(list, {id = page.id, name = sidebar or page.title, title = sidebar and page.title or nil,
				icon = page.icon, color = page.color, key = page.key})
		end
	end
	return list
end
Controller.destinations = destinations()

-- `show(id)` mounts the destination; the root controller owns page lifetime.
-- Back and forward follow locations the way a browser follows URLs
-- (lua/data/location.lua).
function Controller.new(show, go)
	return setmetatable({show = show, go = go, history = {}, position = 0, badges = {}}, Controller)
end

function Controller:list() return Controller.destinations end

function Controller:rows()
	local rows = {}
	for _, row in ipairs(self:list()) do
		local copy = {}
		for key, value in pairs(row) do copy[key] = value end
		copy.badge = row.id and self.badges[row.id] or nil
		table.insert(rows, copy)
	end
	return rows
end

function Controller:render()
	local view, refs = xml.renderFile("apps/diskmap/views/layouts/Sidebar.etlua", {actions = {
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

function Controller:select(id)
	self.current = id
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
	if self.refs then
		self.refs.sidebar:replaceRows(self:rows())
		local index = self.current and self:index(self.current)
		if self.refs.sidebar.documentView.selectedRow ~= (index or -1) then self.refs.sidebar:selectRow(index) end
	end
	return true
end

return Controller
