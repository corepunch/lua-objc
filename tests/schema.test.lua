-- Schemas: XML field declarations, the type tags, states, composed formats,
-- validation of models, and the paths views bind.
_G.__headless = true
local t = require("TestKit")
local xml = require("ui.xml")
local bridge = require("AppKitNative")
local Schema = require("data.schema")

local files = {}
local function load(id)
	return Schema.directory("schemas", function(path) return files[path] end, xml.parse)(id)
end
local function define(id, source) files["schemas/" .. id .. ".xml"] = source end
local function raises(fn, pattern, message)
	local ok, err = pcall(fn)
	t.expect(not ok and tostring(err):find(pattern) ~= nil, message .. " (" .. tostring(err) .. ")")
end

define("Base", [[<Schema id="Base">
	<String id="name" />
	<String id="subtitle" optional="true" />
</Schema>]])
define("Row", [[<Schema id="Row" extends="Base">
	<Bytes id="size" source="bytes" missing="Not measured">
		<State id="calculating" text="Calculating…" />
		<State id="denied" text="No access" icon="lock.fill" color="systemOrange" />
	</Bytes>
	<Percent id="share" source="relative" digits="0" below="&lt;1%" />
	<Number id="count" digits="1" optional="true" />
	<Date id="lastUsed" style="relative" format="Used $value" optional="true" />
	<Symbol id="icon" optional="true" />
	<Color id="color" optional="true" />
	<Bool id="pinned" optional="true" />
	<String id="accessibility" format="$name: $size $share" />
	<Command id="mark" enabled="markable" />
	<Command id="open" />
</Schema>]])

local Row = load("Row")
t.assertEqual(#Row.fields, 12, "extends puts the base fields first")
t.assertEqual(Row.fields[1].id, "name", "base fields come first")
t.assertEqual(Row.byId.size.source, "bytes", "source names the model key")

-- Validation.
local function row(extra)
	local model = { name = "Developer", bytes = 1500000000, relative = 0.34, markable = true,
		mark = function() end, open = function() end }
	for key, value in pairs(extra or {}) do model[key] = value end
	return model
end
t.assertEqual(#Row:problems(row()), 0, "a complete model has no problems")
t.expect(#Row:problems(row({ name = false })) == 0, "false is a value")
local missing = row(); missing.name = nil
t.expect(Row:problems(missing)[1]:find("name"), "a model lacking a declared field fails")
local noCommand = row(); noCommand.mark = nil
t.expect(Row:problems(noCommand)[1]:find("command mark"), "a command needs a method")
local unmeasured = row(); unmeasured.bytes = nil
t.assertEqual(#Row:problems(unmeasured), 0, "a field with `missing` may be absent")
raises(function() Row:check(missing) end, "does not satisfy", "check raises")

-- Projection: type tags and states.
local record = Row:project(row(), { now = 1000 })
t.assertEqual(record.name, "Developer", "a string projects as is")
t.assertEqual(record.size, bridge._formatBytes(1500000000), "Bytes runs on the system formatter")
t.assertEqual(record["size.value"], 1500000000, "the raw number sits beside the display string")
t.assertEqual(record.share, bridge._formatPercent(0.34, 0), "Percent formats a fraction")
t.assertEqual(record["share.value"], 0.34, "Percent keeps the fraction for gauges")
t.assertEqual(record["size.calculating"], false, "an inactive state reads false")
t.assertEqual(record["size.state"], nil, "no state is active")
t.assertEqual(record["mark.enabled"], true, "a command follows its enabling field")
t.assertEqual(record["open.enabled"], true, "a command with no enabling field is always enabled")
t.assertEqual(Row:project(row({ markable = false }))["mark.enabled"], false, "a falsy enabling field disables")
t.assertEqual(record.accessibility, "Developer: " .. record.size .. " " .. record.share, "format composes display values")

local measuring = Row:project(row({ bytes = nil, sizeState = "calculating" }))
t.assertEqual(measuring.size, "Calculating…", "a state replaces the value with its text")
t.assertEqual(measuring["size.calculating"], true, "the active state reads true")
t.assertEqual(measuring["size.state"], "calculating", "the active state's id")
local denied = Row:project(row({ bytes = nil, sizeState = "denied" }))
t.assertEqual(denied["size.icon"], "lock.fill", "a state carries its symbol")
t.assertEqual(denied["size.color"], "systemOrange", "a state carries its colour")
t.assertEqual(denied.accessibility, "Developer: No access " .. denied.share, "format sees the state's text")
local blank = row(); blank.bytes = nil
t.assertEqual(Row:project(blank).size, "Not measured", "missing text stands in for an absent value")
raises(function() Row:project(row({ sizeState = "nope" })) end, "undeclared state", "an unknown state is an error")
raises(function() Row:project(row({ bytes = "big" })) end, "Bytes but the model gives string", "a Bytes field needs a number")

local tiny = Row:project(row({ relative = 0.004 }))
t.assertEqual(tiny.share, "<1%", "below is the text for a sliver")
t.assertEqual(Row:project(row({ relative = 0 })).share, bridge._formatPercent(0, 0), "zero is a measured zero")
t.assertEqual(Row:project(row({ count = 3 })).count, bridge._formatNumber(3, 1), "Number honours digits")
local dated = Row:project(row({ lastUsed = 0 }), { now = 86400 * 3 })
t.assertEqual(dated.lastUsed, "Used " .. bridge._formatDate(0, "relative", 86400 * 3), "format wraps a converted date")
t.assertEqual(Row:project(row({ pinned = true })).pinned, true, "a Bool projects raw")
t.assertEqual(Row:project(row({ color = "systemRed" }))["color.color"], "systemRed", "a Color exposes its name")

-- A model that computes: a function field is called with the model.
local computed = row(); computed.bytes = function(self) return self.base * 2 end; computed.base = 500
t.assertEqual(Row:project(computed)["size.value"], 1000, "a computed field is called with the model")

-- Lists and records.
define("Page", [[<Schema id="Page">
	<String id="title" />
	<Bool id="history" writable="true" />
	<List id="rows" of="Row" />
	<Record id="lead" of="Row" />
</Schema>]])
local Page = load("Page")
local page = { title = "T", history = false, setHistory = function() end,
	rows = { row(), row({ name = "Two" }) }, lead = row({ name = "Lead" }) }
t.assertEqual(#Page:problems(page), 0, "a page model with a setter validates")
local projected = Page:project(page)
t.assertEqual(#projected.rows, 2, "a List projects to an array of records")
t.assertEqual(projected.rows[2].name, "Two", "each row is projected with its schema")
t.assertEqual(projected.lead.name, "Lead", "a Record projects to a nested record")
local noSetter = {}; for k, v in pairs(page) do noSetter[k] = v end; noSetter.setHistory = nil
t.expect(Page:problems(noSetter)[1]:find("setter setHistory"), "a writable field needs a setter")

-- Paths.
local path, field = Row:resolve({ "size" }, "string")
t.assertEqual(table.concat(path, "|"), "size", "a text attribute reads the display string")
path = Row:resolve({ "size" }, "number")
t.assertEqual(table.concat(path, "|"), "size.value", "a numeric attribute reads the raw number")
path = Row:resolve({ "share" }, "number")
t.assertEqual(table.concat(path, "|"), "share.value", "a Percent binds its fraction")
path = Row:resolve({ "size", "color" }, "color")
t.assertEqual(table.concat(path, "|"), "size.color", "a part of a field")
path = Row:resolve({ "size", "calculating" }, "bool")
t.assertEqual(table.concat(path, "|"), "size.calculating", "a state binds as a part")
path = Row:resolve({ "pinned" }, "bool")
t.assertEqual(table.concat(path, "|"), "pinned", "a Bool binds itself")
path = Row:resolve({ "icon" }, "bool")
t.assertEqual(table.concat(path, "|"), "icon.value", "presence of a value binds its raw value")
path = Page:resolve({ "lead", "size", "color" }, "color")
t.assertEqual(table.concat(path, "|"), "lead|size.color", "a path descends through a record")
raises(function() Row:resolve({ "nope" }, "string") end, "undeclared field nope", "an undeclared field is an error")
raises(function() Row:resolve({ "size", "weight" }, "string") end, "no part", "an unknown part is an error")
raises(function() Row:resolve({ "name" }, "number") end, "cannot bind String", "a text field cannot drive a number")
raises(function() Row:resolve({ "mark" }, "string") end, "is a command", "a command is not a value")
raises(function() Page:resolve({ "lead" }, "string") end, "ends at a record", "a record is not a value")

t.assertEqual(Schema.lookup({ ["size.color"] = "x" }, { "size", "color" }), "x", "lookup reads dotted keys")
t.assertEqual(Schema.lookup({ lead = { ["size.color"] = "y" } }, { "lead", "size", "color" }), "y", "lookup descends")
t.assertEqual(Schema.lookup({}, { "a" }), nil, "lookup of a missing field is nil")

-- Errors at load.
local function bad(source, pattern, message)
	define("Bad", source)
	raises(function() load("Bad") end, pattern, message)
end
bad('<Schema id="Bad"><Widget id="a" /></Schema>', "not a field type", "unknown field type")
bad('<Schema id="Bad"><String id="a" /><String id="a" /></Schema>', "declared twice", "duplicate field")
bad('<Schema id="Bad"><String /></Schema>', "needs an id", "field without id")
bad('<Schema id="Bad"><String id="a" format="$b" /><String id="b" format="$a" /></Schema>', "depends on itself", "format cycle")
bad('<Schema id="Bad"><String id="a" format="$z" /></Schema>', "undeclared field %$z", "format names a missing field")
bad('<Schema id="Bad"><List id="r" /></Schema>', "needs of=", "list without of")
bad('<Schema id="Other"><String id="a" /></Schema>', "must match the file name", "id and file name agree")
bad('<Schema id="Bad" extends="Bad"><String id="a" /></Schema>', "extends itself", "self extension")

-- A Map is keyed by id: a template of static structure binds one entry.
define("Keyed", [[<Schema id="Keyed"><Map id="sizes" /><Bool id="shown" /></Schema>]])
local Keyed = load("Keyed")
local keyed = {sizes = {cache = "12 GB"}, shown = true}
t.assertEqual(Keyed:check(keyed), keyed, "a map is satisfied by a table")
local record = Keyed:project(keyed)
local path = Keyed:resolve({"sizes", "cache"}, "string")
t.assertEqual(table.concat(path, "."), "sizes.cache", "a map entry resolves to its key")
t.assertEqual(Schema.lookup(record, path), "12 GB", "the entry is read from the projected map")
t.assertEqual(Schema.lookup(record, Keyed:resolve({"sizes", "absent"}, "string")), nil, "an absent entry reads as nothing")
raises(function() Keyed:resolve({"sizes"}, "string") end, "is a map", "the map itself is not a value")

os.exit(t.summary() and 0 or 1)
