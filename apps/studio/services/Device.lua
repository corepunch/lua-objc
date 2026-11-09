local Connection = require("data.appwrite.connection")
local Device = {}
local function providerError(status, detail)
	local hints = {
		[401] = "Check your API key in Settings.",
		[402] = "Check your OpenRouter credits or choose a free model in Settings.",
		[404] = "Choose an available provider/model in Settings.",
		[429] = "Try again later or choose another model in Settings.",
	}
	local hint = hints[status] or "Try again or choose another model in Settings."
	return "OpenRouter HTTP " .. status .. ": " .. detail .. ". " .. hint
end
function Device.new(ns)
	local ok, speech = pcall(require, "Speech")
	local json = { encode = ns._jsonEncode, decode = ns.json_parse }
	return {
		json = json,
		-- Framework and shared asset files bundled with Studio (asset kit manifests).
		readFramework = ns._readFile,
		github = {
			credentials = {
				read = function() return ns.Credentials.get("github") end,
				save = function(key) return ns.Credentials.set("github", key) end,
				clear = function() return ns.Credentials.remove("github") end,
			},
			request = function(method, path, token, body, completion)
				return ns.http({method = method, url = "https://api.github.com" .. path, headers = {
					Authorization = "Bearer " .. token, Accept = "application/vnd.github+json", ["User-Agent"] = "Lua-Studio",
					["Content-Type"] = "application/json", ["X-GitHub-Api-Version"] = "2022-11-28",
				}, body = body and json.encode(body) or nil}, function(response, err)
					if err then completion(nil, err); return end
					local status = response.status
					local ok, result = pcall(json.decode, response.body)
					if not ok or type(result) ~= "table" then completion(nil, "GitHub returned invalid JSON"); return end
					if status < 200 or status >= 300 then
						completion(nil, "GitHub HTTP " .. status .. ": " .. tostring(result.message or "Request failed")); return
					end
					completion(result)
				end)
			end,
		},
		-- The person's own Appwrite project for apps that keep data online:
		-- the Keychain entry the framework reads (data.appwrite.connection).
		appwrite = Connection.keychain(ns),
		speech = ok and speech or nil,
		importText = ns.importTextFiles,
		credentials = {
			read = function() return ns.Credentials.get("openrouter") end,
			save = function(key)
				if type(key) ~= "string" or not key:match("%S") then return nil, "Enter an OpenRouter API key" end
				return ns.Credentials.set("openrouter", key:match("^%s*(.-)%s*$"))
			end,
			clear = function() return ns.Credentials.remove("openrouter") end,
		},
		transport = function(payload, key, completion)
			return ns.http({method = "POST", url = "https://openrouter.ai/api/v1/chat/completions", headers = {
				Authorization = "Bearer " .. key, ["Content-Type"] = "application/json", ["X-Title"] = "Lua Studio",
			}, body = json.encode(payload)}, function(response, err)
				if err then completion(nil, "OpenRouter request failed: " .. tostring(err) .. ". Try again or choose another model in Settings."); return end
				local status = response.status
				local ok, result = pcall(json.decode, response.body)
				local decoded = ok and type(result) == "table"
				if status < 200 or status >= 300 or (decoded and result.error) then
					local detail = decoded and result.error
					if type(detail) == "table" then detail = detail.message end
					completion(nil, providerError(status, type(detail) == "string" and detail or "Request failed")); return
				end
				if not decoded then completion(nil, "OpenRouter returned invalid JSON (HTTP " .. status .. "). Try again or choose another model in Settings."); return end
				completion(result)
			end)
		end,
	}
end
return Device
