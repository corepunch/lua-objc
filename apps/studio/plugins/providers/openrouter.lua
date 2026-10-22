-- OpenRouter: one key for many models, through the OpenAI dialect. The
-- model id names the upstream model ("anthropic/claude-sonnet-4.5").
return {
	api = 1,
	title = "OpenRouter",
	symbol = "arrow.triangle.branch",
	website = "https://openrouter.ai/keys",
	keyPrefix = "sk-or-",
	models = {
		{ id = "openrouter/auto", title = "Auto (best for the request)" },
		{ id = "anthropic/claude-sonnet-4.5", title = "Claude Sonnet 4.5" },
		{ id = "openai/gpt-5", title = "GPT-5" },
		{ id = "google/gemini-2.5-flash", title = "Gemini 2.5 Flash" },
	},
	defaultModel = "openrouter/auto",
	request = function(host, turn, key)
		return {
			url = "https://openrouter.ai/api/v1/chat/completions",
			headers = {
				Authorization = "Bearer " .. key,
				["Content-Type"] = "application/json",
				["HTTP-Referer"] = "https://github.com/corepunch/lua-objc",
				["X-Title"] = "Lua Studio",
			},
			body = host.chat.request(turn),
		}
	end,
	reply = function(host, status, body)
		return host.chat.reply(status, body)
	end,
}
