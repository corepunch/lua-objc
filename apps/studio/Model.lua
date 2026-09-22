local Model = {}
Model.__index = Model
local PREFIX = "apps/playground/"
local REQUIRED = { "init.lua", "Model.lua", "Controller.lua", "views/Window.etlua" }
local LIMITS = { fileBytes = 128 * 1024, totalBytes = 1024 * 1024, history = 20 }
local DEFAULT_MODEL = "openrouter/free"
local SAVED_PREFIX = "examples/playground/"

local function copy(files)
	local result = {}
	for path, source in pairs(files) do result[path] = source end
	return result
end

local function migrateSavedFiles(files)
	if type(files) ~= "table" then return files, false end
	local migrated, changed = {}, false
	for path, source in pairs(files) do
		local canonical = path
		if type(path) == "string" and path:sub(1, #SAVED_PREFIX) == SAVED_PREFIX then
			canonical = PREFIX .. path:sub(#SAVED_PREFIX + 1)
			changed = true
		end
		if type(source) == "string" then
			local current = source:gsub("examples%.playground", "apps.playground")
			current = current:gsub("examples/playground", "apps/playground")
			if current ~= source then
				source = current
				changed = true
			end
		end
		if migrated[canonical] ~= nil then
			return nil, false, "Saved project has conflicting paths after moving to apps/playground: " .. canonical
		end
		migrated[canonical] = source
	end
	return migrated, changed
end

function Model.validPath(path)
	if type(path) ~= "string" or path:sub(1, #PREFIX) ~= PREFIX then return false end
	if path:find("[^%w_./%-]") or path:find("//", 1, true) then return false end
	for part in path:gmatch("[^/]+") do
		if part == "." or part == ".." then return false end
	end
	return path:match("%.lua$") ~= nil or path:match("%.etlua$") ~= nil
end

function Model.new(storage, seed)
	local self = setmetatable({ storage = storage, files = copy(seed), history = {}, messages = {},
		model = DEFAULT_MODEL, revision = 0 }, Model)
	local saved = storage.load()
	if saved then
		local files, changed, migrationError = migrateSavedFiles(saved.files)
		if migrationError then error(migrationError) end
		local ok, err = self:validate(files)
		if not ok then error("Saved project is invalid: " .. err) end
		if changed then
			local canonical = { files = files, model = saved.model }
			local written, writeError = storage.save(canonical)
			if not written then error("Could not save migrated project paths: " .. tostring(writeError)) end
		end
		self.files = copy(files)
		if type(saved.model) == "string" then self.model = saved.model end
	end
	return self
end

function Model:validate(files)
	if type(files) ~= "table" then return nil, "Project must contain files" end
	local total = 0
	for path, source in pairs(files) do
		if not Model.validPath(path) then return nil, "Invalid project path: " .. tostring(path) end
		if type(source) ~= "string" or #source > LIMITS.fileBytes then return nil, "File too large: " .. path end
		total = total + #source
		local ok, err
		if path:match("%.lua$") then
			ok, err = load(source, "@" .. path, "t", {})
		else
			local parser = require("etlua").Parser()
			local code
			code, err = parser:compile_to_lua(source)
			if code then ok, err = parser:load(code, "@" .. path) end
		end
		if not ok then return nil, tostring(err) end
	end
	if total > LIMITS.totalBytes then return nil, "Project exceeds 1 MB" end
	for _, path in ipairs(REQUIRED) do
		if not files[PREFIX .. path] then return nil, "Missing " .. path end
	end
	return true
end

function Model:listFiles()
	local result = {}
	for path in pairs(self.files) do result[#result + 1] = path end
	table.sort(result)
	return result
end

function Model:commit(files)
	local ok, err = self:validate(files)
	if not ok then return nil, err end
	ok, err = self.storage.save({ files = files, model = self.model })
	if not ok then return nil, err or "Could not save project" end
	self.history[#self.history + 1] = copy(self.files)
	if #self.history > LIMITS.history then table.remove(self.history, 1) end
	self.files = copy(files)
	self.revision = self.revision + 1
	return true
end

function Model:apply(changes)
	if type(changes) ~= "table" or #changes == 0 then return nil, "Expected nonempty changes" end
	local files, seen = copy(self.files), {}
	for _, change in ipairs(changes) do
		if type(change) ~= "table" or not Model.validPath(change.path) then return nil, "Invalid file path" end
		if seen[change.path] then return nil, "Duplicate file path" end
		seen[change.path] = true
		if type(change.content) ~= "string" then return nil, "Expected file content" end
		files[change.path] = change.content
	end
	return self:commit(files)
end

function Model:undo()
	local previous = self.history[#self.history]
	if not previous then return nil, "Nothing to undo" end
	local ok, err = self.storage.save({ files = previous, model = self.model })
	if not ok then return nil, err end
	self.files = table.remove(self.history)
	self.revision = self.revision + 1
	return true
end

function Model:setModel(value)
	if type(value) ~= "string" or not value:match("^%S+/%S+$") then return nil, "Enter a provider/model ID" end
	local ok, err = self.storage.save({ files = self.files, model = value })
	if not ok then return nil, err end
	self.model = value
	return true
end

function Model:message(role, text)
	self.messages[#self.messages + 1] = { role = role, text = text }
end

function Model:transcript()
	local lines = {}
	for _, item in ipairs(self.messages) do lines[#lines + 1] = item.role .. "\n" .. item.text end
	return table.concat(lines, "\n\n")
end
return Model
