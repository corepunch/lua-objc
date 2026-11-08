local Changes = require("apps.studio.helpers.Changes")
local Api = require("apps.studio.helpers.Api")
local Agent = {}
Agent.__index = Agent
local LIMITS = {steps=24, outputTokens=8192}
local PROMPT = [[You develop the user's Lua app, which runs live in UIKit on the iPhone or iPad in front of the user.
Use listFiles and readFile before editing. Read each needed file once; multiple readFile calls may share a reply.
If the project has demo/playground/AGENTS.md, read it first and follow it: it is the project's own rulebook. A game project also needs readDocumentation("games").
Call readDocumentation before using controls, model methods, or templates not demonstrated in the starter.
Never guess event bindings, model methods, or pass custom action arguments through Resources. Apply complete files with applyFiles; changes reload immediately.
applyFiles takes {"files":[{"path":"demo/playground/Model.lua","content":"complete source"}]}.
The files value is a JSON array, never a JSON-encoded string. Send source with normal JSON escaping only.
Use demo/playground/init.lua returning Controller; Model.lua owns domain logic; Controller.lua binds actions;
Lapis models (data.model) own queries and mutations; bind the project store at entry points.
views/layouts, views/pages, and views/components contain etlua templates and own ALL view trees. Use require("ns") and require("ui.xml"). Only createWindow calls ns.Window.
Templates support Window, VStack, HStack, Spacer, Label, Button, TextField, TextEditor, Toggle, ScrollView,
Divider, SystemImage. Use native controls and semantic colors. Flexible content uses flexGrow="1".
Button action="name" resolves data.actions.name. id="name" gives refs.name for a rendered view.
Column and ToolbarItem keep their own id fields.
Use <%= value %> for escaped attributes and partial() for reusable etlua views. Read existing code to follow its API.
No shell, network tools, package installation, or native compilation. Changes must fit existing UIKit APIs.
After rendering, use testAction to exercise input, add, filter and toggle actions. A ready preview alone does not prove they work.
If preview or testAction reports an error, fix it. Be concise and describe what changed.]]
local function tool(name, description, properties, required)
	return { type = "function", ["function"] = { name = name, description = description,
		parameters = { type = "object", properties = properties, required = required } } }
end
local TOOLS = {
	tool("listFiles", "List project source paths", { project = { type = "string", description = "Use playground" } }, { "project" }),
	tool("readFile", "Read a project source file", { path = { type = "string" } }, { "path" }),
	tool("readDocumentation", "Read the actual supported app API with working examples before adding controls or model operations", {
		topic = {type = "string", enum = {"controls", "models", "templates", "games"}},
	}, {"topic"}),
	tool("readKit", "Read a shared 3-D asset kit's manifest: every model's size, pivot, tags and animation clips. Read it before placing models", {
		kit = {type = "string", description = "Kit folder name, such as platformer-kit"},
	}, {"kit"}),
	tool("applyFiles", "Atomically save files, validate syntax, and reload preview; returns errors for repair", {
		files = { type = "array", description = "An array of file objects, NOT a JSON-encoded string. Each content is the complete source text.", items = { type = "object", properties = { path = { type = "string" }, content = { type = "string" } }, required = { "path", "content" } } },
	}, { "files" }),
	tool("testAction", "Run a named controller action in the current preview and return its data (not a reload). Use it to test interactions and repair errors", {
		action = {type = "string", description = "An existing key in the preview controller actions table"},
		text = {type = "string", description = "Optional string argument, for a text input action"},
		index = {type = "number", description = "Optional numeric argument, such as a zero-based picker index"},
		state = {type = "boolean", description = "Optional boolean argument, for a toggle"},
	}, {"action"}),
	tool("preview", "Reload the app and get its runtime error, if any", { project = { type = "string" } }, { "project" }),
}
function Agent.new(session, transport, json, preview, changed, interact, readFramework)
	return setmetatable({ session = session, transport = transport, json = json, preview = preview, readFramework = readFramework,
		changed = changed, interact = interact, generation = 0, conversation = { { role = "system", content = PROMPT } } }, Agent)
end
local function cancelRequest(agent)
	agent.generation = agent.generation + 1
	local cancel = agent.cancel
	agent.cancel, agent.busy = nil, false
	if cancel then cancel() end
end
function Agent:stop()
	cancelRequest(self)
	self.conversation = { { role = "system", content = PROMPT } }
	self.changed()
end
function Agent:execute(call)
	local fn = assert(call["function"], "Missing tool function")
	local args = self.json.decode(fn.arguments)
	assert(type(args) == "table", "Invalid tool arguments")
	if fn.name == "listFiles" then return self.session.workspace:listFiles() end
	if fn.name == "readFile" then return assert(self.session.workspace.files[args.path], "File not found") end
	if fn.name == "readDocumentation" then
		local guide, err = Api.read(args.topic)
		return guide or {error=err}
	end
	if fn.name == "readKit" then
		if not self.readFramework then return {error = "Asset kits are not available here"} end
		local manifest, err = Api.kit(args.kit, self.readFramework)
		return manifest or {error = err}
	end
	if fn.name == "applyFiles" then
		if type(args.files) ~= "table" or #args.files == 0 then
			return { error = 'applyFiles.files must be a nonempty JSON array of {path, content} objects, not a JSON-encoded string. Example: {"files":[{"path":"demo/playground/Model.lua","content":"return {}"}]}' }
		end
		local before = self.session.workspace.files
		local ok, err = self.session:apply(args.files)
		if not ok then return { error = err } end
		local rendered, previewError = self.preview()
		local state = rendered and "ready" or "error"
		self.session.workspace:message("agent", "Saved " .. #args.files .. " file(s). Undo is available.",
			{ changes = Changes.between(before, self.session.workspace.files), previewState = state, previewError = previewError })
		return { saved = true, preview = state, error = previewError }
	end
	if fn.name == "testAction" then
		if not self.interact then return {error="Preview interaction testing is unavailable"} end
		local value, count
		count = 0
		for _, key in ipairs({"text", "index", "state"}) do
			if args[key] ~= nil then value, count = args[key], count + 1 end
		end
		if count > 1 then return {error="Supply only one of text, index, or state"} end
		local data, err = self.interact(args.action, value)
		return data and {data=data} or {error=err}
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
	local checkpoint = #self.conversation
	local function fail(message)
		self.session.workspace:message("error", message)
		cancelRequest(self)
		-- Keep completed exchanges for a manual retry; discard a partial tool
		-- exchange if executing or encoding its results failed.
		for index = #self.conversation, checkpoint + 1, -1 do table.remove(self.conversation, index) end
		self.changed()
	end
	local function step()
		if generation ~= self.generation then return end
		rounds = rounds + 1
		if rounds > LIMITS.steps then
			self.session.workspace:message("error", "Stopped after " .. LIMITS.steps .. " agent steps. You can continue with another message.")
			self.busy = false
			self.changed()
			return
		end
		self.changed()
		checkpoint = #self.conversation
		local payload = { model = self.session.workspace.modelId, provider = { require_parameters = true }, messages = self.conversation, tools = TOOLS,
			stream = false, max_tokens = LIMITS.outputTokens }
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
			if choice.finish_reason == "length" then
				fail("OpenRouter reached the response token limit. Incomplete edits were not applied. Ask for a smaller change or choose another model."); return
			end
			if choice.finish_reason == "content_filter" or (type(message.refusal) == "string" and message.refusal:match("%S")) then
				fail("The model declined this request. Rephrase it or choose another model."); return
			end
			if choice.finish_reason == "error" or choice.error then
				local detail = type(choice.error) == "table" and choice.error.message or "The provider could not complete the response"
				fail("OpenRouter: " .. tostring(detail)); return
			end
			local calls = message.tool_calls
			if calls ~= nil and type(calls) ~= "table" then fail("OpenRouter returned invalid tool calls"); return end
			if type(calls) == "table" and next(calls) ~= nil and #calls == 0 then fail("OpenRouter returned invalid tool calls"); return end
			if not (type(message.content) == "string" and message.content:match("%S")) and not (calls and #calls > 0) then
				fail("OpenRouter returned an empty response. Try again or choose another model."); return
			end
			local ids = {}
			for _, call in ipairs(calls or {}) do
				if type(call) ~= "table" or type(call.id) ~= "string" or call.id == "" or ids[call.id] then
					fail("Invalid tool call ID"); return
				end
				ids[call.id] = true
			end
			table.insert(self.conversation, message)
			if type(message.content) == "string" and message.content ~= "" then self.session.workspace:message("agent", message.content) end
			if type(calls) == "table" and #calls > 0 then
				for _, call in ipairs(calls) do
					local ok, result = pcall(self.execute, self, call)
					local encoded, content = pcall(self.json.encode, ok and { result = result } or { error = tostring(result) })
					if not encoded then fail("Could not encode tool result: " .. tostring(content)); return end
					table.insert(self.conversation, { role = "tool", tool_call_id = call.id, content = content })
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
