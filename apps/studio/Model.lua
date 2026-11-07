local Model = require("data.model")
local PREFIX = "demo/playground/"
local REQUIRED = { "init.lua", "Model.lua", "Controller.lua" }
local LIMITS = { fileBytes = 128 * 1024, totalBytes = 1024 * 1024, history = 20 }

local function copy(files)
	local result = {}
	for path, source in pairs(files) do result[path] = source end
	return result
end

local function validPath(path)
	if type(path) ~= "string" or path:sub(1, #PREFIX) ~= PREFIX or path == PREFIX .. "project.lua" then return false end
	if path:find("[^%w_./%-]") or path:find("//", 1, true) then return false end
	for part in path:gmatch("[^/]+") do
		if part == "." or part == ".." or part:lower() == ".git" then return false end
	end
	return path:match("%.lua$") ~= nil or path:match("%.etlua$") ~= nil
end

local function validate(files)
	if type(files) ~= "table" then return nil, "Project must contain files" end
	local total = 0
	for path, source in pairs(files) do
		if not validPath(path) then return nil, "Invalid project path: " .. tostring(path) end
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
	local hasView = false
	for path in pairs(files) do if path:match("%.etlua$") then hasView = true end end
	if not hasView then return nil, "A project needs an etlua view" end
	return true
end

local Workspaces, Workspace = Model:extend("studioWorkspaces", {
	primaryKey = "id",
	constraints = {
		files = function(_, files)
			local ok, err = validate(files)
			if not ok then return err end
		end,
		modelId = function(_, value)
			if type(value) ~= "string" or not value:match("^[%w_.:%-]+/[%w_./:%-]+$") then
				return "Enter a provider/model ID"
			end
		end,
	},
})
Workspaces.validPath = validPath
Workspaces.validate = validate

function Workspaces:open(id, seed, saved)
	local existing = self:find(id)
	if existing then return existing end
	local row, err = self:create({ id = id, files = copy(saved and saved.files or seed),
		modelId = saved and saved.modelId or "openrouter/free", revision = 0,
		history = {}, messages = {}, drafts = {} })
	assert(row, err)
	return row
end

function Workspace:listFiles()
	local result = {}
	for path in pairs(self.files) do table.insert(result, path) end
	table.sort(result)
	return result
end

function Workspace:prepare(changes)
	if type(changes) ~= "table" or #changes == 0 then return nil, "Expected nonempty changes" end
	local files, seen = copy(self.files), {}
	for _, change in ipairs(changes) do
		if type(change) ~= "table" or not validPath(change.path) then return nil, "Invalid file path" end
		if seen[change.path] then return nil, "Duplicate file path" end
		seen[change.path] = true
		if type(change.content) ~= "string" then return nil, "Expected file content" end
		files[change.path] = change.content
	end
	local ok, err = validate(files)
	if not ok then return nil, err end
	return files
end

function Workspace:commit(files)
	local ok, err = validate(files)
	if not ok then return nil, err end
	table.insert(self.history, (copy(self.files)))
	if #self.history > LIMITS.history then table.remove(self.history, 1) end
	self.files, self.drafts, self.revision = copy(files), {}, self.revision + 1
	return true
end

function Workspace:edit(path, source)
	if not validPath(path) or self.files[path] == nil then return nil, "Select a project source file" end
	if type(source) ~= "string" or #source > LIMITS.fileBytes then return nil, "Source exceeds 128 KB" end
	self.drafts[path] = source ~= self.files[path] and source or nil
	return true
end

function Workspace:source(path)
	return self.drafts[path] or self.files[path]
end

function Workspace:pendingChanges()
	local changes = {}
	for path, content in pairs(self.drafts) do table.insert(changes, { path = path, content = content }) end
	table.sort(changes, function(a, b) return a.path < b.path end)
	return changes
end

function Workspace:undo()
	if next(self.drafts) then self.drafts = {}; return true end
	local previous = table.remove(self.history)
	if not previous then return nil, "Nothing to undo" end
	self.files, self.revision = previous, self.revision + 1
	return true
end

function Workspace:message(role, text, details)
	local message = { id = #self.messages + 1, role = role, text = text }
	for key, value in pairs(details or {}) do message[key] = value end
	table.insert(self.messages, message)
	return message
end

function Workspace:clearConversation()
	self.messages = {}
end

function Workspace:transcript()
	local lines = {}
	for _, item in ipairs(self.messages) do table.insert(lines, item.role .. "\n" .. item.text) end
	return table.concat(lines, "\n\n")
end

return Workspaces
