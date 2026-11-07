local Changes = require("apps.studio.helpers.Changes")
local Agent = {}
Agent.__index = Agent
local PROMPT = [[You develop the user's Lua app running in a live UIKit preview on iPad.
Use listFiles and readFile before editing. Apply complete files with applyFiles; changes reload immediately.
Use demo/playground/init.lua returning Controller; Model.lua owns domain logic; Controller.lua binds actions;
Lapis models (data.model) own queries and mutations; bind the project store at entry points.
views/layouts, views/pages, and views/components contain etlua templates and own ALL view trees. Use require("ns") and require("ui.xml"). Only createWindow calls ns.Window.
Templates support Window, VStack, HStack, Spacer, Label, Button, TextField, TextEditor, Toggle, ScrollView,
Divider, SystemImage. Use native controls and semantic colors. Flexible content uses flexGrow="1".
Button action="name" resolves data.actions.name. id="name" gives refs.name for a rendered view.
Column and ToolbarItem keep their own id fields.
Use <%= value %> for escaped attributes and partial() for reusable etlua views. Read existing code to follow its API.
No shell, network tools, package installation, or native compilation. Changes must fit existing UIKit APIs.
If preview reports an error, fix it. Be concise and describe what changed.]]
local function tool(name, description, properties, required)
	return { type = "function", ["function"] = { name = name, description = description,
		parameters = { type = "object", properties = properties, required = required } } }
end
local TOOLS = {
	tool("listFiles", "List project source paths", { project = { type = "string", description = "Use playground" } }, { "project" }),
	tool("readFile", "Read a project source file", { path = { type = "string" } }, { "path" }),
	tool("applyFiles", "Atomically save files, validate syntax, and reload preview; returns errors for repair", {
		files = { type = "array", items = { type = "object", properties = { path = { type = "string" }, content = { type = "string" } }, required = { "path", "content" } } },
	}, { "files" }),
	tool("preview", "Reload the app and get its runtime error, if any", { project = { type = "string" } }, { "project" }),
}
function Agent.new(session, transport, json, preview, changed)
	return setmetatable({ session = session, transport = transport, json = json, preview = preview,
		changed = changed, generation = 0, conversation = { { role = "system", content = PROMPT } } }, Agent)
end
function Agent:stop()
	self.generation = self.generation + 1
	if self.cancel then self.cancel(); self.cancel = nil end
	self.busy = false
	-- Discard incomplete tool exchanges after cancellation or transport failure.
	self.conversation = { { role = "system", content = PROMPT } }
	self.changed()
end
function Agent:execute(call)
	local fn = assert(call["function"], "Missing tool function")
	local args = self.json.decode(fn.arguments)
	assert(type(args) == "table", "Invalid tool arguments")
	if fn.name == "listFiles" then return self.session.workspace:listFiles() end
	if fn.name == "readFile" then return assert(self.session.workspace.files[args.path], "File not found") end
	if fn.name == "applyFiles" then
		local before = self.session.workspace.files
		local ok, err = self.session:apply(args.files)
		if not ok then return { error = err } end
		self.session.workspace:message("agent", "Saved " .. #args.files .. " file(s). Undo is available.",
			{ changes = Changes.between(before, self.session.workspace.files) })
		local rendered, previewError = self.preview()
		return { saved = true, preview = rendered and "ready" or "error", error = previewError }
	end
	if fn.name == "preview" then
		local ok, err = self.preview()
		return { preview = ok and "ready" or "error", error = err }
	end
	error("Unknown tool: " .. tostring(fn.name))
end
function Agent:send(text, key, attachments)
	if self.busy then return nil, "The agent is already working" end
	if type(text) ~= "string" or not text:match("%S") then return nil, "Enter a message" end
	if not key or key == "" then return nil, "Add an OpenRouter API key in Settings to use the free router or a stronger model" end
	self.busy = true
	self.generation = self.generation + 1
	local generation, rounds = self.generation, 0
	self.session.workspace:message("user", text)
	local content = text
	for _, file in ipairs(attachments or {}) do
		content = content .. "\n\nAttached context (" .. file.name .. "):\n" .. file.text
	end
	table.insert(self.conversation, { role = "user", content = content })
	local function fail(message)
		self.session.workspace:message("error", message)
		self:stop()
	end
	local function step()
		if generation ~= self.generation then return end
		rounds = rounds + 1
		if rounds > 12 then fail("Stopped after 12 agent steps. You can continue with another message."); return end
		self.changed()
		local payload = { model = self.session.workspace.modelId, provider = { require_parameters = true }, messages = self.conversation, tools = TOOLS,
			stream = false, max_tokens = 8192 }
		local request = {}
		self.request = request
		local ok, cancel = pcall(self.transport, payload, key, function(response, err)
			if request.finished then return end
			request.finished = true
			if generation ~= self.generation then return end
			self.cancel = nil
			if err then fail(err); return end
			local choice = type(response) == "table" and type(response.choices) == "table" and response.choices[1]
			local message = type(choice) == "table" and choice.message
			if type(message) ~= "table" then fail("OpenRouter returned no assistant message"); return end
			table.insert(self.conversation, message)
			if type(message.content) == "string" and message.content ~= "" then self.session.workspace:message("agent", message.content) end
			local calls = message.tool_calls
			if type(calls) == "table" and #calls > 0 then
				for _, call in ipairs(calls) do
					if type(call) ~= "table" or type(call.id) ~= "string" then fail("Invalid tool call ID"); return end
					local ok, result = pcall(self.execute, self, call)
					table.insert(self.conversation, { role = "tool", tool_call_id = call.id,
						content = self.json.encode(ok and { result = result } or { error = tostring(result) }) })
				end
				step()
			else
				self.busy = false
				self.changed()
			end
		end)
		if not ok then fail("Request failed: " .. tostring(cancel)); return end
		-- A synchronous response can already have completed or started the next
		-- request. Never install its old cancellation function over the new one.
		if self.request == request and not request.finished and generation == self.generation then
			self.cancel = cancel
		end
	end
	step()
	return true
end
return Agent
