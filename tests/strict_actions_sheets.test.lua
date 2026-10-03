_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Template = require("ui.template")
for _, source in ipairs({
	'<Button title="Run" action="missing"/>',
	'<Window><Commands><CommandMenu title="File"><MenuItem title="Run" action="missing"/></CommandMenu></Commands></Window>',
	'<Window><Toolbar><ToolbarItem id="run" label="Run" action="missing"/></Toolbar></Window>',
}) do t.assertThrows(function() xml.render(source, {actions = {}}, ns) end, "unbound action is rejected during construction") end
local path = os.tmpname() .. ".etlua"
local file = assert(io.open(path, "w")); file:write('<Button id="run" title="Run" action="run"/>'); file:close()
local template = Template.new(ns.VStack {}, path, ns)
local _, refs = template:update({actions = {run = function() end}})
t.assertThrows(function() template:update({actions = {}}) end, "unchanged markup cannot conceal a removed action")
t.assertEqual(refs.run.title, "Run", "a refused update preserves the mounted control")
template:dispose(); os.remove(path)
local parent = ns.Window {visible = false}
local function build() return ns.Sheet {title = "Test", width = 300, height = 150} end
local sheet = ns.presentSheet(build, {parent = parent})
t.assertThrows(function() ns.presentSheet(build, {parent = parent}) end, "headless sheets enforce one parent")
ns.dismiss(sheet)
t.expect(ns.presentSheet(build, {parent = parent}), "dismiss releases the parent")
local other, disposed = ns.Window {visible = false}, 0
local failedScope
_G.__headless = false
local ok = pcall(ns.presentSheet, function()
	failedScope = ns.Scope.current()
	failedScope:add({dispose = function() disposed = disposed + 1 end})
	return {presentSheet = function() error("native presentation failed") end}
end, {parent = other})
_G.__headless = true
t.expect(not ok and failedScope.closed, "failed presentation closes its scope")
t.assertEqual(disposed, 1, "failed presentation disposes owned work exactly once")
t.expect(ns.presentSheet(build, {parent = other}), "failed presentation does not reserve the parent")
t.assertEqual(ns.Alert {title = "Confirm", parent = other, buttons = {"Cancel", "Run"}, response = 2}, 2, "headless parented alerts use scripted responses")
parent:close(); other:close()
os.exit(t.summary() and 0 or 1)
