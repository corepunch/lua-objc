-- The launcher for an app described by a manifest (lua/data/manifest.lua).
-- An app's `init.lua` returns the launch class built from its manifest:
--
--   return require("data.app").launcher("demo/storage/app.xml")
--
-- the class the launch contract already expects: `new()` and `createWindow()`
-- (so every host, macOS and iOS, starts it unchanged). From the
-- manifest the framework builds the window, the sidebar, the Go menu and one
-- generic page controller per page, each drawing the page its route builds
-- (lua/data/routes.lua). `options.store` is bound as the store every model
-- reads (lua/data/model.lua). It provides two launch options for every app:
--
--   --page=<id>   starts on that page instead of the manifest's startup page
--   --isolated    shows that page alone: no sidebar and no menu
--
-- An app of one page is always shown alone, as with --isolated: there is
-- nothing to navigate to, so no sidebar, menu or navigation title.
--
-- That is "playable from every scene": a page asks its models for what it
-- shows, so it runs on its own.
local ns = require("ns")
local xml = require("ui.xml")
local Resources = require("ui.resources")
local Model = require("data.model")
local Manifest = require("data.manifest")
local Routes = require("data.routes")
local PageController = require("data.pagecontroller")

local SHELL = "lua/data/views/Shell.etlua"
local SIDEBAR = "lua/data/views/Sidebar.etlua"

local App = {}

local function dirname(path) return path:match("^(.*)/[^/]*$") or "." end

-- Reads a framework or app file; a missing one is an error naming it.
local function read(path)
	return xml.source(path) or error("cannot read " .. path, 0)
end

local Launcher = {}
Launcher.__index = Launcher

-- The module `name`, or nil when no searcher has it. Any other error, one
-- inside the module, is raised. `require` (not package.searchpath) so modules
-- the iOS host streams from the packager are found too.
function App.optional(name)
	local ok, module = pcall(require, name)
	if ok then return module end
	if tostring(module):find("module '" .. name .. "' not found", 1, true) then return nil end
	error(module, 0)
end

-- Returns the launch class for the manifest at `path`. `options.services`
-- is every page's `self.app` (a mock service runs the real routes;
-- `Services.lua` beside app.xml when omitted),
-- `options.store` the store the models read (or a function that
-- returns a fresh one; `Store.lua` beside app.xml when omitted) and `options.args` replaces the
-- process arguments. `defaults` are options for every instance.
function App.launcher(path, defaults)
	local manifest = Manifest.load(path)
	-- An app with a root controller coordinates its own window.
	if manifest.controller then return require(dirname(path):gsub("/", ".") .. "." .. manifest.controller) end
	local class = {}
	class.__index = class
	setmetatable(class, { __index = Launcher })
	function class.new(options)
		return Launcher.create(path, setmetatable(options or {}, { __index = defaults }))
	end
	return class
end

function Launcher.create(path, options)
	local self = setmetatable({}, Launcher)
	self.manifest = Manifest.load(path)
	self.dir = dirname(path)
	-- Module path of the app: apps/diskmap -> apps.diskmap
	self.module = self.dir:gsub("/", ".")
	self.options = Manifest.options(options.args or rawget(_G, "arg"))
	local startup = self.options.page or self.manifest.startup
	if not self.manifest.pages[startup] then
		error("--page=" .. startup .. ": the manifest of " .. self.manifest.name .. " has no such page", 0)
	end
	self.startup = startup
	self.routes = require(self.module .. "." .. self.manifest.routes)
	-- A page that names no route fails at launch, not when first shown.
	for _, entry in ipairs(self.manifest.order) do Routes.find(self.routes, entry) end
	-- The services every page sees as `self.app` are `Services.lua` beside
	-- app.xml, a function returning them, built fresh for each launch as
	-- the store is; an app that has none hands its pages an empty table.
	local services = options.services
	if services == nil then services = App.optional(self.module .. ".Services") end
	if type(services) == "function" then services = services() end
	self.services = services or {}
	self.pages = {}
	-- The store's seed is `Store.lua` beside app.xml, a function returning the
	-- tables the models read; each launch binds a fresh store from it.
	local store = options.store
	if store == nil then store = App.optional(self.module .. ".Store") end
	if type(store) == "function" then store = store() end
	if store then self.store = Model.bind(store) end
	local resources = xml.source(self.dir .. "/resources.xml")
	self.resources = resources and Resources.fromNodes(xml.parse(resources)) or nil
	return self
end

-- The page `id` built from its route, the first time it is asked for.
function Launcher:request(id)
	local entry = self.manifest.pages[id]
	if not entry then error("no page " .. tostring(id), 0) end
	if not self.pages[id] then self.pages[id] = Routes.page(Routes.find(self.routes, entry), entry, self.services, self.module) end
	return self.pages[id]
end

-- Shows page `id` in the content area, disposing the previous one.
function Launcher:show(id)
	local entry = self.manifest.pages[id]
	if not entry then error("no page " .. tostring(id), 0) end
	if self.page then self.page:dispose() end
	self.page = PageController.new({ page = entry, request = self:request(id), ns = ns,
		viewsDir = self.dir .. "/views/", resources = self.resources, store = self.store })
	self.refs = self.page:mount(self.content)
	self.current = id
	self:select(id)
	return self.refs
end

-- Sidebar rows: a header per titled section, then its pages.
function Launcher:rows()
	local rows = {}
	for _, section in ipairs(self.manifest.sections) do
		if section.title then table.insert(rows, { section = true, title = section.title }) end
		for _, page in ipairs(section.pages) do
			table.insert(rows, { id = page.id, name = page.attrs.sidebar or page.title, icon = page.icon, color = page.color })
		end
	end
	return rows
end

function Launcher:select(id)
	local sidebar = self.sidebar
	if not sidebar then return end
	for index, row in ipairs(self:rows()) do
		if row.id == id and sidebar.documentView.selectedRow ~= index - 1 then sidebar:selectRow(index - 1) end
	end
end

-- The Go menu's actions: `page_<id>` shows a page, `isPage_<id>` validates.
-- A toolbar item's `tool_<action>` runs that action of the page being shown
-- and `canTool_<action>` says whether it is enabled: the page has the action
-- and its `validate` method, if the item names one, agrees.
function Launcher:actions()
	local actions = {}
	for _, page in ipairs(self.manifest.order) do
		actions["page_" .. page.id] = function() self:show(page.id) end
		actions["isPage_" .. page.id] = function() return true, self.current == page.id end
	end
	for _, item in ipairs(self.manifest.toolbar) do
		local name, validate = item.action, item.validate
		actions["tool_" .. name] = function()
			local action = self.page and self.page.actions[name]
			if action then return action() end
		end
		actions["canTool_" .. name] = function()
			local request = self.page and self.page.request
			if type(request) ~= "table" or type(request[name]) ~= "function" then return false end
			if validate then return type(request[validate]) == "function" and request[validate](request) and true or false end
			return true
		end
	end
	return actions
end

function Launcher:createWindow()
	local isolated = self.options.isolated == true or #self.manifest.order == 1
	local config, refs = xml.renderFile(SHELL, {
		app = self.manifest, isolated = isolated, actions = self:actions(),
		platform = ns.platform, page = self.manifest.pages[self.startup],
	}, ns)
	self.content = refs.content
	if ns.platform == "AppKit" and not isolated then
		local view, sidebarRefs = xml.renderFile(SIDEBAR, { actions = {
			navigate = function(_, _, row) if row and row.id and row.id ~= self.current then self:show(row.id) end end,
		} }, ns)
		config.sidebar, self.sidebar = view, sidebarRefs.sidebar
		self.sidebar:replaceRows(self:rows())
	end
	-- The page is in the content before the window hosts it: UIKit sizes a
	-- hosted tree when it is installed, not views added to it afterwards.
	self:show(self.startup)
	self.window = ns.Window(config)
	return self.window
end

return App
