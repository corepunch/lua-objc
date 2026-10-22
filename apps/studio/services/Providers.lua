-- Model providers are plugins of the `provider` extension point: one Lua
-- file each, bundled under plugins/providers/ or dropped by the user into
-- the app's Documents/Plugins folder. A provider turns a neutral turn into
-- one HTTPS request and reads one response back; the agent never sees a
-- wire format.
--
-- The turn a provider receives:
--   { model = "id", system = "prompt", maxTokens = n,
--     tools = { {name, description, parameters = <JSON schema>} },
--     messages = { {role = "user", text},
--                  {role = "assistant", text, calls = { {id, name, arguments = <table>} }},
--                  {role = "tool", id, name, result = <table>} } }
-- `request(host, turn, key)` returns {url, headers, body}; `body` may be a
-- table (encoded as JSON by Studio) or a string. `reply(host, status, body)`
-- receives the decoded JSON body and returns {text, calls} or nil and a
-- message. The host API is `host.encode`/`host.decode` (JSON) and
-- `host.chat`, the OpenAI dialect, so a gateway provider is a few lines.
local Plugins = require("Plugins")
local ChatCompletions = require("apps.studio.helpers.ChatCompletions")

local Providers = {}

Providers.api = 1
Providers.prefix = "apps.studio.plugins.providers"
Providers.bundled = { "anthropic", "openai", "gemini", "openrouter" }
Providers.folder = "Plugins"
Providers.manifest = {
	title = "string", symbol = "string?", website = "string?", keyPrefix = "string?",
	models = "table", defaultModel = "string", request = "function", reply = "function",
}

--- The extension point with the bundled providers loaded, then any plugin
--- file in Documents/Plugins. `json` is {encode, decode}; `documents` is
--- {list, read} over the app's Documents folder, optional. A user plugin
--- that fails to load is reported in `problems` rather than raised, as an
--- editor reports a broken plugin and starts anyway.
function Providers.load(json, documents)
	local host = {
		encode = json.encode,
		decode = json.decode,
		chat = {
			request = function(turn) return ChatCompletions.request(turn, json.encode) end,
			reply = function(status, body) return ChatCompletions.reply(status, body, json.decode) end,
		},
	}
	local point = Plugins.extensionPoint({ name = "provider", api = Providers.api, host = host,
		manifest = Providers.manifest })
	point:load(Providers.prefix, Providers.bundled)
	local problems = {}
	for _, entry in ipairs(documents and documents.list(Providers.folder) or {}) do
		local id = not entry.directory and Plugins.pluginName(entry.name) or nil
		local file = Providers.folder .. "/" .. entry.name
		if id and point:get(id) then
			table.insert(problems, { file = file, message = "a bundled provider is already called " .. id })
		elseif id then
			local source = documents.read(file)
			local ok, err = pcall(point.loadSource, point, id, source or "", file)
			if not ok then table.insert(problems, { file = file, message = tostring(err) }) end
		end
	end
	return point, problems
end

--- The model a provider offers under `id`, or its default.
function Providers.model(descriptor, id)
	for _, model in ipairs(descriptor.models) do
		if model.id == id then return model end
	end
	return nil
end

--- Resolves a saved choice against the loaded providers: the provider by
--- id (or the first one) and a model it offers, else its default.
function Providers.choice(point, providerId, modelId)
	local descriptor = (providerId and point:get(providerId)) or point:list()[1]
	if not descriptor then return nil end
	local model = modelId
	if type(model) ~= "string" or model == "" then model = descriptor.defaultModel end
	return descriptor, model
end

return Providers
