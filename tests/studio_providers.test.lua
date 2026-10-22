_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local Providers = require("apps.studio.services.Providers")
local ChatCompletions = require("apps.studio.helpers.ChatCompletions")
local Keys = require("apps.studio.services.Keys")

local json = { encode = ns._jsonEncode, decode = ns.json_parse }

-- Every bundled provider is a one-file plugin of the provider extension point.
local point, problems = Providers.load(json)
t.assertEqual(#problems, 0, "bundled providers load without problems")
local ids = {}
for _, descriptor in ipairs(point:list()) do table.insert(ids, descriptor.id) end
t.assertEqual(table.concat(ids, ","), "anthropic,openai,gemini,openrouter", "providers keep the bundled order")
for _, descriptor in ipairs(point:list()) do
	t.expect(descriptor.file ~= nil and descriptor.file:find(descriptor.id .. ".lua", 1, true), descriptor.id .. " is one Lua file")
	t.expect(#descriptor.models > 0 and descriptor.defaultModel ~= nil, descriptor.id .. " lists models and a default")
	t.expect(Providers.model(descriptor, descriptor.defaultModel) ~= nil, descriptor.id .. "'s default is one of its models")
	t.expect(descriptor.website and descriptor.website:match("^https://"), descriptor.id .. " says where a key comes from")
end

-- A neutral turn: a system prompt, a user line, a tool call and its result.
local turn = {
	model = "m", system = "Be brief.", maxTokens = 100,
	tools = { { name = "readFile", description = "Read", parameters = { type = "object", properties = { path = { type = "string" } }, required = { "path" } } } },
	messages = {
		{ role = "user", text = "Hello" },
		{ role = "assistant", text = "Reading.", calls = { { id = "c1", name = "readFile", arguments = { path = "a.lua" } } } },
		{ role = "tool", id = "c1", name = "readFile", result = { result = "return 1" } },
		{ role = "assistant", text = "Done" },
	},
}

-- Anthropic: the Messages API.
local request = point:invoke("anthropic", "request", turn, "sk-ant-key")
t.assertEqual(request.url, "https://api.anthropic.com/v1/messages", "Anthropic posts to the Messages API")
t.assertEqual(request.headers["x-api-key"], "sk-ant-key", "the key is the x-api-key header")
t.expect(request.headers["anthropic-version"] ~= nil, "the API version is pinned")
t.assertEqual(request.body.system, "Be brief.", "the system prompt is a top-level field")
t.assertEqual(request.body.max_tokens, 100, "max tokens travel")
t.assertEqual(request.body.tools[1].input_schema.properties.path.type, "string", "tools carry their schema as input_schema")
t.assertEqual(#request.body.messages, 4, "user, assistant, tool result, assistant")
t.assertEqual(request.body.messages[2].content[2].type, "tool_use", "a call is a tool_use block")
t.assertEqual(request.body.messages[2].content[2].input.path, "a.lua", "with its arguments as input")
t.assertEqual(request.body.messages[3].role, "user", "a tool result is a user message")
t.assertEqual(request.body.messages[3].content[1].tool_use_id, "c1", "tied to its call")
t.expect(request.body.messages[3].content[1].content:find("return 1", 1, true), "carrying the result as JSON")
local merged = point:invoke("anthropic", "request", { model = "m", messages = {
	{ role = "assistant", calls = { { id = "1", name = "a", arguments = {} }, { id = "2", name = "b", arguments = {} } } },
	{ role = "tool", id = "1", name = "a", result = {} }, { role = "tool", id = "2", name = "b", result = {} },
} }, "k")
t.assertEqual(#merged.body.messages, 2, "several tool results share one user message")
t.assertEqual(#merged.body.messages[2].content, 2, "as two tool_result blocks")
local reply = point:invoke("anthropic", "reply", 200, { content = {
	{ type = "text", text = "Let me look." }, { type = "tool_use", id = "t1", name = "readFile", input = { path = "x" } } } })
t.assertEqual(reply.text, "Let me look.", "text blocks become the reply text")
t.assertEqual(reply.calls[1].id, "t1", "tool_use blocks become calls")
t.assertEqual(reply.calls[1].arguments.path, "x", "with their input as arguments")
local _, err = point:invoke("anthropic", "reply", 401, { type = "error", error = { type = "authentication_error", message = "invalid x-api-key" } })
t.expect(err and err:find("401") and err:find("invalid x-api-key", 1, true), "an API error is reported with its status: " .. tostring(err))

-- OpenAI: the chat-completions dialect through host.chat.
request = point:invoke("openai", "request", turn, "sk-key")
t.assertEqual(request.url, "https://api.openai.com/v1/chat/completions", "OpenAI posts to chat completions")
t.assertEqual(request.headers.Authorization, "Bearer sk-key", "the key is a bearer token")
t.assertEqual(request.body.messages[1].role, "system", "the system prompt is the first message")
t.assertEqual(request.body.messages[3].tool_calls[1]["function"].name, "readFile", "a call is a tool_calls entry")
t.assertEqual(request.body.messages[3].tool_calls[1]["function"].arguments, '{"path":"a.lua"}', "with JSON-string arguments")
t.assertEqual(request.body.messages[4].role, "tool", "a tool result is a tool message")
t.assertEqual(request.body.messages[4].tool_call_id, "c1", "tied to its call")
t.assertEqual(request.body.tools[1]["function"].parameters.required[1], "path", "tools carry their schema")
t.assertEqual(request.body.max_completion_tokens, 100, "current models take max_completion_tokens")
t.assertEqual(request.body.parallel_tool_calls, false, "one call at a time")
reply = point:invoke("openai", "reply", 200, { choices = { { message = { role = "assistant", content = "Hi", tool_calls = {
	{ id = "call_1", type = "function", ["function"] = { name = "readFile", arguments = '{"path":"b.lua"}' } } } } } } })
t.assertEqual(reply.text, "Hi", "content becomes the reply text")
t.assertEqual(reply.calls[1].arguments.path, "b.lua", "JSON-string arguments are decoded")
_, err = point:invoke("openai", "reply", 200, { choices = { { message = { tool_calls = { { id = "x", ["function"] = { name = "f", arguments = "{broken" } } } } } } })
t.expect(err and err:find("not JSON", 1, true), "broken arguments are an error, not a crash")
_, err = point:invoke("openai", "reply", 429, { error = { message = "rate limited" } })
t.expect(err and err:find("429") and err:find("rate limited", 1, true), "an API error is reported")
_, err = point:invoke("openai", "reply", 200, {})
t.expect(err and err:find("no assistant message", 1, true), "an empty body is an error")

-- OpenRouter speaks the same dialect with its own address and headers.
request = point:invoke("openrouter", "request", turn, "sk-or-key")
t.assertEqual(request.url, "https://openrouter.ai/api/v1/chat/completions", "OpenRouter posts to its gateway")
t.assertEqual(request.headers.Authorization, "Bearer sk-or-key", "with a bearer token")
t.assertEqual(request.headers["X-Title"], "Lua Studio", "and names the app")
t.assertEqual(request.body.messages[3].tool_calls[1].id, "c1", "the body is the chat-completions shape")

-- Gemini: generateContent, calls answered by name.
request = point:invoke("gemini", "request", turn, "AIza-key")
t.assertEqual(request.url, "https://generativelanguage.googleapis.com/v1beta/models/m:generateContent", "the model is in the URL")
t.assertEqual(request.headers["x-goog-api-key"], "AIza-key", "the key is the x-goog-api-key header")
t.assertEqual(request.body.systemInstruction.parts[1].text, "Be brief.", "the system prompt is a systemInstruction")
t.assertEqual(request.body.contents[2].role, "model", "assistant turns are model turns")
t.assertEqual(request.body.contents[2].parts[2].functionCall.args.path, "a.lua", "a call is a functionCall part")
t.assertEqual(request.body.contents[3].parts[1].functionResponse.name, "readFile", "a result is a functionResponse named after the function")
t.assertEqual(request.body.tools[1].functionDeclarations[1].name, "readFile", "tools are function declarations")
t.assertEqual(request.body.generationConfig.maxOutputTokens, 100, "max tokens travel")
reply = point:invoke("gemini", "reply", 200, { candidates = { { content = { role = "model", parts = {
	{ text = "Looking." }, { functionCall = { name = "readFile", args = { path = "c.lua" } } } } } } } })
t.assertEqual(reply.text, "Looking.", "text parts become the reply text")
t.assertEqual(reply.calls[1].name, "readFile", "functionCall parts become calls")
t.assertEqual(reply.calls[1].id, "readFile#2", "calls get ids from their position")
_, err = point:invoke("gemini", "reply", 400, { error = { code = 400, message = "API key not valid" } })
t.expect(err and err:find("API key not valid", 1, true), "an API error is reported")

-- The dialect helper is pure and reusable by any gateway plugin.
local body = ChatCompletions.request({ model = "m", messages = { { role = "user", text = "x" } } }, json.encode)
t.assertEqual(body.tools, nil, "no tools, no tools field")
t.assertEqual(body.messages[1].content, "x", "a user line is a user message")

-- Choices resolve against what is installed.
local descriptor, model = Providers.choice(point, "openai", "gpt-5-mini")
t.assertEqual(descriptor.id .. "/" .. model, "openai/gpt-5-mini", "a saved choice is honoured")
descriptor, model = Providers.choice(point, "openai", "any-id-at-all")
t.assertEqual(model, "any-id-at-all", "a model id the list does not know is kept; the provider decides")
descriptor, model = Providers.choice(point, "gone", nil)
t.assertEqual(descriptor.id, "anthropic", "an uninstalled provider falls back to the first one")
t.assertEqual(model, descriptor.defaultModel, "with its default model")
descriptor, model = Providers.choice(point, nil, nil)
t.assertEqual(descriptor.id, "anthropic", "a new project talks to the first provider")

-- Dropped-in plugins join the bundled ones; broken ones are reported, not fatal.
local documents = {
	["Plugins/acme.lua"] = [[return { api = 1, title = "Acme", models = { { id = "acme-1", title = "Acme 1" } }, defaultModel = "acme-1",
		request = function(host, turn, key) return { url = "https://acme.test/v1/chat/completions", headers = { Authorization = key }, body = host.chat.request(turn) } end,
		reply = function(host, status, body) return host.chat.reply(status, body) end }]],
	["Plugins/broken.lua"] = "return {",
	["Plugins/openai.lua"] = "return { api = 1 }",
	["Plugins/_off.lua"] = "error('never loaded')",
	["Plugins/notes.txt"] = "not a plugin",
}
local listing = {}
for name in pairs(documents) do table.insert(listing, { name = name:match("[^/]+$"), directory = false }) end
table.sort(listing, function(a, b) return a.name < b.name end)
table.insert(listing, { name = "folder", directory = true })
local withUser, userProblems = Providers.load(json, {
	list = function(folder) t.assertEqual(folder, "Plugins", "plugins are read from Documents/Plugins"); return listing end,
	read = function(path) return documents[path] end,
})
t.assertEqual(#withUser:list(), 5, "the user's provider joins the four bundled ones")
t.assertEqual(withUser:get("acme").source, "user", "and is marked as the user's")
t.assertEqual(withUser:get("acme").file, "Plugins/acme.lua", "with its file")
local acme = withUser:invoke("acme", "request", turn, "k")
t.assertEqual(acme.body.messages[1].role, "system", "a gateway plugin reuses the host's chat dialect")
t.assertEqual(#userProblems, 2, "the broken file and the name clash are reported")
t.expect(userProblems[1].file == "Plugins/broken.lua" and userProblems[1].message:find("Plugins/broken.lua", 1, true), "a syntax error names its file")
t.expect(userProblems[2].file == "Plugins/openai.lua" and userProblems[2].message:find("already called openai", 1, true), "a bundled id cannot be replaced")

-- Keys live in the keychain under the provider's id.
local store, calls = {}, {}
local keys = Keys.new({
	_keychainGet = function(service, account) table.insert(calls, "get " .. service .. "/" .. account); return store[account] end,
	_keychainSet = function(service, account, value) store[account] = value; return true end,
	_keychainDelete = function(service, account) store[account] = nil; return true end,
})
t.assertEqual(keys:get("openai"), nil, "no key until one is saved")
t.expect(keys:set("openai", "  sk-abc  "), "a key saves")
t.assertEqual(store.openai, "sk-abc", "trimmed")
t.assertEqual(calls[1], "get org.luaobjc.studio/openai", "under Studio's service name and the provider id")
t.expect(keys:has("openai"), "and is reported present")
t.expect(keys:set("openai", ""), "an empty key clears it")
t.assertEqual(store.openai, nil, "the item is deleted")
t.expect(not keys:set("", "x") and not keys:set("openai", 42), "bad arguments are refused")

os.exit(t.summary() and 0 or 1)
