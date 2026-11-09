-- The person's own Appwrite project (lua/data/appwrite/connection.lua) and
-- the tables created there at launch (lua/data/appwrite/provision.lua), over
-- a recording transport: no network, no Keychain.
_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local Connection = require("data.appwrite.connection")
local Provision = require("data.appwrite.provision")
local Schema = require("data.appwrite.schema")
local Backend = require("data.backend")
local Account = require("data.appwrite.account")
local Model = require("data.model")
local App = require("data.app")
local Mock = require("tests.support.appwrite")

local ENDPOINT = "https://fra.cloud.appwrite.io/v1"

-- Checking what the person typed.
local function refused(fields, fragment, label)
	local ok, message = Connection.check(fields)
	t.expect(ok == nil and tostring(message):find(fragment, 1, true) ~= nil, label .. ": " .. tostring(message))
end
refused({project = "p", key = "k"}, "endpoint", "an endpoint is needed")
refused({endpoint = "fra.cloud.appwrite.io", project = "p", key = "k"}, "endpoint", "the endpoint is a URL")
refused({endpoint = ENDPOINT, project = "a/b", key = "k"}, "project ID", "a project ID is one segment")
refused({endpoint = ENDPOINT, project = "p", key = "  "}, "API key", "a key is needed")
refused({endpoint = ENDPOINT, project = "p", key = "two words"}, "API key", "a key has no spaces")
local checked = Connection.check({endpoint = " " .. ENDPOINT .. "/ ", project = " proj1 ", key = " standard_abc\n"})
t.expect(checked and checked.endpoint == ENDPOINT and checked.project == "proj1" and checked.key == "standard_abc",
	"fields are trimmed and the endpoint loses its trailing slash")

-- One Keychain entry, a JSON object.
local secrets = Mock.secrets()
secrets.decode = ns.json_parse
local connection = Connection.new(secrets)
t.assertEqual(connection:load(), nil, "nothing is connected at first")
t.expect(select(2, connection:save({endpoint = ENDPOINT, project = "", key = "k"})) ~= nil, "a bad connection is not saved")
t.assertEqual(secrets.writes, 0, "and nothing is written")
t.expect(connection:save({endpoint = ENDPOINT, project = "proj1", key = "standard_abc"}), "a connection is saved")
local stored = ns.json_parse(secrets.value)
t.expect(stored.endpoint == ENDPOINT and stored.project == "proj1" and stored.key == "standard_abc", "as one JSON object")
local loaded = connection:load()
t.expect(loaded and loaded.project == "proj1" and loaded.key == "standard_abc", "and read back")
secrets.value = "{not json"
t.assertEqual(connection:load(), nil, "an entry that no longer reads is no connection")
connection:clear()
t.assertEqual(secrets.value, nil, "clearing removes the entry")

-- The key is a header of the provisioning client only.
local mock = Mock.new({project = "proj1"})
local keyClient = Connection.keyClient({endpoint = ENDPOINT, project = "proj1", key = "standard_abc"}, mock.http, ns.json_parse)
mock.answer({status = 200, body = {}})
keyClient:call({path = "/tablesdb/x"}, function() end)
t.assertEqual(mock.last().headers["X-Appwrite-Key"], "standard_abc", "provisioning sends the API key")
t.assertEqual(mock.last().headers["X-Appwrite-Project"], "proj1", "to the connected project")

-- A host that runs untrusted code hands the launcher its own connection.
local saved = ns.appwriteConnection
ns.appwriteConnection = function() return {endpoint = ENDPOINT, project = "hosted"} end
t.assertEqual(Connection.current(ns).project, "hosted", "the host's connection comes first")
ns.appwriteConnection = function() return nil, "Connect your Appwrite project in Settings" end
local none, message = Connection.current(ns)
t.expect(none == nil and message:find("Settings", 1, true), "and so does its message")
ns.appwriteConnection = saved

-- Provisioning a project that has nothing yet.
local Items = Model:extend("provision_items", {
	remote = "private",
	fields = {
		title = "string(64)", body = "text?", score = {"float?", min = 0}, kind = "enum(a|b)",
		count = {"integer?", default = 0}, mail = "email?",
	},
	indexes = {{"kind", "createdAt desc"}},
})
local config = Schema.config({project = "proj1", endpoint = ENDPOINT, database = "shop", models = {Items}})
local waits = {}
local function after(seconds, fn) table.insert(waits, seconds); fn() end
local notFound = {status = 404, body = {type = "database_not_found", message = "Database not found"}}
local function columns(list) return {status = 200, body = {total = #list, columns = list}} end

mock = Mock.new({project = "proj1"})
local client = Connection.keyClient({endpoint = ENDPOINT, project = "proj1", key = "k"}, mock.http, ns.json_parse)
mock.answer(notFound)                           -- GET database
mock.answer({status = 201, body = {}})          -- create database
mock.answer({status = 404, body = {type = "table_not_found", message = "Table not found"}})
mock.answer({status = 201, body = {}})          -- create table
mock.answer(columns({}))                        -- a new table has no columns
for _ = 1, 6 do mock.answer({status = 202, body = {}}) end
local building = {}
for _, key in ipairs({"body", "count", "kind", "mail", "score", "title"}) do table.insert(building, {key = key, status = "processing"}) end
mock.answer(columns(building))                  -- still being built
local built = {}
for _, key in ipairs({"body", "count", "kind", "mail", "score", "title"}) do table.insert(built, {key = key, status = "available"}) end
mock.answer(columns(built))
mock.answer({status = 200, body = {total = 0, indexes = {}}})
mock.answer({status = 202, body = {}})          -- create index
local result = "pending"
Provision.run({client = client, config = config, after = after}, function(err) result = err or "done" end)
t.assertEqual(result, "done", "a project with nothing yet is provisioned")
t.assertEqual(#mock.answers, 0, "with every request answered")
local requests = {}
for _, request in ipairs(mock.sent) do table.insert(requests, request.method .. " " .. request.url:gsub("%?.*$", "")) end
local base = ENDPOINT .. "/tablesdb"
t.assertEqual(requests[1], "GET " .. base .. "/shop", "it asks for the database")
t.assertEqual(requests[2], "POST " .. base, "and creates it")
t.assertEqual(ns.json_parse(mock.sent[2].body).databaseId, "shop", "named after the app")
t.assertEqual(requests[4], "POST " .. base .. "/shop/tables", "then the table")
local tableBody = ns.json_parse(mock.sent[4].body)
t.expect(tableBody.tableId == "provision_items" and tableBody.rowSecurity == true
	and tableBody.permissions[1] == 'create("users")', "with row security and the users' create permission")
local paths = {}
for index = 6, 11 do paths[ns.json_parse(mock.sent[index].body).key] = requests[index]:match("/columns/(%a+)$") end
t.expect(paths.title == "varchar" and paths.body == "text" and paths.score == "float" and paths.kind == "enum"
	and paths.count == "integer" and paths.mail == "email", "each column goes to the endpoint of its type")
local title = ns.json_parse(mock.sent[6].body)
for index = 6, 11 do
	local body = ns.json_parse(mock.sent[index].body)
	if body.key == "title" then title = body end
	if body.key == "kind" then t.expect(body.elements[1] == "a" and body.elements[2] == "b", "an enum sends its elements") end
	if body.key == "count" then t.expect(body.default == 0 and body.required == false, "an optional column sends its default") end
end
t.expect(title.size == 64 and title.required == true and title.array == false, "a varchar sends its size")
t.assertEqual(#waits, 1, "it waits once while the columns are built")
t.assertEqual(waits[1], Provision.wait.seconds, "for the named interval")
local indexBody = ns.json_parse(mock.sent[#mock.sent].body)
t.expect(indexBody.key == "idx_kind_createdAt" or indexBody.columns[1] == "kind", "then it creates the index: " .. tostring(indexBody.key))
t.assertEqual(indexBody.columns[2], "$createdAt", "system columns keep their Appwrite names")

-- A project that has everything: one request for the database, two per table.
mock = Mock.new({project = "proj1"})
client = Connection.keyClient({endpoint = ENDPOINT, project = "proj1", key = "k"}, mock.http, ns.json_parse)
mock.answer({status = 200, body = {}})
mock.answer({status = 200, body = {}})
mock.answer(columns(built))
mock.answer({status = 200, body = {total = 1, indexes = {{key = indexBody.key}}}})
result, waits = "pending", {}
Provision.run({client = client, config = config, after = after}, function(err) result = err or "done" end)
t.assertEqual(result, "done", "nothing missing is nothing to do")
t.assertEqual(#mock.sent, 4, "and costs four requests")
t.assertEqual(#waits, 0, "without waiting")

-- A key without the scopes: the error names what was being done.
mock = Mock.new({project = "proj1"})
client = Connection.keyClient({endpoint = ENDPOINT, project = "proj1", key = "k"}, mock.http, ns.json_parse)
mock.answer({status = 401, body = {type = "general_unauthorized_scope", message = "Missing scope (databases.read)"}})
Provision.run({client = client, config = config, after = after}, function(err) result = err end)
t.expect(type(result) == "table" and result.status == 401 and result.message:find("database shop", 1, true)
	and result.message:find("databases.read", 1, true), "a refused key reports the step and Appwrite's reason")

-- A column Appwrite could not build stops provisioning.
mock = Mock.new({project = "proj1"})
client = Connection.keyClient({endpoint = ENDPOINT, project = "proj1", key = "k"}, mock.http, ns.json_parse)
mock.answer({status = 200, body = {}})
mock.answer({status = 200, body = {}})
local partial = {}
for _, column in ipairs(built) do if column.key ~= "title" then table.insert(partial, column) end end
mock.answer(columns(partial))
mock.answer({status = 202, body = {}})
mock.answer(columns({{key = "title", status = "failed"}}))
Provision.run({client = client, config = config, after = after}, function(err) result = err end)
t.expect(type(result) == "table" and result.type == "column_failed" and result.message:find("title", 1, true),
	"a failed column is reported")
t.assertEqual(ns.json_parse(mock.sent[4].body).key, "title", "only the missing column is created")

-- The launcher: a <Backend> without a project uses the connection, and the
-- backend provisions before the account opens.
local provisioned
ns.appwriteConnection = function()
	return {endpoint = ENDPOINT, project = "hosted", provision = function(schema, done) provisioned = schema; done(nil) end}
end
local backend = App.backend({provider = "appwrite", connected = true, database = "shop"})
ns.appwriteConnection = saved
t.assertEqual(backend.client.project, "hosted", "the rows go to the connected project")
t.assertEqual(backend.client.credential, nil, "and the rows client carries no API key")
t.expect(type(backend.provision) == "function", "the connected project is provisioned")
backend.provision(function() end)
t.expect(provisioned and provisioned.projectId == "hosted" and provisioned.tablesDB[1]["$id"] == "shop",
	"with the schema of the app's models")
t.assertEqual(App.backend({provider = "appwrite", endpoint = ENDPOINT, project = "own", database = "shop"}).provision, nil,
	"an app's own project is never provisioned from the app")
ns.appwriteConnection = function() return nil, "Connect your Appwrite project in Settings" end
local ok, err = pcall(App.backend, {provider = "appwrite", connected = true, database = "shop"})
ns.appwriteConnection = saved
t.expect(not ok and tostring(err):find("Settings", 1, true), "without a connection the app does not start, and says why")

-- A refused provisioning is reported; the account opens all the same.
mock = Mock.new()
local order, reported = {}, nil
backend = Backend.new({client = mock.client, account = Account.new(mock.client, Mock.secrets()), database = "shop",
	provision = function(done) table.insert(order, "provision"); done({message = "Missing scope (tables.write)"}) end})
backend.changed = function(text) reported = text end
mock.answer({status = 201, headers = {["set-cookie"] = "a_session_lua-objc-dev=s; path=/"}, body = {secret = ""}})
mock.answer({status = 200, body = {["$id"] = "u1"}})
backend:start(function() table.insert(order, "account") end)
t.expect(order[1] == "provision" and order[2] == "account", "provisioning runs before the account opens")
t.assertEqual(reported, "Missing scope (tables.write)", "and its refusal reaches the page")
t.expect(backend.account.user and backend.account.user.id == "u1", "the account opened anyway")

os.exit(t.summary() and 0 or 1)
