-- The remote models of an app as the `appwrite.json` the Appwrite CLI
-- pushes (`appwrite push tables`): one TablesDB database, one table per
-- remote model, its columns and indexes. The models are the source; the file
-- is generated into build/ and never committed (docs/backend.md).
--
--   local config = Schema.config({project = "…", endpoint = "https://…/v1",
--   	database = "notes", models = {Lists, Notes}})
--   io.open("build/notes.appwrite.json", "w"):write(Schema.encode(config))
--
-- Column types are Appwrite 1.8's: `varchar` with its size, `text`,
-- `integer`, `double` (Appwrite's float), `boolean`, `datetime`, and
-- `string` with a `format` for email, url and enum.
local Json = require("data.appwrite.json")
local Client = require("data.appwrite.client")

local Schema = {}

-- Every remote row is created by a signed-in user and read as its row
-- permissions say (Rows.permissions); the table grants nothing else.
Schema.tablePermissions = {'create("users")'}

local SYSTEM = {id = "$id", createdAt = "$createdAt", updatedAt = "$updatedAt"}

local function column(parsed)
	local entry = {key = parsed.key, required = parsed.required, array = parsed.array}
	local kind = parsed.kind
	if kind == "string" then entry.type, entry.size = "varchar", parsed.size
	elseif kind == "text" then entry.type = "text"
	elseif kind == "integer" then entry.type = "integer"
	elseif kind == "float" then entry.type = "double"
	elseif kind == "boolean" or kind == "datetime" then entry.type = kind
	elseif kind == "email" or kind == "url" then entry.type, entry.format = "string", kind
	elseif kind == "enum" then entry.type, entry.format, entry.elements = "string", "enum", parsed.elements
	else error("schema: no Appwrite column for " .. tostring(kind), 0) end
	entry.min, entry.max, entry.default = parsed.min, parsed.max, parsed.default
	return Json.object(entry)
end

local function index(parsed)
	local columns = {}
	for _, name in ipairs(parsed.columns) do table.insert(columns, SYSTEM[name] or name) end
	return Json.object({key = parsed.key, type = parsed.type, columns = columns, orders = parsed.orders})
end

function Schema.table(model, database)
	assert(model.remote, "schema: " .. tostring(model.tableName) .. " is not a remote model")
	local columns, indexes = {}, {}
	for _, parsed in ipairs(model.columns) do table.insert(columns, (column(parsed))) end
	for _, parsed in ipairs(model.indexes) do table.insert(indexes, (index(parsed))) end
	return Json.object({
		["$id"] = model.tableName,
		["$permissions"] = Schema.tablePermissions,
		databaseId = database,
		name = model.tableName,
		enabled = true,
		rowSecurity = true,
		columns = columns,
		indexes = indexes,
	})
end

-- The remote models among `models` (a list, or Model.models by table name),
-- in table-name order.
function Schema.remoteModels(models)
	local remote = {}
	for _, model in pairs(models) do
		if model.remote then table.insert(remote, model) end
	end
	table.sort(remote, function(a, b) return a.tableName < b.tableName end)
	return remote
end

function Schema.config(options)
	assert(type(options.project) == "string" and options.project ~= "", "schema: a project is required")
	assert(type(options.endpoint) == "string" and options.endpoint:match("^https?://"), "schema: an endpoint is required")
	assert(Client.validId(options.database), "schema: a database ID is required")
	local models = Schema.remoteModels(options.models or {})
	assert(#models > 0, "schema: the app has no remote models")
	local tables = {}
	for _, model in ipairs(models) do table.insert(tables, (Schema.table(model, options.database))) end
	return Json.object({
		projectId = options.project,
		endpoint = options.endpoint,
		tablesDB = {Json.object({["$id"] = options.database, name = options.database, enabled = true})},
		tables = tables,
	})
end

function Schema.encode(config)
	return Json.encode(config)
end

return Schema
