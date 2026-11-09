-- demo/cloud-notes: lists of notes kept online, and the account page, over a
-- recording Appwrite transport (tests/support/appwrite.lua): no network.
_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local App = require("data.app")
local Model = require("data.model")
local Backend = require("data.backend")
local Account = require("data.appwrite.account")
local Mock = require("tests.support.appwrite")
local Notes = require("demo.cloud-notes.models.Notes")

local COOKIE = "a_session_lua-objc-dev"
local function note(id, list, title, done, created)
	return {["$id"] = id, ["$createdAt"] = created or "2026-11-08T10:00:00.000+00:00", list = list, title = title, done = done or false}
end
local function rows(...) local list = {...}; return {status = 200, body = {total = #list, rows = list}} end
local function session(value) return {status = 201, headers = {["set-cookie"] = COOKIE .. "=" .. value .. "; path=/"}, body = {secret = ""}} end
local function account(id, email) return {status = 200, body = {["$id"] = id, email = email or ""}} end

local mock = Mock.new()
mock.hold = true
local secrets = Mock.secrets()
local backend = Backend.new({client = mock.client, account = Account.new(mock.client, secrets), database = "cloud-notes"})
local app = App.launcher("demo/cloud-notes/app.xml").new({args = {}, backend = backend})
app:createWindow()

-- The model.
t.assertEqual(Notes.remote, "private", "notes are each person's own")
t.assertEqual(app.manifest.backend.database, "cloud-notes", "the database is the app's folder")
t.assertEqual(app.manifest.backend.connected, true, "the demo saves to the project connected on the device")

-- Launch: anonymous session, then the Inbox's notes.
t.assertEqual(app.refs.notes.rowCount, 0, "nothing is shown before the rows arrive")
mock.answer(session("anon")); mock.answer(account("u1"))
mock.answer(rows(note("n1", "inbox", "Call the bank", false, "2026-11-08T09:00:00.000+00:00"),
	note("n2", "inbox", "Buy milk", true, "2026-11-08T11:00:00.000+00:00"),
	note("n3", "inbox", "Water plants", false, "2026-11-08T12:00:00.000+00:00")))
mock.drain()
local listed = mock.sent[3]
t.expect(listed.url:find("/tablesdb/cloud%-notes/tables/notes/rows%?") ~= nil, "the Inbox lists its table")
t.expect(listed.url:find("inbox", 1, true) ~= nil, "for its own list")
t.assertEqual(app.refs.notes.rowCount, 3, "the Inbox shows its notes")
t.expect(Notes:of("inbox")[1].title == "Water plants" and Notes:of("inbox")[3].title == "Buy milk",
	"open notes come first, newest first; done ones after")

-- Adding: an empty note is refused before anything is sent.
local sent = #mock.sent
app.page.actions.add()
t.assertEqual(#mock.sent, sent, "an empty note sends nothing")
t.assertEqual(app.refs.refusal and app.refs.refusal.text, "A note needs some text.", "and the page says why")

app.page.actions.setDraft("Pay rent")
app.page.actions.add()
t.assertEqual(app.refs.notes.rowCount, 4, "a new note shows at once")
local created = ns.json_parse(mock.sent[#mock.sent].body)
t.expect(created.data.list == "inbox" and created.data.title == "Pay rent" and created.data.done == false,
	"it is sent to the Inbox")
t.assertEqual(created.permissions[1], 'read("user:u1")', "as the person's own")
mock.answer({status = 201, body = note(created.rowId, "inbox", "Pay rent")})
mock.answer(rows(note("n1", "inbox", "Call the bank"), note("n2", "inbox", "Buy milk", true),
	note("n3", "inbox", "Water plants"), note(created.rowId, "inbox", "Pay rent", false, "2026-11-08T13:00:00.000+00:00")))
mock.drain()
t.assertEqual(app.refs.notes.rowCount, 4, "after the save and the reload it stays")
t.assertEqual(app.refs.refusal, nil, "the earlier refusal is gone")

-- Completing and deleting work on the selected note.
app.page.actions.toggle()
t.assertEqual(app.refs.refusal and app.refs.refusal.text, "Choose a note.", "nothing selected, nothing to complete")
app.page.actions.selectNote(nil, 0, {id = "n1"})
app.page.actions.toggle()
t.expect(Notes:find("n1").done == true and mock.sent[#mock.sent].method == "PATCH", "complete updates the note")
mock.answer({status = 401, body = {message = "Not allowed"}})
mock.answer(rows(note("n1", "inbox", "Call the bank"), note("n3", "inbox", "Water plants")))
mock.drain()
t.expect(Notes:find("n1").done == false, "a refused change is undone")
t.assertEqual(app.refs.failure and app.refs.failure.text, "Not allowed", "and the page says what the server answered")

app.page.actions.selectNote(nil, 0, {id = "n3"})
app.page.actions.remove()
t.expect(Notes:find("n3") == nil and mock.sent[#mock.sent].method == "DELETE", "delete removes the note")
mock.answer({status = 204})
mock.answer(rows(note("n1", "inbox", "Call the bank")))
mock.drain()
t.assertEqual(app.refs.notes.rowCount, 1, "the list shows what the server has")

-- Another list loads its own notes and keeps the Inbox's.
app:show("work")
mock.answer(rows(note("w1", "work", "Send invoice")))
mock.drain()
t.expect(mock.sent[#mock.sent].url:find("work", 1, true) ~= nil and app.refs.notes.rowCount == 1, "Work loads its notes")
t.assertEqual(#Notes:of("inbox"), 1, "the Inbox's rows stay in the store")

-- The account page: register keeps the anonymous person's notes.
app:show("account")
t.expect(app.refs.status.text:find("without an account", 1, true) ~= nil, "an anonymous person is told so")
t.expect(app.refs.email ~= nil and app.refs.password ~= nil, "with fields to register or sign in")
app.page.actions.setEmail("igor@example")
app.page.actions.setPassword("correct horse")
app.page.actions.register()
t.assertEqual(app.refs.refusal and app.refs.refusal.text, "Enter an email address.", "an address is checked first")
app.page.actions.setEmail("igor@example.com")
app.page.actions.setPassword("short")
app.page.actions.register()
t.expect(app.refs.refusal.text:find("8 characters", 1, true) ~= nil, "and the password's length")
sent = #mock.sent
app.page.actions.setPassword("correct horse")
app.page.actions.register()
local request = mock.sent[sent + 1]
t.expect(request.method == "PATCH" and request.url:find("/account/email$") ~= nil, "register gives the account an email")
t.expect(ns.json_parse(request.body).password == "correct horse", "with the typed password")
t.expect(app.page.request.password == nil, "which the page drops once sent")
mock.answer(account("u1", "igor@example.com"))
mock.drain()
t.expect(app.refs.status.text == "Signed in as igor@example.com" and app.refs.email == nil, "the same person, now registered")
t.assertEqual(#Notes:of("inbox"), 1, "and the notes are still theirs")

-- Sign out: a new anonymous account, and the old notes leave the store.
app.page.actions.signOut()
mock.answer({status = 204})
mock.answer(session("anon2")); mock.answer(account("u2"))
mock.drain()
t.expect(secrets.value:find("anon2", 1, true) ~= nil and app.refs.status.text:find("without an account", 1, true) ~= nil,
	"signed out, the app keeps saving anonymously")
t.expect(#Notes:of("inbox") == 0 and #Notes:of("work") == 0, "another account's notes leave the store")

-- Sign in to an existing account.
app.page.actions.setEmail("igor@example.com")
app.page.actions.setPassword("correct horse")
app.page.actions.signIn()
local signIn = mock.sent[#mock.sent]
t.expect(signIn.url:find("/account/sessions/email$") ~= nil and signIn.headers.Cookie == nil, "sign in opens a session of its own")
mock.answer({status = 401, body = {type = "user_invalid_credentials", message = "Invalid credentials."}})
mock.drain()
t.assertEqual(app.refs.failure and app.refs.failure.text, "Invalid credentials.", "a refused sign-in is shown")
app.page.actions.setPassword("correct horse")
app.page.actions.signIn()
mock.answer(session("mine")); mock.answer(account("u1", "igor@example.com"))
mock.drain()
t.assertEqual(app.refs.status.text, "Signed in as igor@example.com", "signed in")
app:show("inbox")
mock.answer(rows(note("n1", "inbox", "Call the bank")))
mock.drain()
t.expect(mock.sent[#mock.sent].headers.Cookie == COOKIE .. "=mine" and app.refs.notes.rowCount == 1,
	"the lists load with the new session")

t.assertEqual(#mock.answers, 0, "every queued answer was used")
Model.connect(nil)
os.exit(t.summary() and 0 or 1)
