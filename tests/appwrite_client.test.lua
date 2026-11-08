-- The Appwrite client of lua/data/appwrite: JSON bodies, queries, the error
-- shape and TablesDB rows, over a recording transport (no network).
local t = require("TestKit")
local ns = require("AppKit")
local Json = require("data.appwrite.json")
local Query = require("data.appwrite.query")
local Client = require("data.appwrite.client")
local Rows = require("data.appwrite.rows")
local Mock = require("tests.support.appwrite")

-- JSON: the shapes the native encoder cannot write.
t.assertEqual(Json.encode({}), "[]", "an unmarked empty table is an array")
t.assertEqual(Json.encode(Json.object()), "{}", "a marked empty table is an object")
t.assertEqual(Json.encode({b = 1, a = Json.null}), '{"a":null,"b":1}', "null encodes and keys are sorted")
t.assertEqual(Json.encode({1, "two", true, 2.5}), '[1,"two",true,2.5]', "arrays keep order and types")
t.assertEqual(Json.encode('q"\\\n\1'), '"q\\"\\\\\\n\\u0001"', "strings escape quotes, backslashes and controls")
t.assertEqual(Json.encode("Grüße"), '"Grüße"', "UTF-8 passes through")
t.expect(not pcall(Json.encode, {[1] = "a", [3] = "c"}), "a sparse table is neither array nor object")
t.expect(not pcall(Json.encode, {a = 1, [true] = 1}), "non-string object keys are refused")
t.expect(not pcall(Json.encode, 0 / 0), "NaN is refused")
local loop = {}; loop.self = loop
t.expect(not pcall(Json.encode, loop), "a table containing itself is refused")
t.assertEqual(ns.json_parse(Json.encode({n = 3, list = {1, 2}})).list[2], 2, "the native decoder reads what we encode")

-- Queries: Appwrite's {method, attribute, values} objects.
t.assertEqual(Json.encode(Query.equal("listId", "inbox")), '{"attribute":"listId","method":"equal","values":["inbox"]}',
	"equal names its attribute and values")
t.assertEqual(Json.encode(Query.limit(25)), '{"method":"limit","values":[25]}', "limit has no attribute")
t.assertEqual(Json.encode(Query.isNull("dueAt")), '{"attribute":"dueAt","method":"isNull","values":[]}',
	"a query without values still sends an empty list")
t.assertEqual(Json.encode(Query.any(Query.equal("a", 1), Query.equal("b", 2))),
	'{"method":"or","values":[{"attribute":"a","method":"equal","values":[1]},{"attribute":"b","method":"equal","values":[2]}]}',
	"or nests its queries")
t.assertEqual(Query.encode({}), "", "no queries make no query string")
t.assertEqual(Query.encode({Query.limit(1), Query.orderDesc("dueAt")}),
	"queries[0]=%7B%22method%22%3A%22limit%22%2C%22values%22%3A%5B1%5D%7D&queries[1]="
	.. "%7B%22attribute%22%3A%22dueAt%22%2C%22method%22%3A%22orderDesc%22%2C%22values%22%3A%5B%5D%7D",
	"queries are numbered from zero and URL-encoded")

-- Client: construction and IDs.
t.expect(not pcall(Client.new, {endpoint = "ftp://x", project = "p", http = print, decode = print}), "the endpoint is http(s)")
t.expect(not pcall(Client.new, {endpoint = "https://x/v1", project = "", http = print, decode = print}), "a project is required")
t.expect(Client.validId("notes") and Client.validId("a.b_c-1"), "plain IDs are valid")
t.expect(not Client.validId("../x") and not Client.validId("a/b") and not Client.validId(("a"):rep(37))
	and not Client.validId("") and not Client.validId(7), "path-breaking, long and non-string IDs are not")

-- Client: requests and the error shape.
local mock = Mock.new()
local value, err, response
mock.answer({status = 200, body = {ok = true}})
mock.client:call({path = "/health"}, function(v, e, r) value, err, response = v, e, r end)
local sent = mock.last()
t.assertEqual(sent.url, "https://fra.cloud.appwrite.io/v1/health", "the endpoint loses its trailing slash")
t.assertEqual(sent.method, "GET", "a call is a GET by default")
t.assertEqual(sent.headers["X-Appwrite-Project"], "lua-objc-dev", "every call names the project")
t.assertEqual(sent.headers["Content-Type"], nil, "a call without a body sends no content type")
t.assertEqual(sent.body, nil, "and no body")
t.expect(value.ok == true and err == nil and response.status == 200, "a 2xx answers its decoded body")

mock.answer({status = 204})
mock.client:call({method = "DELETE", path = "/x"}, function(v, e) value, err = v, e end)
t.expect(value == true and err == nil, "an empty 2xx answers true")

mock.answer({status = 401, body = {message = "No session", type = "user_unauthorized", code = 401}})
mock.client:call({path = "/account"}, function(v, e) value, err = v, e end)
t.expect(value == nil and err.type == "user_unauthorized" and err.status == 401 and err.message == "No session",
	"an Appwrite error keeps its type, status and message")

mock.answer({status = 502, body = "<html>Bad gateway</html>"})
mock.client:call({path = "/account"}, function(v, e) value, err = v, e end)
t.expect(err.type == "http_error" and err.status == 502 and err.message:find("502", 1, true),
	"an error that is not JSON still reports its status")

mock.answer({status = 200, body = "not json"})
mock.client:call({path = "/account"}, function(v, e) value, err = v, e end)
t.expect(value == nil and err.type == "invalid_response", "a 2xx that is not JSON is an invalid response")

mock.answer({err = "The Internet connection appears to be offline."})
mock.client:call({path = "/account"}, function(v, e) value, err = v, e end)
t.expect(err.type == "network" and err.message:find("offline", 1, true) and err.status == nil,
	"no answer is a network error with the system's message")

mock.client.credential = {name = "Cookie", value = "a_session_lua-objc-dev=s3cret"}
mock.answer({status = 200, body = {}})
mock.client:call({method = "POST", path = "/x", body = Json.object()}, function() end)
t.assertEqual(mock.last().headers.Cookie, "a_session_lua-objc-dev=s3cret", "the credential rides on every call")
t.assertEqual(mock.last().headers["Content-Type"], "application/json", "a body is JSON")
t.assertEqual(mock.last().body, "{}", "an empty object body stays an object")
mock.client.credential = nil

-- Rows: records, data, IDs and permissions.
local record = Rows.record({["$id"] = "n1", ["$createdAt"] = "2026-11-08T10:00:00.000+00:00",
	["$updatedAt"] = "2026-11-08T11:00:00.000+00:00", ["$tableId"] = "notes", ["$databaseId"] = "notes",
	["$permissions"] = {}, ["$sequence"] = 4, title = "Milk", done = false})
t.assertEqual(record.id, "n1", "$id reads as id")
t.assertEqual(record.createdAt, "2026-11-08T10:00:00.000+00:00", "$createdAt reads as createdAt")
t.assertEqual(record.updatedAt, "2026-11-08T11:00:00.000+00:00", "$updatedAt reads as updatedAt")
t.expect(record.title == "Milk" and record.done == false, "columns read as fields")
local dollars = 0
for key in pairs(record) do if key:sub(1, 1) == "$" then dollars = dollars + 1 end end
t.assertEqual(dollars, 0, "no other $ field is exposed")
t.assertEqual(Json.encode(Rows.data(record)), '{"done":false,"title":"Milk"}', "data leaves out id and the dates")
t.assertEqual(Json.encode(Rows.data({id = "x"})), "{}", "a record of no fields sends an empty object")

local ids = {}
for _ = 1, 200 do
	local id = Rows.newId()
	t.expect(#id == 20 and id:match("^[a-z][a-z0-9]+$") and Client.validId(id), "a new ID is 20 of [a-z0-9]: " .. id)
	ids[id] = true
end
local unique = 0
for _ in pairs(ids) do unique = unique + 1 end
t.assertEqual(unique, 200, "new IDs do not repeat")

t.assertEqual(Json.encode(Rows.permissions("private", "u1")),
	'["read(\\"user:u1\\")","update(\\"user:u1\\")","delete(\\"user:u1\\")"]', "a private row is its owner's alone")
t.assertEqual(Rows.permissions("shared", "u1")[1], 'read("users")', "a shared row is read by every signed-in user")
t.assertEqual(Rows.permissions("public", "u1")[1], 'read("any")', "a public row is read by anyone")
t.assertEqual(Rows.permissions("public", "u1")[2], 'update("user:u1")', "only the owner changes a public row")
t.expect(not pcall(Rows.permissions, "open", "u1"), "remote is one of three")
t.expect(not pcall(Rows.permissions, "private", nil), "permissions need a user")

-- Rows over the client.
local rows = Rows.new(mock.client, "notes")
t.expect(not pcall(Rows.new, {}, "notes"), "rows need a client")
t.expect(not pcall(Rows.new, mock.client, "no/db"), "rows need a valid database ID")
t.expect(not pcall(rows.list, rows, "../tables", {}, function() end), "a table ID cannot leave its path")

local records, total
mock.answer({status = 200, body = {total = 2, rows = {
	{["$id"] = "n1", ["$tableId"] = "notes", title = "Milk"},
	{["$id"] = "n2", ["$tableId"] = "notes", title = "Bread"},
}}})
rows:list("notes", {Query.equal("listId", "inbox")}, function(r, e, n) records, err, total = r, e, n end)
t.expect(mock.last().url:find("^https://fra%.cloud%.appwrite%.io/v1/tablesdb/notes/tables/notes/rows%?queries%[0%]="),
	"a list reads the TablesDB rows of its table with its queries")
t.expect(#records == 2 and records[2].id == "n2" and records[2].title == "Bread" and records[1]["$tableId"] == nil,
	"listed rows arrive as records, in order")
t.assertEqual(total, 2, "the list reports Appwrite's total")

mock.answer({status = 200, body = {total = 0}})
rows:list("notes", {}, function(r, e) records, err = r, e end)
t.expect(records == nil and err.type == "invalid_response", "a list without rows is an invalid response")

local created
mock.answer({status = 201, body = {["$id"] = "n3", ["$createdAt"] = "2026-11-08T12:00:00.000+00:00", title = "Eggs"}})
rows:create("notes", {id = "n3", title = "Eggs"}, Rows.permissions("private", "u1"), function(r) created = r end)
sent = ns.json_parse(mock.last().body)
t.assertEqual(mock.last().method, "POST", "create posts")
t.assertEqual(sent.rowId, "n3", "create keeps the record's own ID")
t.expect(sent.data.title == "Eggs" and sent.data.id == nil, "create sends the fields without the ID")
t.assertEqual(#sent.permissions, 3, "create sends the row permissions")
t.expect(created.id == "n3" and created.createdAt ~= nil, "create answers the stored record")

mock.answer({status = 201, body = {["$id"] = "made"}})
rows:create("notes", {title = "No id"}, nil, function() end)
sent = ns.json_parse(mock.last().body)
t.expect(#sent.rowId == 20 and sent.permissions == nil, "create makes an ID when the record has none")

mock.answer({status = 200, body = {["$id"] = "n3", title = "Eggs", done = true}})
rows:update("notes", "n3", {done = true, note = Json.null}, nil, function(r) created = r end)
t.assertEqual(mock.last().method, "PATCH", "update patches")
t.expect(mock.last().url:find("/rows/n3$"), "update addresses its row")
t.assertEqual(mock.last().body, '{"data":{"done":true,"note":null}}', "update sends only its fields; null clears one")
t.assertEqual(created.done, true, "update answers the changed record")

mock.answer({status = 404, body = {type = "row_not_found", message = "Row with the requested ID could not be found."}})
rows:update("notes", "gone", {done = true}, nil, function(r, e) value, err = r, e end)
t.expect(value == nil and err.type == "row_not_found", "updating a missing row reports Appwrite's error")

mock.answer({status = 200, body = {title = "no id"}})
rows:update("notes", "n3", {done = true}, nil, function(r, e) value, err = r, e end)
t.expect(value == nil and err.type == "invalid_response", "a row answer without an ID is refused")

mock.answer({status = 204})
rows:delete("notes", "n3", function(ok, e) value, err = ok, e end)
t.expect(mock.last().method == "DELETE" and value == true, "delete removes its row")

t.assertEqual(#mock.answers, 0, "every queued answer was used")
os.exit(t.summary() and 0 or 1)
