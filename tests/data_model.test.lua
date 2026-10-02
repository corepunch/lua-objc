-- Lapis-style models over a bound store: a class per table, a metatable per
-- row, queries that return the stored rows themselves, and relations.
_G.__headless = true
local t = require("TestKit")
local Model = require("data.model")

local function raises(fn, pattern, message)
	local ok, err = pcall(fn)
	t.expect(not ok and tostring(err):find(pattern) ~= nil, message .. " (" .. tostring(err) .. ")")
end

local Files, File = Model:extend("test_files", {primaryKey = "path", limit = 2,
	relations = {{"folder", belongsTo = "test_folders", key = "folderId"}}})
local Folders, Folder = Model:extend("test_folders", {relations = {{"files", hasMany = "test_files", key = "folderId"}}})
function Files:largest() return self:select(nil, {order = "bytes desc", limit = self.limit}) end
function File:megabytes() return self.bytes / 1e6 end
function Folder:label() return "Folder " .. self.name end

-- Before a store is bound every table is empty.
Model.db = nil
t.assertEqual(#Files:all(), 0, "no store, no rows")
t.expect(Files:find("/a") == nil, "and nothing to find")

local movie = {path = "/m/movie.mov", bytes = 4e9, folderId = "m"}
local store = Model.bind({
	test_files = {movie, {path = "/d/notes.txt", bytes = 2e6, folderId = "d"}, {path = "/d/app.dmg", bytes = 800e6, folderId = "d"},
		{path = "/x/unsized", folderId = "x"}},
	test_folders = {{id = "m", name = "Movies"}, {id = "d", name = "Downloads"}},
})
t.expect(Model.db == store, "bind returns the store and makes it current")

-- Class queries.
t.assertEqual(#Files:all(), 4, "all rows of the table")
t.expect(Files:find("/m/movie.mov") == movie, "find by the primary key returns the stored row itself")
t.assertEqual(Files:find({bytes = 2e6}).path, "/d/notes.txt", "find by fields")
t.assertEqual(Files:count({folderId = "d"}), 2, "count by fields")
t.assertEqual(Files:count(function(row) return (row.bytes or 0) > 1e9 end), 1, "count by a predicate")
local largest = Files:largest()
t.assertEqual(#largest, 2, "a limit cuts the result")
t.assertEqual(largest[1].path .. "," .. largest[2].path, "/m/movie.mov,/d/app.dmg", "ordered by a field, descending")
local ascending = Files:select(nil, {order = "bytes"})
t.assertEqual(ascending[1].path, "/d/notes.txt", "ascending by default")
t.assertEqual(ascending[#ascending].path, "/x/unsized", "rows without the field sort last")
t.assertEqual(#Files:select({folderId = "d"}, {order = function(a, b) return a.path < b.path end}), 2, "a comparator orders")
t.assertEqual(Files.limit, 2, "other spec fields are class constants")
t.assertEqual(Files.tableName, "test_files", "the class knows its table")

-- Row methods and relations.
t.assertEqual(movie:megabytes(), 4000, "a row answers its model's row methods")
t.expect(movie:model() == Files, "and knows its model")
t.assertEqual(movie:folder():label(), "Folder Movies", "belongsTo follows the key to the other model")
t.assertEqual(#Folders:find("d"):files(), 2, "hasMany selects the rows that point back")
t.expect(Files:find("/x/unsized"):folder() == nil, "a key that matches nothing is nil")
t.expect(movie.megabytes ~= nil and rawget(movie, "megabytes") == nil, "methods are not copied into the stored row")

-- create stores a row.
local created = Files:create({path = "/n/new", bytes = 1})
t.expect(store.test_files[#store.test_files] == created and created:megabytes() == 1e-6, "create stores and returns the row")
local Empty = Model:extend("test_empty")
Empty:create({id = 1})
t.assertEqual(#store.test_empty, 1, "create starts a table that is not stored yet")

-- A table computed from others names its rows.
local Large = Model:extend("test_large", {source = function(db)
	local rows = {}
	for _, row in ipairs(db.test_files) do if (row.bytes or 0) >= 800e6 then table.insert(rows, {id = row.path}) end end
	return rows
end})
t.assertEqual(#Large:all(), 2, "source(db) computes a table from the store")

-- A store bound later is the one queried.
Model.bind({test_files = {{path = "/only"}}})
t.assertEqual(#Files:all(), 1, "queries read the store bound now")

Model.bind(store)
-- Plain rows for views: fields copy, methods and functions compute.
local plain = Files:select({folderId = "m"}, {fields = {"path", mb = "megabytes", big = function(row) return row.bytes > 1e9 end}})
t.assertEqual(plain[1].path .. " " .. math.floor(plain[1].mb) .. " " .. tostring(plain[1].big), "/m/movie.mov 4000 true", "fields builds plain tables")
t.expect(getmetatable(plain[1]) == nil and plain[1].megabytes == nil, "which are not rows")

-- findAll keeps the order of the keys and skips unknown ones.
local found = Files:findAll({"/d/app.dmg", "/nope", "/m/movie.mov"})
t.assertEqual(#found .. found[1].path, "2/d/app.dmg", "findAll resolves keys in order")
t.assertEqual(#Files:findAll({"d"}, {key = "folderId"}), 1, "by another field, the first row per key")

-- update validates through constraints; delete removes.
local Settings, Setting = Model:extend("test_settings", {constraints = {
	name = function(_, value) if value:match("^%s*$") then return "A name is required" end end,
	threshold = function(_, value) if value < 0 then return "No negative thresholds" end end}})
Model.db.test_settings = {{id = "device", name = "Mac", threshold = 1}}
local device = Settings:find("device")
t.expect(device:update({name = "Studio"}) == true and device.name == "Studio", "update sets accepted fields")
local ok, message = device:update({name = " ", threshold = 5})
t.expect(ok == nil and message == "A name is required", "a constraint refuses with its message")
t.expect(device.name == "Studio" and device.threshold == 1, "and nothing changes")
ok, message = Settings:create({id = "other", name = ""})
t.expect(ok == nil and message == "A name is required" and #Model.db.test_settings == 1, "create checks constraints too")
t.expect(Settings:create({id = "second", name = "Second"}):delete() and #Model.db.test_settings == 1, "delete removes the row")
t.expect(not Setting.delete(setmetatable({}, Setting)), "deleting a row that is not stored does nothing")

-- Relation options: default keys, order, where, hasOne and fetch.
local Shelves = Model:extend("test_shelves", {singular = "test_shelf", relations = {
	{"books", hasMany = "test_books", order = "pages desc", where = {hidden = false}},
	{"thickest", hasOne = "test_books", order = "pages desc"},
	{"label", fetch = function(shelf) return "Shelf " .. shelf.id end}}})
Model:extend("test_books", {relations = {{"test_shelf", belongsTo = "test_shelves"}}})
Model.db.test_shelves = {{id = "a"}}
Model.db.test_books = {{id = 1, test_shelfId = "a", pages = 10, hidden = false}, {id = 2, test_shelfId = "a", pages = 300, hidden = true},
	{id = 3, test_shelfId = "a", pages = 90, hidden = false}}
local shelf = Shelves:find("a")
t.assertEqual(#shelf:books() .. ":" .. shelf:books()[1].id, "2:3", "hasMany filters with where and sorts with order, by the singular key")
t.assertEqual(shelf:thickest().id, 2, "hasOne is the first related row")
t.assertEqual(shelf:label(), "Shelf a", "fetch computes a relation")
t.expect(Model.models.test_books:find(1):test_shelf() == shelf, "belongsTo defaults its key to the name plus Id")

-- Enums name a picker's positions.
local filters = Model.enum({"Yours", "All", "Unused"})
t.assertEqual(filters[2], "All", "an enum is its list")
t.assertEqual(filters:index("Unused"), 3, "index of a name")
t.assertEqual(filters:name(1), "Yours", "name of a position")
raises(function() filters:index("Nope") end, "no option Nope", "an unknown name is an error")
raises(function() filters:name(9) end, "no option at 9", "an unknown position is an error")

-- bound binds a store for code that enters from outside.
local first, second = {test_files = {{path = "/first"}}}, {test_files = {{path = "/second"}}}
local readFirst = Model.bound(first, function() return Files:all()[1].path end)
Model.bind(second)
t.assertEqual(readFirst(), "/first", "a bound function reads its own store")
t.expect(Model.db == first, "and leaves it bound")

-- Errors.
raises(function() Model:extend("") end, "needs a table name", "a model names its table")
raises(function() Files:select(42) end, "nil, a table of fields or a function", "a where clause is a table or a function")
raises(function() Files:select(nil, {order = "a b c"}) end, "field desc", "an order is a field and a direction")
raises(function() Model:extend("test_bad", {relations = {{"x"}}}) end, "a relation is", "a relation names a table or a fetch")
local Ghost = Model:extend("test_ghost_holder", {relations = {{"ghost", belongsTo = "test_nobody", key = "id"}}})
Model.bind({test_ghost_holder = {{id = 1}}})
raises(function() Ghost:find(1):ghost() end, "which no model extends", "a relation to a model nobody extends")
Model.db = nil
raises(function() Files:create({}) end, "no store is bound", "create needs a store")

os.exit(t.summary() and 0 or 1)
