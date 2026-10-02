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
	db[self.tableName] = db[self.tableName] or {}
	table.insert(db[self.tableName], record)
	return record
end

local Row = {}

-- Sets `fields` on the row when every constraint accepts them.
function Row:update(fields)
	local class = self:model()
	local message = check(class, self, fields)
	if message then return nil, message end
	for key, value in pairs(fields) do self[key] = value end
	return true
end

-- Removes the row from the stored table.
function Row:delete()
	local rows = self:model():source(Model.db) or {}
	for index, record in ipairs(rows) do
		if record == self then table.remove(rows, index); return true end
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
function Model:extend(tableName, spec)
	if type(tableName) ~= "string" or tableName == "" then error("Model:extend needs a table name", 2) end
	spec = spec or {}
	local class = setmetatable({tableName = tableName, primaryKey = spec.primaryKey or "id"}, Base)
	local row = setmetatable({}, {__index = Row})
	row.__index = row
	function row.model() return class end
	class.row = row
	for key, value in pairs(spec) do
		if key == "source" then
			class.source = function(_, db) return value(db) end
		elseif key ~= "relations" and key ~= "primaryKey" then
			class[key] = value
		end
	end
	for _, relationSpec in ipairs(spec.relations or {}) do relation(class, relationSpec) end
	-- A module loaded again (a reload) replaces its model.
	Model.models[tableName] = class
	return class, row
end

return Model
