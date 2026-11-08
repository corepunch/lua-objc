-- JSON encoding for Appwrite request bodies.
--
-- The native encoder (`_jsonEncode`) turns every empty Lua table into `[]`
-- and has no way to write `null`; Appwrite needs both: `{"data": {}}` for a
-- row with no fields, `null` to clear an optional column. This encoder is
-- the small pure-Lua answer: `Json.object(t)` marks a table to encode as an
-- object even when empty, `Json.null` encodes as `null`. Object keys are
-- sorted so a request is the same bytes every time (tests compare them).
-- Decoding stays native (`ns.json_parse`), injected by the caller.
local Json = {}

Json.null = setmetatable({}, {__tostring = function() return "null" end})

local objects = setmetatable({}, {__mode = "k"})

-- Marks `t` (a new table when nil) to encode as an object, and returns it.
function Json.object(t)
	t = t or {}
	objects[t] = true
	return t
end

local escapes = {
	['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
	["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

local function quote(text)
	return '"' .. (text:gsub('[%c"\\]', function(c)
		return escapes[c] or string.format("\\u%04x", c:byte())
	end)) .. '"'
end

local function isArray(t)
	if objects[t] then return false end
	local count = 0
	for key in pairs(t) do
		if math.type(key) ~= "integer" or key < 1 then return false end
		count = count + 1
	end
	return count == #t
end

local encode

local function encodeTable(t, seen)
	if seen[t] then error("JSON cannot encode a table that contains itself", 0) end
	seen[t] = true
	local parts = {}
	if isArray(t) then
		for _, value in ipairs(t) do table.insert(parts, (encode(value, seen))) end
		seen[t] = nil
		return "[" .. table.concat(parts, ",") .. "]"
	end
	local keys = {}
	for key in pairs(t) do
		if type(key) ~= "string" then error("JSON object keys must be strings", 0) end
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		table.insert(parts, quote(key) .. ":" .. encode(t[key], seen))
	end
	seen[t] = nil
	return "{" .. table.concat(parts, ",") .. "}"
end

encode = function(value, seen)
	if value == Json.null or value == nil then return "null" end
	local kind = type(value)
	if kind == "string" then return quote(value) end
	if kind == "boolean" then return value and "true" or "false" end
	if kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			error("JSON cannot encode " .. tostring(value), 0)
		end
		if math.type(value) == "integer" then return string.format("%d", value) end
		return string.format("%.17g", value)
	end
	if kind == "table" then return encodeTable(value, seen) end
	error("JSON cannot encode a " .. kind, 0)
end

function Json.encode(value)
	return encode(value, {})
end

return Json
