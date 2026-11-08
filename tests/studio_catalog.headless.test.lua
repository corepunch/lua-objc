local t = require("TestKit")
local Catalog = require("apps.studio.services.Catalog")
local documents, encoded, serial, failPath, failRemove = {}, {}, 0, nil, false
local function read(path) local f=io.open(path,"rb"); if not f then return end; local value=f:read("a"); f:close(); return value end
local ns = {
	_documentRead = function(path) return documents[path] end,
	_documentExists = function(path) return documents[path] ~= nil end,
	_documentPath = function(path) return "/Documents/" .. path end,
	_documentWrite = function(path,value)
		if path == failPath then failPath = nil; return nil,"disk full" end
		documents[path]=value; return true
	end,
	_documentWriteData = function(path,value) documents[path]=value; return true end,
	_documentRemove = function(path)
		if failRemove then return nil,"permission denied" end
		for key in pairs(documents) do
			if key == path or key:sub(1,#path+1) == path .. "/" then documents[key]=nil end
		end
		return true
	end,
	_jsonEncode = function(value) serial=serial+1; local id=tostring(serial); encoded[id]=value; return id end,
	json_parse = function(source) if source:match("^%[") then return {"HabitTracker","StarterApp"} end; return assert(encoded[source],"bad json") end,
	_readFile = read,
}
local repos = {}
local git = {open=function(path) return repos[path] end, init=function(path)
	local history = {}
	local repo={log=function() return history end,add=function() return true end,status=function() return {{index=true}} end,
		commit=function(_,message) table.insert(history,{id="first",summary=message}); return "first" end,close=function() end}
	repos[path]=repo; return repo
end}
local catalog = Catalog.new(ns,git,read)
t.assertEqual(#catalog:list(),2,"bundled projects appear on a fresh device")
t.expect(documents["projects.json"] ~= nil,"the bundled project registry is persisted before creation")
t.expect(not catalog:create(" ","StarterApp"),"empty names are rejected")
t.expect(not catalog:create("Test","Untrusted"),"creation accepts only bundled templates")
local namedLikeTemplate = assert(catalog:create("StarterApp","StarterApp"))
t.assertEqual(namedLikeTemplate.id,"StarterApp2","unmaterialized bundled project names are reserved")
assert(catalog:delete(namedLikeTemplate.id))
local created = assert(catalog:create("My App","StarterApp"))
t.assertEqual(created.id,"MyApp","the directory name is safe")
t.expect(documents["MyApp/Controller.lua"] ~= nil,"creation copies executable source")
t.expect(documents["MyApp/views/pages/Main.etlua"] ~= nil,"creation includes etlua page folders")
t.assertEqual(#created.workspace.versions:log(),1,"creation makes an initial Git snapshot")
t.assertEqual(#catalog:list(),3,"the created project joins the bundled catalog")
local duplicate = assert(catalog:create("My App","StarterApp"))
t.assertEqual(duplicate.id,"MyApp2","duplicate titles get separate project folders")
local original = documents["MyApp/Controller.lua"]
local files={}; for path,text in pairs(created.workspace.seed) do files[path]=text end
files["demo/playground/Controller.lua"]="return { edited = true }"
files["demo/playground/Added.lua"]="return 1"
failPath="MyApp/project.lua"
t.expect(not created.workspace.storage.save({files=files,modelId="openrouter/free"}),"a late write error fails the save")
t.assertEqual(documents["MyApp/Controller.lua"],original,"earlier writes are rolled back")
t.assertEqual(documents["MyApp/Added.lua"],nil,"new files from a failed save are removed")
t.expect(created.workspace.storage.save({files=files,modelId="openrouter/free"}),"a repaired save succeeds")
local reopened=assert(catalog:open("MyApp"))
t.assertEqual(reopened.seed["demo/playground/Controller.lua"],"return { edited = true }","opening a project uses saved source")
t.assertEqual(documents["MyApp2/Controller.lua"],original,"saving does not touch another project")
t.expect(not catalog:delete("../MyApp"),"deletion requires a catalog project")
failPath="projects.json"
t.expect(not catalog:delete("MyApp"),"a registry write error blocks deletion")
t.expect(documents["MyApp/Controller.lua"] ~= nil,"failed registration leaves source intact")
failRemove=true
t.expect(not catalog:delete("MyApp"),"a folder removal error is reported")
t.assertEqual(#catalog:list(),4,"failed deletion restores the catalog")
failRemove=false
documents["MyApp/data/private.json"]="private"
documents["MyApp/.git/config"]="git"
t.expect(catalog:delete("MyApp"),"delete removes the selected project")
t.assertEqual(documents["MyApp/data/private.json"],nil,"delete removes local app data")
t.assertEqual(documents["MyApp/.git/config"],nil,"delete removes local Git history")
t.assertEqual(documents["MyApp2/Controller.lua"],original,"deletion preserves other projects")
for _, id in ipairs({"MyApp2","HabitTracker","StarterApp"}) do assert(catalog:delete(id)) end
t.assertEqual(#catalog:list(),0,"deleting every project leaves an empty catalog")
t.assertEqual(#Catalog.new(ns,git,read):list(),0,"a fresh session does not resurrect deleted bundled projects")
local fresh=assert(catalog:create("Fresh","StarterApp"))
t.assertEqual(fresh.id,"Fresh","creation works after deleting all projects")
t.assertEqual(#catalog:list(),1,"only the new project returns to the catalog")
local ids={}; for _, entry in ipairs(catalog:templates()) do table.insert(ids, entry.id) end
t.assertEqual(table.concat(ids,","),"StarterApp,HabitTracker,Platformer,Racing","templates are listed in sheet order")
local platformer=assert(catalog:create("My Game","Platformer"))
t.assertEqual(platformer.id,"MyGame","a game template creates a project")
t.expect(documents["MyGame/AGENTS.md"] ~= nil,"a game project carries its agent rulebook")
t.expect(documents["MyGame/models/systems/Hero.lua"] ~= nil and documents["MyGame/catalog/levels/meadow.lua"] ~= nil,
	"nested template folders are copied")
t.expect(platformer.workspace.seed["demo/playground/AGENTS.md"] ~= nil,"the agent can read AGENTS.md from the project")
os.exit(t.summary() and 0 or 1)
