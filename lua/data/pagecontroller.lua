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
-- is set on the `<List id>` of that name, not copied into the template. A
-- model method that only reads (a row's menu, a reveal) lists itself in
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
		local method = self.model[name]
		if type(method) ~= "function" then return nil end
		return function(...)
			local results = table.pack(method(self.model, ...))
			local queries = self.model.queries
			if not (queries and queries[name]) then self:update(self.state) end
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
	local lists = data.lists
	data.lists = nil
	local _, refs = self.template:update(data)
	self.refs = refs
	for id, rows in pairs(lists or {}) do refs[id]:replaceRows(rows) end
end

function PageController:dispose()
	if self.model and self.model.deactivate then self.model:deactivate() end
	if self.template then self.template:dispose() end
	self.template, self.refs, self.model = nil, nil, nil
end

return PageController
