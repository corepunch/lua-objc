-- Creates what an app's remote models need and the person's project lacks
-- (docs/backend.md): the database, each table, each column, each index of
-- `config` (Schema.config). It runs at launch for an app saving to the
-- connected project (lua/data/appwrite/connection.lua), over a client that
-- carries the project's API key.
--
--   Provision.run({client = keyClient, config = config, after = ns._timerAfter}, function(err) end)
--
-- It only adds. A column whose type changed, or one the models no longer
-- name, stays as it is: changing or dropping one loses data, which is the
-- Appwrite CLI's job (`appwrite push tables` with the schema script's file),
-- asked for on purpose. A launch with nothing missing costs one request for
-- the database and two per table.
--
-- Appwrite builds a new column in the background. Indexes need their columns
-- built and rows written before then are refused, so after adding columns it
-- asks again every `Provision.wait.seconds` until they are, at most
-- `Provision.wait.tries` times, with the one-shot `after(seconds, fn)`; it
-- does not wait for indexes, which queries do not need.
local Json = require("data.appwrite.json")
local Query = require("data.appwrite.query")

local Provision = {}

Provision.wait = {seconds = 0.5, tries = 60}

-- The column endpoint of each schema type (Schema's `column`).
local ENDPOINTS = {
	varchar = "varchar", text = "text", integer = "integer", double = "float",
	boolean = "boolean", datetime = "datetime",
}
local FORMATS = {email = "email", url = "url", enum = "enum"}

function Provision.columnPath(column)
	local kind = column.type == "string" and FORMATS[column.format] or ENDPOINTS[column.type]
	assert(kind, "provision: no Appwrite column endpoint for " .. tostring(column.type))
	return kind
end

function Provision.columnBody(column)
	return Json.object({
		key = column.key, required = column.required == true, array = column.array == true,
		size = column.size, min = column.min, max = column.max,
		elements = column.elements, default = column.default,
	})
end

local function each(items, step, finish)
	local index = 0
	local function continue(err)
		if err then finish(err); return end
		index = index + 1
		if index > #items then finish(nil); return end
		step(items[index], continue)
	end
	continue(nil)
end

local function labelled(err, what)
	return {type = err.type, status = err.status, message = what .. ": " .. tostring(err.message)}
end

-- GETs `path`; on 404 sends `create`. `done(err)`.
local function ensure(client, path, create, what, done)
	client:call({path = path}, function(_, err)
		if not err then done(nil); return end
		if err.status ~= 404 then done(labelled(err, what)); return end
		client:call(create, function(_, createErr)
			done(createErr and labelled(createErr, "Creating " .. what) or nil)
		end)
	end)
end

local function keyed(list)
	local byKey = {}
	for _, item in ipairs(list or {}) do byKey[item.key] = item end
	return byKey
end

local LIMIT = Query.limit(5000)

local function provisionTable(client, after, database, spec, done)
	local base = "/tablesdb/" .. database .. "/tables/" .. spec["$id"]
	local what = "table " .. spec["$id"]
	ensure(client, base, {method = "POST", path = "/tablesdb/" .. database .. "/tables", body = Json.object({
		tableId = spec["$id"], name = spec.name, permissions = spec["$permissions"],
		rowSecurity = spec.rowSecurity, enabled = spec.enabled,
	})}, what, function(err)
		if err then done(err); return end
		client:call({path = base .. "/columns", queries = {LIMIT}}, function(list, listErr)
			if listErr then done(labelled(listErr, what)); return end
			local existing, added = keyed(list.columns), {}
			local missing = {}
			for _, column in ipairs(spec.columns) do
				if not existing[column.key] then table.insert(missing, column) end
			end
			each(missing, function(column, continue)
				client:call({method = "POST", path = base .. "/columns/" .. Provision.columnPath(column),
					body = Provision.columnBody(column)}, function(_, columnErr)
					if columnErr then continue(labelled(columnErr, "Creating column " .. column.key .. " of " .. what)); return end
					added[column.key] = true
					continue(nil)
				end)
			end, function(columnsErr)
				if columnsErr then done(columnsErr); return end
				local tries = 0
				local function indexes()
					client:call({path = base .. "/indexes", queries = {LIMIT}}, function(indexList, indexErr)
						if indexErr then done(labelled(indexErr, what)); return end
						local have, wanted = keyed(indexList.indexes), {}
						for _, index in ipairs(spec.indexes) do
							if not have[index.key] then table.insert(wanted, index) end
						end
						each(wanted, function(index, continue)
							client:call({method = "POST", path = base .. "/indexes", body = Json.object({
								key = index.key, type = index.type, columns = index.columns, orders = index.orders,
							})}, function(_, createErr)
								continue(createErr and labelled(createErr, "Creating index " .. index.key .. " of " .. what) or nil)
							end)
						end, done)
					end)
				end
				-- Columns just added are built in the background; wait until they are.
				local function built()
					if next(added) == nil then indexes(); return end
					client:call({path = base .. "/columns", queries = {LIMIT}}, function(columns, waitErr)
						if waitErr then done(labelled(waitErr, what)); return end
						local byKey = keyed(columns.columns)
						for key in pairs(added) do
							local status = byKey[key] and byKey[key].status
							if status == "failed" or status == "stuck" then
								done({type = "column_" .. status, message = "Appwrite could not build column " .. key .. " of " .. what})
								return
							end
							if status ~= "available" then
								tries = tries + 1
								if tries > Provision.wait.tries then
									done({type = "column_processing", message = "Column " .. key .. " of " .. what .. " is still being built. Open the app again in a moment."})
									return
								end
								after(Provision.wait.seconds, built)
								return
							end
						end
						indexes()
					end)
				end
				built()
			end)
		end)
	end)
end

-- `options` = {client, config, after}; `done(err)` once, err `{type, message, status}`.
function Provision.run(options, done)
	local client, config, after = options.client, options.config, options.after
	assert(client and client.credential, "provision: the client carries the API key")
	local database = config.tablesDB[1]
	ensure(client, "/tablesdb/" .. database["$id"], {method = "POST", path = "/tablesdb", body = Json.object({
		databaseId = database["$id"], name = database.name, enabled = true,
	})}, "database " .. database["$id"], function(err)
		if err then done(err); return end
		each(config.tables, function(spec, continue)
			provisionTable(client, after, database["$id"], spec, continue)
		end, done)
	end)
end

return Provision
