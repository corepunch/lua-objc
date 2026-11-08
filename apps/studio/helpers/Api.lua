local Api = {}
local GUIDES = {
	controls = [[The app uses XML tags, not direct ns view constructors. Supported examples:
<TextField id="taskInput" text="<%= draft %>" placeholder="New task" onChange="editTitle" accessibilityLabel="New task" />
<Button title="Add" action="addTask" style="borderedProminent" />
<Toggle value="<%= task.completed == true %>" onChange="toggle_1" accessibilityLabel="Complete task" />
<Picker value="<%= filterIndex %>" onChange="chooseFilter" style="segmented"><Option title="All" /><Option title="Open" /><Option title="Done" /></Picker>
<Label text="<%= task.title %>" lines="0" flexGrow="1" flexShrink="1" />
<ScrollView flexGrow="1" maxWidth="infinity" maxHeight="infinity"><VStack spacing="12" maxWidth="infinity">...</VStack></ScrollView>
TextField.onChange receives the new string. Toggle.onChange receives the new boolean. Picker.onChange receives a ZERO-BASED option index.
Use onChange, NOT action, on input controls. Toggle uses value, NOT isOn. Button.action receives no custom arguments.
Each event attribute is a string naming data.actions[name]. For repeated rows create a distinct action per record in the controller:
for _, task in ipairs(Tasks:all()) do
 local id = task.id
 actions["toggle_" .. id] = Model.bound(self.store, function(value)
  Tasks:find(id):update({completed=value})
  self.template:update(self:data())
 end)
end
Rebuild these row actions when tasks are added or removed, not only during createWindow. Otherwise a new row will have no handler.
Then <Toggle value="<%= task.completed == true %>" onChange="toggle_<%= task.id %>" /> in the etlua loop.
Resources contain Number, String, Bool or Color constants only; they NEVER pass action arguments. There is no actionArg or <Table> resource.
Use background, NOT backgroundColor; SystemImage uses size, NOT pointSize. Colors: primary, secondary, systemBlue, systemOrange, background, secondaryBackground.
Stacks use alignment="leading|center|trailing" (VStack) and alignment="top|center|bottom" (HStack).
Use semantic textStyle values, size for explicit font sizes, and lines="0" for wrapping. Do not invent XML attributes.]],
	models = [[require("data.model") exposes Lapis-style models over a plain Lua store, NOT a SQL database.
local Model = require("data.model")
local Tasks, Task = Model:extend("tasks", {primaryKey="id"})
function Task:toggle() return self:update({completed=not self.completed}) end
return Tasks
A controller owns {store={tasks={{id="1",title="Example",completed=false}}}}.
Call Model.bind(self.store) before querying; wrap EVERY UI action in Model.bound(self.store, fn).
Tasks:all() returns an array of row tables. Tasks:find(id) returns a row or nil.
Tasks:select({completed=false}) or Tasks:select(function(row) return ... end) filters rows.
Tasks:count({completed=false}) counts matching rows.
Tasks:create({id="unique-id",title="New",completed=false}) appends a row. IDs are NOT generated automatically: supply a unique id yourself.
row:update({completed=true}) mutates fields; row:delete() removes it. Rows already ARE tables; there is no toTable(), save(), insert(), SQL where(), or migration API.
constraints={title=function(row,value) if not value:match("%S") then return "Enter a task title" end end} rejects create/update with nil,error.
Lua strings have no trim() method. Use title:match("^%s*(.-)%s*$") to trim.
Use ns.LocalStorage for persistence: get(key) returns JSON text or nil; decode(text) returns data; set(key, encode(data)) saves it.
get/set/encode/decode are plain functions called with a dot, not a colon. Keep files and native IO out of model methods; inject the storage service.]],
	templates = [[Keep all view structure in .etlua. Controllers prepare plain data and actions.
init.lua returns require("demo.playground.Controller"). Controller.new() returns an instance; createWindow() returns ns.Window(config).
Follow the starter's retained Template pattern:
local config, refs = xml.renderFile("demo/playground/views/layouts/Window.etlua", {}, ns)
self.template = Template.new(refs.content, "demo/playground/views/pages/Main.etlua", ns)
self.template:update(self:data())
return ns.Window(config)
self:data() must provide every variable used by the page, including actions=self.actions.
Use the CURRENT draft in data(), never an empty-string constant; a filter or toggle must not erase typed input.
After mutation call self.template:update(self:data()). This reconciles native controls and keeps focus.
<%= value %> escapes an attribute; <%- partial("../components/Row.etlua", {task=task}) %> includes a relative component.
<% for _, task in ipairs(tasks) do %> ... <% end %> repeats rows. Supply empty arrays instead of nil.
Related model/controller/view changes belong in ONE applyFiles batch, so no intermediate file set disagrees about the data contract.
A ready preview confirms initial rendering only. Test event handlers too; do not claim interactions work just because preview() returned ready.]],
}
function Api.read(topic)
	if not GUIDES[topic] then return nil, "Choose controls, models, or templates" end
	return GUIDES[topic]
end
return Api
