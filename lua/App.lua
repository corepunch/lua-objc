local bridge = require("bridge")

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
	local self = setmetatable({
		name = props.name or "app",
		spec = props,
		plugins = props.plugins,
		currentWindow = nil,
		storageRoot = storageRoot(props.storageRoot),
	}, App)
	if props.recent then
		self.recent = props.recent
	elseif props.recentKey then
		self.recent = App.recentStore(props.recentKey, {
			storageRoot = self.storageRoot,
			limit = props.recentLimit or 12,
		})
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
			bridge._perform(self.currentWindow, "close")
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
