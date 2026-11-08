-- Remote models (lua/data/model.lua) and the appwrite.json made from them
-- (lua/data/appwrite/schema.lua).
local t = require("TestKit")
local ns = require("AppKit")
local Model = require("data.model")
local Schema = require("data.appwrite.schema")

local function refuses(name, spec, fragment, label)
	local ok, err = pcall(Model.extend, Model, name, spec)
	t.expect(not ok and tostring(err):find(fragment, 1, true) ~= nil, label .. ": " .. tostring(err))
end

-- Declaration.
local Lists = Model:extend("remote_lists", {remote = "private", fields = {name = "string(80)"}})
local Notes = Model:extend("remote_notes", {
	remote = "shared",
	fields = {
		title = "string(255)",
		body = "text?",
		done = "boolean?",
		dueAt = "datetime?",
		listId = "string(36)",
		tags = "string(32)[]?",
		contact = "email?",
		link = "url?",
		state = {"enum(open|done|archived)?", default = "open"},
		priority = {"integer?", min = 0, max = 3, default = 0},
		weight = {"float?", min = 0},
	},
	indexes = {{"listId", "dueAt desc"}, {"title", fulltext = true}, {"listId", "title", unique = true, key = "one_title"},
		{"listId", "createdAt desc"}},
	constraints = {title = function(_, title) if title:match("^%s*$") then return "A title is required" end end},
	relations = {{"list", belongsTo = "remote_lists"}},
})
t.assertEqual(Notes.remote, "shared", "a remote model keeps who reads it")
t.assertEqual(#Notes.columns, 11, "every field is a column")
t.assertEqual(Notes.columns[1].key, "body", "columns are in name order")
t.assertEqual(Notes.fields, nil, "the raw field specs are not class values")
t.expect(Notes.row.list ~= nil and Notes.constraints.title ~= nil, "relations and constraints still work")
local byKey = {}
for _, column in ipairs(Notes.columns) do byKey[column.key] = column end
t.expect(byKey.title.kind == "string" and byKey.title.size == 255 and byKey.title.required and not byKey.title.array,
	"string(n) is a required string of n")
t.expect(byKey.tags.array and not byKey.tags.required and byKey.tags.size == 32, "[] is a list, ? optional")
t.expect(byKey.state.kind == "enum" and #byKey.state.elements == 3 and byKey.state.elements[3] == "archived"
	and byKey.state.default == "open", "an enum lists its values and may have a default")
t.expect(byKey.priority.min == 0 and byKey.priority.max == 3 and byKey.priority.default == 0, "numbers take min, max and default")
t.assertEqual(Notes.indexes[1].key, "idx_listId_dueAt", "an index is named after its columns")
t.assertEqual(table.concat(Notes.indexes[1].orders, ","), "ASC,DESC", "desc orders a column down")
t.expect(Notes.indexes[2].type == "fulltext" and Notes.indexes[3].type == "unique" and Notes.indexes[3].key == "one_title",
	"fulltext, unique and named indexes")

-- A local model is unchanged.
local Local = Model:extend("remote_local", {primaryKey = "path"})
t.expect(Local.remote == nil and Local.columns == nil, "a model without remote has no columns")

-- Mistakes are errors at declaration.
refuses("remote_bad", {fields = {a = "text"}}, "add remote", "fields without remote")
refuses("remote_bad", {indexes = {{"a"}}}, "add remote", "indexes without remote")
refuses("remote_bad", {remote = "everyone", fields = {a = "text"}}, "private", "remote is one of three")
refuses("remote_bad", {remote = "private"}, "declares its fields", "a remote model needs fields")
refuses("remote_bad", {remote = "private", fields = {}}, "declares its fields", "empty fields")
refuses("remote bad", {remote = "private", fields = {a = "text"}}, "remote table name", "a table name with a space")
refuses("remote_bad", {remote = "private", primaryKey = "path", fields = {a = "text"}}, "key is id", "remote rows are keyed by id")
refuses("remote_bad", {remote = "private", source = function() return {} end, fields = {a = "text"}}, "computed", "a computed model")
refuses("remote_bad", {remote = "private", fields = {a = "string"}}, "unknown type string", "string needs a size")
refuses("remote_bad", {remote = "private", fields = {a = "string(0)"}}, "at least one", "a zero-size string")
refuses("remote_bad", {remote = "private", fields = {a = "varchar(4)"}}, "unknown type", "an unknown type")
refuses("remote_bad", {remote = "private", fields = {a = "enum(a||b)"}}, "enum(a|b|c)", "an empty enum value")
refuses("remote_bad", {remote = "private", fields = {id = "text"}}, "belong to every row", "id is not declared")
refuses("remote_bad", {remote = "private", fields = {createdAt = "datetime"}}, "belong to every row", "createdAt is not declared")
refuses("remote_bad", {remote = "private", fields = {["2nd"] = "text"}}, "a letter then", "a column name starts with a letter")
refuses("remote_bad", {remote = "private", fields = {a = 5}}, "is a type", "a column is a type string")
refuses("remote_bad", {remote = "private", fields = {a = {"text", default = "x"}}}, "required column has no default",
	"a required column with a default")
refuses("remote_bad", {remote = "private", fields = {a = {"text[]?", default = "x"}}}, "list has no default", "a list with a default")
refuses("remote_bad", {remote = "private", fields = {a = {"text?", min = 1}}}, "only a number", "min on text")
refuses("remote_bad", {remote = "private", fields = {a = {"text?", size = 1}}}, "unknown option size", "an unknown option")
refuses("remote_bad", {remote = "private", fields = {a = "text"}, indexes = {{"b"}}}, "is not a field", "an index of a missing column")
refuses("remote_bad", {remote = "private", fields = {a = "text"}, indexes = {{}}}, "lists its columns", "an empty index")
refuses("remote_bad", {remote = "private", fields = {a = "text"}, indexes = {{"a sideways"}}}, "name desc", "a bad direction")
refuses("remote_bad", {remote = "private", fields = {a = "text"}, indexes = {{"a", unique = true, fulltext = true}}},
	"not both", "unique and fulltext")
refuses("remote_bad", {remote = "private", fields = {a = "text"}, indexes = {{"a"}, {"a"}}}, "two indexes", "duplicate index names")
refuses("remote_bad", {remote = "private", fields = {averyveryveryverylongcolumnnamexyz = "text"},
	indexes = {{"averyveryveryverylongcolumnnamexyz"}}}, "longer than 36", "a generated index key that is too long")

-- appwrite.json.
local config = Schema.config({project = "lua-objc-dev", endpoint = "https://fra.cloud.appwrite.io/v1",
	database = "notes", models = {Notes, Lists, Local}})
local decoded = ns.json_parse(Schema.encode(config))
t.assertEqual(decoded.projectId, "lua-objc-dev", "the config names its project")
t.assertEqual(decoded.endpoint, "https://fra.cloud.appwrite.io/v1", "and its endpoint")
t.expect(#decoded.tablesDB == 1 and decoded.tablesDB[1]["$id"] == "notes" and decoded.tablesDB[1].enabled,
	"one TablesDB database")
t.assertEqual(#decoded.tables, 2, "only remote models become tables")
t.assertEqual(decoded.tables[1]["$id"], "remote_lists", "tables are in name order")
local notes = decoded.tables[2]
t.expect(notes.databaseId == "notes" and notes.name == "remote_notes" and notes.enabled and notes.rowSecurity,
	"a table lives in the database and checks each row's permissions")
t.expect(#notes["$permissions"] == 1 and notes["$permissions"][1] == 'create("users")',
	"the table only lets signed-in users create rows")
local columns = {}
for _, entry in ipairs(notes.columns) do columns[entry.key] = entry end
t.expect(columns.title.type == "varchar" and columns.title.size == 255 and columns.title.required == true
	and columns.title.array == false, "string(n) is a varchar of n")
t.expect(columns.body.type == "text" and columns.body.size == nil and columns.body.required == false, "text has no size")
t.expect(columns.weight.type == "double" and columns.weight.min == 0, "float is Appwrite's double")
t.expect(columns.priority.type == "integer" and columns.priority.max == 3 and columns.priority.default == 0, "integers keep bounds")
t.expect(columns.done.type == "boolean" and columns.dueAt.type == "datetime", "booleans and datetimes")
t.expect(columns.contact.type == "string" and columns.contact.format == "email", "email is a string format")
t.expect(columns.link.type == "string" and columns.link.format == "url", "url is a string format")
t.expect(columns.state.type == "string" and columns.state.format == "enum" and columns.state.elements[2] == "done"
	and columns.state.default == "open", "enum is a string format with elements")
t.expect(columns.tags.array == true and columns.tags.size == 32, "a list column")
t.expect(columns.title.default == nil and columns.title.min == nil, "unset options are left out")
local system = notes.indexes[4]
t.assertEqual(table.concat(system.columns, ","), "listId,$createdAt", "createdAt indexes Appwrite's $createdAt")
t.assertEqual(table.concat(notes.indexes[1].orders, ","), "ASC,DESC", "orders reach the index")
t.expect(Schema.encode(config) == Schema.encode(Schema.config({project = "lua-objc-dev",
	endpoint = "https://fra.cloud.appwrite.io/v1", database = "notes", models = {Lists, Notes}})),
	"the same models make the same bytes, whatever their order")
local lists = decoded.tables[1]
t.expect(#lists.indexes == 0 and ns._jsonEncode ~= nil and Schema.encode(config):find('"indexes":[]', 1, true),
	"a table without indexes sends an empty list")
t.expect(not pcall(Schema.config, {project = "p", endpoint = "https://x/v1", database = "notes", models = {Local}}),
	"an app without remote models has no schema")
t.expect(not pcall(Schema.config, {project = "", endpoint = "https://x/v1", database = "notes", models = {Notes}}),
	"a schema needs a project")
t.expect(not pcall(Schema.config, {project = "p", endpoint = "https://x/v1", database = "no/db", models = {Notes}}),
	"a schema needs a valid database ID")
t.assertEqual(#Schema.remoteModels(Model.models) >= 2, true, "Model.models gives the remote models too")

os.exit(t.summary() and 0 or 1)
