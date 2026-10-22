-- The OpenAI chat-completions dialect, which OpenAI, OpenRouter and most
-- hosted gateways speak: a neutral turn becomes its request body and its
-- response body becomes a neutral reply. Provider plugins reach it as
-- `host.chat`, so a provider that speaks this dialect is a URL, a header
-- and a model list. Pure: it computes over the turn and the body it is
-- given; `encode`/`decode` are the JSON codec the host passes in, since
-- the dialect carries tool arguments and results as JSON strings.
local ChatCompletions = {}

local function toolDefinitions(tools)
	local result = {}
	for _, tool in ipairs(tools or {}) do
		table.insert(result, { type = "function", ["function"] = {
			name = tool.name, description = tool.description, parameters = tool.parameters } })
	end
	return result
end

--- The request body for `turn` ({model, system, messages, tools, maxTokens}).
function ChatCompletions.request(turn, encode)
	local messages = {}
	if turn.system and turn.system ~= "" then table.insert(messages, { role = "system", content = turn.system }) end
	for _, message in ipairs(turn.messages) do
		if message.role == "user" then
			table.insert(messages, { role = "user", content = message.text })
		elseif message.role == "assistant" then
			local entry = { role = "assistant", content = message.text }
			if message.calls and #message.calls > 0 then
				entry.tool_calls = {}
				for _, call in ipairs(message.calls) do
					table.insert(entry.tool_calls, { id = call.id, type = "function",
						["function"] = { name = call.name, arguments = encode(call.arguments or {}) } })
				end
			end
			table.insert(messages, entry)
		elseif message.role == "tool" then
			table.insert(messages, { role = "tool", tool_call_id = message.id, content = encode(message.result) })
		end
	end
	local body = { model = turn.model, messages = messages, stream = false }
	if turn.tools and #turn.tools > 0 then
		body.tools = toolDefinitions(turn.tools)
		body.parallel_tool_calls = false
	end
	-- `max_tokens` is the older name; current OpenAI models reject it.
	if turn.maxTokens then body.max_completion_tokens = turn.maxTokens end
	return body
end

--- The neutral reply ({text, calls}) in a decoded response body, or nil
--- and the service's error message.
function ChatCompletions.reply(status, body, decode)
	if type(body) ~= "table" then return nil, "HTTP " .. tostring(status) .. ": no JSON body" end
	if body.error then
		local detail = type(body.error) == "table" and body.error.message or tostring(body.error)
		return nil, "HTTP " .. tostring(status) .. ": " .. tostring(detail)
	end
	local choice = type(body.choices) == "table" and body.choices[1]
	local message = type(choice) == "table" and choice.message
	if type(message) ~= "table" then return nil, "HTTP " .. tostring(status) .. ": no assistant message" end
	local reply = { text = type(message.content) == "string" and message.content or nil, calls = {} }
	for _, call in ipairs(message.tool_calls or {}) do
		local fn = type(call) == "table" and call["function"] or nil
		if type(fn) ~= "table" or type(call.id) ~= "string" or type(fn.name) ~= "string" then
			return nil, "The reply carried a malformed tool call"
		end
		local ok, arguments = pcall(decode, fn.arguments or "{}")
		if not ok or type(arguments) ~= "table" then return nil, "Tool arguments for " .. fn.name .. " are not JSON" end
		table.insert(reply.calls, { id = call.id, name = fn.name, arguments = arguments })
	end
	return reply
end

return ChatCompletions
