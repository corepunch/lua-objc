local ns = require("AppKit")
local xml = require("ui.xml")
local Controller = {}; Controller.__index = Controller

-- Sidebar destinations in the order they matter: what uses storage, the
-- developer tools behind it, then how macOS lays it out. Section rows are
-- native source-list group headers and cannot be selected.
Controller.destinations = {
	{section = true, title = "Storage"},
	{id = "overview", name = "Overview", icon = "chart.pie.fill"},
	{id = "largest", name = "Largest Items", icon = "chart.bar.fill"},
	{section = true, title = "Tools"},
	{id = "developer", name = "Developer", icon = "hammer.fill"},
	{section = true, title = "Learn"},
	{id = "guide", name = "Storage Guide", icon = "book.fill"},
}

-- `show(id)` mounts the destination; the root controller owns page lifetime.
function Controller.new(show)
	return setmetatable({show = show}, Controller)
end

function Controller:render()
	local view, refs = xml.renderFile("apps/diskmap/views/Sidebar.etlua", {actions = {
		navigate = function(_, _, row) if row and row.id then self.show(row.id) end end,
	}}, ns)
	self.refs = refs
	refs.sidebar:replaceRows(Controller.destinations)
	return view
end

function Controller:index(id)
	for index, row in ipairs(Controller.destinations) do
		if row.id == id then return index - 1 end
	end
end

-- Keeps the sidebar selection in step with navigation that starts elsewhere,
-- such as "Show All" on the overview.
function Controller:select(id)
	local index = self:index(id)
	if self.refs and index and self.refs.sidebar.documentView.selectedRow ~= index then
		self.refs.sidebar:selectRow(index)
	end
end

return Controller
