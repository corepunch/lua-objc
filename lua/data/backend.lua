-- The backend of an app's remote models (docs/backend.md): the network in
-- front of the store, never inside it. A page stays a request: `data(state)`
-- reads the store, synchronously. This service fills the store from a route's
-- `load` and sends the models' writes, and says when it is done so the page
-- is asked again.
--
--   local backend = Backend.new({client = client, account = account, database = "notes"})
--   Model.connect(backend)
--   backend.changed = function(message) page:remoteChanged(message) end
--   backend:start()
--
-- Reading: `load(query, done)` lists the rows of `query` (Model:query) and
-- REPLACES the store rows matching its `where` with them, so a row deleted on
-- the server or another device goes; rows outside `where` stay. A query with
-- `after` appends the next window instead.
--
-- Writing: a remote model changes the store at once, then calls `create`,
-- `update` or `delete` here; a refused write is undone in the store it was made
-- in and `changed(message)` reports it. Loads wait until every write sent has
-- answered: a load that overtook a create would replace its new row away.
--
-- Nothing polls, nothing listens: the backend sends a request only when a
-- page asks or a model writes.
local Rows = require("data.appwrite.rows")
local Query = require("data.appwrite.query")
local Client = require("data.appwrite.client")

local Backend = {}
Backend.__index = Backend

function Backend.new(options)
	assert(getmetatable(options.client) == Client, "a backend needs an Appwrite client")
	assert(options.account, "a backend needs an account")
	return setmetatable({
		client = options.client,
		account = options.account,
		rows = Rows.new(options.client, options.database),
		started = false,
		writes = 0,     -- writes sent and not yet answered
		-- The stores rows were loaded into or written in: another account's
		-- rows leave them when the account changes.
		stores = setmetatable({}, {__mode = "k"}),
		waiting = {},   -- loads held until the account is known and writes are done
		-- `changed(message)` after a load or a write answered; message when it failed.
		changed = function() end,
	}, Backend)
end

-- Opens the account (the stored session, or a new anonymous one), then runs
-- the loads that waited for it. Offline, they run anyway and report it.
function Backend:start(done)
	self.account:start(function(user, err)
		self.started = true
		self.startError = err
		self:flush()
		if done then done(user, err) end
	end)
end

function Backend:flush()
	if not self.started or self.writes > 0 then return end
	local waiting = self.waiting
	self.waiting = {}
	for _, run in ipairs(waiting) do run() end
end

function Backend:newId()
	return Rows.newId()
end

local SYSTEM = {id = "$id", createdAt = "$createdAt", updatedAt = "$updatedAt"}

-- The Appwrite queries of a Model:query.
function Backend.queries(query)
	local queries, keys = {}, {}
	for key in pairs(query.where or {}) do table.insert(keys, key) end
	table.sort(keys)
	for _, key in ipairs(keys) do
		table.insert(queries, (Query.equal(SYSTEM[key] or key, query.where[key])))
	end
	local opts = query.opts or {}
	if opts.order then
		local field, direction = opts.order:match("^(%S+)%s*(%a*)$")
		local column = SYSTEM[field] or field
		table.insert(queries, direction:lower() == "desc" and Query.orderDesc(column) or Query.orderAsc(column))
	end
	if opts.limit then table.insert(queries, (Query.limit(opts.limit))) end
	if opts.after then table.insert(queries, (Query.cursorAfter(opts.after))) end
	return queries
end

local function matches(record, where)
	for key, value in pairs(where or {}) do
		if record[key] ~= value then return false end
	end
	return true
end

-- Lists the rows of `query` into `db` (the store bound when the load was
-- asked), then `done(err)`. Held until the account is known and no write is
-- in flight.
function Backend:load(query, db, done)
	self.stores[db] = true
	local run = function()
		self.rows:list(query.model.tableName, Backend.queries(query), function(records, err)
			if err then done(err); return end
			local name = query.model.tableName
			local stored = db[name] or {}
			db[name] = stored
			if not (query.opts and query.opts.after) then
				for index = #stored, 1, -1 do
					if matches(stored[index], query.where) then table.remove(stored, index) end
				end
			end
			for _, record in ipairs(records) do table.insert(stored, record) end
			done(nil)
		end)
	end
	table.insert(self.waiting, run)
	self:flush()
end

-- A write was answered: the next loads may run, and the page is asked again.
function Backend:answered(message)
	self.writes = self.writes - 1
	self.changed(message)
	self:flush()
end

local function copyFields(target, source)
	for key, value in pairs(source) do target[key] = value end
end

local function removeRecord(rows, record)
	for index, candidate in ipairs(rows or {}) do
		if candidate == record then table.remove(rows, index); return index end
	end
end

-- `record` is in `db` already. On refusal it leaves it again.
function Backend:create(model, record, db)
	self.stores[db] = true
	local user = self.account.user
	if not user then
		removeRecord(db[model.tableName], record)
		self.changed("Sign-in is needed to save. Check the connection and try again.")
		return
	end
	self.writes = self.writes + 1
	self.rows:create(model.tableName, record, Rows.permissions(model.remote, user.id), function(saved, err)
		if err then
			removeRecord(db[model.tableName], record)
			self:answered(err.message)
			return
		end
		copyFields(record, saved)
		self:answered(nil)
	end)
end

-- `record` has `fields` already; `previous` are its values before. On refusal
-- they come back.
function Backend:update(model, record, fields, previous)
	self.writes = self.writes + 1
	self.rows:update(model.tableName, record.id, fields, nil, function(saved, err)
		if err then
			for key in pairs(fields) do record[key] = previous[key] end
			self:answered(err.message)
			return
		end
		copyFields(record, saved)
		self:answered(nil)
	end)
end

-- `record` left `db` from `index`. On refusal it returns there.
function Backend:delete(model, record, db, index)
	self.writes = self.writes + 1
	self.rows:delete(model.tableName, record.id, function(_, err)
		if err and err.status ~= 404 then
			local rows = db[model.tableName] or {}
			db[model.tableName] = rows
			table.insert(rows, math.min(index, #rows + 1), record)
			self:answered(err.message)
			return
		end
		-- A row already gone is deleted all the same.
		self:answered(nil)
	end)
end

-- The account (docs/backend.md). Each is sent like a write: loads wait for
-- it, and `changed(message)` follows. `accountBusy` is true while one is out.
-- Signing in or out moves to another account, so the remote rows of the
-- stores leave and the pages load the new account's.

function Backend:forgetRows()
	local Model = require("data.model")
	for db in pairs(self.stores) do
		for name, model in pairs(Model.models) do
			if model.remote then db[name] = {} end
		end
	end
end

function Backend:accountStep(step, moves)
	self.writes = self.writes + 1
	self.accountBusy = true
	step(function(_, err)
		self.accountBusy = false
		if not err and moves then self:forgetRows() end
		self:answered(err and err.message or nil)
	end)
end

-- Gives the anonymous account an email and password; its rows stay.
function Backend:register(email, password)
	self:accountStep(function(done) self.account:register(email, password, done) end, false)
end

function Backend:signIn(email, password)
	self:accountStep(function(done) self.account:signIn(email, password, done) end, true)
end

-- Ends the session and opens a new anonymous one, so the app keeps saving.
function Backend:signOut()
	self:accountStep(function(done)
		self.account:signOut(function(_, err)
			if err then done(nil, err); return end
			self.account:anonymous(done)
		end)
	end, true)
end

return Backend
