-- Google Gemini: generateContent. The model is part of the URL, tools are
-- function declarations, and a call is answered by a functionResponse part
-- named after the function; Gemini gives calls no id, so this plugin
-- numbers them.
local BASE = "https://generativelanguage.googleapis.com/v1beta/models/"

local function contents(turn)
	local result = {}
	for _, message in ipairs(turn.messages) do
		if message.role == "user" then
			table.insert(result, { role = "user", parts = { { text = message.text } } })
		elseif message.role == "assistant" then
			local parts = {}
			if message.text and message.text ~= "" then table.insert(parts, { text = message.text }) end
			for _, call in ipairs(message.calls or {}) do
				table.insert(parts, { functionCall = { name = call.name, args = call.arguments or {} } })
			end
			table.insert(result, { role = "model", parts = parts })
		elseif message.role == "tool" then
			local part = { functionResponse = { name = message.name, response = { result = message.result } } }
			local last = result[#result]
			if last and last.role == "user" and last.parts[1] and last.parts[1].functionResponse then
				table.insert(last.parts, part)
			else
				table.insert(result, { role = "user", parts = { part } })
			end
		end
	end
	return result
end

return {
	api = 1,
	title = "Google Gemini",
	symbol = "diamond",
	website = "https://aistudio.google.com/app/apikey",
	keyPrefix = "AIza",
	models = {
		{ id = "gemini-2.5-pro", title = "Gemini 2.5 Pro" },
		{ id = "gemini-2.5-flash", title = "Gemini 2.5 Flash" },
	},
	defaultModel = "gemini-2.5-flash",
	request = function(_, turn, key)
		local body = { contents = contents(turn), generationConfig = { maxOutputTokens = turn.maxTokens or 8192 } }
		if turn.system and turn.system ~= "" then body.systemInstruction = { parts = { { text = turn.system } } } end
		if turn.tools and #turn.tools > 0 then
			local declarations = {}
			for _, tool in ipairs(turn.tools) do
				table.insert(declarations, { name = tool.name, description = tool.description, parameters = tool.parameters })
			end
			body.tools = { { functionDeclarations = declarations } }
		end
		return {
			url = BASE .. turn.model .. ":generateContent",
			headers = { ["x-goog-api-key"] = key, ["Content-Type"] = "application/json" },
			body = body,
		}
	end,
	reply = function(_, status, body)
		if type(body) ~= "table" then return nil, "HTTP " .. tostring(status) .. ": no JSON body" end
		if body.error then
			local detail = type(body.error) == "table" and body.error.message or tostring(body.error)
			return nil, "HTTP " .. tostring(status) .. ": " .. tostring(detail)
		end
		local candidate = type(body.candidates) == "table" and body.candidates[1]
		local content = type(candidate) == "table" and candidate.content
		if type(content) ~= "table" or type(content.parts) ~= "table" then
			return nil, "HTTP " .. tostring(status) .. ": no candidate content"
		end
		local texts, calls = {}, {}
		for index, part in ipairs(content.parts) do
			if type(part.text) == "string" then
				table.insert(texts, part.text)
			elseif type(part.functionCall) == "table" then
				local call = part.functionCall
				if type(call.name) ~= "string" then return nil, "The reply carried a malformed tool call" end
				table.insert(calls, { id = call.name .. "#" .. index, name = call.name,
					arguments = type(call.args) == "table" and call.args or {} })
			end
		end
		return { text = #texts > 0 and table.concat(texts, "\n") or nil, calls = calls }
	end,
}
