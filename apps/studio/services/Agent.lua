-- The coding agent: a conversation in the neutral shape every provider
-- plugin reads, the tools it may call on the project, and the loop that
-- sends a turn, applies the reply's tool calls and sends again until the
-- provider answers in words. Which provider and model speak is the
-- project's choice; the API key comes from the keychain at send time.
local Providers = require("apps.studio.services.Providers")

local Agent = {}
Agent.__index = Agent

local PROMPT = [[You develop the user's Lua app running in a live UIKit preview on iPad.
Use listFiles and readFile before editing. Apply complete files with applyFiles; changes reload immediately.
Use demo/playground/init.lua returning Controller; Model.lua owns domain logic; Controller.lua binds actions;
views/*.etlua own ALL view trees. Use require("ns") and require("ui.xml"). Only createWindow calls ns.Window.
Templates support Window, VStack, HStack, Spacer, Label, Button, TextField, TextEditor, Toggle, ScrollView,
Divider, SystemImage. Use native controls and semantic colors. Flexible content uses flexGrow="1".
Button action="name" resolves data.actions.name. id="name" gives refs.name for a rendered view.
Column and ToolbarItem keep their own id fields.
Use <%= value %> for escaped attributes and partial() for reusable etlua views. Read existing code to follow its API.
No shell, network tools, package installation, or native compilation. Changes must fit existing UIKit APIs.
If preview reports an error, fix it. Be concise and describe what changed.]]

local LIMITS = { rounds = 12, maxTokens = 8192, excerpt = 200 }

-- Tools in the neutral shape: name, description and a JSON schema.
local TOOLS = {
	{ name = "listFiles", description = "List project source paths",
		parameters = { type = "object", properties = {} } },
	{ name = "readFile", description = "Read a project source file",
		parameters = { type = "object", properties = { path = { type = "string" } }, required = { "path" } } },
	{ name = "applyFiles", description = "Atomically save files, validate syntax, and reload preview; returns errors for repair",
		parameters = { type = "object", properties = {
			files = { type = "array", items = { type = "object",
				properties = { path = { type = "string" }, content = { type = "string" } }, required = { "path", "content" } } },
		}, required = { "files" } } },
	{ name = "preview", description = "Reload the app and get its runtime error, if any",
		parameters = { type = "object", properties = {} } },
}
Agent.tools = TOOLS

-- `options`: model (the project), providers (the extension point), keys,
-- http(request, completion) returning a cancel function, json
-- ({encode, decode}), preview() reloading the project, changed() telling
-- the controller to draw again.
function Agent.new(options)
	return setmetatable({
		model = options.model, providers = options.providers, keys = options.keys,
		http = options.http, json = options.json, preview = options.preview, changed = options.changed,
		generation = 0, conversation = {},
	}, Agent)
end

--- The provider descriptor and model id the project talks to.
function Agent:choice()
	return Providers.choice(self.providers, self.model.provider, self.model.model)
end

--- Cancels the turn in flight and drops its partial exchange, so the next
--- send starts from a conversation whose every call has its result.
function Agent:stop()
	self.generation = self.generation + 1
	if self.cancel then self.cancel(); self.cancel = nil end
	if self.busy and self.mark then
		for index = #self.conversation, self.mark + 1, -1 do table.remove(self.conversation, index) end
	end
	self.busy, self.mark = false, nil
	self.changed()
end

function Agent:reset()
	self:stop()
	self.conversation = {}
	self.model:clearMessages()
	self.changed()
end

-- Runs one tool call; the result is what the provider reads back.
function Agent:execute(call)
	local args = call.arguments
	assert(type(args) == "table", "Invalid tool arguments")
	if call.name == "listFiles" then return self.model:listFiles() end
	if call.name == "readFile" then return assert(self.model.files[args.path], "File not found") end
	if call.name == "applyFiles" then
		local summary, err = self.model:apply(args.files)
		if not summary then return { error = err } end
		local noun = #summary == 1 and "file" or "files"
		self.model:message("agent", "", summary)
		local rendered, previewError = self.preview()
		return { saved = true, files = #summary .. " " .. noun, preview = rendered and "ready" or "error", error = previewError }
	end
	if call.name == "preview" then
		local ok, err = self.preview()
		return { preview = ok and "ready" or "error", error = err }
	end
	error("Unknown tool: " .. tostring(call.name))
end

local function excerpt(body)
	body = tostring(body or ""):gsub("%s+", " ")
	if #body > LIMITS.excerpt then body = body:sub(1, LIMITS.excerpt) .. "…" end
	return body
end

function Agent:send(text)
	if self.busy then return nil, "The agent is already working" end
	if type(text) ~= "string" or not text:match("%S") then return nil, "Enter a message" end
	local descriptor, modelId = self:choice()
	if not descriptor then return nil, "No model provider is installed" end
	local key = self.keys:get(descriptor.id)
	if not key then return nil, "Add a " .. descriptor.title .. " API key in Settings" end
	self.busy = true
	self.generation = self.generation + 1
	self.mark = #self.conversation
	local generation, rounds = self.generation, 0
	self.model:message("user", text)
	table.insert(self.conversation, { role = "user", text = text })
	local function fail(message)
		self.model:message("error", message)
		self:stop()
	end
	local function step()
		if generation ~= self.generation then return end
		rounds = rounds + 1
		if rounds > LIMITS.rounds then
			fail("Stopped after " .. LIMITS.rounds .. " agent steps. You can continue with another message.")
			return
		end
		self.changed()
		local turn = { model = modelId, system = PROMPT, messages = self.conversation, tools = TOOLS,
			maxTokens = LIMITS.maxTokens }
		local ok, request = pcall(self.providers.invoke, self.providers, descriptor.id, "request", turn, key)
		if not ok then fail(descriptor.title .. " plugin failed: " .. tostring(request)); return end
		if type(request) ~= "table" or type(request.url) ~= "string" then
			fail(descriptor.title .. " plugin returned no request"); return
		end
		local body = request.body
		if type(body) == "table" then body = self.json.encode(body) end
		self.cancel = self.http({ url = request.url, headers = request.headers or {}, body = body or "" },
			function(responseBody, err, status)
				if generation ~= self.generation then return end
				self.cancel = nil
				if err and not responseBody then fail(err); return end
				local decodedOk, decoded = pcall(self.json.decode, responseBody or "")
				if not decodedOk or type(decoded) ~= "table" then
					fail("HTTP " .. tostring(status) .. ": " .. (err or excerpt(responseBody))); return
				end
				local replyOk, reply, replyErr = pcall(self.providers.invoke, self.providers, descriptor.id, "reply", status, decoded)
				if not replyOk then fail(descriptor.title .. " plugin failed: " .. tostring(reply)); return end
				if not reply then fail(descriptor.title .. ": " .. tostring(replyErr)); return end
				local calls = type(reply.calls) == "table" and reply.calls or {}
				table.insert(self.conversation, { role = "assistant", text = reply.text, calls = calls })
				if type(reply.text) == "string" and reply.text:match("%S") then self.model:message("agent", reply.text) end
				if #calls == 0 then
					self.busy, self.mark = false, nil
					self.changed()
					return
				end
				for _, call in ipairs(calls) do
					if type(call.id) ~= "string" or type(call.name) ~= "string" then fail("Invalid tool call"); return end
					local okCall, result = pcall(self.execute, self, call)
					table.insert(self.conversation, { role = "tool", id = call.id, name = call.name,
						result = okCall and { result = result } or { error = tostring(result) } })
				end
				step()
			end)
	end
	step()
	return true
end

return Agent
