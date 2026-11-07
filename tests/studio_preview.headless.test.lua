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
os.exit(t.summary() and 0 or 1)
