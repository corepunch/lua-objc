-- A page's location, written as a browser writes a URL: the page id, then
-- the page's own argument, then the rest of its params as a query.
--
--   /overview
--   /help/shortcuts               <Page id="help" arg="topic">     {topic = "shortcuts"}
--   /files/video                  <Page id="files" arg="kind">     {kind = "video"}
--   /folder//Users/me/Downloads   <Page id="folder" arg="path">    {path = "/Users/me/Downloads"}
--   /folder//a?focus=%2Fa%2Fb     <Page id="folder" arg="path">    {path = "/a", focus = "/a/b"}
--
-- The argument keeps its slashes, so a folder path reads as itself after the
-- one that separates it from the page. History holds these strings: two
-- visits are one place when their strings are equal, and the query is sorted
-- by name so that they are. Values come back as strings.
local Location = {}

local function encode(value, keepSlash)
	return (tostring(value):gsub("[^%w%-%._~" .. (keepSlash and "/" or "") .. "]", function(c)
		return string.format("%%%02X", c:byte())
	end))
end
local function decode(value)
	return (value:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

-- The location of `page` (a manifest entry) showing `params`.
function Location.format(page, params)
	local arg = page.attrs and page.attrs.arg
	local text = "/" .. page.id
	if arg and params and params[arg] ~= nil then text = text .. "/" .. encode(params[arg], true) end
	local names = {}
	for name in pairs(params or {}) do
		if name ~= arg then table.insert(names, name) end
	end
	table.sort(names)
	local query = {}
	for _, name in ipairs(names) do table.insert(query, encode(name) .. "=" .. encode(params[name])) end
	if #query > 0 then text = text .. "?" .. table.concat(query, "&") end
	return text
end

-- The page id and params a location names; `pages` is the manifest's pages
-- by id. A location of no page is an error.
function Location.parse(text, pages)
	local path, query = tostring(text):match("^([^?]*)%??(.*)$")
	local id, rest = path:match("^/([^/]+)/?(.*)$")
	local page = id and pages[id]
	if not page then error("Unknown page location: " .. tostring(text), 0) end
	local params = {}
	local arg = page.attrs and page.attrs.arg
	if rest ~= "" or path:match("^/[^/]+/$") then
		if not arg then error("Page " .. id .. " takes no argument: " .. tostring(text), 0) end
		params[arg] = decode(rest)
	end
	for pair in query:gmatch("[^&]+") do
		local name, value = pair:match("^([^=]*)=?(.*)$")
		params[decode(name)] = decode(value)
	end
	return id, params
end

return Location
