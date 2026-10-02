-- Page-level bindings: `$field` anywhere in a template, the data context,
-- <List items>, commands and two-way controls, all through a schema and the
-- generic binder (lua/data/binder.lua).
_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local xml = require("ui.xml")
local Schema = require("data.schema")
local Binder = require("data.binder")

local files = {
	["schemas/Row.xml"] = [[<Schema id="Row">
		<String id="name" />
		<Bytes id="size" source="bytes" missing="Not measured">
			<State id="calculating" text="Calculating…" />
		</Bytes>
		<Percent id="share" source="relative" digits="0" />
		<Command id="mark" enabled="markable" />
	</Schema>]],
	["schemas/Page.xml"] = [[<Schema id="Page">
		<String id="summary" />
		<String id="query" writable="true" />
		<Bool id="history" writable="true" />
		<Number id="filter" writable="true" />
		<Bool id="locked" optional="true" />
		<List id="rows" of="Row" />
		<Record id="lead" of="Row" />
		<Command id="refresh" />
	</Schema>]],
}
local loader = Schema.directory("schemas", function(path) return files[path] end, xml.parse)
local Page = loader("Page")

local calls = {}
local function newModel()
	local model = { summary = "3 items", query = "q", history = false, filter = 0, locked = false,
		rows = {
			{ name = "One", bytes = 1000000, relative = 0.5, markable = true },
			{ name = "Two", bytes = nil, sizeState = "calculating", relative = 0, markable = false },
		},
		lead = { name = "Lead", bytes = 2000000, relative = 0.25, markable = true },
	}
	for _, row in ipairs(model.rows) do row.mark = function() table.insert(calls, "mark " .. row.name) end end
	model.lead.mark = function() table.insert(calls, "mark lead") end
	function model:refresh() table.insert(calls, "refresh"); self.summary = "refreshed" end
	function model:setHistory(value) table.insert(calls, "history " .. tostring(value)); self.history = value end
	function model:setQuery(value) if value == "no" then return false end; self.query = value end
	function model:setFilter(value) self.filter = value end
	return model
end

-- Controls report their change callbacks through the constructors.
local captured = {}
local constructors = { "Toggle", "TextField", "Picker", "Button" }
local originals = {}
for _, name in ipairs(constructors) do
	originals[name] = ns[name]
	ns[name] = function(props)
		captured[name] = props
		captured[name .. "s"] = captured[name .. "s"] or {}
		table.insert(captured[name .. "s"], props)
		return originals[name](props)
	end
end

local function render(source, model)
	local binder = Binder.new({ schema = Page, model = model or newModel(), now = 0 })
	local root, refs = xml.render(source, { binder = binder }, ns)
	binder:update()
	return root, refs, binder
end
local function rejects(source, pattern, message)
	local ok, err = pcall(render, source)
	t.expect(not ok and tostring(err):find(pattern) ~= nil, message .. " (" .. tostring(err) .. ")")
end

-- One-way bindings anywhere in the page.
local root, refs, binder = render([[<VStack>
	<Label id="summary" text="$summary" />
	<Gauge id="gauge" value="$lead.share" />
	<Label id="size" text="$lead.size" />
	<Label id="spinner" text="x" visible="$locked" />
	<Label id="shown" text="y" hidden="$locked" />
</VStack>]])
t.assertEqual(refs.summary.text, "3 items", "a label binds a string field")
t.assertEqual(refs.gauge.doubleValue, 0.25, "a numeric attribute gets the raw fraction")
t.assertEqual(refs.size.text, bridge._formatBytes(2000000), "a text attribute gets the formatted string")
t.expect(refs.spinner.hidden and not refs.shown.hidden, "visible and hidden pair against a bound boolean")
binder.model.summary = "changed"
binder.model.locked = true
binder:update()
t.assertEqual(refs.summary.text, "changed", "update sets the property again")
t.expect(not refs.spinner.hidden and refs.shown.hidden, "the pair follows the field")

-- The data context.
local _, contextRefs = render([[<VStack context="$lead">
	<Label id="name" text="$name" />
	<VStack><Label id="deep" text="$size.calculating" /></VStack>
</VStack>]])
t.assertEqual(contextRefs.name.text, "Lead", "context narrows to a record")
t.assertEqual(contextRefs.deep.text, "false", "a context is inherited by the subtree")

-- Errors reach the author when the page renders.
rejects('<Label text="$nope" />', "undeclared field nope", "an undeclared field")
rejects('<Label text="$summary" size="$summary" />', "cannot bind size", "an attribute that is not bindable")
rejects('<Label text="$lead" />', "ends at a record", "a record is not a value")
rejects('<Gauge value="$summary" />', "cannot bind String", "a string field cannot drive a number")
rejects('<VStack context="$summary"><Label text="x" /></VStack>', "context needs a <Record>", "context needs a record")
rejects('<Label text="$size" />', "undeclared field size", "row fields are not page fields")
rejects('<Label text="Used $summary" />', "exactly one", "no interpolation on a page")
local ok = pcall(xml.render, '<Label text="$summary" />', {}, ns)
t.expect(ok, "without a binder, $ is ordinary text")

-- <List items>: each row binds through the row schema.
local window = ns.Window { visible = false, width = 400, height = 240 }
local listRoot, listRefs, listBinder = render([[<VStack>
	<List id="list" items="$rows" style="fullWidth" header="false" rowHeight="40" height="200">
		<Column id="name" title="Name" minWidth="80" />
		<Column id="size" title="Size" width="160">
			<VStack>
				<Label id="size" text="$size" />
				<Gauge id="gauge" value="$share" />
				<ProgressView id="spinner" visible="$size.calculating" />
			</VStack>
		</Column>
	</List>
</VStack>]])
window:add(listRoot)
window:layout()
bridge._appkitLayout(window)
local function cell(index)
	local found = {}
	local view = bridge._tableCell(listRefs.list, 1, index)
	view:layout()
	local function visit(v)
		local id = v.accessibilityIdentifier
		if id and id ~= "" then found[id] = v end
		for _, child in ipairs(v.subviews) do visit(child) end
	end
	visit(view)
	return found
end
t.assertEqual(bridge._tableCell(listRefs.list, 0, 0).textField.stringValue, "One", "a text column shows the projected row")
t.assertEqual(cell(0).size.text, bridge._formatBytes(1000000), "a cell binds a typed field")
t.assertEqual(cell(0).gauge.doubleValue, 0.5, "a cell's numeric attribute gets the raw value")
t.assertEqual(cell(1).size.text, "Calculating…", "a state's text replaces the size")
t.expect(cell(0).spinner.hidden and not cell(1).spinner.hidden, "a state shows its spinner")
listBinder.model.rows[1].bytes = 5000000
listBinder:update()
t.assertEqual(cell(0).size.text, bridge._formatBytes(5000000), "update replaces the rows")
rejects('<List items="$summary"><Column id="a" /></List>', "needs a <List> field", "items needs a List field")
rejects('<List items="$rows"><Column id="a"><Label text="$nope" /></Column></List>', "undeclared field nope",
	"a cell binding is checked against the row schema")

-- Commands.
calls = {}
captured.Buttons = {}
local _, commandRefs, commandBinder = render([[<VStack>
	<Label id="summary" text="$summary" />
	<Button id="refresh" title="Refresh" action="$refresh" />
	<Button id="mark" title="Mark" action="$lead.mark" />
</VStack>]])
t.assertEqual(type(captured.Buttons[1].action), "function", "a command becomes the button's action")
captured.Buttons[1].action()
t.assertEqual(calls[1], "refresh", "the action dispatches to the model")
t.assertEqual(commandRefs.summary.text, "refreshed", "the views rebind after a command")
captured.Buttons[2].action()
t.assertEqual(calls[2], "mark lead", "a command reaches the model its context designates")
t.expect(commandRefs.mark.enabled, "the control is enabled by the command's field")
commandBinder.model.lead.markable = false
commandBinder:update()
t.expect(not commandRefs.mark.enabled, "the control follows the command's enabling field")
rejects('<List items="$rows"><Column id="a"><Button title="x" action="$mark" /></Column></List>', "cannot bind action",
	"a cell cannot bind a command")
rejects('<Button title="x" action="refresh" />', "is a literal", "a literal command name is an error")
rejects('<Button title="x" action="$summary" />', "not a command", "action binds commands only")

-- Two-way controls.
calls = {}
local twoWay = newModel()
local _, formRefs, formBinder = render([[<VStack>
	<Toggle id="history" label="History" isOn="$history" />
	<TextField id="query" text="$query" />
	<Picker id="filter" selection="$filter"><Option title="A" /><Option title="B" /></Picker>
</VStack>]], twoWay)
t.assertEqual(formRefs.history.state, 0, "the toggle shows the model")
t.assertEqual(formRefs.query.text, "q", "the text field shows the model")
captured.Toggle.onChange(true)
t.assertEqual(twoWay.history, true, "a write reaches the model's setter")
t.assertEqual(formRefs.history.state, 1, "the control shows the accepted value")
captured.TextField.onChange("hello")
t.assertEqual(twoWay.query, "hello", "text writes through")
formRefs.query.text = "no"
captured.TextField.onChange("no")
t.assertEqual(twoWay.query, "hello", "a refused write leaves the model alone")
t.assertEqual(formRefs.query.text, "hello", "a refused write reverts the control")
local picked = captured.Picker.action or captured.Picker.onChange
picked(1)
t.assertEqual(twoWay.filter, 1, "a picker writes its index")
t.assertEqual(formRefs.filter.indexOfSelectedItem, 1, "the picker shows the model")
rejects('<TextField text="$summary" />', "not writable", "two-way needs writable")
rejects('<Toggle label="x" isOn="$locked" />', "not writable", "two-way needs writable on a Bool")
rejects('<TextField text="$lead.name" />', "not writable", "writable is per field")

for name, original in pairs(originals) do ns[name] = original end
os.exit(t.summary() and 0 or 1)
