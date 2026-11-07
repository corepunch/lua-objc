_G.__headless = true
local t = require("TestKit")
local ns = require("ns")
local Template = require("ui.template")
local path = os.tmpname() .. ".etlua"
local file = assert(io.open(path,"w"))
file:write('<VStack><CodeView id="source" text="<%= text %>" language="lua" editable="true" onChange="edit" /></VStack>')
file:close()
local template = Template.new(ns.VStack {}, path, ns)
local state, calls = {text = "return 1"}, 0
local function draw()
	template:update({text=state.text, actions={edit=function(text) state.text=text; calls=calls+1; draw() end}})
end
draw()
local source = template.refs.source
t.expect(source.documentView.editable, "CodeView supports native source editing")
ns._textEditorTestInput(source,"return 2")
t.assertEqual(state.text,"return 2","code edits reach the controller")
t.assertEqual(template.refs.source,source,"editing keeps the native editor")
state.text="return 3"; draw()
t.assertEqual(template.refs.source,source,"an external edit updates the same native editor")
t.assertEqual(source.text,"return 3","the editor shows generated source")
t.assertEqual(calls,1,"programmatic replacement does not emit another user edit")
template:dispose(); os.remove(path)
os.exit(t.summary() and 0 or 1)
