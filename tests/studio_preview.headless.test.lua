local t = require("TestKit")
local Preview = require("apps.studio.services.Preview")
local scopes={}
local ns={HostingController=function(value) return value end,Scope={new=function()
	local scope={disposed=false}; function scope:dispose() self.disposed=true end
	table.insert(scopes,scope); return scope
end,withScope=function(_,fn) return fn() end}}
local source='local ns=require("ns"); return {new=function() return {createWindow=function() return ns.Window {content="native controller"} end} end}'
local files={["demo/playground/init.lua"]=source}
local preview=Preview.new(ns,function() error("unexpected framework read") end)
t.assertEqual(preview:render(files),"native controller","a project returns its hosted content")
t.expect(not scopes[1].disposed,"the active preview retains its scope")
t.assertEqual(preview:render(files),"native controller","reloading renders a fresh controller")
t.expect(scopes[1].disposed,"a successful reload releases old native registrations")
files["demo/playground/init.lua"]='error("broken preview")'
local result,err=preview:render(files)
t.expect(not result and err:find("broken preview",1,true),"a preview error is returned")
t.expect(scopes[3].disposed,"a failed render releases its own registrations")
t.expect(not scopes[2].disposed,"a failed render preserves the working preview's registrations")
preview:close(); t.expect(scopes[2].disposed,"switching projects releases the active preview")
files["demo/playground/init.lua"] = [=[local ns=require("ns")
return {new=function()
	local c={value=0,text="",enabled=true}; c.cycle=c
	c.actions={increment=function() c.value=c.value+1 end,edit=function(value) c.text=value end,
		toggle=function(value) c.enabled=value end,broken=function() error("interaction failed") end,
		loop=function() while true do end end}
	function c:createWindow() return ns.Window{content="interactive"} end
	function c:data() return {value=self.value,text=self.text,enabled=self.enabled,actions=self.actions,cycle=self} end
	return c
end}]=]
t.expect(preview:render(files),"render an interactive controller")
local running=preview.controller
local data=preview:interact("increment")
t.assertEqual(data.value,1,"the action changes the live preview controller without reloading")
t.assertEqual(preview.controller,running,"interaction preserves controller identity")
t.expect(data.actions==nil,"snapshots omit callback tables")
local node,depth=data,0
while node do depth=depth+1; node=node.cycle end
t.expect(depth<=5,"snapshot depth bounds cyclic data")
t.assertEqual(preview:interact("edit","draft").text,"draft","text arguments reach the action")
local unicode=preview:interact("edit",string.rep("界",1000)).text
t.expect(#unicode<=2048 and utf8.len(unicode)~=nil,"bounded snapshot text preserves UTF-8 for the JSON transport")
t.assertEqual(preview:interact("toggle",false).enabled,false,"false is preserved as an event argument")
local failed,problem=preview:interact("unknown")
t.expect(not failed and problem:find("No preview controller action",1,true),"unknown actions are actionable errors")
failed,problem=preview:interact("broken")
t.expect(not failed and problem:find("interaction failed",1,true),"interaction errors reach the agent")
failed,problem=preview:interact("loop")
t.expect(not failed and problem:find("execution budget",1,true),"runaway test actions cannot hang Studio")
t.assertEqual(preview:interact("increment").value,2,"a failed action leaves the preview usable")
files["demo/playground/init.lua"]='error("failed replacement")'
t.expect(not preview:render(files),"a bad replacement fails")
t.assertEqual(preview.controller,running,"a bad replacement preserves the interactive controller")
local stale,reason=preview:interact("increment")
t.expect(not stale and reason:find("Current source did not render",1,true),"the agent cannot validate old controls as though failed source were running")
preview:close()
t.assertEqual(preview.controller,nil,"closing releases the controller")
t.expect(not preview:interact("increment"),"a closed preview cannot run actions")
os.exit(t.summary() and 0 or 1)
