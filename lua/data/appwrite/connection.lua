-- The person's own Appwrite project, connected on this device (docs/backend.md).
-- An app whose `<Backend provider="appwrite" />` names no project keeps its
-- rows there. Nothing is shared: there is no project of ours. The person
-- creates a project on Appwrite Cloud (or their own server), makes an API key
-- for it and enters the endpoint, the project ID and the key once, as they
-- enter the OpenRouter key in Lua Studio's Settings. On a Mac:
--
--   ./lua-objc scripts/appwrite/connect.lua https://fra.cloud.appwrite.io/v1 <project ID>
--
-- The three are one Keychain entry, `appwrite`, a JSON object. The key never
-- reaches the app's rows client: it is sent only by Provision, which creates
-- the app's missing tables at launch, so the rows an app reads and writes are
-- still those its signed-in person may.
--
--   local connection = Connection.keychain(ns)
--   connection:save({endpoint = "https://…/v1", project = "6af…", key = "standard_…"})
--   connection:load() -- {endpoint, project, key} or nil
--
-- `Connection.current(ns)` is what the launcher asks: the connected project
-- and a `provision(config, done)` that holds the key. A host that runs app
-- code it does not trust (Lua Studio's preview) gives that code
-- `ns.appwriteConnection` instead of the Keychain, so the key stays outside it.
local Json = require("data.appwrite.json")
local Client = require("data.appwrite.client")
local Provision = require("data.appwrite.provision")

local Connection = {}
Connection.__index = Connection

Connection.entry = "appwrite"
Connection.endpoint = "https://fra.cloud.appwrite.io/v1"

local function trim(value)
	return type(value) == "string" and value:match("^%s*(.-)%s*$") or ""
end

-- The fields of a connection, trimmed, or nil and what is wrong with them.
function Connection.check(fields)
	local endpoint, project, key = trim(fields.endpoint), trim(fields.project), trim(fields.key)
	if not endpoint:match("^https?://[^%s/]") then
		return nil, "Enter the Appwrite endpoint, such as " .. Connection.endpoint
	end
	if not Client.validId(project) then return nil, "Enter the project ID from the Appwrite console" end
	if key == "" or key:match("%s") then return nil, "Enter an API key of the project" end
	return {endpoint = (endpoint:gsub("/+$", "")), project = project, key = key}
end

-- `secrets` is {read, write, remove} over one stored string and `decode`
-- reads JSON; tests pass a store in memory.
function Connection.new(secrets)
	return setmetatable({secrets = secrets}, Connection)
end

function Connection.keychain(ns)
	return Connection.new({
		read = function() return ns.Credentials.get(Connection.entry) end,
		write = function(value) return ns.Credentials.set(Connection.entry, value) end,
		remove = function() return ns.Credentials.remove(Connection.entry) end,
		decode = ns.json_parse,
	})
end

-- The saved connection, or nil when there is none or it no longer reads.
function Connection:load()
	local stored = self.secrets.read()
	if type(stored) ~= "string" or stored == "" then return nil end
	local ok, value = pcall(self.secrets.decode, stored)
	if not ok or type(value) ~= "table" then return nil end
	return Connection.check(value)
end

function Connection:save(fields)
	local connection, message = Connection.check(fields)
	if not connection then return nil, message end
	local ok, err = self.secrets.write(Json.encode(Json.object(connection)))
	if not ok then return nil, err or "The Keychain refused the connection" end
	return connection
end

function Connection:clear()
	return self.secrets.remove()
end

-- The client that carries the API key: provisioning only.
function Connection.keyClient(connection, http, decode)
	local client = Client.new({endpoint = connection.endpoint, project = connection.project, http = http, decode = decode})
	client.credential = {name = "X-Appwrite-Key", value = connection.key}
	return client
end

-- What the launcher uses: {endpoint, project, provision(config, done)}, or
-- nil and how to connect one.
function Connection.current(ns)
	if ns.appwriteConnection then return ns.appwriteConnection() end
	local connection = Connection.keychain(ns):load()
	if not connection then
		return nil, "This app keeps its data in your own Appwrite project, and none is connected. "
			.. "Create a project and an API key at cloud.appwrite.io, then run "
			.. "./lua-objc scripts/appwrite/connect.lua " .. Connection.endpoint .. " <project ID>"
	end
	return Connection.provider(connection, ns.http, ns.json_parse, ns._timerAfter)
end

-- A connection as the launcher sees it: the key is inside `provision`.
function Connection.provider(connection, http, decode, after)
	return {
		endpoint = connection.endpoint,
		project = connection.project,
		provision = function(config, done)
			Provision.run({client = Connection.keyClient(connection, http, decode), config = config, after = after}, done)
		end,
	}
end

return Connection
