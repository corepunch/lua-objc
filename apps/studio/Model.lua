-- A project open in Studio: its source files, the undo history of the
-- agent's edits, the conversation, and the agent it talks to (a provider
-- plugin and one of its models). Files are keyed by their module path
-- under demo/playground/, the namespace every project runs in.
local Changes = require("apps.studio.helpers.Changes")
local Model = {}
Model.__index = Model
local PREFIX = "demo/playground/"
local REQUIRED = { "init.lua", "Model.lua", "Controller.lua", "views/Window.etlua" }
local LIMITS = { fileBytes = 128 * 1024, totalBytes = 1024 * 1024, history = 20 }

Model.prefix = PREFIX

local function copy(files)
	local result = {}
	for path, source in pairs(files) do result[path] = source end
	return result
end

function Model.validPath(path)
	if type(path) ~= "string" or path:sub(1, #PREFIX) ~= PREFIX then return false end
	if path:find("[^%w_./%-]") or path:find("//", 1, true) then return false end
	for part in path:gmatch("[^/]+") do
		if part == "." or part == ".." then return false end
	end
	return path:match("%.lua$") ~= nil or path:match("%.etlua$") ~= nil
end

-- `storage.load()` returns {files, provider, model} or nil; `storage.save`
-- takes the same shape. `seed` is the project's source when nothing is saved.
function Model.new(storage, seed)
	local self = setmetatable({ storage = storage, files = copy(seed), history = {}, messages = {}, revision = 0 }, Model)
	local saved = storage.load()
	if saved then
		local ok, err = self:validate(saved.files)
		if not ok then error("Saved project is invalid: " .. err) end
		self.files = copy(saved.files)
		if type(saved.provider) == "string" then self.provider = saved.provider end
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
	for path in pairs(self.files) do table.insert(result, path) end
	table.sort(result)
	return result
end

local function record(self, files)
	return self.storage.save({ files = files, provider = self.provider, model = self.model })
end

function Model:commit(files)
	local ok, err = self:validate(files)
	if not ok then return nil, err end
	ok, err = record(self, files)
	if not ok then return nil, err or "Could not save project" end
	table.insert(self.history, (copy(self.files)))
	if #self.history > LIMITS.history then table.remove(self.history, 1) end
	self.files = copy(files)
	self.revision = self.revision + 1
	return true
end

--- Applies `changes` ({path, content} each) as one edit. Returns the
--- change summary ({path, added, removed} per file) or nil and an error.
function Model:apply(changes)
	if type(changes) ~= "table" or #changes == 0 then return nil, "Expected nonempty changes" end
	local files, seen, paths = copy(self.files), {}, {}
	for _, change in ipairs(changes) do
		if type(change) ~= "table" or not Model.validPath(change.path) then return nil, "Invalid file path" end
		if seen[change.path] then return nil, "Duplicate file path" end
		seen[change.path] = true
		if type(change.content) ~= "string" then return nil, "Expected file content" end
		files[change.path] = change.content
		table.insert(paths, change.path)
	end
	local summary = Changes.summary(self.files, files, paths, PREFIX)
	local ok, err = self:commit(files)
	if not ok then return nil, err end
	return summary
end

function Model:undo()
	local previous = self.history[#self.history]
	if not previous then return nil, "Nothing to undo" end
	local ok, err = record(self, previous)
	if not ok then return nil, err end
	self.files = table.remove(self.history)
	self.revision = self.revision + 1
	return true
end

--- The agent this project talks to: a provider plugin id and a model id.
function Model:setAgent(provider, model)
	if type(provider) ~= "string" or provider == "" then return nil, "Choose a provider" end
	if type(model) ~= "string" or not model:match("^%S+$") then return nil, "Enter a model ID" end
	local previousProvider, previousModel = self.provider, self.model
	self.provider, self.model = provider, model
	local ok, err = record(self, self.files)
	if not ok then
		self.provider, self.model = previousProvider, previousModel
		return nil, err
	end
	return true
end

--- A line of the conversation: `role` is "user", "agent" or "error";
--- `changes` is a change summary shown as a card.
function Model:message(role, text, changes)
	table.insert(self.messages, { role = role, text = text or "", changes = changes })
end

function Model:clearMessages()
	self.messages = {}
end

function Model:transcript()
	local lines = {}
	for _, item in ipairs(self.messages) do table.insert(lines, item.role .. "\n" .. item.text) end
	return table.concat(lines, "\n\n")
end

return Model
