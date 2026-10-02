-- The generic page controller. A page with a view, a model and a schema
-- needs no controller class: this one owns mount, dispose, staleness and
-- command dispatch. Behaviour that needs more is a class of the app, the
-- WPF code-behind: `controller="SheetController"` in the manifest names a
-- class whose `new(context)` receives this generic controller as
-- `context.generic` and mounts it (`context.generic:mount(host)`) beside
-- whatever it coordinates.
--
-- Rule against option creep: if a page needs a function to express
-- behaviour, write a controller. This one does not grow a configuration
-- language.
local xml = require("ui.xml")
local Binder = require("data.binder")

local PageController = {}
PageController.__index = PageController

-- context: { page, graph, schemas, ns, viewsDir, resources }
function PageController.new(context)
	return setmetatable({ context = context, page = context.page }, PageController)
end

function PageController:mount(host)
	local context = self.context
	local graph = context.graph
	local models = graph:build({ self.page.model })
	self.model = models[self.page.model]
	local class = graph:class(self.page.model)
	if not class.schema then error("model " .. class.id .. " has no schema; a bound page needs one", 0) end
	local schema = context.schemas(class.schema)
	self.binder = Binder.new({
		schema = schema, model = self.model, now = context.now,
		changed = function() graph:post(self.page.model) end,
	})
	-- The graph rebinds this page when its model goes stale; the binder does
	-- not also update itself.
	self.binder.propagates = true
	local path = context.viewsDir .. self.page.view .. ".etlua"
	local root, refs = xml.renderFile(path, { binder = self.binder, resources = context.resources }, context.ns)
	self.root, self.refs, self.host = root, refs, host
	context.ns._insertSubview(host, root, 1)
	self.unsubscribe = graph:subscribe(self.page.model, function() self.binder:update() end)
	self.binder:update()
	return refs
end

-- Rebinds every view; call after changing the model outside a command.
function PageController:update()
	if self.binder then self.binder:update() end
end

function PageController:dispose()
	if self.unsubscribe then self.unsubscribe(); self.unsubscribe = nil end
	if self.root then
		pcall(function() self.root:removeFromSuperview() end)
		self.root = nil
	end
	self.binder, self.refs = nil, nil
end

return PageController
