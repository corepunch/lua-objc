-- Routes: Lapis' application over the manifest's pages.
--
-- A route is a table: the view it draws, `data(self, state)`, the request
-- that answers the table the view reads, and a method per action the view
-- names. An action runs, then the page is requested again, like a form post
-- and the page it shows next.
--
--   -- demo/storage/routes.lua
--   return {
--   	folders = {
--   		view = "Folders",
--   		data = function(self) return {lists = {folders = Folders:visible()}} end,
--   		rescan = function(self) Folders:rescan() end,
--   	},
--   }
--
-- A `<Page>` of app.xml names its route (`route="workflow"`; the page id
-- when omitted). The page's other attributes are `self.params`, so one route
-- serves every page that differs only by an argument:
--
--   <Page id="music" title="Music Production" route="workflow" workflow="music" />
--   <Page id="video" title="Video Production" route="workflow" workflow="video" />
--   -- in the route: Workflows:find(self.params.workflow)
--
-- `self` is the page built from its route, the first time the page is
-- shown, and kept while the app runs: what a person chose there (a filter,
-- a selection) is still there when they come back. `self.id` is the page
-- id, `self.params` its manifest attributes and `self.app` the services the
-- app hands its pages (show a page, open a resource, refresh).
--
-- Route fields the page controller reads besides `data` and actions:
--   init        runs once, when the page is built: the page's own tables
--               (a selection, a set of choices), never shared through the route
--   before      runs before `data` and before every action (Lapis'
--               before filter): look up what the params name
--   queries     {name = true}: actions that only read; no request follows
--   activate    runs when the page appears (start work: ask a service)
--   deactivate  runs when it goes (cancel that work)
--   rendered    runs after a draw with the view's refs
--
-- An action refuses with `Routes.fail(message)` or `Routes.assert(value,
-- message)` (Lapis' yield_error and assert_error): the action stops, and the
-- page is drawn again with `errors = {message}` in its data for the view to
-- show. Any other error is a bug and propagates.
--
--   rename = function(self, name) Routes.assert(Settings:current():update{name = name}) end
--
-- `self:flow(name)` wraps the page in the app's flow `flows/<name>.lua`
-- (lua/data/flow.lua): action code several pages share.
--
-- An app's routes are one module, `routes` beside app.xml (or the module
-- the manifest's `routes` attribute names), which may gather route files as
-- Lapis includes sub-applications:
--
--   return Routes.include("apps.diskmap.pages.Explore", "apps.diskmap.pages.System")
local Routes = {}

-- One table of routes from route tables and module names; a name defined
-- twice is an error.
function Routes.include(...)
	local routes, from = {}, {}
	for index = 1, select("#", ...) do
		local source = select(index, ...)
		local module = type(source) == "string" and require(source) or source
		if type(module) ~= "table" then error("Routes.include: " .. tostring(source) .. " is not a table of routes", 2) end
		for name, route in pairs(module) do
			if routes[name] then
				error("route " .. name .. " is defined by " .. from[name] .. " and " .. tostring(source), 2)
			end
			routes[name], from[name] = route, tostring(source)
		end
	end
	return routes
end

-- A route that inherits the methods of `base` and overrides what it defines.
function Routes.extend(base, route)
	return setmetatable(route or {}, {__index = base})
end

-- The route of manifest page `entry` in `routes`.
function Routes.find(routes, entry)
	local name = entry.route or entry.id
	local route = routes[name]
	if type(route) ~= "table" then error("page " .. entry.id .. " names the route " .. name .. ", which no route defines", 0) end
	if type(route.view) ~= "string" then error("route " .. name .. " needs a view", 0) end
	return route
end

local Refusal = {}
Refusal.__index = Refusal
Refusal.__tostring = function(refusal) return refusal.message end

function Routes.fail(message)
	error(setmetatable({message = tostring(message)}, Refusal), 0)
end

-- `value`, or a refusal with `message` (or the second value a model
-- returned with nil: `Routes.assert(row:update{...})`).
function Routes.assert(value, message, ...)
	if not value then Routes.fail(message or "refused") end
	return value, message, ...
end

-- Whether an error raised by an action is a refusal.
function Routes.refusal(err)
	return getmetatable(err) == Refusal
end

local Page = {}

function Page:flow(name)
	if not self.module then error("page " .. tostring(self.id) .. " belongs to no app module; it has no flows", 2) end
	return require(self.module .. ".flows." .. name)(self)
end

-- The page built from `route` for manifest page `entry`. `module` is the
-- app's module path, where `self:flow(name)` finds flows.
function Routes.page(route, entry, app, module)
	local page = setmetatable({id = entry.id, params = entry.attrs or {}, app = app, module = module}, {__index = function(_, key)
		local value = route[key]
		if value == nil then value = Page[key] end
		return value
	end})
	if page.init then page:init() end
	return page
end

return Routes
