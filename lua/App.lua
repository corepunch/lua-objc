local bridge = require("AppKitNative")

local App = {}
App.__index = App

local RecentStore = {}
RecentStore.__index = RecentStore

local function pathJoin(...)
	local parts = {...}
	local sep = package.config:sub(1, 1)
	return table.concat(parts, sep)
end

local function basename(path)
	if type(path) ~= "string" then return "" end
	return path:match("([^/\\]+)$") or path
end

local function dirname(path)
	if type(path) ~= "string" then return "." end
	return path:match("^(.*)[/\\][^/\\]+$") or "."
end

local function ensureDirectory(path)
	if not path or path == "" then return end
	os.execute("mkdir -p " .. string.format("%q", path))
end

local function jsonEscape(str)
	return (str
		:gsub("\\", "\\\\")
		:gsub("\"", "\\\"")
		:gsub("\b", "\\b")
		:gsub("\f", "\\f")
		:gsub("\n", "\\n")
		:gsub("\r", "\\r")
		:gsub("\t", "\\t"))
end

local function isArray(tableValue)
	if type(tableValue) ~= "table" then return false, 0 end
	local count = 0
	for key, value in pairs(tableValue) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			return false, 0
		end
		if key > count then
			count = key
		end
	end
	for i = 1, count do
		if tableValue[i] == nil then
			return false, 0
		end
	end
	return true, count
end

local function encodeJsonValue(value)
	local kind = type(value)
	if kind == "nil" then
		return "null"
	elseif kind == "boolean" then
		return value and "true" or "false"
	elseif kind == "number" then
		return string.format("%.17g", value)
	elseif kind == "string" then
		return "\"" .. jsonEscape(value) .. "\""
	elseif kind == "table" then
		local arrayLike, count = isArray(value)
		if arrayLike then
			local parts = {}
			for i = 1, count do
				parts[#parts + 1] = encodeJsonValue(value[i])
			end
			return "[" .. table.concat(parts, ",") .. "]"
		end

		local keys = {}
		for key, item in pairs(value) do
			if type(key) == "string" then
				keys[#keys + 1] = key
			end
		end
		table.sort(keys)
		local parts = {}
		for _, key in ipairs(keys) do
			parts[#parts + 1] = "\"" .. jsonEscape(key) .. "\":" .. encodeJsonValue(value[key])
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end

	error("unsupported JSON value: " .. kind)
end

local function storageRoot(customRoot)
	if customRoot and customRoot ~= "" then
		return customRoot
	end
	local home = os.getenv("HOME") or "."
	return pathJoin(home, "Library", "Application Support", "lua-objc")
end

local function loadJsonFile(path)
	local file = io.open(path, "r")
	if not file then
		return {}
	end
	local body = file:read("*a")
	file:close()
	if not body or body == "" then
		return {}
	end
	local value, err = bridge._jsonParse(body)
	if not value then
		io.stderr:write("recent store load error: " .. tostring(err) .. "\n")
		return {}
	end
	if type(value) ~= "table" then
		return {}
	end
	return value
end

local function recentTitle(path, fallback)
	local name = basename(path)
	if name ~= "" then
		return name
	end
	return fallback or path or ""
end

function RecentStore:save()
	ensureDirectory(dirname(self.path))
	local file = assert(io.open(self.path, "w"))
	file:write(encodeJsonValue(self.items))
	file:close()
end

function RecentStore:list()
	return self.items
end

function RecentStore:itemsOfKind(kind)
	local items = {}
	for _, item in ipairs(self.items) do
		if kind == nil or item.kind == kind then
			items[#items + 1] = item
		end
	end
	return items
end

function RecentStore:touch(entry)
	if type(entry) ~= "table" or type(entry.path) ~= "string" then
		error("recent entry requires a path")
	end

	local updated = {}
	updated[1] = entry
	for _, item in ipairs(self.items) do
		if not (item.kind == entry.kind and item.path == entry.path) then
			updated[#updated + 1] = item
		end
	end

	entry.openedAt = entry.openedAt or os.time()
	entry.title = entry.title or recentTitle(entry.path)

	self.items = updated
	while #self.items > self.limit do
		table.remove(self.items)
	end
	self:save()
	return entry
end

function RecentStore:recordFolder(path, title)
	return self:touch({
		kind = "folder",
		path = path,
		title = title or recentTitle(path),
	})
end

function RecentStore:recordFile(path, title)
	return self:touch({
		kind = "file",
		path = path,
		title = title or recentTitle(path),
	})
end

function RecentStore:clear()
	self.items = {}
	if self.path then
		os.remove(self.path)
	end
end

--------------------------------------------------------------------------------
-- Plugin registry -- self-registering modules, like lite-xl's core.load_plugins.
-- Plugin files are discoverable Lua modules that call App.registerPlugin(spec)
-- at load time. App scans directories and requires them; the files themselves
-- are pure plugin definitions with no framework boilerplate.
--------------------------------------------------------------------------------

local _plugins = {}

local function moduleNameFromPath(path)
	local name = path:match("([^/\\]+)%.lua$")
	return name or path
end

local function parsePluginPriority(filepath)
	local f = io.open(filepath, "r")
	if not f then return 100 end
	local priority = 100
	for line in f:lines() do
		local pri = line:match("%-%-%s*priority%s*:%s*(%-?[%d%.]+)")
		if pri then
			priority = tonumber(pri) or 100
			break
		end
	end
	f:close()
	return priority
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

--- Shared plugin registry (module-level, not per-instance).
--- Plugins self-register via App.registerPlugin() when their file is required.

local function _isAppInstance(maybeApp)
	return type(maybeApp) == "table" and rawget(maybeApp, "spec") ~= nil
end

function App.registerPlugin(spec)
	if type(spec) ~= "table" then
		error("App.registerPlugin requires a spec table")
	end
	if type(spec.id) ~= "string" or spec.id == "" then
		error("App.registerPlugin requires spec.id")
	end
	if type(spec.create) ~= "function" then
		error("App.registerPlugin requires spec.create")
	end

	local existing = _plugins[spec.id]
	if existing and existing ~= spec then
		error("plugin already registered: " .. spec.id)
	end

	if spec.capabilities ~= nil and type(spec.capabilities) ~= "table" then
		error("App.registerPlugin requires spec.capabilities to be a table")
	end
	if spec.activation ~= nil and type(spec.activation) ~= "table" then
		error("App.registerPlugin requires spec.activation to be a table")
	end

	_plugins[spec.id] = spec
	return spec
end

-- Each public function handles both App.fn(args) and app:fn(args) via
-- _isAppInstance(self). When self looks like an App instance (table with
-- a spec field), it's an instance call; otherwise it's a module call.
-- This avoids the overwrite problem of defining both App.fn and App:fn
-- on the same table key.

local function _pluginList(kind)
	local plugins = {}
	for _, spec in pairs(_plugins) do
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

function App.getPlugin(self, id)
	if _isAppInstance(self) then return _plugins[id] end
	return _plugins[self]
end

function App.listPlugins(self, kind)
	if _isAppInstance(self) then return _pluginList(kind) end
	return _pluginList(self)
end

function App.resolvePluginByFile(self, path, kind)
	if _isAppInstance(self) then
		for _, spec in ipairs(_pluginList(kind)) do
			if matchesFilePattern(path, spec) then return spec end
		end
		return nil
	end
	for _, spec in ipairs(_pluginList(path)) do
		if matchesFilePattern(self, spec) then return spec end
	end
	return nil
end

function App.resolvePluginByCommand(self, name, kind)
	if _isAppInstance(self) then
		for _, spec in ipairs(_pluginList(kind)) do
			if matchesCommand(name, spec) then return spec end
		end
		return nil
	end
	for _, spec in ipairs(_pluginList(name)) do
		if matchesCommand(self, spec) then return spec end
	end
	return nil
end

function App.usePlugin(self, id, props)
	if _isAppInstance(self) then
		local spec = _plugins[id]
		if not spec then error("unknown plugin: " .. tostring(id)) end
		return spec.create(cloneProps(props))
	end
	local spec = _plugins[self]
	if not spec then error("unknown plugin: " .. tostring(self)) end
	return spec.create(cloneProps(id))
end

local function _loadNativePlugin(path, moduleName)
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

function App.loadNativePlugin(self, path, moduleName)
	if _isAppInstance(self) then
		if type(path) ~= "string" or path == "" then
			error("App.loadNativePlugin requires a dylib path")
		end
		return _loadNativePlugin(path, moduleName)
	end
	if type(self) ~= "string" or self == "" then
		error("App.loadNativePlugin requires a dylib path")
	end
	return _loadNativePlugin(self, path)
end

-- Called from App.new() only; no instance form needed.
function App.loadPluginsFromDirectory(dir)
	if type(dir) ~= "string" or dir == "" then
		return {}
	end
	local fh = io.popen("ls -1 " .. string.format("%q", dir) .. " 2>/dev/null")
	if not fh then return {} end
	local entries = {}
	for name in fh:lines() do
		if name:match("%.lua$") then
			local filepath = pathJoin(dir, name)
			entries[#entries + 1] = {
				name = name:gsub("%.lua$", ""),
				filepath = filepath,
				priority = parsePluginPriority(filepath),
			}
		end
	end
	fh:close()

	table.sort(entries, function(a, b)
		if a.priority ~= b.priority then
			return a.priority < b.priority
		end
		return a.name < b.name
	end)

	local loaded = {}
	for _, entry in ipairs(entries) do
		local ok, result = pcall(require, "examples.ide.plugins." .. entry.name)
		if ok then
			loaded[#loaded + 1] = entry.name
		end
	end
	return loaded
end

function App.basename(path)
	return basename(path)
end

function App.dirname(path)
	return dirname(path)
end

function App.describeRecent(item)
	if type(item) ~= "table" then
		return ""
	end
	local openedAt = tonumber(item.openedAt) or os.time()
	local elapsed = math.max(0, os.time() - openedAt)
	if elapsed < 60 then
		return "just now"
	elseif elapsed < 3600 then
		return string.format("%d min ago", math.floor(elapsed / 60))
	elseif elapsed < 86400 then
		return string.format("%d hr ago", math.floor(elapsed / 3600))
	else
		return string.format("%d days ago", math.floor(elapsed / 86400))
	end
end

function App.args()
	return rawget(_G, "arg") or {}
end

function App.new(props)
	props = props or {}
	local pluginDir = props.pluginDir or "examples/ide/plugins"
	local self = setmetatable({
		name = props.name or "app",
		spec = props,
		currentWindow = nil,
		storageRoot = storageRoot(props.storageRoot),
		pluginDir = pluginDir,
	}, App)
	if props.recent then
		self.recent = props.recent
	elseif props.recentKey then
		self.recent = App.recentStore(props.recentKey, {
			storageRoot = self.storageRoot,
			limit = props.recentLimit or 12,
		})
	end
	if props.plugins == false then
	else
		App.loadPluginsFromDirectory(pluginDir)
	end
	return self
end

function App.recentStore(key, opts)
	opts = opts or {}
	local root = storageRoot(opts.storageRoot)
	local path = pathJoin(root, "recent", key .. ".json")
	local store = setmetatable({
		key = key,
		limit = opts.limit or 12,
		path = path,
		items = loadJsonFile(path),
	}, RecentStore)
	return store
end

function App:recentFiles()
	if not self.recent then return {} end
	return self.recent:itemsOfKind("file")
end

function App:recentFolders()
	if not self.recent then return {} end
	return self.recent:itemsOfKind("folder")
end

function App:firstArgument()
	local args = App.args()
	return args[1]
end

function App:present(window)
	if self.currentWindow and self.currentWindow ~= window then
		pcall(function()
			self.currentWindow:close()
		end)
	end
	self.currentWindow = window
	return window
end

function App:pickFolder(prompt)
	return bridge._pickFolder(prompt or self.spec.openFolderPrompt or "Open Folder")
end

function App:pickFile(prompt)
	return bridge._pickFile(prompt or self.spec.openFilePrompt or "Open File")
end

function App:openFolder(path)
	local create = self.spec.openFolder
	if type(create) ~= "function" then
		error("App requires spec.openFolder")
	end
	local window = create(self, path)
	if self.recent then
		self.recent:recordFolder(path)
	end
	return self:present(window)
end

function App:openFile(path)
	local create = self.spec.openFile
	if type(create) ~= "function" then
		error("App requires spec.openFile")
	end
	local window = create(self, path)
	if self.recent then
		self.recent:recordFile(path)
	end
	return self:present(window)
end

function App:showWelcome()
	local create = self.spec.welcome
	if type(create) ~= "function" then
		error("App requires spec.welcome")
	end
	return self:present(create(self))
end

function App:run()
	local folder = self.spec.folder or self:firstArgument()
	if folder and folder ~= "" then
		return self:openFolder(folder)
	end
	return self:showWelcome()
end

return App
