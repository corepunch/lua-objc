local Routes = require("data.routes")
local Manifest = require("data.manifest")
local Template = require("ui.template")
local xml = require("ui.xml")

-- Draws the app's pages from their routes (pages/*.lua, routes.lua): a page is
-- asked for its data and the view is rendered with it, and an action of the
-- view is a method of the route, followed by the same request again for
-- every page that is on screen. A page is mounted in a view the root
-- controller owns (a tab, a shelf, the tab accessory) or pushed on a
-- navigation stack; the host owns neither.
--
-- `services` is every page's `self.app`: what only the window can do (push a
-- page, open a story, select a tab).
local PageHost = {}
PageHost.__index = PageHost

local MODULE = "apps.adventure-arena"
local VIEWS = "apps/adventure-arena/views/"
-- Route fields that are not actions.
local RESERVED = { view = true, init = true, before = true, data = true, rendered = true, activate = true,
	deactivate = true, queries = true }

function PageHost.new(ns, services)
	return setmetatable({
		ns = ns, services = services, manifest = Manifest.load("apps/adventure-arena/app.xml"),
		routes = require(MODULE .. ".routes"), pages = {}, mounted = {},
	}, PageHost)
end

-- The page `id` built from its route, the first time it is asked for.
function PageHost:page(id)
	local entry = self.manifest.pages[id] or error("no page " .. tostring(id), 0)
	if not self.pages[id] then
		self.pages[id] = Routes.page(Routes.find(self.routes, entry), entry, self.services, MODULE)
	end
	return self.pages[id], entry
end

-- The actions of page `id`: its route's methods and the handlers its data
-- names. Any that is not a query asks every mounted page again.
function PageHost:actions(id, page, handlers)
	local route = Routes.find(self.routes, self.manifest.pages[id])
	local actions = {}
	local function add(name, method, query)
		actions[name] = function(...)
			local results = table.pack(method(page, ...))
			if not query then self:refresh() end
			return table.unpack(results, 1, results.n)
		end
	end
	for name, method in pairs(route) do
		if type(method) == "function" and not RESERVED[name] then add(name, method, route.queries and route.queries[name]) end
	end
	for name, method in pairs(handlers or {}) do
		add(name, function(_, ...) return method(...) end)
	end
	return actions
end

-- What page `id` shows for `state`: the data its route answers and the
-- actions of the view.
function PageHost:data(id, state)
	local page = self:page(id)
	if page.before then page:before(state or {}) end
	local data = page:data(state or {})
	local handlers = data.handlers
	data.handlers = nil
	data.actions = self:actions(id, page, handlers)
	return data, page
end

-- Renders page `id` and returns its root view and refs: a screen pushed on a
-- navigation stack, drawn once.
function PageHost:render(id, state)
	local data, page = self:data(id, state)
	local view, refs = xml.renderFile(VIEWS .. page.view .. ".etlua", data, self.ns)
	return view, refs
end

-- Mounts page `id` retained in `host`: later requests reconcile it.
function PageHost:mount(id, host, state)
	self:unmount(id)
	local page = self:page(id)
	local entry = { id = id, state = state, template = Template.new(host, VIEWS .. page.view .. ".etlua", self.ns) }
	self.mounted[id] = entry
	self:draw(entry)
	return entry.template
end

function PageHost:unmount(id)
	local entry = self.mounted[id]
	if entry and not entry.template:isDisposed() then entry.template:dispose() end
	self.mounted[id] = nil
end

function PageHost:draw(entry)
	local data, page = self:data(entry.id, entry.state)
	local _, refs = entry.template:update(data)
	if page.rendered then page:rendered(refs) end
	return refs
end

-- Asks every mounted page again: after an action, and when the reader's
-- saved stories change.
function PageHost:refresh()
	for id, entry in pairs(self.mounted) do
		if entry.template:isDisposed() then self.mounted[id] = nil else self:draw(entry) end
	end
end

-- The refs of mounted page `id`.
function PageHost:refs(id)
	local entry = self.mounted[id]
	return entry and entry.template.refs
end

return PageHost
