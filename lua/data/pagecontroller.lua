-- The generic page controller: a page is a request. Showing it asks the
-- page (built from its route, lua/data/routes.lua) for `data(state)` and
-- renders the route's view with it; an action in the view is a method of the
-- page, run and followed by the same request again, like a form post and the
-- page it shows next. Nothing is bound and nothing notifies: the view is plain
-- etlua over plain data, drawn by a retained template (`ui/template.lua`),
-- which reconciles to the new description and costs nothing when the data
-- did not change.
--
--   routes.lua           files = {view = "pages/Files", data = function(self, state) ... end,
--                                 markFiles = function(self) ... end}
--   views/pages/Files.etlua   <%= summary %>, loops, partials, action="markFiles"
--
-- Template data is `data` plus `page` (the app.xml entry) and `actions`.
-- Rows go to native tables, which reuse their cells: `data.lists = {id = rows}`
-- is set on the `<List id>` of that name, not copied into the template, and
-- `loading = {id = true}` shows that list's own native spinner. `texts`,
-- `hidden` and `disabled` set a node's text, visibility and enabled state by
-- id. A page that must touch live views after a draw (a chart that follows a
-- running scan, a native selection) defines `rendered(refs)`. Actions the
-- view cannot name in advance (a button per row) are `handlers = {name =
-- function}` in the data. A method that only reads (a row's menu, a reveal)
-- lists itself in `queries = {name = true}` and the page is not drawn again
-- after it. A page with work to start when it appears (a service to ask)
-- defines `activate()`, and `deactivate()` for work to cancel when it goes;
-- work that finishes later says so by calling the app's `refresh()`. An
-- action that refuses (`Routes.fail`) draws the page again with
-- `errors = {message}` in its data; `before` runs before every request.
local Template = require("ui.template")
local Model = require("data.model")
local Routes = require("data.routes")

local PageController = {}
PageController.__index = PageController

-- context: { page = manifest entry, request = the page built from its route
-- (or a function that builds it when the page is first mounted),
-- ns, viewsDir, resources, store }. `store` is bound before every request
-- and action (lua/data/model.lua), so each window of an app reads its own.
function PageController.new(context)
	return setmetatable({ context = context, page = context.page, request = context.request }, PageController)
end

function PageController:mount(host, state)
	local context = self.context
	-- A request given as a function is the page built when first shown.
	if type(self.request) == "function" then self.request = self.request() end
	self.template = Template.new(host, context.viewsDir .. self.request.view .. ".etlua", context.ns)
	self.actions = setmetatable({}, { __index = function(_, name)
		local method = self.request[name] or self.handlers and self.handlers[name]
		if type(method) ~= "function" then return nil end
		return function(...)
			-- What drawing itself makes fire (a table reloading its selection)
			-- is not the person acting.
			if self.drawing then return end
			if context.store then Model.bind(context.store) end
			local request = self.request
			-- A bug keeps its traceback; a refusal stays the value it was raised as.
			local results = table.pack(xpcall(function(...)
				if request.before then request:before() end
				return method(request, ...)
			end, function(err) return Routes.refusal(err) and err or debug.traceback(err, 2) end, ...))
			if not results[1] then
				-- A refusal is drawn on the page; anything else is a bug.
				if not Routes.refusal(results[2]) then error(results[2], 0) end
				self.errors = { results[2].message }
				if self.template then self:update(self.state) end
				return nil, results[2].message
			end
			-- A menu the action returns runs its items later, when the person
			-- picks one: each runs with this page's store bound again.
			local menu = results[2]
			if context.store and type(menu) == "table" then
				for _, item in ipairs(menu) do
					if type(item) == "table" and type(item.action) == "function" then item.action = Model.bound(context.store, item.action) end
				end
			end
			-- The action may have left the page (a row that opens another).
			if self.template and not (request.queries and request.queries[name]) then self:update(self.state) end
			return table.unpack(results, 2, results.n)
		end
	end })
	self:update(state)
	if self.request.activate then self.request:activate() end
	return self.refs
end

-- Asks the page again and draws the answer.
function PageController:update(state)
	if not self.template then return end
	self.state = state
	local request = self.request
	if self.context.store then Model.bind(self.context.store) end
	if request.before then request:before() end
	local data = request:data(state or {})
	-- A refusal shows on the one draw that follows it.
	data.errors, self.errors = self.errors, nil
	-- The page entry without its section, which points back at the page.
	local page = self.page
	data.page = { id = page.id, title = page.title, icon = page.icon, color = page.color, key = page.key, attrs = page.attrs }
	data.actions, data.resources = self.actions, self.context.resources
	data.overrides = { texts = data.texts, hidden = data.hidden, disabled = data.disabled }
	local lists, loading = data.lists, data.loading
	data.lists, data.loading = nil, nil
	-- Actions named by the data itself (one button per row), not by the view.
	self.handlers, data.handlers = data.handlers, nil
	self.drawing = true
	local _, refs = self.template:update(data)
	self.refs = refs
	for id, rows in pairs(lists or {}) do
		refs[id]:replaceRows(rows)
		if loading and loading[id] then refs[id]:showLoading() else refs[id]:hideLoading() end
	end
	if request.rendered then request:rendered(refs) end
	self.drawing = false
end

-- A mark changed what the page shows.
function PageController:marksChanged() self:update(self.state) end

function PageController:dispose()
	if self.context.store then Model.bind(self.context.store) end
	if self.template and self.request.deactivate then self.request:deactivate() end
	if self.template then self.template:dispose() end
	self.template, self.refs = nil, nil
end

return PageController
