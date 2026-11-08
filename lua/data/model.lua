-- Models: Lapis' Model over the app's store.
--
-- A model is one table of the store. `extend` returns the class, whose
-- methods query the table, and the metatable of its rows, whose methods a
-- row answers (Lapis: `local Users, User = Model:extend("users")`):
--
--   local Model = require("data.model")
--   local Files, File = Model:extend("files", {primaryKey = "path"})
--
--   function Files:largest(limit)                 -- a class method: a query
--   	return self:select(nil, {order = "bytes desc", limit = limit})
--   end
--   function File:folder()                        -- a row method
--   	return self.path:match("^(.*)/")
--   end
--
--   Files:find("/Users/me/movie.mov"):folder()
--
-- The store is plain Lua data the app binds, as Lapis connects to its
-- database: `Model.bind(store)`, after which the rows of Files are
-- `store.files`. A table that is not stored under its own name, or is
-- computed from other tables, names its rows with `source(db)`:
--
--   local Leftovers = Model:extend("leftovers", {source = function(db) ... end})
--
-- Rows are the stored tables themselves, given the row metatable when read:
-- a query returns new arrays of them but never copies a row, and native
-- lists read a row's own fields, never its methods. There are no
-- notifications: a page asks its models again each time it is drawn.
--
-- Class methods:
--   all()                    every row
--   find(key | where)        one row by primary key, or by fields
--   findAll(keys, opts)      the rows whose keys are listed, in that order
--                            (`opts.key` names another field)
--   select(where, opts)      `where` is nil, a table of fields a row must
--                            equal, or a function of the row; `opts.order` is
--                            "field", "field desc" or a comparator,
--                            `opts.limit` a count, `opts.fields` the plain
--                            tables to return (below)
--   count(where)
--   create(record)           stores a row; nil, message when a constraint refuses
--   load(record)             gives a record the row metatable
-- Row methods: `row:update(fields)` (nil, message when a constraint
-- refuses; nothing changes then), `row:delete()`, `row:model()`.
--
-- `opts.fields` turns rows into the plain tables a view or a native list
-- reads: a list of field names copies them, and `name = "method"` or
-- `name = function(row)` computes one:
--
--   Folders:select(nil, {order = "bytes desc", fields = {"name", "icon", size = "sizeText"}})
--
-- `constraints` validate a field when a row is created or updated: each is
-- `function(row, value)` returning a message to refuse it (Lapis does the same):
--
--   Model:extend("settings", {constraints = {
--   	deviceName = function(_, name) if name:match("^%s*$") then return "A name is required" end end,
--   }})
--
-- `relations` adds row methods that look rows up in other models, by the
-- other model's table name; it must have been required before a relation
-- is followed. `key` defaults to the relation's name plus "Id" for
-- belongsTo, and to this table's singular name plus "Id" otherwise
-- (`singular`, or the name without a trailing "s"); hasMany takes `where`
-- and `order` like select, and `fetch = function(row)` computes a relation:
--
--   Model:extend("files", {relations = {
--   	{"location", belongsTo = "locations"},                           -- file:location(), by locationId
--   }})
--   Model:extend("locations", {relations = {
--   	{"files", hasMany = "files", order = "bytes desc"},              -- location:files()
--   	{"largest", hasOne = "files", order = "bytes desc"},
--   	{"owner", fetch = function(location) return Apps:owning(location.path) end},
--   }})
--
-- `remote` keeps a model's rows online (docs/backend.md): it names who reads
-- a row, `fields` are its columns and `indexes` its indexes, parsed into
-- `Model.columns` and `Model.indexes` when the model is declared:
--
--   Model:extend("notes", {remote = "private",
--   	fields = {title = "string(255)", body = "text?", tags = "string(32)[]?",
--   		priority = {"integer?", min = 0, max = 3, default = 0}},
--   	indexes = {{"listId", "dueAt desc"}, {"title", fulltext = true}},
--   })
--
-- `Model.enum{...}` names the positions of a list, a picker's options:
--   Files.filters = Model.enum{"Yours", "All", "Unused for a year"}
--   Files.filters[2] == "All"; Files.filters:index("All") == 2
local Model = {}

-- The bound store, and every model by its table name.
Model.db = nil
Model.models = {}

-- Binds the store every model reads and returns it.
function Model.bind(db)
	assert(type(db) == "table", "Model.bind needs the store table")
	Model.db = db
	return db
end

-- Connects the backend that remote models write through and read from
-- (lua/data/backend.lua): the launcher of an app with a `<Backend>` does
-- this once. nil disconnects it.
Model.backend = nil
function Model.connect(backend)
	Model.backend = backend
	return backend
end

local function remoteBackend(class)
	return Model.backend or error("model " .. class.tableName .. " is remote, but the app has no <Backend>", 3)
end

-- `fn` with `db` bound: for code that enters an app from outside (a
-- callback of a service, an action of one window of several) when more
-- than one store is open.
function Model.bound(db, fn)
	return function(...)
		Model.db = db
		return fn(...)
	end
end

local Enum = {}
Enum.__index = Enum

-- The position of option `name`; an unknown name is an error.
function Enum:index(name)
	for index, value in ipairs(self) do
		if value == name then return index end
	end
	error("enum: no option " .. tostring(name), 2)
end

-- The option at `index`; an unknown position is an error.
function Enum:name(index)
	local value = self[index]
	if value == nil then error("enum: no option at " .. tostring(index), 2) end
	return value
end

function Model.enum(list)
	assert(type(list) == "table", "Model.enum needs a list of names")
	local enum = {}
	for index, name in ipairs(list) do enum[index] = name end
	return setmetatable(enum, Enum)
end

local Base = {}
Base.__index = Base

local function matcher(where)
	if where == nil then return nil end
	if type(where) == "function" then return where end
	if type(where) ~= "table" then error("a model query takes nil, a table of fields or a function", 3) end
	return function(row)
		for key, value in pairs(where) do
			if row[key] ~= value then return false end
		end
		return true
	end
end

local function comparator(order)
	if order == nil or type(order) == "function" then return order end
	local field, direction = order:match("^(%S+)%s*(%a*)$")
	if not field then error("model order " .. tostring(order) .. ": use \"field\" or \"field desc\"", 3) end
	local descending = direction:lower() == "desc"
	return function(a, b)
		local x, y = a[field], b[field]
		if x == nil then return false end
		if y == nil then return true end
		if descending then return x > y end
		return x < y
	end
end

local function project(row, fields)
	local plain = {}
	for key, field in pairs(fields) do
		if type(key) == "number" then plain[field] = row[field]
		elseif type(field) == "function" then plain[key] = field(row)
		else plain[key] = row[field](row) end
	end
	return plain
end

-- The stored rows of the table, or an empty list before anything is stored.
function Base:source(db)
	if db == nil then return {} end
	return db[self.tableName] or {}
end

-- Gives a stored record the row metatable. A record with a metatable of its
-- own is left as it is. Queries call this local, so a model may name a
-- class method of its own `load`.
local function wrap(class, record)
	if record ~= nil and getmetatable(record) == nil then setmetatable(record, class.row) end
	return record
end

function Base:load(record) return wrap(self, record) end

function Base:all()
	local rows, result = self:source(Model.db) or {}, {}
	for _, record in ipairs(rows) do table.insert(result, (wrap(self, record))) end
	return result
end

function Base:select(where, opts)
	local test, result = matcher(where), {}
	for _, row in ipairs(self:all()) do
		if not test or test(row) then table.insert(result, row) end
	end
	opts = opts or {}
	local order = comparator(opts.order)
	if order then table.sort(result, order) end
	if opts.limit then
		for index = #result, opts.limit + 1, -1 do table.remove(result, index) end
	end
	if opts.fields then
		for index, row in ipairs(result) do result[index] = project(row, opts.fields) end
	end
	return result
end

function Base:count(where)
	local test, count = matcher(where), 0
	for _, row in ipairs(self:all()) do
		if not test or test(row) then count = count + 1 end
	end
	return count
end

-- `find(key)` by the primary key, or `find{field = value}`.
function Base:find(key)
	if key == nil then return nil end
	local test = type(key) == "table" and matcher(key) or nil
	local primary = self.primaryKey
	for _, record in ipairs(self:source(Model.db) or {}) do
		if (test and test(wrap(self, record))) or (not test and record[primary] == key) then return wrap(self, record) end
	end
	return nil
end

function Base:findAll(keys, opts)
	local field, byKey, result = opts and opts.key or self.primaryKey, {}, {}
	for _, row in ipairs(self:all()) do
		if row[field] ~= nil and byKey[row[field]] == nil then byKey[row[field]] = row end
	end
	for _, key in ipairs(keys or {}) do
		if byKey[key] then table.insert(result, byKey[key]) end
	end
	return result
end

local function check(class, row, fields)
	for key, value in pairs(fields) do
		local constraint = class.constraints and class.constraints[key]
		local message = constraint and constraint(row, value)
		if message then return message end
	end
end

-- Stores a new row in the bound store and returns it.
function Base:create(record)
	local db = Model.db
	if not db then error("model " .. self.tableName .. ": no store is bound", 2) end
	local message = check(self, wrap(self, record), record)
	if message then return nil, message end
	local backend = self.remote and remoteBackend(self)
	-- A remote row's ID is made here, so the stored row and the server's
	-- share it from the start.
	if backend and record.id == nil then record.id = backend:newId() end
	db[self.tableName] = db[self.tableName] or {}
	table.insert(db[self.tableName], record)
	if backend then backend:create(self, record, db) end
	return record
end

-- The request for the rows a page shows: a route's `load` returns it, the
-- page controller sends it, and the rows matching `where` are replaced by
-- the answer (docs/backend.md). `where` is a table of exact fields; `opts`
-- takes `order` ("field" or "field desc"), `limit` and `after` (a row ID:
-- the next window, appended).
function Base:query(where, opts)
	if not self.remote then error("model " .. self.tableName .. " is not remote; read it with select", 2) end
	if where ~= nil and type(where) ~= "table" then
		error("model " .. self.tableName .. ": a query's where is a table of fields; a function cannot be sent", 2)
	end
	if opts and type(opts.order) == "function" then
		error("model " .. self.tableName .. ": a query orders by \"field\" or \"field desc\"", 2)
	end
	return {model = self, where = where or {}, opts = opts or {}}
end

local Row = {}

-- Sets `fields` on the row when every constraint accepts them.
function Row:update(fields)
	local class = self:model()
	local message = check(class, self, fields)
	if message then return nil, message end
	local backend = class.remote and remoteBackend(class)
	if backend then
		for key in pairs(fields) do
			if key == "id" or key == "createdAt" or key == "updatedAt" then
				error("model " .. class.tableName .. ": " .. key .. " belongs to the server", 2)
			end
		end
	end
	local previous = {}
	for key, value in pairs(fields) do
		previous[key] = self[key]
		self[key] = value
	end
	if backend then backend:update(class, self, fields, previous) end
	return true
end

-- Removes the row from the stored table.
function Row:delete()
	local class, db = self:model(), Model.db
	local rows = class:source(db) or {}
	for index, record in ipairs(rows) do
		if record == self then
			table.remove(rows, index)
			if class.remote then remoteBackend(class):delete(class, self, db, index) end
			return true
		end
	end
	return false
end

local function relation(class, spec)
	local name = spec[1]
	local target = spec.belongsTo or spec.hasMany or spec.hasOne
	if type(name) ~= "string" or (target == nil and type(spec.fetch) ~= "function") then
		error("model " .. class.tableName .. ": a relation is {name, belongsTo | hasMany | hasOne = table} or {name, fetch = function}", 3)
	end
	if spec.fetch then class.row[name] = spec.fetch; return end
	local function other()
		return Model.models[target] or error("model " .. class.tableName .. ": relation " .. name .. " names " .. target .. ", which no model extends", 0)
	end
	if spec.belongsTo then
		local key = spec.key or (name .. "Id")
		class.row[name] = function(row) return other():find(row[key]) end
		return
	end
	local key = spec.key or ((class.singular or class.tableName:gsub("s$", "")) .. "Id")
	local where = matcher(spec.where)
	local function related(row)
		local id = row[class.primaryKey]
		return other():select(function(candidate) return candidate[key] == id and (not where or where(candidate)) end,
			{order = spec.order})
	end
	if spec.hasOne then
		class.row[name] = function(row) return related(row)[1] end
	else
		class.row[name] = related
	end
end

-- `extend(tableName, spec)` returns the class and the row metatable's
-- methods. `spec` sets `primaryKey` (default "id"), `source(db)`,
-- `relations`, `constraints` and `singular`; any other field is a constant
-- of the class.
-- Remote tables (docs/backend.md). `remote` names who reads a row; `fields`
-- are the table's columns and `indexes` its indexes, both declared here so
-- the models are the schema. They are parsed when the model is declared, so
-- a mistake is an error at require time, not at provisioning. Nothing here
-- knows Appwrite: data/appwrite/schema.lua maps the parsed columns.
local REMOTE = {private = true, shared = true, public = true}
local KINDS = {text = true, integer = true, float = true, boolean = true, datetime = true, email = true, url = true}
-- The fields every remote row has; a model reads them but never declares them.
local SYSTEM = {id = true, createdAt = true, updatedAt = true}
local COLUMN_KEY = "^[%a][%w_]*$"

local function columnError(tableName, key, message)
	error("model " .. tableName .. " field " .. tostring(key) .. ": " .. message, 0)
end

-- "string(255)", "enum(draft|done)[]?", {"integer?", min = 0, default = 0}
-- -> {key, kind, size, elements, array, required, min, max, default}
local function parseColumn(tableName, key, spec)
	if type(key) ~= "string" or not key:match(COLUMN_KEY) or #key > 36 then
		columnError(tableName, key, "a column name is a letter then letters, digits or _, at most 36")
	end
	if SYSTEM[key] then columnError(tableName, key, "id, createdAt and updatedAt belong to every row") end
	local options = {}
	if type(spec) == "table" then options, spec = spec, spec[1] end
	if type(spec) ~= "string" then columnError(tableName, key, "a column is a type such as \"string(64)\"") end
	local column = {key = key, required = true, array = false}
	local text = spec
	if text:sub(-1) == "?" then column.required, text = false, text:sub(1, -2) end
	if text:sub(-2) == "[]" then column.array, text = true, text:sub(1, -3) end
	local size = text:match("^string%((%d+)%)$")
	local elements = text:match("^enum%((.+)%)$")
	if size then
		column.kind, column.size = "string", tonumber(size)
		if column.size < 1 then columnError(tableName, key, "a string holds at least one character") end
	elseif elements then
		column.kind, column.elements = "enum", {}
		for element in (elements .. "|"):gmatch("([^|]*)|") do
			if element == "" then columnError(tableName, key, "an enum lists its values as enum(a|b|c)") end
			table.insert(column.elements, element)
		end
	elseif KINDS[text] then
		column.kind = text
	else
		columnError(tableName, key, "unknown type " .. spec .. "; use string(n), text, integer, float, "
			.. "boolean, datetime, email, url or enum(a|b), with [] for a list and ? when optional")
	end
	if options.min ~= nil or options.max ~= nil then
		if column.kind ~= "integer" and column.kind ~= "float" then
			columnError(tableName, key, "only a number has min and max")
		end
		column.min, column.max = options.min, options.max
	end
	if options.default ~= nil then
		-- Appwrite's rule: a required column and a list have no default.
		if column.required then columnError(tableName, key, "a required column has no default; make it optional (?)") end
		if column.array then columnError(tableName, key, "a list has no default") end
		column.default = options.default
	end
	for option in pairs(options) do
		if option ~= 1 and option ~= "min" and option ~= "max" and option ~= "default" then
			columnError(tableName, key, "unknown option " .. tostring(option))
		end
	end
	return column
end

-- {"listId", "dueAt desc", unique = true, key = "…"} -> {key, type, columns, orders}
local function parseIndex(tableName, columns, spec)
	if type(spec) ~= "table" or #spec == 0 then
		error("model " .. tableName .. ": an index lists its columns, {\"listId\", \"dueAt desc\"}", 0)
	end
	if spec.unique and spec.fulltext then error("model " .. tableName .. ": an index is unique or fulltext, not both", 0) end
	local index = {type = spec.unique and "unique" or spec.fulltext and "fulltext" or "key", columns = {}, orders = {}}
	for _, entry in ipairs(spec) do
		local name, direction = tostring(entry):match("^(%S+)%s*(%a*)$")
		direction = (direction or ""):lower()
		if not name or (direction ~= "" and direction ~= "asc" and direction ~= "desc") then
			error("model " .. tableName .. ": index column " .. tostring(entry) .. " is \"name\" or \"name desc\"", 0)
		end
		if not columns[name] and not SYSTEM[name] then
			error("model " .. tableName .. ": index column " .. name .. " is not a field", 0)
		end
		table.insert(index.columns, name)
		table.insert(index.orders, direction == "desc" and "DESC" or "ASC")
	end
	index.key = spec.key or ("idx_" .. table.concat(index.columns, "_"))
	if not index.key:match(COLUMN_KEY) or #index.key > 36 then
		error("model " .. tableName .. ": index key " .. index.key .. " is longer than 36 characters; name it with key = \"…\"", 0)
	end
	return index
end

local function declareRemote(class, spec)
	local tableName = class.tableName
	if spec.remote == nil then
		if spec.fields or spec.indexes then
			error("model " .. tableName .. ": fields and indexes describe a remote table; add remote = \"private\"", 0)
		end
		return
	end
	if not REMOTE[spec.remote] then error("model " .. tableName .. ": remote is \"private\", \"shared\" or \"public\"", 0) end
	if not tableName:match("^[%w][%w%._%-]*$") or #tableName > 36 then
		error("model " .. tableName .. ": a remote table name is letters, digits, . _ or -, at most 36", 0)
	end
	if spec.source then error("model " .. tableName .. ": a computed model cannot be remote", 0) end
	if class.primaryKey ~= "id" then error("model " .. tableName .. ": a remote row's key is id", 0) end
	if type(spec.fields) ~= "table" or next(spec.fields) == nil then
		error("model " .. tableName .. ": a remote model declares its fields", 0)
	end
	local columns, byKey = {}, {}
	for key, column in pairs(spec.fields) do
		local parsed = parseColumn(tableName, key, column)
		byKey[key] = parsed
		table.insert(columns, parsed)
	end
	-- Fields are a map, so the column order is the names' order: stable output.
	table.sort(columns, function(a, b) return a.key < b.key end)
	local indexes, keys = {}, {}
	for _, indexSpec in ipairs(spec.indexes or {}) do
		local index = parseIndex(tableName, byKey, indexSpec)
		if keys[index.key] then error("model " .. tableName .. ": two indexes are named " .. index.key, 0) end
		keys[index.key] = true
		table.insert(indexes, index)
	end
	class.remote, class.columns, class.indexes = spec.remote, columns, indexes
end

function Model:extend(tableName, spec)
	if type(tableName) ~= "string" or tableName == "" then error("Model:extend needs a table name", 2) end
	spec = spec or {}
	local class = setmetatable({tableName = tableName, primaryKey = spec.primaryKey or "id"}, Base)
	declareRemote(class, spec)
	local row = setmetatable({}, {__index = Row})
	row.__index = row
	function row.model() return class end
	class.row = row
	for key, value in pairs(spec) do
		if key == "source" then
			class.source = function(_, db) return value(db) end
		elseif key ~= "relations" and key ~= "primaryKey" and key ~= "remote"
				and key ~= "fields" and key ~= "indexes" then
			class[key] = value
		end
	end
	for _, relationSpec in ipairs(spec.relations or {}) do relation(class, relationSpec) end
	-- A module loaded again (a reload) replaces its model.
	Model.models[tableName] = class
	return class, row
end

return Model
