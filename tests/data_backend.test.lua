-- The backend of remote models (lua/data/backend.lua): a route's load fills
-- the store, writes change it at once and are undone when refused, and the
-- page is drawn loading, loaded and with the message of what failed. All over
-- a recording transport (tests/support/appwrite.lua): no network.
_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local App = require("data.app")
local Model = require("data.model")
local Backend = require("data.backend")
local Account = require("data.appwrite.account")
local Json = require("data.appwrite.json")
local Mock = require("tests.support.appwrite")

local Items = require("tests.fixtures.backend.models.Items")
local PROJECT = "lua-objc-dev"
local COOKIE = "a_session_" .. PROJECT

local function row(id, title, extra)
	local value = {["$id"] = id, ["$tableId"] = "fixture_items", ["$createdAt"] = "2026-11-08T10:00:00.000+00:00", title = title}
	for key, item in pairs(extra or {}) do value[key] = item end
	return value
end
local function list(...) local rows = {...}; return {status = 200, body = {total = #rows, rows = rows}} end
local function session() return {status = 201, headers = {["set-cookie"] = COOKIE .. "=abc; path=/"}, body = {secret = ""}} end
local user = {status = 200, body = {["$id"] = "u1", email = ""}}

local function newBackend()
	local mock = Mock.new({project = PROJECT})
	local backend = Backend.new({client = mock.client, account = Account.new(mock.client, Mock.secrets()), database = "backend"})
	return backend, mock
end

local function titles(db)
	local result = {}
	for _, record in ipairs(db.fixture_items or {}) do table.insert(result, record.title) end
	table.sort(result)
	return table.concat(result, ",")
end

-- Queries: a Model:query as Appwrite queries.
local queries = Backend.queries(Items:query({done = false, title = "x"}, {order = "createdAt desc", limit = 20, after = "r9"}))
t.assertEqual(#queries, 5, "two fields, an order, a limit and a cursor")
t.assertEqual(Json.encode(queries[1]), '{"attribute":"done","method":"equal","values":[false]}', "fields are equal queries, by name")
t.assertEqual(queries[3].method, "orderDesc", "desc orders down")
t.assertEqual(queries[3].attribute, "$createdAt", "createdAt is Appwrite's $createdAt")
t.expect(queries[4].method == "limit" and queries[5].method == "cursorAfter" and queries[5].values[1] == "r9", "limit and cursor")
t.assertEqual(Backend.queries(Items:query()).n, nil, "no where and no options")
t.assertEqual(#Backend.queries(Items:query()), 0, "send no queries")
t.expect(not pcall(Items.query, Items, function() return true end), "a function cannot be sent")
t.expect(not pcall(Items.query, Items, {}, {order = function() end}), "nor a comparator")
local Kinds = require("tests.fixtures.backend.models.Kinds")
t.expect(not pcall(Kinds.query, Kinds), "a local model has no query")

-- Without a backend a remote model cannot write.
Model.connect(nil)
Model.bind({})
local ok, err = pcall(Items.create, Items, {title = "x"})
t.expect(not ok and tostring(err):find("has no <Backend>", 1, true), "a remote write needs a backend: " .. tostring(err))

-- Loads wait for the account.
local backend, mock = newBackend()
Model.connect(backend)
local db = Model.bind({fixture_items = {{id = "old", title = "Stale"}}, other = {}})
local loaded
backend:load(Items:query({}), db, function(e) loaded = e or true end)
t.expect(loaded == nil and #mock.sent == 0, "a load before the account starts waits")
mock.answer(session()); mock.answer(user)
mock.answer(list(row("r1", "Milk"), row("r2", "Bread")))
backend:start()
t.assertEqual(loaded, true, "it runs once the account is known")
t.assertEqual(titles(db), "Bread,Milk", "the rows matching the query replace the store's: a deleted row goes")
t.expect(db.fixture_items[1].id == "r1" and db.fixture_items[1].createdAt ~= nil and db.fixture_items[1]["$tableId"] == nil,
	"rows arrive as records")
t.expect(mock.sent[3].url:find("/tablesdb/backend/tables/fixture_items/rows", 1, true), "it lists the model's table")
t.assertEqual(mock.sent[3].headers.Cookie, COOKIE .. "=abc", "with the session")

-- Replace only what the query names; `after` appends.
db.fixture_items = {{id = "a", title = "Kept", done = true}, {id = "b", title = "Gone", done = false}}
mock.answer(list(row("c", "New", {done = false})))
backend:load(Items:query({done = false}), db, function() end)
t.assertEqual(titles(db), "Kept,New", "rows outside the query's where stay")
mock.answer(list(row("d", "Next", {done = false})))
backend:load(Items:query({done = false}, {after = "c"}), db, function() end)
t.assertEqual(titles(db), "Kept,New,Next", "the next window is appended")
mock.answer({status = 500, body = {type = "general_unknown", message = "Server error"}})
backend:load(Items:query({}), db, function(e) loaded = e end)
t.expect(loaded.message == "Server error" and titles(db) == "Kept,New,Next", "a failed load leaves the rows as they were")

-- Create: in the store at once, sent with the owner's permissions.
local changed = {}
backend.changed = function(message) table.insert(changed, message or "ok") end
mock.hold = true
db.fixture_items = {}
local item = Items:create({title = "Eggs"})
t.expect(#item.id == 20 and db.fixture_items[1] == item, "a created row is stored at once with an ID made here")
local body = ns.json_parse(mock.last().body)
t.expect(body.rowId == item.id and body.data.title == "Eggs" and body.data.id == nil, "the row is sent with the same ID")
t.assertEqual(body.permissions[1], 'read("user:u1")', "a private row is the signed-in user's")
local waited
backend:load(Items:query({}), db, function() waited = true end)
t.expect(waited == nil and #mock.held == 1, "a load waits while a write is out")
mock.answer({status = 201, body = row(item.id, "Eggs")})
mock.answer(list(row(item.id, "Eggs")))
mock.drain()
t.expect(item.createdAt ~= nil and changed[1] == "ok", "the saved row's server fields are merged in, and the page hears it")
t.expect(waited and titles(db) == "Eggs", "then the load runs and keeps the new row")

-- A refused create leaves the store.
changed = {}
local refused = Items:create({title = "Too long"})
mock.answer({status = 400, body = {type = "row_invalid_structure", message = "Invalid title"}})
mock.drain()
t.expect(Items:find(refused.id) == nil and titles(db) == "Eggs", "a refused row is removed")
t.assertEqual(changed[1], "Invalid title", "and the page hears why")

-- Constraints refuse before anything is sent.
local sentBefore = #mock.sent
local saved = Items.constraints
Items.constraints = {title = function(_, title) if title == "" then return "A title is required" end end}
local none, message = Items:create({title = ""})
t.expect(none == nil and message == "A title is required" and #mock.sent == sentBefore, "a constraint refuses locally")
Items.constraints = saved

-- Update: changed at once; refused, the old values return.
local eggs = Items:find(item.id)
eggs:update({title = "Brown eggs", done = true})
t.expect(eggs.title == "Brown eggs" and mock.last().method == "PATCH", "an update changes the row and is sent")
t.assertEqual(ns.json_parse(mock.last().body).data.title, "Brown eggs", "with only its fields")
mock.answer({status = 401, body = {type = "user_unauthorized", message = "Not allowed"}})
mock.drain()
t.expect(eggs.title == "Eggs" and eggs.done == nil, "a refused update restores every field it changed")
t.expect(not pcall(eggs.update, eggs, {id = "other"}), "a row's id belongs to the server")
t.assertEqual(eggs.id, item.id, "and stays")

-- Delete: gone at once; refused, it returns to its place.
db.fixture_items = {{id = "x1", title = "One"}, eggs, {id = "x3", title = "Three"}}
eggs:delete()
t.expect(titles(db) == "One,Three" and mock.last().method == "DELETE", "a deleted row leaves at once")
mock.answer({status = 500, body = {message = "Try again"}})
mock.drain()
t.expect(db.fixture_items[2] == eggs, "a refused delete puts the row back where it was")
eggs:delete()
mock.answer({status = 404, body = {type = "row_not_found", message = "gone"}})
mock.drain()
t.expect(titles(db) == "One,Three", "a row already gone on the server is deleted all the same")

-- Offline at launch: writes cannot be owned, so they are undone.
local offline, offlineMock = newBackend()
Model.connect(offline)
local offlineDb = Model.bind({})
offlineMock.answer({err = "offline"})
offline:start()
local offlineChanged
offline.changed = function(m) offlineChanged = m end
Items:create({title = "Nowhere"})
t.expect(#offlineDb.fixture_items == 0 and offlineChanged:find("Sign-in", 1, true), "without a user a create is undone")

-- The page: loading, loaded, a refused write, and a load after each action.
local app, appMock = nil, nil
do
	local pageBackend
	pageBackend, appMock = newBackend()
	appMock.hold = true
	app = App.launcher("tests/fixtures/backend/app.xml").new({args = {}, backend = pageBackend, store = {}})
end
app:createWindow()
t.assertEqual(app.refs.summary.text, "Loading", "the page is drawn loading while the account and rows are out")
appMock.answer(session()); appMock.answer(user)
appMock.answer(list(row("r1", "Milk"), row("r2", "Bread")))
appMock.drain()
t.assertEqual(app.refs.summary.text, "Bread, Milk", "and again with the rows")
t.assertEqual(app.refs.error, nil, "no error")

app.page.actions.add("Apples")
t.assertEqual(app.refs.summary.text, "Loading", "an action loads the page again")
appMock.answer({status = 400, body = {message = "Invalid row"}})
appMock.answer(list(row("r1", "Milk"), row("r2", "Bread")))
appMock.drain()
t.assertEqual(app.refs.summary.text, "Bread, Milk", "a refused create is gone from the page")
t.assertEqual(app.refs.error and app.refs.error.text, "Invalid row", "and the page says why, after the load that followed")

local sentNow = #appMock.sent
app.page.actions.rename("r1", "Oat milk")
t.assertEqual(app.refs.error, nil, "the next action clears a write's message")
appMock.answer({status = 200, body = row("r1", "Oat milk")})
appMock.answer(list(row("r1", "Oat milk"), row("r2", "Bread")))
appMock.drain()
t.expect(#appMock.sent == sentNow + 2 and app.refs.summary.text == "Bread, Oat milk", "an accepted update stays")

appMock.answer({status = 500, body = {message = "Down"}})
app.page:load()
appMock.drain()
t.expect(app.refs.summary.text == "Bread, Oat milk" and app.refs.error.text == "Down", "a failed load keeps the rows and says why")

-- A page that is gone draws nothing when its load answers late.
app.page:load()
app.page:dispose()
appMock.answer(list())
t.expect(pcall(appMock.drain), "a late answer after dispose is harmless")

Model.connect(nil)
os.exit(t.summary() and 0 or 1)
