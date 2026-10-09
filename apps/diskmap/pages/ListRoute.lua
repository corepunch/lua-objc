local Routes = require("data.routes")
local Selection = require("apps.diskmap.helpers.Selection")

-- The route of a page that ranks storage in lists (Largest Locations, Clean
-- Up, the kinds of work, Large Files…): views/pages/Page.etlua over what the
-- route presents. A list route extends this one (`ListRoute.extend{...}`)
-- with:
--
--   layout    what Page.etlua lays out: tiles, sections of lists, a footnote
--             (the fields are listed in the template), or a function
--             `layout(self, presented)` when the structure depends on the data
--   children  {slot = template}: partials drawn into the slots Page.etlua names
--   menu      function(self, row) -> a row's menu items, when it is not its
--             resource's menu
--   load      function(self): work to start when the page appears (a service
--             to ask); call `self.app.refresh()` when it finishes
--   unload    function(self): work to cancel when the page goes
--   present(self, state) -> {
--     lists     {id = rows}: rows for each list
--     subtitle  the second line of the window title (the page's summary);
--               `layout.subtitle` until the page presents one
--     title     the window title, when it is not the page's manifest title
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
--   and its actions, as methods like any route's; `self.filterIndex` is the
--   filter picker's segment, from 1.
--
-- A row's menu is its resource's menu, and opening a row goes where
-- its location sends it; a row that stands for another page
-- (`row.page`) opens that page.
local ListRoute = {view = "pages/Page", filterIndex = 1}

-- Row menus, activation and links only read or navigate.
ListRoute.queries = {rowMenu = true, open = true, reveal = true}

-- A list route: `route` over this one, its queries beside the shared ones.
function ListRoute.extend(route)
	route.queries = setmetatable(route.queries or {}, {__index = ListRoute.queries})
	return Routes.extend(ListRoute, route)
end

-- Every list reads the store; its rows' menus and marks are the Rows flow
-- (flows/Rows.lua), `self.rowActions`.
function ListRoute:init()
	self.rowActions = self:flow("Rows")
end

function ListRoute:rowMenu(_, _, row)
	if self.menu then return self:menu(row) end
	if row.page then
		return {{title = "Open " .. (row.pageName or "Page"), systemImage = "arrow.right.circle",
			action = function() self.app.show(row.page, {filter = row.filter}) end}}
	end
	return self.rowActions:resource(row.id)
end

function ListRoute:activateRow(row)
	if not row then return end
	if row.page then self.app.show(row.page, {filter = row.filter}) else self.app.open(row.id) end
end

function ListRoute:open(_, _, row) self:activateRow(row) end

function ListRoute:markRow(_, _, row) self.rowActions:toggleReview(row) end

function ListRoute:select(_, _, row)
	self.selectedRow, self.selectedId = row, row and row.id
end

function ListRoute:reveal(_, _, row)
	if row then self.app.service.reveal(row.path) end
end

-- The segmented filter (Page.etlua's `filters`) picked a segment.
function ListRoute:filter(index) self.filterIndex = (index or 0) + 1 end

function ListRoute:follow(link)
	if link.handler then
		local handlers = {review = self.app.openReview, refresh = self.app.rescan}
		handlers[link.handler](table.unpack(link.args or {}))
	elseif link.open then self.app.open(link.open)
	elseif link.page then self.app.show(link.page, {filter = link.filter})
	elseif link.settings then self.app.service.openSettings(link.settings) end
end

-- The page's own work, started when it appears and cancelled when it goes.
function ListRoute:activate()
	if self.load then self:load() end
end

function ListRoute:deactivate()
	if self.unload then self:unload() end
end

function ListRoute:data(state)
	local presented = self:present(state or {})
	local layout = self.layout
	if type(layout) == "function" then layout = layout(self, presented) end
	for _, rows in pairs(presented.lists or {}) do
		for _, row in ipairs(rows) do self.rowActions:annotateReview(row) end
	end
	self.presented = presented
	-- One row stays selected across the page's lists, named by its id.
	self.selectedRow = nil
	for _, rows in pairs(presented.lists or {}) do
		local index = Selection.index(rows, self.selectedId)
		if index then self.selectedRow = rows[index + 1] end
	end
	if not self.selectedRow then self.selectedId = nil end
	-- A link named by `present` is an action of the view that follows it.
	local handlers = {}
	for name, link in pairs(presented.links or {}) do handlers[name] = function() self:follow(link) end end
	return {layout = layout, title = presented.title, subtitle = presented.subtitle or layout.subtitle, lists = presented.lists, loading = presented.loading,
		filterIndex = self.filterIndex, waiting = presented.waiting, computing = presented.computing, texts = presented.texts,
		hidden = presented.hidden, disabled = presented.disabled, children = presented.children, childViews = self.children,
		handlers = handlers}
end

-- After a draw the native selection follows the selected row, so selecting
-- in one list clears the others.
function ListRoute:rendered(refs)
	for id, rows in pairs(self.presented.lists or {}) do Selection.show(refs[id], rows, self.selectedId) end
end

return ListRoute
