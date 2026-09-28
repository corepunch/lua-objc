--[[
  Plugins — host-defined extension points with isolated Lua plugins.

  The shape follows audio and editor plugin standards:

  - An *extension point* (Eclipse) is declared by the host: a name, an API
    version, the manifest fields a plugin must provide, and the host API
    object plugins receive. CLAP's `clap_host` and VS Code's `vscode`
    namespace play that role there.
  - A *plugin* is a folder whose `init.lua` returns a manifest table
    (CLAP's descriptor, VS Code's package.json): declarative fields the host
    reads without running plugin code, plus an optional `create(host, ...)`
    factory run on first use (VS Code activation, CLAP `create_plugin`).
  - The manifest's `api` must equal the extension point's, as CLAP checks
    `clap_version_is_compatible` before instantiating.
  - Isolation: each `init.lua` runs in its own environment holding only pure
    standard-library functions — no `require`, `io`, `os`, `load`, `debug` or
    `package`. Everything else a plugin needs comes from the host API, which
    it receives read-only, so one plugin cannot reach into another, into the
    app, or change the services it shares.

  Plugins are listed explicitly (`point:load(prefix, {"a", "b"})`) rather
  than discovered by scanning a directory: the same code then loads from
  disk on macOS and from the packager on iOS, and the list fixes the order a
  picker shows them in.

      local styles = Plugins.extensionPoint({
          name = "style", api = 1, host = StyleKit,
          manifest = {title = "string", tempo = "table", create = "function"},
      })
      styles:load("apps.dnb.plugins.styles", {"dnb", "techno"})
      for _, style in ipairs(styles:list()) do print(style.id, style.title) end
      local composer = styles:create("techno", seed)
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
local function runIsolated(module, env)
	local loader, extra = findLoader(module)
	local name = debug.getupvalue(loader, 1)
	if name ~= "_ENV" then
		error("plugin " .. module .. " must be Lua source, not a native module", 0)
	end
	debug.setupvalue(loader, 1, env)
	return loader(module, extra)
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

--- Loads plugins `prefix.<name>` for each name, in order, and returns the
--- extension point. Plugins are folders: `prefix/<name>/init.lua`. Any
--- failure raises with the plugin's module name; a broken plugin is a
--- programming error, not something to skip silently.
function ExtensionPoint:load(prefix, names)
	assert(type(prefix) == "string" and type(names) == "table", "load requires a module prefix and names")
	for _, name in ipairs(names) do
		assert(type(name) == "string" and name:match("^[%w_%-]+$"), "bad plugin name: " .. tostring(name))
		local module = prefix .. "." .. name
		local where = self.name .. " plugin " .. module
		local ok, result = pcall(runIsolated, module, sandbox())
		if not ok then error(where .. ": " .. tostring(result), 0) end
		if type(result) ~= "table" then error(where .. " must return a manifest table", 0) end
		if result.api ~= self.api then
			error(string.format("%s targets api %s; this host provides api %d", where, tostring(result.api), self.api), 0)
		end
		local id = result.id or name
		if id ~= name then error(where .. " declares id " .. tostring(id) .. " but lives in folder " .. name, 0) end
		if self.byId[id] then error(self.name .. " plugin " .. id .. " is already loaded", 0) end
		local descriptor = {id = id, module = module, directory = prefix:gsub("%.", "/") .. "/" .. name}
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
	end
	return self
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

--- Runs the plugin's factory: `create(host, ...)`. Each call makes a new
--- instance, as CLAP's factory does; the host API object is built once per
--- plugin.
function ExtensionPoint:create(id, ...)
	local descriptor = self.byId[id]
	if not descriptor then error("unknown " .. self.name .. " plugin: " .. tostring(id), 2) end
	if type(descriptor.create) ~= "function" then
		error(self.name .. " plugin " .. id .. " has no create function", 2)
	end
	local host = self.hosts[id]
	if not host then
		host = hostFor(self, descriptor)
		self.hosts[id] = host
	end
	return descriptor.create(host, ...)
end

return Plugins
