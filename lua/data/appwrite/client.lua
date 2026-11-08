-- One Appwrite project over HTTP: the endpoint, the project header, the
-- signed-in credential, JSON both ways and one error shape.
--
--   local client = Client.new({
--   	endpoint = "https://fra.cloud.appwrite.io/v1", project = "69f1…",
--   	http = ns.http, decode = ns.json_parse,
--   })
--   client:call({method = "GET", path = "/account"}, function(value, err, response) end)
--
-- `http` and `decode` are injected: the data layer never touches `ns`, and
-- tests pass a recording transport. `call` answers once, from the transport's
-- callback: `done(value, nil, response)` for a 2xx (value is the decoded
-- body, or true when there is none), `done(nil, err, response)` otherwise.
-- `err` is always `{type, message, status}`: `type` is Appwrite's stable
-- error ID (`user_unauthorized`, `row_not_found`…) or ours: `network` when
-- no answer arrived, `invalid_response` when a 2xx body is not JSON.
local Json = require("data.appwrite.json")
local Query = require("data.appwrite.query")

local Client = {}
Client.__index = Client

function Client.new(options)
	assert(type(options) == "table", "Client.new needs options")
	assert(type(options.endpoint) == "string" and options.endpoint:match("^https?://"),
		"an Appwrite client needs an http(s) endpoint")
	assert(type(options.project) == "string" and options.project ~= "", "an Appwrite client needs a project")
	assert(type(options.http) == "function", "an Appwrite client needs an http transport")
	assert(type(options.decode) == "function", "an Appwrite client needs a JSON decoder")
	return setmetatable({
		endpoint = (options.endpoint:gsub("/+$", "")),
		project = options.project,
		http = options.http,
		decode = options.decode,
		-- {name = header, value = value}: set by Account once a session exists.
		credential = nil,
	}, Client)
end

-- IDs Appwrite accepts for databases, tables, rows and users; checking them
-- keeps a path segment from being anything but one segment.
function Client.validId(id)
	return type(id) == "string" and #id <= 36 and id:match("^[%w][%w%._%-]*$") ~= nil
end

function Client:url(path, queries)
	local query = Query.encode(queries)
	return self.endpoint .. path .. (query ~= "" and "?" .. query or "")
end

local function failure(kind, message, status)
	return {type = kind, message = message, status = status}
end

-- Sends `request` = {method, path, queries, body}; returns the cancel
-- function of the transport. A cancelled call answers nothing.
function Client:call(request, done)
	local headers = {["X-Appwrite-Project"] = self.project}
	if self.credential then headers[self.credential.name] = self.credential.value end
	local body
	if request.body ~= nil then
		headers["Content-Type"] = "application/json"
		body = Json.encode(request.body)
	end
	return self.http({
		method = request.method or "GET",
		url = self:url(request.path, request.queries),
		headers = headers,
		body = body,
	}, function(response, err)
		if not response then
			done(nil, failure("network", err or "The server could not be reached."))
			return
		end
		local status, text = response.status, response.body or ""
		local ok, value = true, nil
		if text:match("%S") then ok, value = pcall(self.decode, text) end
		if status >= 200 and status < 300 then
			if not ok then
				done(nil, failure("invalid_response", "Appwrite sent a response that is not JSON.", status), response)
			else
				done(value == nil and true or value, nil, response)
			end
			return
		end
		local data = ok and type(value) == "table" and value or {}
		done(nil, failure(data.type or "http_error",
			data.message or ("Appwrite answered HTTP " .. status .. "."), status), response)
	end)
end

return Client
