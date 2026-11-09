local t = require("TestKit")
local Root = require("apps.studio.Controller")
local Export = require("apps.studio.services.Export")
local Connection = require("data.appwrite.connection")
local appwriteEntry
local appwrite = Connection.new({read = function() return appwriteEntry end, write = function(v) appwriteEntry = v; return true end,
	remove = function() appwriteEntry = nil; return true end, decode = require("AppKit").json_parse})
local seed = { ["demo/playground/init.lua"] = "return {}", ["demo/playground/Model.lua"] = "return {}",
	["demo/playground/Controller.lua"] = "return {}", ["demo/playground/views/pages/Main.etlua"] = '<Label text="Hello" />' }
local saved, key, pending, cancelled, closed = {}, nil, nil, 0, 0
local projects = {{id = "One", title = "One", icon = "app"}, {id = "Two", title = "Two", icon = "app"}}
local catalog = {
	list = function()
		local result = {}
		for _, project in ipairs(projects) do
			local row = {}; for key,value in pairs(project) do row[key]=value end
			table.insert(result,row)
		end
		return result
	end,
	templates = function() return {{id = "StarterApp", title = "Blank App"}, {id = "HabitTracker", title = "Habit Tracker"},
		{id = "Platformer", title = "3-D Platformer"}} end,
	open = function(_, id) return { seed = seed, versions = {close = function() closed = closed + 1 end},
		storage = {load = function() return saved[id] end, save = function(value) saved[id] = value; return true end} } end,
}
local sheet, confirmation
local root = Root.new({
	ns = {_documentExists = function() return false end, _documentPath = function(p) return p end,
		confirm = function(props) confirmation=props; return props end,
		shareFiles = function(items, name) saved.export = {items = items, name = name}; return true end},
	catalog = catalog,
	device = {json = {encode = function(v) return v end, decode = function(v) return v end},
		transport = function(_, _, callback) pending = callback; return function() cancelled = cancelled + 1 end end,
		credentials = {read = function() return key end, save = function(v) key = v; return true end, clear = function() key = nil; return true end},
		appwrite = appwrite},
	sheets = {present = function(_, kind, data) sheet = {kind = kind, data = data} end, update = function() end, close = function() sheet = nil end},
	previewFactory = function() return {render = function() return {} end, close = function() end} end,
})
root.render = function(self)
	for _, project in ipairs(self.projects or {}) do
		assert(type(self.actions[project.action]) == "function", "every rendered project must already have an action")
	end
end
t.expect(root:openProject("One"), "open project without UIKit or a window")
t.assertEqual(root.model.id, "One", "the root owns the selected workspace")
root.actions.editSource("broken lua !")
t.expect(not root:openProject("Two"), "invalid editor drafts block switching")
t.assertEqual(root.model.id, "One", "the old project remains available for repair")
root.actions.undoChange()
t.expect(root:openProject("Two"), "switch after undoing the draft")
t.assertEqual(closed, 1, "the old Git repository is closed")
root.chat.draft = "Make a change"
local ok = root:sendMessage()
t.expect(not ok and sheet.kind == "Settings", "missing credentials open Settings")
t.assertEqual(root.chat.draft, "Make a change", "a rejected send keeps its draft")
root.actions.editKey("fixture-key")
root.actions.saveCredential()
t.assertEqual(sheet.data.keyDraft, "", "saved credentials are cleared from the visible form")

-- The person's own Appwrite project, kept like the OpenRouter key.
t.assertEqual(sheet.data.hasAppwrite, false, "no Appwrite project is connected at first")
t.assertEqual(sheet.data.appwriteEndpoint, Connection.endpoint, "the endpoint starts at Appwrite Cloud")
root.actions.editAppwriteProject("proj1")
root.actions.saveAppwrite()
t.expect(appwriteEntry == nil and sheet.data.message:find("API key", 1, true), "a connection needs its key: " .. tostring(sheet.data.message))
root.actions.editAppwriteKey("standard_abc")
root.actions.saveAppwrite()
t.expect(appwrite:load().project == "proj1" and appwrite:load().key == "standard_abc", "the connection is saved in the Keychain")
t.expect(sheet.data.appwriteKeyDraft == "" and sheet.data.hasAppwrite, "and the key leaves the visible form")
root.actions.editAppwriteProject("proj2")
root.actions.saveAppwrite()
t.expect(appwrite:load().project == "proj2" and appwrite:load().key == "standard_abc", "an empty key field keeps the saved key")
root:showSettings()
t.expect(sheet.data.appwriteProject == "proj2" and sheet.data.hasAppwrite, "Settings show the connected project")
root.actions.clearAppwrite()
t.expect(appwrite:load() == nil and not sheet.data.hasAppwrite, "removing forgets the connection")
t.expect(root:sendMessage(), "the composer sends through the injected transport")
t.expect(root.chat.agent.busy, "the working state reaches presentation")
root.actions.stopAgent()
t.assertEqual(cancelled, 1, "Stop is wired to cancellation")
local count = #root.model.messages
pending({choices = {{message = {content = "Late"}}}})
t.assertEqual(#root.model.messages, count, "late UI responses cannot update the transcript")
root.actions.editSource("return { updated = true }")
t.expect(root.actions.saveSource(), "the source Save action persists edits")
t.assertEqual(saved.Two.files["demo/playground/Controller.lua"], "return { updated = true }", "the selected source is saved")
t.expect(root.actions.shareProject(), "Share supplies a source archive to the native sheet")
t.assertEqual(saved.export.name, "Two", "the selected project is exported")
for _, item in ipairs(saved.export.items) do
	t.expect(not item.name:find("settings") and not item.name:find("data/") and not item.name:find(".git",1,true), "exports omit runtime and host state")
end
root.actions.toggleZoom(); t.assertEqual(root.previewZoom, 0.75, "zoom changes state")
root.actions.toggleAppearance(); t.assertEqual(root.previewAppearance, "dark", "appearance changes state")
root.chat.listening = true
root.actions.showTemplates(); t.expect(not root.chat.listening,"opening a sheet stops hidden dictation"); t.assertEqual(sheet.kind, "Catalog", "Templates opens its catalog")
root.actions.newBlank(); t.assertEqual(sheet.kind, "Project", "Blank opens project creation")
t.assertEqual(sheet.data.templateIndex,0,"Blank selects the first native picker item")
root.actions.newHabit(); t.assertEqual(sheet.data.templateIndex,1,"Habit selects the second native picker item")
t.assertEqual(#sheet.data.templates,3,"the picker lists every bundled template")
root.actions.newConversation(); t.assertEqual(#root.model.messages, 0, "New Conversation clears real turns")
t.expect(not pcall(Export.items,"Two", {["private/key.lua"] = "secret"}), "export rejects sources outside the project")
catalog.create = function(_, title, template)
	t.assertEqual(template,"StarterApp","creation uses the chosen blank template")
	table.insert(projects,{id="Three",title=title,icon="app"})
	return {id="Three",workspace=catalog:open("Three")}
end
root:showNewProject(); root.actions.editProjectName("Created App")
root.actions.editSource("broken lua !")
t.expect(not root.actions.createProject(),"invalid drafts block creation before any folder is registered")
t.assertEqual(#projects,2,"failed creation does not leave an unopened project behind")
root.actions.undoChange()
t.expect(root.actions.createProject(),"project creation wires the new menu action before rendering")
t.assertEqual(root.model.id,"Three","the newly created project is opened")
local failDelete=true
catalog.delete=function(_,id)
	if failDelete then return nil,"permission denied" end
	for index,project in ipairs(projects) do if project.id==id then table.remove(projects,index);return true end end
end
root.actions.showDeleteProject()
t.assertEqual(confirmation.cancel,"Cancel","deletion uses the native Cancel action")
t.assertEqual(confirmation.destructive,"Delete Project","deletion uses the native destructive action")
t.assertEqual(#projects,3,"cancel leaves all projects intact")
root.actions.showDeleteProject()
t.expect(not confirmation.action(),"failed deletion is reported")
t.assertEqual(root.model.id,"Three","failed deletion leaves the workspace usable")
failDelete=false
root.actions.editSource("invalid draft to discard !")
local oldConfirmation=confirmation
t.expect(confirmation.action(),"confirmed deletion discards unsaved drafts")
t.assertEqual(root.model.id,"One","another project opens after deletion")
t.expect(not oldConfirmation.action(),"a stale confirmation cannot delete the next project")
t.assertEqual(root.model.id,"One","the next project survives a stale confirmation")
t.assertEqual(require("apps.studio.Model"):find("Three"),nil,"deleted workspaces leave the in-memory store")
root.actions.showDeleteProject(); assert(confirmation.action())
root.actions.showDeleteProject(); assert(confirmation.action())
t.expect(root:workspaceData().empty,"deleting the final project presents an empty state")
t.expect(root.actions.newProject~=nil,"empty workspace still offers creation")
root.actions.newProject();root.actions.editProjectName("Recreated")
t.expect(root.actions.createProject(),"creation works again from the empty state")
t.assertEqual(root.model.id,"Three","recreated folder gets a fresh workspace row")
local exported = Export.items("Example",{["demo/playground/Controller.lua"]='return require("demo.playground.Model")'})
for _, item in ipairs(exported) do
	if item.name == "Controller.lua" then t.assertEqual(item.text,'return require("apps.Example.Model")',"exported modules resolve from their standalone app folder") end
end
os.exit(t.summary() and 0 or 1)
