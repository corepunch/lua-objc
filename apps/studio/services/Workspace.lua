local Workspace = {}

local PROJECT = "HabitTracker"
local BUNDLED = "apps/studio/Documents/HabitTracker/"
local PREFIX = "demo/playground/"

local function validRelative(path)
	if type(path) ~= "string" or path == "" or path:sub(1, 1) == "/"
		or path:find("\\", 1, true) or path:find("//", 1, true) then return false end
	for part in path:gmatch("[^/]+") do if part == "." or part == ".." then return false end end
	return true
end

local function manifestSource(metadata)
	local files = {}
	for _, path in ipairs(metadata.files or {}) do
		table.insert(files, "\t\t" .. string.format("%q", path) .. ",")
	end
	return "return {\n"
		.. "\tname = " .. string.format("%q", metadata.name) .. ",\n"
		.. "\tbundleId = " .. string.format("%q", metadata.bundleId) .. ",\n"
		.. "\tappIcon = " .. string.format("%q", metadata.appIcon) .. ",\n"
		.. "\tfiles = {\n" .. table.concat(files, "\n") .. "\n\t},\n}\n"
end

function Workspace.new(ns, readBundled)
	local function read(relative)
		if not validRelative(relative) then return nil end
		return ns._documentRead(PROJECT .. "/" .. relative)
			or readBundled(BUNDLED .. relative)
	end

	local source = read("project.lua")
	assert(source, "Habit Tracker project metadata is missing")
	local metadata = assert(load(source, "@HabitTracker/project.lua", "t", {}))()
	if type(metadata) ~= "table" or type(metadata.files) ~= "table" then
		local bundled = assert(load(assert(readBundled(BUNDLED .. "project.lua")), "@bundled/HabitTracker/project.lua", "t", {}))()
		metadata = type(metadata) == "table" and metadata or {}
		metadata.files = bundled.files
		metadata.name = metadata.name or bundled.name
		metadata.bundleId = metadata.bundleId or bundled.bundleId
		metadata.appIcon = metadata.appIcon or bundled.appIcon
	end
	local listed = {}
	for _, path in ipairs(metadata.files) do
		assert(validRelative(path) and (path:match("%.lua$") or path:match("%.etlua$")),
			"Invalid Habit Tracker project file: " .. tostring(path))
		listed[path] = true
	end

	local function loadFiles()
		local files = {}
		for path in pairs(listed) do
			local content = read(path)
			assert(content, "Habit Tracker file is missing: " .. path)
			files[PREFIX .. path] = content
		end
		return files
	end

	local function save(value)
		local names = {}
		for path, content in pairs(value.files) do
			local relative = path:sub(1, #PREFIX) == PREFIX and path:sub(#PREFIX + 1) or nil
			if not validRelative(relative) then return nil, "Invalid Habit Tracker file path: " .. tostring(path) end
			local ok, err = ns._documentWrite(PROJECT .. "/" .. relative, content)
			if not ok then return nil, err or ("Could not save " .. relative) end
			table.insert(names, relative)
		end
		table.sort(names)
		local nextMetadata = {
			name = metadata.name,
			bundleId = metadata.bundleId,
			appIcon = metadata.appIcon,
			files = names,
		}
		local ok, err = ns._documentWrite(PROJECT .. "/project.lua", manifestSource(nextMetadata))
		if not ok then return nil, err or "Could not save project file list" end
		local settings = ns._jsonEncode({ model = value.model })
		ok, err = ns._documentWrite(PROJECT .. "/settings.json", settings)
		if not ok then return nil, err or "Could not save project settings" end
		listed, metadata = {}, nextMetadata
		for _, path in ipairs(names) do listed[path] = true end
		return true
	end

	local settingsSource = ns._documentRead(PROJECT .. "/settings.json")
	local settings
	if settingsSource then
		local ok, result = pcall(ns.json_parse, settingsSource)
		if ok and type(result) == "table" then settings = result end
	end
	local seed = loadFiles()
	-- Materialize the bundled starter in Documents on first launch so the
	-- project tree, code viewer and Files app all inspect the same source.
	if not ns._documentRead(PROJECT .. "/project.lua") then
		local ok, err = save({ files = seed, model = settings and settings.model or "openrouter/free" })
		assert(ok, err)
	end
	local localStorage = {
		get = function(key)
			if type(key) ~= "string" or not key:match("^[%w_%-]+$") then return nil end
			return ns._documentRead(PROJECT .. "/data/" .. key .. ".json")
		end,
		set = function(key, value)
			if type(key) ~= "string" or not key:match("^[%w_%-]+$")
				or type(value) ~= "string" then return nil, "Invalid local storage value" end
			return ns._documentWrite(PROJECT .. "/data/" .. key .. ".json", value)
		end,
		encode = ns._jsonEncode,
		decode = ns.json_parse,
	}
	return {
		seed = seed,
		localStorage = localStorage,
		storage = {
			load = function()
				return { files = loadFiles(), model = settings and settings.model }
			end,
			save = function(value)
				local ok, err = save(value)
				if ok then settings = { model = value.model } end
				return ok, err
			end,
		},
	}
end

return Workspace
