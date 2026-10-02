-- The generic page controller: a page is a request. Showing it asks the
-- page's model for `data(state)` and renders the page's view with it; an
-- action in the view is a method of the model, run and followed by the same
-- request again, like a form post and the page it shows next. Nothing is
-- bound and nothing notifies: the view is plain etlua over plain data, drawn
-- by a retained template (`ui/template.lua`), which reconciles to the new
-- description and costs nothing when the data did not change.
--
--   models/FilesPage.lua    data(state) -> the table the view reads, and the
--                           methods the view's actions name
--   views/Files.etlua       <%= summary %>, loops, partials, action="markFiles"
--
-- Template data is `data` plus `page` (the app.xml entry) and `actions`.
-- Rows go to native tables, which reuse their cells: `data.lists = {id = rows}`
-- is set on the `<List id>` of that name, not copied into the template, and
-- `loading = {id = true}` shows that list's own native spinner. `texts`,
-- `hidden` and `disabled` set a node's text, visibility and enabled state by
-- id. A model that must touch live views after a draw (a chart that follows a
-- running scan, a native selection) defines `rendered(refs)`. Actions the
-- view cannot name in advance (a button per row) are `handlers = {name =
-- function}` in the data. A model method that only reads (a row's menu, a reveal) lists itself in
-- `queries = {name = true}` and the page is not drawn again after it. A
-- model with work to start when its page appears (a service to ask) defines
-- `activate()`, and `deactivate()` for work to cancel when it goes; work that
-- finishes later says so by calling the app's `services.refresh()`.
--
-- Behaviour that needs more than an action is a class of the app, the WPF
-- code-behind: `controller="SheetController"` in the manifest names a class
-- whose `new(context)` receives this generic controller as `context.generic`.
-- Rule against option creep: if a page needs a function to express
-- behaviour, write a controller.
local Template = require("ui.template")

local PageController = {}
PageController.__index = PageController

-- context: { page, graph, ns, viewsDir, resources }
function PageController.new(context)
	return setmetatable({ context = context, page = context.page }, PageController)
end

function PageController:mount(host, state)
	local context = self.context
	self.model = context.graph:build({ self.page.model })[self.page.model]
	self.template = Template.new(host, context.viewsDir .. self.page.view .. ".etlua", context.ns)
	self.actions = setmetatable({}, { __index = function(_, name)
		local method = self.model[name] or self.handlers and self.handlers[name]
		if type(method) ~= "function" then return nil end
		return function(...)
			-- What drawing itself makes fire (a table reloading its selection)
			-- is not the person acting.
			if self.drawing then return end
			local model = self.model
			local results = table.pack(method(model, ...))
			-- The action may have left the page (a row that opens another).
			if self.model and not (model.queries and model.queries[name]) then self:update(self.state) end
			return table.unpack(results, 1, results.n)
		end
	end })
	self:update(state)
	if self.model.activate then self.model:activate() end
	return self.refs
end

-- Asks the model again and draws the answer.
function PageController:update(state)
	if not self.template then return end
	self.state = state
	local data = self.model:data(state or {})
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
	if self.model.rendered then self.model:rendered(refs) end
	self.drawing = false
end

-- A mark changed what the page shows.
function PageController:marksChanged() self:update(self.state) end

function PageController:dispose()
	if self.model and self.model.deactivate then self.model:deactivate() end
	if self.template then self.template:dispose() end
	self.template, self.refs, self.model = nil, nil, nil
end

return PageController
