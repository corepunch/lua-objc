--[[
  Plugins — host-defined extension points with isolated Lua plugins.

  The shape follows audio and editor plugin standards:

  - An *extension point* (Eclipse) is declared by the host: a name, an API
    version, the manifest fields a plugin must provide, and the host API
    object plugins receive. CLAP's `clap_host` and VS Code's `vscode`
    namespace play that role there.
  - A *plugin* is one Lua file (`<prefix>/<id>.lua`, as the lite editor's
    `plugins/*.lua`) or a folder with assets (`<prefix>/<id>/init.lua`).
    Either returns a manifest table (CLAP's descriptor, VS Code's
    package.json): declarative fields the host reads without running
    plugin code, functions the host invokes by name, plus an optional
    `create(host, ...)` factory run on first use (VS Code activation,
    CLAP `create_plugin`).
  - The manifest's `api` must equal the extension point's, as CLAP checks
    `clap_version_is_compatible` before instantiating.
  - Isolation: each plugin runs in its own environment holding only pure
    standard-library functions — no `require`, `io`, `os`, `load`, `debug` or
    `package`. Everything else a plugin needs comes from the host API, which
    it receives read-only, so one plugin cannot reach into another, into the
    app, or change the services it shares. Where several plugins would
    repeat the same code (providers speaking one wire dialect), the host
    API carries that code once.

  Plugins are listed explicitly (`point:load(prefix, {"a", "b"})`) rather
  than discovered by scanning a directory: the same code then loads from
  disk on macOS and from the packager on iOS, and the list fixes the order a
  picker shows them in. A host that does let the user drop plugin files in
  (an iPad app's Documents folder) reads each file itself and hands the
  source to `point:loadSource(id, source, where)`; `Plugins.pluginName`
  turns a listing's file names into ids.

      local styles = Plugins.extensionPoint({
          name = "style", api = 1, host = StyleKit,
          manifest = {title = "string", tempo = "table", create = "function"},
      })
      styles:load("apps.dnb.plugins.styles", {"dnb", "techno"})
      for _, style in ipairs(styles:list()) do print(style.id, style.title) end
      local composer = styles:create("techno", seed)
      local reply = providers:invoke("openai", "reply", status, body)
]]

local Plugins = {}

-- Pure functions only: nothing that reaches files, processes, the loader or
-- other plugins' state. Library tables are copied per plugin, so a plugin
-- that reassigns `math.floor` changes only its own copy.
local SAFE_GLOBALS = {
	"assert", "error", "ipairs", "next", "pairs", "pcall", "print", "rawequal", "rawget", "rawlen",
	"rawset", "select", "setmetatable", "getmetatable", "tonumber", "tostring", "type", "xpcall",
}
local SAFE_LIBRARIES = {"math", "string", "table", "utf8"}

local function sandbox()
	local env = {}
	for _, name in ipairs(SAFE_GLOBALS) do env[name] = _G[name] end
	for _, name in ipairs(SAFE_LIBRARIES) do
		local copy = {}
		for key, value in pairs(_G[name]) do copy[key] = value end
		env[name] = copy
	end
	env._G = env
	env._VERSION = _VERSION
	return env
end

-- A read-only view of `target`: reads, `pairs`, `ipairs` and `#` pass
-- through, nested tables come back read-only too, and writes raise.
local readonlyViews = setmetatable({}, {__mode = "k"})
local readonlyTargets = setmetatable({}, {__mode = "k"})

function Plugins.readonly(target)
	if type(target) ~= "table" or readonlyTargets[target] then return target end
	local view = readonlyViews[target]
	if view then return view end
	view = setmetatable({}, {
		__index = function(_, key) return Plugins.readonly(target[key]) end,
		__newindex = function(_, key) error("plugin host API is read-only: " .. tostring(key), 2) end,
		__pairs = function()
			return function(_, key)
				local k, v = next(target, key)
				return k, Plugins.readonly(v)
			end, target, nil
		end,
		__len = function() return #target end,
		__metatable = false,
	})
	readonlyViews[target], readonlyTargets[view] = view, true
	return view
end

--- The plugin id a file name in a plugins folder stands for: `openai.lua`
--- is `openai`; folders, other files and names beginning with `.` or `_`
--- (notes, disabled plugins) are nil.
function Plugins.pluginName(filename)
	if type(filename) ~= "string" then return nil end
	local id = filename:match("^([%w][%w_%-]*)%.lua$")
	return id
end

-- The loader `require` would use, without registering the module: plugin
-- code never enters package.loaded, so it cannot be required by the app.
local function findLoader(module)
	local messages = {}
	for _, searcher in ipairs(package.searchers) do
		local loader, extra = searcher(module)
		if type(loader) == "function" then return loader, extra end
		if type(loader) == "string" then table.insert(messages, loader) end
	end
	error("plugin module " .. module .. " not found:" .. table.concat(messages), 0)
end

-- Runs a main chunk in `env`. A Lua main chunk's first and only upvalue is
-- its _ENV, so replacing it confines every global the chunk touches.
-- Returns the chunk's value and what the searcher found (the file path on
-- disk), which tells a single-file plugin from a folder.
local function runIsolated(module, env)
	local loader, extra = findLoader(module)
	local name = debug.getupvalue(loader, 1)
	if name ~= "_ENV" then
		error("plugin " .. module .. " must be Lua source, not a native module", 0)
	end
	debug.setupvalue(loader, 1, env)
	return loader(module, extra), extra
end

local function runSource(source, chunkName, env)
	local chunk, err = load(source, "@" .. chunkName, "t", env)
	if not chunk then error(err, 0) end
	return chunk()
end

local FIELD_TYPES = {string = true, number = true, table = true, ["function"] = true, boolean = true}

local function checkField(where, key, value, spec)
	local optional = spec:sub(-1) == "?"
	local kind = optional and spec:sub(1, -2) or spec
	assert(FIELD_TYPES[kind], "unknown manifest field type: " .. spec)
	if value == nil then
		if not optional then error(where .. " is missing required field " .. key, 0) end
	elseif type(value) ~= kind then
		error(where .. " field " .. key .. " must be a " .. kind .. ", not " .. type(value), 0)
	end
end

local ExtensionPoint = {}
ExtensionPoint.__index = ExtensionPoint

--- Declares an extension point.
--- `spec.name` names it in messages; `spec.api` is the version manifests
--- must declare; `spec.manifest` maps field names to types (`"string"`,
--- `"table?"` for optional); `spec.host` is the shared API every plugin
--- receives, read-only.
function Plugins.extensionPoint(spec)
	assert(type(spec) == "table", "extensionPoint requires a spec table")
	assert(type(spec.name) == "string" and spec.name ~= "", "extensionPoint requires a name")
	assert(math.type(spec.api) == "integer", "extensionPoint requires an integer api version")
	local manifest = {}
	for key, kind in pairs(spec.manifest or {}) do
		assert(key ~= "id" and key ~= "api", "id and api are reserved manifest fields")
		assert(type(kind) == "string" and FIELD_TYPES[kind:gsub("%?$", "")], "bad manifest type for " .. key)
		manifest[key] = kind
	end
	return setmetatable({
		name = spec.name, api = spec.api, manifest = manifest,
		host = spec.host or {}, plugins = {}, byId = {}, hosts = {},
	}, ExtensionPoint)
end

-- The host API as one plugin sees it: its own context first (id, folder and
-- resource paths, as VS Code's ExtensionContext), then the shared services.
local function hostFor(point, descriptor)
	local shared = Plugins.readonly(point.host)
	local context = {
		id = descriptor.id,
		directory = descriptor.directory,
		resource = descriptor.resource,
	}
	return setmetatable({}, {
		__index = function(_, key)
			local own = context[key]
			if own ~= nil then return own end
			return shared[key]
		end,
		__newindex = function(_, key) error("plugin host API is read-only: " .. tostring(key), 2) end,
		__metatable = false,
	})
end

-- Checks a manifest against the extension point and records it. `location`
-- is {directory, file?, source?}: where the plugin's assets live and, for a
-- single file, which file it is and where the host found it.
local function register(self, id, result, where, location)
	if type(result) ~= "table" then error(where .. " must return a manifest table", 0) end
	if result.api ~= self.api then
		error(string.format("%s targets api %s; this host provides api %d", where, tostring(result.api), self.api), 0)
	end
	if result.id ~= nil and result.id ~= id then
		error(where .. " declares id " .. tostring(result.id) .. " but is named " .. id, 0)
	end
	if self.byId[id] then error(self.name .. " plugin " .. id .. " is already loaded", 0) end
	local descriptor = {id = id, module = location.module, directory = location.directory,
		file = location.file, source = location.source}
	for key, kind in pairs(self.manifest) do
		checkField(where, key, result[key], kind)
		descriptor[key] = result[key]
	end
	-- Undeclared fields are the plugin's own data (tables it passes
	-- between its manifest and its factory); they are kept, not checked.
	for key, value in pairs(result) do
		if descriptor[key] == nil and key ~= "api" then descriptor[key] = value end
	end
	local directory = descriptor.directory
	descriptor.resource = function(file) return directory .. "/" .. file end
	table.insert(self.plugins, descriptor)
	self.byId[id] = descriptor
	return descriptor
end

--- Loads plugins `prefix.<name>` for each name, in order, and returns the
--- extension point. A plugin is one file, `prefix/<name>.lua`, or a folder,
--- `prefix/<name>/init.lua`, whose assets `host.resource(file)` names. Any
--- failure raises with the plugin's module name; a broken plugin is a
--- programming error, not something to skip silently.
function ExtensionPoint:load(prefix, names)
	assert(type(prefix) == "string" and type(names) == "table", "load requires a module prefix and names")
	local folder = prefix:gsub("%.", "/")
	for _, name in ipairs(names) do
		assert(type(name) == "string" and name:match("^[%w_%-]+$"), "bad plugin name: " .. tostring(name))
		local module = prefix .. "." .. name
		local where = self.name .. " plugin " .. module
		local ok, result, found = pcall(runIsolated, module, sandbox())
		if not ok then error(where .. ": " .. tostring(result), 0) end
		local location = {module = module, directory = folder .. "/" .. name, source = "bundled"}
		if type(found) == "string" and found:match("%.lua$") and not found:match("[/\\]init%.lua$") then
			location.directory, location.file = folder, found
		end
		register(self, name, result, where, location)
	end
	return self
end

--- Loads one plugin from its source text, for hosts that read plugin files
--- themselves (an iPad app's Documents folder, where the user drops them).
--- `where` names the file in messages; `directory` is where its assets
--- live, when it has any.
function ExtensionPoint:loadSource(id, source, where, directory)
	assert(type(id) == "string" and id:match("^[%w_%-]+$"), "bad plugin id: " .. tostring(id))
	assert(type(source) == "string", "loadSource requires the plugin's source")
	where = where or id
	local label = self.name .. " plugin " .. where
	local ok, result = pcall(runSource, source, where, sandbox())
	if not ok then error(label .. ": " .. tostring(result), 0) end
	return register(self, id, result, label, {directory = directory or "", file = where, source = "user"})
end

--- Manifests in load order.
function ExtensionPoint:list()
	return self.plugins
end

function ExtensionPoint:get(id)
	return self.byId[id]
end

function ExtensionPoint:index(id)
	for i, descriptor in ipairs(self.plugins) do
		if descriptor.id == id then return i end
	end
end

local function hostOf(self, id)
	local descriptor = self.byId[id]
	if not descriptor then error("unknown " .. self.name .. " plugin: " .. tostring(id), 3) end
	local host = self.hosts[id]
	if not host then
		host = hostFor(self, descriptor)
		self.hosts[id] = host
	end
	return descriptor, host
end

--- Runs the plugin's factory: `create(host, ...)`. Each call makes a new
--- instance, as CLAP's factory does; the host API object is built once per
--- plugin.
function ExtensionPoint:create(id, ...)
	return self:invoke(id, "create", ...)
end

--- Calls a function the manifest declares, `field(host, ...)`, with the
--- plugin's host API first. This is how a host drives a plugin that is a
--- set of functions rather than a factory (a provider's `request` and
--- `reply`).
function ExtensionPoint:invoke(id, field, ...)
	local descriptor, host = hostOf(self, id)
	if type(descriptor[field]) ~= "function" then
		error(self.name .. " plugin " .. id .. " has no " .. tostring(field) .. " function", 2)
	end
	return descriptor[field](host, ...)
end

return Plugins
