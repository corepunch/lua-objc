local Workspace = {}

local Versions = require("apps.studio.services.Versions")
local Projects = require("apps.studio.models.Projects")
local PREFIX = "demo/playground/"
local IGNORE = "/data/\n/settings.json\n.DS_Store\n"
local ICONS = "apps/studio/ProjectIcons/"

local function writeBundledIcon(ns, readBundled, destination, choice)
	local data = readBundled(ICONS .. choice.file)
	assert(data, "Project icon is missing from the app bundle: " .. choice.file)
	local ok, err = ns._documentWriteData(destination, data)
	assert(ok, err or ("Could not install project icon: " .. choice.file))
end

local function validRelative(path)
	if type(path) ~= "string" or path == "" or path:sub(1, 1) == "/"
		or path:find("\\", 1, true) or path:find("//", 1, true) then return false end
	for part in path:gmatch("[^/]+") do
		if part == "." or part == ".." or part:lower() == ".git" then return false end
	end
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
		.. "\tprojectIcon = " .. string.format("%q", metadata.projectIcon) .. ",\n"
		.. "\tfiles = {\n" .. table.concat(files, "\n") .. "\n\t},\n}\n"
end

local function initialize(ns, readBundled, git, project, definition)
	assert(type(project) == "string" and project:match("^[%w_%-]+$"), "Invalid project folder")
	local bundledRoot = "apps/studio/Documents/" .. project .. "/"
	local function read(relative)
		if not validRelative(relative) then return nil end
		return ns._documentRead(project .. "/" .. relative)
			or readBundled(bundledRoot .. relative)
	end

	local source = definition and manifestSource(definition.metadata) or read("project.lua")
	assert(source, "Project metadata is missing: " .. project)
	local metadata = assert(load(source, "@" .. project .. "/project.lua", "t", {}))()
	assert(type(metadata) == "table", "Invalid project metadata: " .. project)
	metadata.files = metadata.files or {}
	if not Projects.iconChoice(metadata.projectIcon) then metadata.projectIcon = Projects.defaultProjectIcon end
	local selectedIcon = assert(Projects.iconChoice(metadata.projectIcon))
	for _, choice in ipairs(Projects.iconChoices) do
		local path = project .. "/ProjectIcons/" .. choice.file
		if not ns._documentExists(path) then writeBundledIcon(ns, readBundled, path, choice) end
	end
	if not ns._documentExists(project .. "/AppIcon.png") then
		writeBundledIcon(ns, readBundled, project .. "/AppIcon.png", selectedIcon)
	end
	local listed = {}
	for _, path in ipairs(metadata.files) do
		assert(validRelative(path) and (path:match("%.lua$") or path:match("%.etlua$")),
			"Invalid project file: " .. tostring(path))
		listed[path] = true
	end

	local function loadFiles()
		local files = {}
		for path in pairs(listed) do
			local content = definition and definition.files[path] or read(path)
			assert(content, "Project file is missing: " .. path)
			files[PREFIX .. path] = content
		end
		return files
	end

	local function save(value)
		local names = {}
		local present = {}
		for path, content in pairs(value.files) do
			local relative = path:sub(1, #PREFIX) == PREFIX and path:sub(#PREFIX + 1) or nil
			if not validRelative(relative) then return nil, "Invalid project file path: " .. tostring(path) end
			local ok, err = ns._documentWrite(project .. "/" .. relative, content)
			if not ok then return nil, err or ("Could not save " .. relative) end
			table.insert(names, relative)
			present[relative] = true
		end
		-- Only remove files owned by the previous manifest. Other project assets
		-- and Git metadata share this directory and must survive source edits.
		for path in pairs(listed) do
			if not present[path] and ns._documentRead(project .. "/" .. path) then
				local ok, err = os.remove(ns._documentPath(project .. "/" .. path))
				if not ok then return nil, err or ("Could not remove " .. path) end
			end
		end
		table.sort(names)
		local nextMetadata = {
			name = metadata.name,
			bundleId = metadata.bundleId,
			appIcon = metadata.appIcon,
			projectIcon = metadata.projectIcon,
			files = names,
		}
		local ok, err = ns._documentWrite(project .. "/project.lua", manifestSource(nextMetadata))
		if not ok then return nil, err or "Could not save project file list" end
		local settings = ns._jsonEncode({ model = value.model })
		ok, err = ns._documentWrite(project .. "/settings.json", settings)
		if not ok then return nil, err or "Could not save project settings" end
		listed, metadata = {}, nextMetadata
		for _, path in ipairs(names) do listed[path] = true end
		return true
	end

	local settingsSource = ns._documentRead(project .. "/settings.json")
	local settings
	if settingsSource then
		local ok, result = pcall(ns.json_parse, settingsSource)
		if ok and type(result) == "table" then settings = result end
	end
	local seed = loadFiles()
	-- Materialize the bundled starter in Documents on first launch so the
	-- project tree, code viewer and Files app all inspect the same source.
	if not ns._documentRead(project .. "/project.lua") then
		local ok, err = save({ files = seed, model = settings and settings.model or "openrouter/free" })
		assert(ok, err)
	end
	definition = nil
	if not ns._documentRead(project .. "/.gitignore") then
		local ok, err = ns._documentWrite(project .. "/.gitignore", IGNORE)
		assert(ok, err)
	end
	-- A project is usable only after its own repository and initial snapshot
	-- exist. Reopening never commits edits made since the previous session.
	local versions, gitError = Versions.open(git, ns._documentPath(project))
	assert(versions, gitError)
	local history, historyError = versions:log(1)
	if not history then versions:close(); error(historyError) end
	if #history == 0 then
		local id, commitError = versions:record("Start project")
		if not id then versions:close(); error(commitError or "Project has no initial content") end
	end
	local localStorage = {
		get = function(key)
			if type(key) ~= "string" or not key:match("^[%w_%-]+$") then return nil end
			return ns._documentRead(project .. "/data/" .. key .. ".json")
		end,
		set = function(key, value)
			if type(key) ~= "string" or not key:match("^[%w_%-]+$")
				or type(value) ~= "string" then return nil, "Invalid local storage value" end
			return ns._documentWrite(project .. "/data/" .. key .. ".json", value)
		end,
		encode = ns._jsonEncode,
		decode = ns.json_parse,
	}
	return {
		root = ns._documentPath(project),
		versions = versions,
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
		selectIcon = function(iconID)
			local choice = Projects.iconChoice(iconID)
			if not choice then return nil, "Unknown project icon" end
			local data = readBundled(ICONS .. choice.file)
			if not data then return nil, "Project icon is missing from the app bundle: " .. choice.file end
			local ok, err = ns._documentWriteData(project .. "/AppIcon.png", data)
			if not ok then return nil, err or "Could not save project icon" end
			metadata.projectIcon, metadata.appIcon = choice.id, choice.symbol
			local saved, saveError = ns._documentWrite(project .. "/project.lua", manifestSource(metadata))
			if not saved then return nil, saveError or "Could not save project icon selection" end
			return true
		end,
	}
end

function Workspace.open(ns, readBundled, git, project)
	return initialize(ns, readBundled, git, project)
end

-- All creation paths (blank, template or generated) provide relative source
-- files here. Publish in the project catalog only after the initial commit.
function Workspace.create(ns, git, project, metadata, files)
	assert(type(project) == "string" and project:match("^[%w_%-]+$"), "Invalid project folder")
	assert(not ns._documentRead(project .. "/project.lua"), "Project already exists: " .. project)
	local definition = { metadata = {}, files = files }
	for key, value in pairs(metadata) do definition.metadata[key] = value end
	if not Projects.iconChoice(definition.metadata.projectIcon) then
		definition.metadata.projectIcon = Projects.defaultProjectIcon
	end
	definition.metadata.appIcon = definition.metadata.appIcon or Projects.defaultIcon
	definition.metadata.files = {}
	for path in pairs(files) do table.insert(definition.metadata.files, path) end
	table.sort(definition.metadata.files)
	local workspace = initialize(ns, function(path)
		return ns._readFile and ns._readFile(path) or nil
	end, git, project, definition)
	local source = ns._documentRead("projects.json")
	local names = source and ns.json_parse(source) or {}
	local found = false
	for _, name in ipairs(names) do if name == project then found = true end end
	if not found then table.insert(names, project) end
	local ok, err = ns._documentWrite("projects.json", ns._jsonEncode(names))
	if not ok then workspace.versions:close(); error(err or "Could not register project") end
	return workspace
end

return Workspace
