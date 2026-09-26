-- One JSON document in the platform's local document store (the app sandbox
-- on iOS, Application Support on the Mac): the library's autosaves and the
-- reader's preferences. A missing or unreadable file is an empty document,
-- never an error, so a first launch and a damaged file behave the same.
local JsonDocument = {}

function JsonDocument.new(ns, name)
	assert(type(name) == "string" and name ~= "", "document name is required")
	return {
		load = function()
			if type(ns._documentRead) ~= "function" then return nil end
			local ok, body = pcall(ns._documentRead, name)
			if not ok or type(body) ~= "string" or body == "" then return nil end
			local parsed, value = pcall(ns.json_parse, body)
			return parsed and type(value) == "table" and value or nil
		end,
		save = function(value)
			if type(ns._documentWrite) ~= "function" or type(ns._jsonEncode) ~= "function" then return false end
			local ok, body = pcall(ns._jsonEncode, value)
			if not ok or type(body) ~= "string" then return false end
			return (pcall(ns._documentWrite, name, body))
		end,
	}
end

return JsonDocument
