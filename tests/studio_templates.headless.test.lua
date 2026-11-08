local t = require("TestKit")
local xml = require("ui.xml")
local Chat = require("apps.studio.helpers.Chat")
local Rail = require("apps.studio.helpers.Rail")
local Preview = require("apps.studio.helpers.Preview")
local states = {
	{messages = {}},
	{messages = {{role = "user", text = string.rep("A long request & <source> ", 20)},
		{role = "error", text = "Connection failed"}}, busy = true, draft = "Draft", attachments = {{name="source.lua"}}},
}
for _, state in ipairs(states) do
	local data = {rail = Rail.presentation(), preview = Preview.presentation(), chat = Chat.presentation(state)}
	local source = xml.describeFile("apps/studio/views/sections/Workspace.etlua", data).source
	t.expect(not source:find('action=""', 1, true), "every active button has a named action")
	for _, action in ipairs({"showSettings", "shareProject", "saveSource", "editSource", "editDraft", "attachContext", "toggleDictation"}) do
		t.expect(source:find('="' .. action .. '"', 1, true), "workspace wires " .. action)
	end
	if state.busy then
		t.expect(source:find('action="stopAgent"',1,true), "working state shows Stop")
		t.expect(source:find('editable="false"',1,true), "the editor is protected while the agent works")
	else
		t.expect(source:find('action="sendMessage"',1,true), "idle state shows Send")
		t.expect(source:find('editable="true"',1,true), "source is editable")
	end
end
local sheets = {
	Settings = {keyDraft="",hasKey=false,modelIdDraft="openrouter/free",message=""},
	Project = {projectName="",templateIndex=0,message=""},
	Catalog = {title="Templates",items={{title="Blank",detail="Description",icon="app",button="Create",action="newBlank"}}},
	Export = {projectTitle="Example"},
}
for kind, data in pairs(sheets) do
	local result = xml.describeFile("apps/studio/views/sheets/" .. kind .. ".etlua",data)
	t.expect(result.source ~= nil, "describe " .. kind .. " without a native runtime")
end
local settingsShell = xml.describeFile("apps/studio/views/sheets/SettingsShell.etlua",{actions={closeSheet=function() end}}).source
t.expect(settingsShell:find('systemItem="done"',1,true),"Settings closes with the native system Done item")
local studioWindow = xml.describeFile("apps/studio/views/layouts/Window.etlua",{canvas=require("apps.studio.helpers.Theme").canvas}).source
t.expect(studioWindow:find('orientation="landscape"',1,true),"Studio never requests a portrait window")
local empty = xml.describeFile("apps/studio/views/sections/Workspace.etlua",{empty=true,status=""}).source
t.expect(empty:find('action="newProject"',1,true),"empty state can create a project")
t.expect(not empty:find('<Preview ',1,true),"empty workspace owns no running preview")
t.expect(loadfile("test/studio-smoke/Controller.lua") ~= nil, "the UIKit smoke entry compiles")
t.expect(loadfile("test/studio-smoke/GitHubWorkflow.lua") ~= nil, "the opt-in live GitHub workflow compiles")
for _, state in ipairs({"error","ready"}) do
	local chat = Chat.presentation({messages={{role="agent",text="Saved",previewState=state,previewError="Unknown tag",
		changes={{path="Model.lua",added=1,removed=0}}}}})
	local source = xml.describeFile("apps/studio/views/sections/Workspace.etlua",{
		rail=Rail.presentation(),preview=Preview.presentation(),chat=chat}).source
	local success = source:find('text="Preview updated"',1,true) ~= nil
	local failed = source:find('text="Preview failed. Last working version kept."',1,true) ~= nil
	t.assertEqual(success,state=="ready","only working previews claim to be updated")
	t.assertEqual(failed,state=="error","a failed preview keeps an explicit warning beside its diff")
	t.assertEqual(chat.messages[1].previewError,"Unknown tag","presentation preserves the repair diagnostic")
end
local stage=xml.describeFile("apps/studio/views/sections/PreviewPane.etlua",Preview.presentation()).source
t.expect(not stage:find('name="checkmark.circle.fill"',1,true),"the stage claims no success; the chat reports preview outcomes")
os.exit(t.summary() and 0 or 1)
