-- The launcher for an app described by a manifest (lua/data/manifest.lua).
-- An app's `init.lua` returns the manifest path:
--
--   return "apps/diskmap/app.xml"
--
-- and the host (src/main.m) turns that into `App.launcher(path)`, the class
-- the launch contract already expects: `new()` and `createWindow()`. From the
-- manifest the framework builds the window, the sidebar, the Go menu and one
-- generic page controller per page, and it provides two launch options for
-- every app:
--
--   --page=<id>   starts on that page instead of the manifest's startup page
--   --isolated    shows that page alone: no sidebar, no menu, and only the
--                 models the page needs, built through the model graph
--
-- That is "playable from every scene": a page declares what it binds to, so
-- the framework builds exactly that.
local ns = require("ns")
local xml = require("ui.xml")
local Resources = require("ui.resources")
local Schema = require("data.schema")
local Model = require("data.model")
local Manifest = require("data.manifest")
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

-- Returns the launch class for the manifest at `path`. `options.services`
-- reaches every model's `new` (a mock service runs the real models);
-- `options.args` replaces the process arguments.
function App.launcher(path, defaults)
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
	self.manifest = Manifest.parse(xml.parse(read(path)))
	self.dir = dirname(path)
	-- Module path of the app: apps/diskmap -> apps.diskmap
	self.module = self.dir:gsub("/", ".")
	self.options = Manifest.options(options.args or rawget(_G, "arg"))
	local startup = self.options.page or self.manifest.startup
	if not self.manifest.pages[startup] then
		error("--page=" .. startup .. ": the manifest of " .. self.manifest.name .. " has no such page", 0)
	end
	self.startup = startup
	self.schemas = Schema.directory(self.dir .. "/schemas", read, xml.parse)
	local classes = {}
	for id, class in pairs(self.manifest.models) do
		classes[id] = function() return require(self.module .. "." .. class) end
	end
	self.graph = Model.graph({ classes = classes, services = options.services or {}, schemas = self.schemas })
	local resources = xml.source(self.dir .. "/resources.xml")
	self.resources = resources and Resources.fromNodes(xml.parse(resources)) or nil
	self.now = options.now
	return self
end

function Launcher:context(page)
	return { page = page, graph = self.graph, schemas = self.schemas, ns = ns, now = self.now,
		viewsDir = self.dir .. "/views/", resources = self.resources, app = self }
end

-- Shows page `id` in the content area, disposing the previous one.
function Launcher:show(id)
	local page = self.manifest.pages[id]
	if not page then error("no page " .. tostring(id), 0) end
	if self.page then self.page:dispose() end
	local context = self:context(page)
	if page.controller then
		local class = require(self.module .. ".controllers." .. page.controller)
		context.generic = PageController.new(context)
		self.page = class.new(context)
	else
		self.page = PageController.new(context)
	end
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
			table.insert(rows, { id = page.id, name = page.title, icon = page.icon, color = page.color })
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
function Launcher:actions()
	local actions = {}
	for _, page in ipairs(self.manifest.order) do
		actions["page_" .. page.id] = function() self:show(page.id) end
		actions["isPage_" .. page.id] = function() return true, self.current == page.id end
	end
	return actions
end

function Launcher:createWindow()
	local isolated = self.options.isolated == true
	local config, refs = xml.renderFile(SHELL, {
		app = self.manifest, isolated = isolated, actions = self:actions(),
	}, ns)
	self.content = refs.content
	if ns.platform == "AppKit" and not isolated then
		local view, sidebarRefs = xml.renderFile(SIDEBAR, { actions = {
			navigate = function(_, _, row) if row and row.id and row.id ~= self.current then self:show(row.id) end end,
		} }, ns)
		config.sidebar, self.sidebar = view, sidebarRefs.sidebar
		self.sidebar:replaceRows(self:rows())
	end
	self.window = ns.Window(config)
	self:show(self.startup)
	return self.window
end

return App
