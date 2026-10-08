local Routes = require("data.routes")
local Model = require("data.model")
local Format = require("apps.diskmap.helpers.Format")
local Locations = require("apps.diskmap.models.Locations")
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
--   chart     function(self, presented) -> nodes, total: the marks
--             (helpers/ChartNodes.lua) of the section marked `chart`, drawn
--             as rings or rectangles when the page's view picker asks
--   activateNode  function(self, id): double-clicking a mark no list row
--             stands for (default: open it as a resource)
--   load      function(self): work to start when the page appears (a service
--             to ask); call `self.app.refresh()` when it finishes
--   unload    function(self): work to cancel when the page goes
--   present(self, state) -> {
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
--   and its actions, as methods like any route's; `self.filterIndex` is the
--   filter picker's segment, from 1, and `self.viewIndex` the view picker's.
--
-- A row's menu is its resource's menu, and opening a row goes where
-- its location sends it; a row that stands for another page
-- (`row.page`) opens that page.
local ListRoute = {view = "pages/Page", filterIndex = 1, viewIndex = 1}

ListRoute.viewStyles = Model.enum({"List", "Rings", "Rectangles"})
ListRoute.chartGuidance = "Point at an item to see its size. Double-click opens it."

-- Row menus, activation, links, pointing and drags only read or navigate.
ListRoute.queries = {rowMenu = true, open = true, reveal = true, chartHover = true, dragPath = true}

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

function ListRoute:select(_, _, row)
	self.selectedRow, self.selectedId = row, row and row.id
end

function ListRoute:reveal(_, _, row)
	if row then self.app.service.reveal(row.path) end
end

-- The segmented filter (Page.etlua's `filters`) picked a segment.
function ListRoute:filter(index) self.filterIndex = (index or 0) + 1 end

-- The view picker: the section's items as a list, rings or rectangles.
function ListRoute:pickView(index) self.viewIndex = (index or 0) + 1 end

-- The row any list of the page shows for `id`, if one does.
function ListRoute:rowFor(id)
	for _, rows in pairs(self.presented and self.presented.lists or {}) do
		local index = Selection.index(rows, id)
		if index then return rows[index + 1] end
	end
end

-- The hole and the caption name the pointed mark, as on the Storage Map;
-- pointing never draws the page again.
function ListRoute:chartHover(id)
	local refs, chart = self.refs, self.chartData
	if not refs or not chart then return end
	local node = id and chart.byId[id]
	if refs.chartCenterTitle then
		refs.chartCenterTitle.text = node and node.label or chart.center.title
		refs.chartCenterDetail.text = node and node.detail or chart.center.detail
	end
	if refs.chartCaption then refs.chartCaption.text = node and (node.label .. " · " .. node.detail) or chart.caption end
end

-- A click selects the item a mark stands for; a double-click opens it as
-- its row would.
function ListRoute:chartSelect(id, count)
	if not Selection.isResource(id) then return end
	self.selectedId = id
	if not count or count < 2 then return end
	local row = self:rowFor(id)
	if row then self:activateRow(row)
	elseif self.activateNode then self:activateNode(id)
	elseif Locations:find(id) then self.app.open(id) end
end

function ListRoute:dragPath(id)
	local row = self:rowFor(id) or Locations:find(id)
	return row and row.path
end

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
	-- Rings and rectangles are computed only while the picker shows them.
	local chart
	if self.chart and self.viewIndex > 1 and not presented.waiting and not presented.computing then
		local nodes, total = self:chart(presented)
		local byId = {}
		for _, node in ipairs(nodes) do byId[node.id] = node end
		chart = {style = self.viewIndex == 3 and "rectangles" or "rings", nodes = nodes, byId = byId,
			center = {title = Format.size(total), detail = "Measured"}, caption = #nodes > 0 and ListRoute.chartGuidance or "",
			label = (self.header and self.header.title or self.app.pages[self.id].title) .. ", " .. Format.size(total)}
	end
	self.chartData = chart
	-- The list a chart stands in for is not drawn, so it gets no rows.
	local lists = presented.lists
	if chart and lists then
		lists = {}
		for id, rows in pairs(presented.lists) do lists[id] = rows end
		for _, section in ipairs(layout.sections or {}) do
			if section.chart then lists[section.list.id] = nil end
		end
	end
	return {layout = layout, header = self.header, lists = lists, loading = presented.loading,
		chart = chart, viewIndex = self.viewIndex, viewStyles = self.viewStyles,
		filterIndex = self.filterIndex, waiting = presented.waiting, computing = presented.computing, texts = presented.texts,
		hidden = presented.hidden, disabled = presented.disabled, children = presented.children, childViews = self.children,
		handlers = handlers}
end

-- After a draw the native selection follows the selected row, so selecting
-- in one list clears the others.
function ListRoute:rendered(refs)
	self.refs = refs
	for id, rows in pairs(self.presented.lists or {}) do
		if refs[id] then Selection.show(refs[id], rows, self.selectedId) end
	end
end

return ListRoute
