-- The Appwrite account of lua/data/appwrite: anonymous start, the stored
-- session, register, sign in and sign out, over a recording transport.
local t = require("TestKit")
local ns = require("AppKit")
local Account = require("data.appwrite.account")
local Mock = require("tests.support.appwrite")

local PROJECT = "lua-objc-dev"
local COOKIE = "a_session_" .. PROJECT
local anonymousUser = {["$id"] = "anon1", email = "", name = ""}
local session = {["$id"] = "s1", userId = "anon1", secret = ""}

local function setCookie(value)
	return {["set-cookie"] = COOKIE .. "_legacy=" .. value .. "; expires=Sun, 08-Nov-2027 10:00:00 GMT; path=/, "
		.. COOKIE .. "=" .. value .. "; expires=Sun, 08-Nov-2027 10:00:00 GMT; path=/; secure; httponly"}
end

local mock, secrets = Mock.new({project = PROJECT}), Mock.secrets()
t.expect(not pcall(Account.new, {}, secrets), "an account needs a client")
t.expect(not pcall(Account.new, mock.client, {}), "an account needs a secret store")
local account = Account.new(mock.client, secrets)

-- First launch: no stored session, so an anonymous one opens.
local user, err
mock.answer({status = 201, headers = setCookie("abc123"), body = session})
mock.answer({status = 200, body = anonymousUser})
account:start(function(u, e) user, err = u, e end)
t.assertEqual(mock.sent[1].method, "POST", "the first launch opens a session")
t.expect(mock.sent[1].url:find("/account/sessions/anonymous$"), "an anonymous one")
t.assertEqual(mock.sent[1].body, "{}", "with an empty object body")
t.assertEqual(mock.sent[1].headers.Cookie, nil, "and no credential")
t.assertEqual(mock.sent[2].headers.Cookie, COOKIE .. "=abc123", "the session cookie, not its legacy twin, signs the next call")
t.expect(user and user.id == "anon1" and user.anonymous and err == nil, "the app has an anonymous user")
t.assertEqual(account.user, user, "the account keeps its user")
t.assertEqual(secrets.value, "Cookie\n" .. COOKIE .. "=abc123", "the credential is stored as a secret")

-- Next launch: the stored session is used, no new account.
mock = Mock.new({project = PROJECT})
account = Account.new(mock.client, secrets)
mock.answer({status = 200, body = anonymousUser})
account:start(function(u, e) user, err = u, e end)
t.assertEqual(#mock.sent, 1, "a stored session needs one call")
t.expect(mock.sent[1].url:find("/account$") and mock.sent[1].headers.Cookie == COOKIE .. "=abc123",
	"it reads the account with the stored credential")
t.assertEqual(user.id, "anon1", "the same user comes back")

-- Offline launch keeps the session.
mock = Mock.new({project = PROJECT})
account = Account.new(mock.client, secrets)
mock.answer({err = "offline"})
account:start(function(u, e) user, err = u, e end)
t.expect(user == nil and err.type == "network", "offline reports the network")
t.expect(secrets.value ~= nil and mock.client.credential ~= nil, "and keeps the stored session")

-- A session Appwrite no longer accepts is replaced by a new anonymous one.
mock = Mock.new({project = PROJECT})
account = Account.new(mock.client, secrets)
mock.answer({status = 401, body = {type = "user_unauthorized", message = "expired"}})
mock.answer({status = 201, headers = setCookie("fresh9"), body = session})
mock.answer({status = 200, body = {["$id"] = "anon2", email = ""}})
account:start(function(u, e) user, err = u, e end)
t.assertEqual(mock.sent[2].headers.Cookie, nil, "the expired session is not sent to open a new one")
t.expect(user.id == "anon2" and secrets.value:find("fresh9", 1, true), "a new anonymous user and its session")

-- Other ways a session answer carries its credential.
t.assertEqual(account:credential({secret = "srv"}, {headers = {}}).name, "X-Appwrite-Session",
	"a session secret is sent as X-Appwrite-Session")
local fallback = account:credential({secret = ""}, {headers = {["x-fallback-cookies"] = '{"' .. COOKIE .. '":"fb1"}'}})
t.assertEqual(fallback.value, COOKIE .. "=fb1", "X-Fallback-Cookies carries the cookie too")
t.assertEqual(account:credential({}, {headers = {["set-cookie"] = "other=1; path=/"}}), nil,
	"another project's cookie is not a credential")

mock.answer({status = 201, body = session})
account:anonymous(function(u, e) user, err = u, e end)
t.expect(user == nil and err.type == "invalid_response", "a session without a credential is refused")
t.expect(secrets.value == nil and mock.client.credential == nil, "and nothing is kept")

-- Register: the anonymous account gets an email and stays the same user.
mock = Mock.new({project = PROJECT})
secrets = Mock.secrets("Cookie\n" .. COOKIE .. "=abc123")
account = Account.new(mock.client, secrets)
mock.answer({status = 200, body = anonymousUser})
account:start(function() end)
mock.answer({status = 200, body = {["$id"] = "anon1", email = "igor@example.com", name = ""}})
account:register("igor@example.com", "correct horse", function(u, e) user, err = u, e end)
local sent = mock.last()
t.expect(sent.method == "PATCH" and sent.url:find("/account/email$"), "register patches the account's email")
t.expect(sent.headers.Cookie == COOKIE .. "=abc123", "with the anonymous session")
local body = ns.json_parse(sent.body)
t.expect(body.email == "igor@example.com" and body.password == "correct horse", "and the new email and password")
t.expect(user.id == "anon1" and not user.anonymous, "the same user is no longer anonymous")
account:register("again@example.com", "x", function(u, e) user, err = u, e end)
t.expect(user == nil and err.type == "account_not_anonymous", "only an anonymous account registers")

-- A refused register changes nothing.
mock.answer({status = 409, body = {type = "user_already_exists", message = "taken"}})
account.user.anonymous = true
account:register("taken@example.com", "pw123456", function(u, e) user, err = u, e end)
t.expect(user == nil and err.type == "user_already_exists" and account.user.id == "anon1", "a taken email is reported")

-- Sign in: a new session without sending the current one.
mock.answer({status = 201, headers = setCookie("mine77"), body = {["$id"] = "s2", userId = "u9", secret = ""}})
mock.answer({status = 200, body = {["$id"] = "u9", email = "me@example.com", name = "Me"}})
account:signIn("me@example.com", "pw123456", function(u, e) user, err = u, e end)
t.assertEqual(mock.sent[#mock.sent - 1].headers.Cookie, nil, "sign-in sends no session")
t.expect(user.id == "u9" and user.name == "Me" and secrets.value:find("mine77", 1, true), "the signed-in user and session")

mock.answer({status = 401, body = {type = "user_invalid_credentials", message = "Invalid credentials."}})
account:signIn("me@example.com", "wrong", function(u, e) user, err = u, e end)
t.expect(err.type == "user_invalid_credentials", "wrong credentials are reported")
t.expect(mock.client.credential.value == COOKIE .. "=mine77" and account.user.id == "u9",
	"a refused sign-in keeps the current session")

-- Sign out.
mock.answer({status = 204})
local ok
account:signOut(function(v, e) ok, err = v, e end)
t.expect(mock.last().method == "DELETE" and mock.last().url:find("/account/sessions/current$"), "sign-out ends this session")
t.expect(ok and account.user == nil and secrets.value == nil and mock.client.credential == nil, "and forgets it here")

secrets.value = "Cookie\n" .. COOKIE .. "=old"
mock.client.credential = {name = "Cookie", value = COOKIE .. "=old"}
mock.answer({status = 401, body = {type = "user_unauthorized"}})
account:signOut(function(v, e) ok, err = v, e end)
t.expect(ok and secrets.value == nil, "a session the server already dropped still signs out")

mock.client.credential = {name = "Cookie", value = COOKIE .. "=kept"}
secrets.value = "Cookie\n" .. COOKIE .. "=kept"
mock.answer({err = "offline"})
account:signOut(function(v, e) ok, err = v, e end)
t.expect(ok == nil and err.type == "network" and secrets.value ~= nil, "offline sign-out keeps the session to retry")

t.assertEqual(#mock.answers, 0, "every queued answer was used")
os.exit(t.summary() and 0 or 1)
