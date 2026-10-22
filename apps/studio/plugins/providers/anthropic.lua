-- Anthropic: the Messages API. Tool calls and results travel as content
-- blocks; every tool result of a turn goes in one user message.
local URL = "https://api.anthropic.com/v1/messages"
local VERSION = "2023-06-01"

local function toolDefinitions(tools)
	local result = {}
	for _, tool in ipairs(tools) do
		table.insert(result, { name = tool.name, description = tool.description, input_schema = tool.parameters })
	end
	return result
end

local function messages(host, turn)
	local result = {}
	for _, message in ipairs(turn.messages) do
		if message.role == "user" then
			table.insert(result, { role = "user", content = message.text })
		elseif message.role == "assistant" then
			local blocks = {}
			if message.text and message.text ~= "" then table.insert(blocks, { type = "text", text = message.text }) end
			for _, call in ipairs(message.calls or {}) do
				table.insert(blocks, { type = "tool_use", id = call.id, name = call.name, input = call.arguments or {} })
			end
			table.insert(result, { role = "assistant", content = blocks })
		elseif message.role == "tool" then
			local block = { type = "tool_result", tool_use_id = message.id, content = host.encode(message.result) }
			local last = result[#result]
			if last and last.role == "user" and type(last.content) == "table" then
				table.insert(last.content, block)
			else
				table.insert(result, { role = "user", content = { block } })
			end
		end
	end
	return result
end

return {
	api = 1,
	title = "Anthropic",
	symbol = "sparkle",
	website = "https://console.anthropic.com/settings/keys",
	keyPrefix = "sk-ant-",
	models = {
		{ id = "claude-sonnet-5-5", title = "Claude Sonnet 5.5" },
		{ id = "claude-opus-5-5", title = "Claude Opus 5.5" },
		{ id = "claude-haiku-5-5", title = "Claude Haiku 5.5" },
	},
	defaultModel = "claude-sonnet-5-5",
	request = function(host, turn, key)
		local body = { model = turn.model, max_tokens = turn.maxTokens or 8192, messages = messages(host, turn) }
		if turn.system and turn.system ~= "" then body.system = turn.system end
		if turn.tools and #turn.tools > 0 then body.tools = toolDefinitions(turn.tools) end
		return {
			url = URL,
			headers = { ["x-api-key"] = key, ["anthropic-version"] = VERSION, ["content-type"] = "application/json" },
			body = body,
		}
	end,
	reply = function(_, status, body)
		if type(body) ~= "table" then return nil, "HTTP " .. tostring(status) .. ": no JSON body" end
		if body.type == "error" or body.error then
			local detail = type(body.error) == "table" and body.error.message or "request failed"
			return nil, "HTTP " .. tostring(status) .. ": " .. tostring(detail)
		end
		if type(body.content) ~= "table" then return nil, "HTTP " .. tostring(status) .. ": no content" end
		local texts, calls = {}, {}
		for _, block in ipairs(body.content) do
			if block.type == "text" and type(block.text) == "string" then
				table.insert(texts, block.text)
			elseif block.type == "tool_use" then
				if type(block.id) ~= "string" or type(block.name) ~= "string" then
					return nil, "The reply carried a malformed tool call"
				end
				table.insert(calls, { id = block.id, name = block.name,
					arguments = type(block.input) == "table" and block.input or {} })
			end
		end
		return { text = #texts > 0 and table.concat(texts, "\n") or nil, calls = calls }
	end,
}
