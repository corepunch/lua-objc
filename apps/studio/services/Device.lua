local Device = {}
function Device.new(ns)
	local ok, speech = pcall(require, "Speech")
	local json = { encode = ns._jsonEncode, decode = ns.json_parse }
	return {
		json = json,
		github = {
			credentials = {
				read = function() return ns.Credentials.get("github") end,
				save = function(key) return ns.Credentials.set("github", key) end,
				clear = function() return ns.Credentials.remove("github") end,
			},
			request = function(method, path, token, body, completion)
				local request = ns._httpRequest("https://api.github.com" .. path, {
					Authorization = "Bearer " .. token, Accept = "application/vnd.github+json", ["User-Agent"] = "Lua-Studio",
					["Content-Type"] = "application/json", ["X-GitHub-Api-Version"] = "2022-11-28",
				}, body and json.encode(body) or "", function(source, err, status)
					if err then completion(nil, err); return end
					local ok, result = pcall(json.decode, source or "")
					if not ok or type(result) ~= "table" then completion(nil, "GitHub returned invalid JSON"); return end
					if status < 200 or status >= 300 then
						completion(nil, "GitHub HTTP " .. status .. ": " .. tostring(result.message or "Request failed")); return
					end
					completion(result)
				end, method)
				return function() ns._cancelRequest(request) end
			end,
		},
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
			local request = ns._httpRequest("https://openrouter.ai/api/v1/chat/completions", {
				Authorization = "Bearer " .. key, ["Content-Type"] = "application/json", ["X-Title"] = "Lua Studio",
			}, json.encode(payload), function(body, err, status)
				if err then completion(nil, err); return end
				status = tonumber(status) or 0
				local ok, result = pcall(json.decode, body or "")
				if not ok or type(result) ~= "table" then completion(nil, "OpenRouter returned invalid JSON (HTTP " .. status .. ")"); return end
				if status < 200 or status >= 300 or result.error then
					local detail = type(result.error) == "table" and result.error.message or "Request failed"
					completion(nil, "OpenRouter HTTP " .. status .. ": " .. tostring(detail)); return
				end
				completion(result)
			end)
			return function() ns._cancelRequest(request) end
		end,
	}
end
return Device
