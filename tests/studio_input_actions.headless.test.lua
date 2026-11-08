local t = require("TestKit")
local xml = require("ui.xml")
for _, tag in ipairs({"TextField","TextEditor","Toggle","Picker","Slider","Stepper"}) do
	local source = '<' .. tag .. ' action="edit" />'
	local description = xml.describe(source,{actions={edit=function() end}})
	local ok, err = pcall(xml.validateActions,description)
	t.expect(not ok and err:find('uses onChange="edit", not action',1,true),tag .. " rejects a silently ignored input event")
	ok, err = pcall(xml.render,source,{actions={edit=function() end}},{[tag]=function() return {} end})
	t.expect(not ok and err:find('uses onChange=',1,true),tag .. " also validates non-retained renders")
	local valid = xml.describe('<' .. tag .. ' onChange="edit" />',{actions={edit=function() end}})
	t.expect(pcall(xml.validateActions,valid),tag .. " accepts its documented change event")
end
local bad = xml.describe('<TextField onChange="missing" />',{actions={}})
t.expect(not pcall(xml.validateActions,bad),"valid event names still require a real controller action")
t.expect(pcall(xml.validateActions,xml.describe('<Label text="Static" />',{})),"static templates need no actions table")
t.expect(pcall(xml.validateActions,xml.describe('<Button action="add" />',{actions={add=function() end}})),"buttons retain their native action contract")
os.exit(t.summary() and 0 or 1)
