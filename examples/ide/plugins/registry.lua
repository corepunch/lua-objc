local PluginRegistry = {}

local registry = {}

local function moduleNameFromPath(path)
	local name = path:match("([^/\\]+)%.lua$")
	return name or path
end

local function assertSpec(spec)
	if type(spec) ~= "table" then
		error("IDE plugin register requires a spec table")
	end
	if type(spec.id) ~= "string" or spec.id == "" then
		error("IDE plugin register requires spec.id")
	end
	if type(spec.create) ~= "function" then
		error("IDE plugin register requires spec.create")
	end
end

local function normalizeExtensions(list)
	if type(list) ~= "table" then return nil end
	local result = {}
	for _, ext in ipairs(list) do
		if type(ext) == "string" and ext ~= "" then
			result[#result + 1] = ext:lower():gsub("^%.*", "")
		end
	end
	if #result == 0 then return nil end
	return result
end

local function matchesFilePattern(path, spec)
	if type(path) ~= "string" or path == "" then
		return false
	end
	local activation = spec.activation
	if type(activation) ~= "table" then
		return false
	end
	local exts = normalizeExtensions(activation.onFileExtension)
	if not exts then
		return false
	end
	local ext = path:match("%.([^.]+)$")
	if not ext then
		return false
	end
	ext = ext:lower()
	for _, candidate in ipairs(exts) do
		if ext == candidate then
			return true
		end
	end
	return false
end

local function matchesCommand(name, spec)
	if type(name) ~= "string" or name == "" then
		return false
	end
	local activation = spec.activation
	if type(activation) ~= "table" or type(activation.onCommand) ~= "table" then
		return false
	end
	for _, candidate in ipairs(activation.onCommand) do
		if candidate == name then
			return true
		end
	end
	return false
end

local function cloneProps(props)
	if type(props) ~= "table" then
		return {}
	end
	local copy = {}
	for k, v in pairs(props) do
		copy[k] = v
	end
	return copy
end

function PluginRegistry.register(spec)
	assertSpec(spec)

	local existing = registry[spec.id]
	if existing and existing ~= spec then
		error("plugin already registered: " .. spec.id)
	end

	if spec.capabilities ~= nil and type(spec.capabilities) ~= "table" then
		error("IDE plugin register requires spec.capabilities to be a table")
	end
	if spec.activation ~= nil and type(spec.activation) ~= "table" then
		error("IDE plugin register requires spec.activation to be a table")
	end

	registry[spec.id] = spec
	return spec
end

function PluginRegistry.get(id)
	return registry[id]
end

function PluginRegistry.list(kind)
	local plugins = {}
	for _, spec in pairs(registry) do
		if kind == nil or spec.kind == kind then
			plugins[#plugins + 1] = spec
		end
	end
	table.sort(plugins, function(a, b)
		local an = a.title or a.id
		local bn = b.title or b.id
		if an == bn then
			return a.id < b.id
		end
		return an < bn
	end)
	return plugins
end

function PluginRegistry.resolveByFile(path, kind)
	for _, spec in ipairs(PluginRegistry.list(kind)) do
		if matchesFilePattern(path, spec) then
			return spec
		end
	end
	return nil
end

function PluginRegistry.resolveByCommand(name, kind)
	for _, spec in ipairs(PluginRegistry.list(kind)) do
		if matchesCommand(name, spec) then
			return spec
		end
	end
	return nil
end

function PluginRegistry.use(id, props)
	local spec = registry[id]
	if not spec then
		error("unknown plugin: " .. tostring(id))
	end
	return spec.create(cloneProps(props))
end

function PluginRegistry.activate(specOrId, props)
	local spec = specOrId
	if type(specOrId) == "string" then
		spec = registry[specOrId]
	end
	if not spec then
		error("unknown plugin: " .. tostring(specOrId))
	end
	return spec.create(cloneProps(props))
end

function PluginRegistry.component(id)
	return function(props)
		return PluginRegistry.use(id, props)
	end
end

-- Lua plugins are ordinary modules; native extensions use Lua's standard
-- package.loadlib entry point. Keeping both paths here lets the IDE own
-- plugin discovery without adding a second plugin ABI to the framework.
function PluginRegistry.loadLua(path)
	if type(path) ~= "string" or path == "" then
		error("IDE plugin loadLua requires a path")
	end
	local chunk, err = loadfile(path)
	if not chunk then
		error("failed to load Lua plugin " .. path .. ": " .. tostring(err))
	end
	return chunk()
end

function PluginRegistry.loadNative(path, moduleName)
	if type(path) ~= "string" or path == "" then
		error("IDE plugin loadNative requires a dylib path")
	end
	moduleName = moduleName or moduleNameFromPath(path)
	local symbol = "luaopen_" .. moduleName:gsub("[^%w_]", "_")
	local loader, err = package.loadlib(path, symbol)
	if not loader then
		error("failed to load native plugin " .. path .. ": " .. tostring(err))
	end
	local module = loader(moduleName)
	if module == nil then
		module = package.loaded[moduleName]
	end
	return module
end

return PluginRegistry
