local Model = require("data.model")
local Selection = require("apps.diskmap.models.Selection")

-- The model of a page that ranks storage in lists (Largest Locations, Clean
-- Up, the kinds of work): the shared half of what a page table describes. A
-- page table (models/Largest.lua, Recommendations.lua, Workflow.lua) is
--
--   id        the page's id
--   view      the template in views/, Page.etlua (the list page) when omitted
--   layout    what Page.etlua lays out: tiles, sections of lists, a footnote
--             (the fields are listed in the template), or a function
--             `layout(presented)` when the structure depends on the data
--   children  {slot = template}: partials drawn into the slots Page.etlua names
--   details   function(model, row) -> data for the selection panel, if any
--   menu      function(page, row) -> a row's menu items, when it is not its
--             resource's menu
--   actions   {name = function(page, ...)}: what the view's actions do, beside the
--             row menu, activation, reveal, the filter picker and links every
--             list page has (`page.filterIndex` is the picker's segment, from 1)
--   queries   {name = true}: actions that only read, after which the page is
--             not drawn again
--   load      function(page): work to start when the page appears (a service to
--             ask); call `page.services.refresh()` when it finishes
--   unload    function(page): work to cancel when the page goes
--   present(model, state, page) -> {
--     lists     {id = rows}: rows for each list
--     texts     {id = text}
--     hidden    {id = boolean}
--     disabled  {id = boolean}
--     children  {slot = data} for each child
--     loading   {id = true}: the lists that show their spinner
--     waiting   {title, systemImage, description}: the empty state of a page
--               the running scan has not measured yet (no lists, no partial rows)
--     computing a status line, while a request of the page's own runs (a
--               service to ask): the page shows it with a spinner and no lists
--     links     {action = {open = id} | {page = id, filter = n} | {settings = section}
--               | {handler = name, args = {...}} (a handler of the app's actions)}
--   }
--
-- `data(state)` is the request: it runs `present` and hands the answer to the
-- view as it is. A row's menu is its resource's menu, and opening a row goes
-- where Destinations sends that resource; a row that stands for another page
-- (`row.page`) opens that page. A page that needs more (it reads a folder,
-- runs a search, keeps a filter) is a model of its own, not a page table.
local ListPage = {}

-- A class for one page table; `page(services, id)` returns the table.
function ListPage.class(page)
	local class = Model.define({})
	class.__index = function(self, key)
		local value = class[key]
		if value ~= nil then return value end
		-- A link named by `present` is an action that follows it; an action of
		-- the page table is a function of the page.
		local links = rawget(self, "links")
		local link = links and links[key]
		if link then return function() class.follow(self, link) end end
		local action = rawget(self, "page") and self.page.actions and self.page.actions[key]
		if action then return function(_, ...) return action(self, ...) end end
	end
	-- Row menu, activation and links only read or navigate.
	function class.new(_, services, id)
		local table_ = page(services, id)
		-- Row menu, activation and links only read or navigate.
		local queries = {rowMenu = true, open = true, openSelection = true, reveal = true}
		for name in pairs(table_.queries or {}) do queries[name] = true end
		return setmetatable({storage = services.model, services = services, actions = services.actions, id = id,
			page = table_, queries = queries, filterIndex = 1}, class)
	end
	for name, method in pairs(ListPage.methods) do class[name] = method end
	return class
end

ListPage.methods = {}

function ListPage.methods:menu(row)
	if self.page.menu then return self.page.menu(self, row) end
	if row.page then
		return {{title = "Open " .. (row.pageName or "Page"), systemImage = "arrow.right.circle",
			action = function() self.services.showFiltered(row.page, row.filter) end}}
	end
	return self.actions:resource(row.id)
end

function ListPage.methods:rowMenu(_, _, row) return self:menu(row) end

function ListPage.methods:activateRow(row)
	if not row then return end
	if row.page then self.services.showFiltered(row.page, row.filter) else self.services.open(row.id) end
end

function ListPage.methods:open(_, _, row) self:activateRow(row) end

-- The selection panel's button opens what the selected row stands for.
function ListPage.methods:openSelection() self:activateRow(self.selectedRow) end

function ListPage.methods:select(_, _, row)
	self.selectedRow, self.selectedId = row, row and row.id
end

function ListPage.methods:reveal(_, _, row)
	if row then self.services.service.reveal(row.path) end
end

-- The segmented filter (Page.etlua's `filters`) picked a segment.
function ListPage.methods:filter(index) self.filterIndex = (index or 0) + 1 end

function ListPage.methods:follow(link)
	if link.handler then self.actions.handlers[link.handler](table.unpack(link.args or {}))
	elseif link.open then self.services.open(link.open)
	elseif link.page then self.services.showFiltered(link.page, link.filter)
	elseif link.settings then self.services.service.openSettings(link.settings) end
end

-- The page's own work, started when it appears and cancelled when it goes.
function ListPage.methods:activate()
	if self.page.load then self.page.load(self) end
end

function ListPage.methods:deactivate()
	if self.page.unload then self.page.unload(self) end
end

function ListPage.methods:data(state)
	local page = self.page
	local presented = page.present(self.storage, state or {}, self)
	self.links = presented.links
	local layout = page.layout
	if type(layout) == "function" then layout = layout(presented) end
	self.presented = presented
	-- The row the selection token names, and the panel that explains it.
	self.selectedRow = nil
	if page.details then
		for _, rows in pairs(presented.lists or {}) do
			local index = Selection.index(rows, self.selectedId)
			if index then self.selectedRow = rows[index + 1] end
		end
	end
	if not self.selectedRow then self.selectedId = nil end
	local details
	if page.details and self.selectedRow then
		details = page.details(self.storage, self.selectedRow)
		details.actions = nil
	end
	return {layout = layout, header = self.header, lists = presented.lists, loading = presented.loading,
		filterIndex = self.filterIndex, waiting = presented.waiting, computing = presented.computing, texts = presented.texts,
		hidden = presented.hidden, disabled = presented.disabled, children = presented.children, childViews = page.children, details = details}
end

-- After a draw the native selection follows the selected row.
function ListPage.methods:rendered(refs)
	for id, rows in pairs(self.presented.lists or {}) do
		if self.page.details then Selection.show(refs[id], rows, self.selectedId) end
	end
end

return ListPage
