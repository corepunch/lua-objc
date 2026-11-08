-- The rows of one Appwrite TablesDB database, as the store's plain records.
--
--   local rows = Rows.new(client, "notes")
--   rows:list("notes", {Query.equal("listId", id)}, function(records, err, total) end)
--   rows:create("notes", record, permissions, function(record, err) end)
--   rows:update("notes", id, fields, permissions, function(record, err) end)
--   rows:delete("notes", id, function(ok, err) end)
--
-- A table here is a model's table: its rows are records keyed by `id`, as in
-- the local store. Appwrite's system fields read as `id`, `createdAt` and
-- `updatedAt`; its other `$` fields (`$tableId`, `$permissions`, `$sequence`…)
-- are not exposed. A record sends every field except those three.
local Json = require("data.appwrite.json")
local Client = require("data.appwrite.client")

local Rows = {}
Rows.__index = Rows

local SYSTEM = {["$id"] = "id", ["$createdAt"] = "createdAt", ["$updatedAt"] = "updatedAt"}
local OWN = {id = true, createdAt = true, updatedAt = true}

function Rows.new(client, database)
	assert(getmetatable(client) == Client, "Rows.new needs an Appwrite client")
	assert(Client.validId(database), "Rows.new needs a database ID")
	return setmetatable({client = client, database = database}, Rows)
end

-- The store record of an Appwrite row.
function Rows.record(row)
	local record = {}
	for key, value in pairs(row) do
		if SYSTEM[key] then record[SYSTEM[key]] = value
		elseif key:sub(1, 1) ~= "$" then record[key] = value end
	end
	return record
end

-- The `data` of a record: its fields without the three system ones, always an
-- object (a record of no fields is `{}`, not `[]`).
function Rows.data(record)
	local data = Json.object()
	for key, value in pairs(record) do
		if not OWN[key] then data[key] = value end
	end
	return data
end

-- A new row ID made on the device, so the stored record and the row share
-- it from the start: 20 characters of [a-z0-9], the first a letter.
function Rows.newId()
	local letters, digits = "abcdefghijklmnopqrstuvwxyz", "abcdefghijklmnopqrstuvwxyz0123456789"
	local first = math.random(#letters)
	local id = {letters:sub(first, first)}
	for _ = 2, 20 do
		local index = math.random(#digits)
		table.insert(id, digits:sub(index, index))
	end
	return table.concat(id)
end

-- The row permissions of a model's `remote` for user `userId`
-- (docs/backend.md): the owner updates and deletes; `remote` names who reads.
local READERS = {private = nil, shared = "users", public = "any"}
function Rows.permissions(remote, userId)
	assert(remote == "private" or remote == "shared" or remote == "public",
		"remote is private, shared or public")
	assert(Client.validId(userId), "row permissions need the signed-in user's ID")
	local owner = 'user:' .. userId
	return {
		'read("' .. (READERS[remote] or owner) .. '")',
		'update("' .. owner .. '")',
		'delete("' .. owner .. '")',
	}
end

function Rows:path(tableId, rowId)
	assert(Client.validId(tableId), "a table ID is required")
	local path = "/tablesdb/" .. self.database .. "/tables/" .. tableId .. "/rows"
	if rowId ~= nil then
		assert(Client.validId(rowId), "a row ID is required")
		path = path .. "/" .. rowId
	end
	return path
end

local function rowAnswer(done)
	return function(value, err)
		if err then done(nil, err); return end
		if type(value) ~= "table" or not Client.validId(value["$id"]) then
			done(nil, {type = "invalid_response", message = "Appwrite sent a row without an ID."})
			return
		end
		done(Rows.record(value))
	end
end

-- `done(records, nil, total)`: the rows matching `queries`, as records.
function Rows:list(tableId, queries, done)
	return self.client:call({path = self:path(tableId), queries = queries}, function(value, err)
		if err then done(nil, err); return end
		if type(value) ~= "table" or type(value.rows) ~= "table" then
			done(nil, {type = "invalid_response", message = "Appwrite sent a row list without rows."})
			return
		end
		local records = {}
		for _, row in ipairs(value.rows) do table.insert(records, (Rows.record(row))) end
		done(records, nil, value.total)
	end)
end

-- Creates the row of `record`, whose `id` it keeps (one is made when absent).
function Rows:create(tableId, record, permissions, done)
	local id = record.id or Rows.newId()
	return self.client:call({method = "POST", path = self:path(tableId), body = {
		rowId = id, data = Rows.data(record), permissions = permissions,
	}}, rowAnswer(done))
end

-- Changes `fields` of row `id`; `permissions` nil keeps the row's own.
function Rows:update(tableId, id, fields, permissions, done)
	return self.client:call({method = "PATCH", path = self:path(tableId, id), body = {
		data = Rows.data(fields), permissions = permissions,
	}}, rowAnswer(done))
end

function Rows:delete(tableId, id, done)
	return self.client:call({method = "DELETE", path = self:path(tableId, id)}, function(_, err)
		if err then done(nil, err) else done(true) end
	end)
end

return Rows
