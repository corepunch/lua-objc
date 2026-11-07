local Projects = require("apps.studio.services.Projects")
local Workspace = require("apps.studio.services.Workspace")
local Catalog = {}
Catalog.__index = Catalog

function Catalog.new(ns, git, readBundled)
	return setmetatable({ns = ns, git = git, readBundled = readBundled}, Catalog)
end

function Catalog:list()
	-- Persist the bundled registry before creation can append to it.
	if not self.ns._documentRead("projects.json") then
		local source = assert(self.readBundled("apps/studio/Documents/projects.json"), "Project catalog is missing")
		local ok, err = self.ns._documentWrite("projects.json", source)
		assert(ok, err or "Could not save project catalog")
	end
	return Projects.list(function(path)
		local localSource = self.ns._documentRead(path)
		if path == "projects.json" then return localSource end
		return localSource or self.readBundled("apps/studio/Documents/" .. path)
	end, self.ns.json_parse, self.ns._jsonEncode, self.ns._documentWrite)
end

function Catalog:open(id)
	return Workspace.open(self.ns, self.readBundled, self.git, id)
end

function Catalog:delete(id)
	local names, found = {}, false
	for _, project in ipairs(self:list()) do
		if project.id == id then found = true else table.insert(names, project.id) end
	end
	if not found then return nil, "Choose a project from the project menu" end
	local previous = self.ns._documentRead("projects.json")
	local ok, err = self.ns._documentWrite("projects.json", self.ns._jsonEncode(names))
	if not ok then return nil, err end
	ok, err = self.ns._documentRemove(id)
	if not ok then
		local restored, detail = self.ns._documentWrite("projects.json", previous)
		return nil, tostring(err or "Could not delete project") .. (not restored and ("; restore failed: " .. tostring(detail)) or "")
	end
	return true
end

function Catalog:create(title, template)
	local reserved = {}
	for _, project in ipairs(self:list()) do reserved[project.id] = true end
	if type(title) ~= "string" then return nil, "Enter a project name" end
	title = title:match("^%s*(.-)%s*$")
	if title == "" or #title > 80 then return nil, "Use a project name between 1 and 80 characters" end
	if template ~= "StarterApp" and template ~= "HabitTracker" then return nil, "Choose a bundled template" end
	local base = title:gsub("[^%w_%-]", "")
	if base == "" then base = "Project" end
	local id, suffix = base, 1
	while reserved[id] or self.ns._documentExists(id .. "/project.lua") do
		suffix = suffix + 1
		id = base .. suffix
	end
	local root = "apps/studio/Documents/" .. template .. "/"
	local source = assert(self.readBundled(root .. "project.lua"), "Template metadata is missing")
	local metadata = assert(load(source, "@project.lua", "t", {}))()
	local files = {}
	for _, path in ipairs(metadata.files) do files[path] = assert(self.readBundled(root .. path), "Template source is missing") end
	metadata.name, metadata.bundleId = title, "org.luaobjc." .. id:lower()
	local ok, workspace = pcall(Workspace.create, self.ns, self.git, id, metadata, files)
	if not ok then return nil, tostring(workspace) end
	return { id = id, workspace = workspace }
end
return Catalog
