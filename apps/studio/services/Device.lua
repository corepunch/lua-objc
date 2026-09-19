local Device = {}
function Device.new(ns)
	local json = { encode = ns._jsonEncode, decode = ns.json_parse }
	return {
		json = json,
		storage = {
			load = function()
				local source = ns._documentRead("playground.json")
				if not source then return nil end
				return json.decode(source)
			end,
			save = function(value) return ns._documentWrite("playground.json", json.encode(value)) end,
		},
		transport = function(payload, key, completion)
			local request = ns._httpRequest("https://openrouter.ai/api/v1/chat/completions", {
				Authorization = "Bearer " .. key, ["Content-Type"] = "application/json", ["X-Title"] = "Lua Studio",
			}, json.encode(payload), function(body, err, status)
				if err then completion(nil, err); return end
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
