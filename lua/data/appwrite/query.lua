-- Appwrite query values, ported from orca's plugins/appwrite/query.lua.
-- Each is the JSON object Appwrite reads from a `queries[]` parameter:
-- `{method, attribute, values}`.
local Json = require("data.appwrite.json")

local function make(method, attribute, ...)
	return Json.object({method = method, attribute = attribute, values = {...}})
end

local Query = {
	equal = function(attribute, value, ...) return make("equal", attribute, value, ...) end,
	notEqual = function(attribute, value, ...) return make("notEqual", attribute, value, ...) end,
	lessThan = function(attribute, value) return make("lessThan", attribute, value) end,
	lessThanEqual = function(attribute, value) return make("lessThanEqual", attribute, value) end,
	greaterThan = function(attribute, value) return make("greaterThan", attribute, value) end,
	greaterThanEqual = function(attribute, value) return make("greaterThanEqual", attribute, value) end,
	between = function(attribute, a, b) return make("between", attribute, a, b) end,
	startsWith = function(attribute, value) return make("startsWith", attribute, value) end,
	endsWith = function(attribute, value) return make("endsWith", attribute, value) end,
	contains = function(attribute, value) return make("contains", attribute, value) end,
	search = function(attribute, value) return make("search", attribute, value) end,
	isNull = function(attribute) return make("isNull", attribute) end,
	isNotNull = function(attribute) return make("isNotNull", attribute) end,
	orderAsc = function(attribute) return make("orderAsc", attribute) end,
	orderDesc = function(attribute) return make("orderDesc", attribute) end,
	cursorBefore = function(id) return make("cursorBefore", nil, id) end,
	cursorAfter = function(id) return make("cursorAfter", nil, id) end,
	limit = function(count) return make("limit", nil, count) end,
	offset = function(count) return make("offset", nil, count) end,
	select = function(attribute, ...) return make("select", nil, attribute, ...) end,
	-- `and`/`or` take queries; their values are the queries themselves.
	all = function(...) return make("and", nil, ...) end,
	any = function(...) return make("or", nil, ...) end,
}

local function escape(text)
	return (text:gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", c:byte()) end))
end

-- The query string of a list of queries: `queries[0]=…&queries[1]=…`, empty
-- for none.
function Query.encode(queries)
	local params = {}
	for index, query in ipairs(queries or {}) do
		table.insert(params, "queries[" .. (index - 1) .. "]=" .. escape(Json.encode(query)))
	end
	return table.concat(params, "&")
end

Query.escape = escape

return Query
