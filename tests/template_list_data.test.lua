_G.__headless = true
local t = require("TestKit")
local ns = require("ns")
local Template = require("ui.template")
local path = os.tmpname() .. ".etlua"
local file = assert(io.open(path,"w"))
file:write('<VStack><List id="files" data="rows"><Column id="title" title="Source" /></List><TextEditor id="editor" text="unchanged" /></VStack>'); file:close()
local rows = {{id="one",title="Controller.lua"}}
local template = Template.new(ns.VStack {},path,ns)
local function draw() template:update({rows=rows}) end
draw()
local list, editor = template.refs.files, template.refs.editor
t.assertEqual(list.rowCount,1,"mount uses the supplied rows")
table.insert(rows,{id="two",title="Model.lua"}); draw()
t.assertEqual(template.refs.files,list,"new row data keeps the native list")
t.assertEqual(list.rowCount,2,"in-place array changes refresh the list")
t.assertEqual(template.refs.editor,editor,"updating rows leaves the editor intact")
rows={}; draw(); t.assertEqual(list.rowCount,0,"an empty source clears the list")
rows={{id="other",title="NewProject.lua"}}; draw(); t.assertEqual(list.rowCount,1,"project switching replaces the old rows")
template:dispose(); os.remove(path)
os.exit(t.summary() and 0 or 1)
