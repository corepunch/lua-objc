-- OpenAI: chat completions, the dialect the host API carries as
-- `host.chat`. This file is the pattern for any gateway that speaks it.
return {
	api = 1,
	title = "OpenAI",
	symbol = "brain",
	website = "https://platform.openai.com/api-keys",
	keyPrefix = "sk-",
	models = {
		{ id = "gpt-5.2", title = "GPT-5.2" },
		{ id = "gpt-5.1", title = "GPT-5.1" },
		{ id = "gpt-5-mini", title = "GPT-5 mini" },
	},
	defaultModel = "gpt-5.2",
	request = function(host, turn, key)
		return {
			url = "https://api.openai.com/v1/chat/completions",
			headers = { Authorization = "Bearer " .. key, ["Content-Type"] = "application/json" },
			body = host.chat.request(turn),
		}
	end,
	reply = function(host, status, body)
		return host.chat.reply(status, body)
	end,
}
