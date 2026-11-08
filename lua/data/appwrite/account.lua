-- The person using the app: an Appwrite Account and its session.
--
--   local account = Account.new(client, {read = …, write = …, remove = …})
--   account:start(function(user, err) end)        -- at launch
--   account:register(email, password, done)       -- keeps an anonymous account's rows
--   account:signIn(email, password, done)
--   account:signOut(done)
--
-- Every app starts with an anonymous session (docs/backend.md), so rows save
-- before anyone signs up. `register` turns that same account into an email
-- account; `signIn` moves to another existing account, leaving the anonymous
-- one's rows behind with it. `account.user` is `{id, email, name, anonymous}`
-- once a session is known, nil before.
--
-- The session credential is the one secret: it lives only in `secrets`, the
-- Keychain (`ns.Credentials`) in an app, and in `client.credential` while
-- the app runs; never in the store. The HTTP layer keeps no cookies, so the
-- credential is exactly what this module sends.
local Json = require("data.appwrite.json")
local Client = require("data.appwrite.client")

local Account = {}
Account.__index = Account

function Account.new(client, secrets)
	assert(getmetatable(client) == Client, "Account.new needs an Appwrite client")
	assert(type(secrets) == "table" and type(secrets.read) == "function"
		and type(secrets.write) == "function" and type(secrets.remove) == "function",
		"Account.new needs a secret store with read, write and remove")
	return setmetatable({client = client, secrets = secrets, user = nil}, Account)
end

-- The credential an Appwrite session answer carries. A session made with a
-- server key returns its `secret`; a client session returns it only as the
-- `a_session_<project>` cookie, which Appwrite also repeats in
-- X-Fallback-Cookies for clients without a cookie jar.
function Account:credential(session, response)
	if type(session) == "table" and type(session.secret) == "string" and session.secret ~= "" then
		return {name = "X-Appwrite-Session", value = session.secret}
	end
	local cookie = "a_session_" .. self.client.project
	local headers = response and response.headers or {}
	local fallback = headers["x-fallback-cookies"]
	if fallback then
		local ok, cookies = pcall(self.client.decode, fallback)
		if ok and type(cookies) == "table" and type(cookies[cookie]) == "string" and cookies[cookie] ~= "" then
			return {name = "Cookie", value = cookie .. "=" .. cookies[cookie]}
		end
	end
	-- NSURLSession joins repeated Set-Cookie headers with ", "; the value
	-- itself has no comma, semicolon or space.
	local pattern = (cookie:gsub("%p", "%%%0")) .. "=([^;,%s]+)"
	local value = (headers["set-cookie"] or ""):match(pattern)
	if value and value ~= "" then return {name = "Cookie", value = cookie .. "=" .. value} end
end

local function encodeSecret(credential)
	return credential.name .. "\n" .. credential.value
end

local function decodeSecret(secret)
	if type(secret) ~= "string" then return nil end
	local name, value = secret:match("^([%w%-]+)\n(.+)$")
	if name then return {name = name, value = value} end
end

local function userOf(value)
	if type(value) ~= "table" or not Client.validId(value["$id"]) then return nil end
	local email = type(value.email) == "string" and value.email or ""
	return {id = value["$id"], email = email, name = value.name or "", anonymous = email == ""}
end

local function invalid(message)
	return {type = "invalid_response", message = message}
end

function Account:forget()
	self.user, self.client.credential = nil, nil
	self.secrets.remove()
end

-- Reads the signed-in user with the current credential.
function Account:load(done)
	return self.client:call({path = "/account"}, function(value, err)
		if err then done(nil, err); return end
		local user = userOf(value)
		if not user then done(nil, invalid("Appwrite sent an account without an ID.")); return end
		self.user = user
		done(user)
	end)
end

-- Keeps the credential of a new session and loads its user.
function Account:adopt(session, response, done)
	local credential = self:credential(session, response)
	if not credential then
		done(nil, invalid("Appwrite opened a session but sent no credential for it."))
		return
	end
	self.client.credential = credential
	self.secrets.write(encodeSecret(credential))
	self:load(done)
end

-- Opens a new anonymous session, forgetting any other.
function Account:anonymous(done)
	self:forget()
	return self.client:call({method = "POST", path = "/account/sessions/anonymous", body = Json.object()},
		function(session, err, response)
			if err then done(nil, err); return end
			self:adopt(session, response, done)
		end)
end

-- At launch: the stored session's user, or a new anonymous one when there
-- is no stored session or Appwrite no longer accepts it. Offline keeps the
-- stored session and reports the network error.
function Account:start(done)
	local credential = decodeSecret(self.secrets.read())
	if not credential then return self:anonymous(done) end
	self.client.credential = credential
	return self:load(function(user, err)
		if user then done(user); return end
		if err.status == 401 then self:anonymous(done); return end
		done(nil, err)
	end)
end

-- Gives the anonymous account an email and password: the same user, so its
-- rows stay its own.
function Account:register(email, password, done)
	if not (self.user and self.user.anonymous) then
		done(nil, {type = "account_not_anonymous", message = "Only an anonymous account can be registered."})
		return
	end
	return self.client:call({method = "PATCH", path = "/account/email", body = {email = email, password = password}},
		function(value, err)
			if err then done(nil, err); return end
			local user = userOf(value)
			if not user then done(nil, invalid("Appwrite sent an account without an ID.")); return end
			self.user = user
			done(user)
		end)
end

-- Opens a session of an existing email account. The request carries no
-- credential: Appwrite refuses a new session while one is active.
function Account:signIn(email, password, done)
	local previous = self.client.credential
	self.client.credential = nil
	return self.client:call({method = "POST", path = "/account/sessions/email", body = {email = email, password = password}},
		function(session, err, response)
			if err then self.client.credential = previous; done(nil, err); return end
			self:adopt(session, response, done)
		end)
end

-- Ends the session here and on the server. The next start opens a new
-- anonymous account; a session the server already dropped still signs out.
function Account:signOut(done)
	return self.client:call({method = "DELETE", path = "/account/sessions/current"}, function(_, err)
		if err and err.status ~= 401 then done(nil, err); return end
		self:forget()
		done(true)
	end)
end

return Account
