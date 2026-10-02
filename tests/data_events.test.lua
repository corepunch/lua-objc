-- Change events and list/menu events: models post their changes to the run
-- loop; one event rebinds the views of each changed model once; list rows,
-- menus and toolbar items reach the model through commands.
_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local xml = require("ui.xml")
local Events = require("data.events")
local Model = require("data.model")
local Schema = require("data.schema")
local Binder = require("data.binder")

-- Coalescing: a burst of posts is one event; each key runs once.
Events.immediate = false
local posted, ran = {}, {}
local original = bridge._postEvent
bridge._postEvent = function(fn) table.insert(posted, fn) end
Events.post(function() table.insert(ran, "a") end, "a")
Events.post(function() table.insert(ran, "a again") end, "a")
Events.post(function() table.insert(ran, "b") end, "b")
t.assertEqual(#posted, 1, "a burst posts one event to the run loop")
t.assertEqual(#ran, 0, "and runs nothing until the run loop delivers it")
posted[1]()
t.assertEqual(table.concat(ran, ","), "a,b", "each key runs once, in order")
Events.post(function() table.insert(ran, "c") end, "c")
t.assertEqual(#posted, 2, "the next burst posts the next event")
posted[2]()
t.assertEqual(ran[#ran], "c", "and runs it")
-- A handler's own posts run in the same drain.
local order = {}
Events.post(function() table.insert(order, 1); Events.post(function() table.insert(order, 2) end, "inner") end, "outer")
posted[3]()
t.assertEqual(table.concat(order, ","), "1,2", "posts made while draining are drained too")

-- A graph model posts its change; dependents rebind once per burst.
local Source = Model.define({ id = "source" })
function Source.new() return setmetatable({ count = 0 }, Source) end
local Mirror = Model.define({ id = "mirror", needs = { "source" } })
function Mirror.new(needs) return setmetatable({ source = needs.source, invalidated = 0 }, Mirror) end
function Mirror:invalidate() self.invalidated = self.invalidated + 1 end
local graph = Model.graph({ classes = { source = Source, mirror = Mirror } })
graph:build({ "mirror" })
local heard = 0
graph:subscribe("mirror", function() heard = heard + 1 end)
local source = graph:get("source")
source:changed(); source:changed(); source:changed()
t.assertEqual(heard, 0, "nothing rebinds before the event")
posted[#posted]()
t.assertEqual(heard, 1, "three changes rebind the dependent once")
t.assertEqual(graph:get("mirror").invalidated, 1, "and invalidate it once")

Events.immediate = true
bridge._postEvent = original

-- List events, menus, validation and loading, through a schema.
local files = {
	["schemas/Row.xml"] = '<Schema id="Row"><String id="name" /></Schema>',
	["schemas/Page.xml"] = [[<Schema id="Page">
		<List id="rows" of="Row" />
		<Bool id="loading" />
		<String id="title" />
		<Command id="open" />
		<Command id="select" />
		<Command id="menu" query="true" />
		<Command id="refresh" enabled="canRefresh" />
	</Schema>]],
}
local Page = Schema.directory("schemas", function(path) return files[path] end, xml.parse)("Page")
local seen = {}
local model = { rows = { { name = "One" }, { name = "Two" } }, loading = true, title = "T", canRefresh = false }
function model:open(row) table.insert(seen, "open " .. row.name) end
function model:select(row) table.insert(seen, "select " .. tostring(row and row.name)) end
function model:menu(row) table.insert(seen, "menu " .. row.name); return { { title = "Item for " .. row.name } } end
function model:refresh() table.insert(seen, "refresh") end

local lists = {}
local list = ns.List
ns.List = function(props) table.insert(lists, props); return list(props) end
local binder = Binder.new({ schema = Page, model = model })
local root, refs = xml.render([[<VStack>
	<List id="rows" items="$rows" loading="$loading" onActivate="$open" onSelect="$select" rowMenu="$menu" style="fullWidth" header="false" rowHeight="40" height="100">
		<Column id="name" title="Name" />
	</List>
</VStack>]], { binder = binder }, ns)
binder:update()
local props = lists[#lists]
t.assertEqual(type(props.onActivate), "function", "a list event binds to a command")
props.onActivate(0, 0, { name = "Two", __row = 2 })
t.assertEqual(seen[1], "open Two", "the command receives the row's model, not its record")
props.onSelect(1, 0, { name = "One", __row = 1 })
t.assertEqual(seen[2], "select One", "selection too")
local items = props.rowMenu(1, 0, { name = "One", __row = 1 })
t.assertEqual(seen[3], "menu One", "a menu command runs for the row")
t.assertEqual(items[1].title, "Item for One", "and returns its items to the control")
model.rows = { { name = "Only" } }
binder:update()
props.onActivate(0, 0, { name = "Only", __row = 1 })
t.assertEqual(seen[4], "open Only", "events follow the rows last shown")
t.expect(refs.rows ~= nil, "the list is a ref")
ns.List = list

-- Literal event names are still controller actions; a command must be bound.
local ok, err = pcall(xml.render, '<List items="$rows" onActivate="open"><Column id="name" /></List>', { binder = binder }, ns)
t.expect(not ok and tostring(err):find("is a literal"), "a literal command name on an event is an error (" .. tostring(err) .. ")")
ok, err = pcall(xml.render, '<List items="$rows" onActivate="$title"><Column id="name" /></List>', { binder = binder }, ns)
t.expect(not ok and tostring(err):find("not a command"), "an event binds commands only (" .. tostring(err) .. ")")

-- Menu items and toolbar items: action and validate.
local captured = {}
local menuItem = xml.registry.MenuItem
local menuView, menuRefs = xml.render([[<VStack>
	<Label id="title" text="$title" />
</VStack>]], { binder = binder }, ns)
local config = xml.render([[<Window title="$title" subtitle="$title" width="300" height="200">
	<Commands appName="X">
		<CommandMenu title="Go">
			<MenuItem title="Refresh" action="$refresh" validate="$refresh" />
		</CommandMenu>
	</Commands>
	<VStack />
</Window>]], { binder = binder }, ns)
t.assertEqual(type(config.commands), "table", "a window config with bound menu items renders")
local built = require("ui.commands").build(config.commands)
local refresh
for _, menu in ipairs(built.menus) do for _, item in ipairs(menu.items) do if item.title == "Refresh" then refresh = item end end end
t.expect(refresh ~= nil, "the menu item exists")
t.assertEqual(refresh.validate(), false, "validate follows the command's enabling field")
model.canRefresh = true
binder:update()
t.assertEqual(refresh.validate(), true, "and changes with it")
refresh.action()
t.assertEqual(seen[#seen], "refresh", "the menu item runs the command")
t.assertEqual(#config.bindings, 2, "the window's own bindings wait for the window")
local window = { title = "", subtitle = "" }
binder:addWindow(config, window)
binder:update()
t.assertEqual(window.title, "T", "the window title binds")

os.exit(t.summary() and 0 or 1)
