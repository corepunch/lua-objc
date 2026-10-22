-- The iPad's services as the controller injects them: JSON, HTTPS, the
-- Documents folder and the keychain, all from the platform module.
local Device = {}

function Device.new(ns)
	local json = { encode = ns._jsonEncode, decode = ns.json_parse }
	return {
		json = json,
		keychain = ns,
		documents = {
			list = function(folder) return ns._documentList(folder) end,
			read = function(path) return ns._documentRead(path) end,
		},
		-- One POST; `completion(body, err, status)`. Returns a cancel function.
		http = function(request, completion)
			local task = ns._httpRequest(request.url, request.headers, request.body, completion)
			return function() ns._cancelRequest(task) end
		end,
	}
end

return Device
