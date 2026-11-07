local t = require("TestKit")
local Model = require("data.model")
local Store = require("apps.studio.Store")
local Workspaces = require("apps.studio.Model")
local Session = require("apps.studio.services.Session")
local seed = {}
for _, path in ipairs({ "init.lua", "Model.lua", "Controller.lua", "views/Window.etlua" }) do
	seed["demo/playground/" .. path] = path:match("%.etlua$") and '<Label text="Hello" />' or "return {}"
end
local writes, fail = {}, false
local storage = { load = function() return nil end, save = function(value)
	if fail then return nil, "disk full" end
	table.insert(writes, value)
	return true
end }
Model.bind(Store())
local session = Session.open(storage, seed, "One")
local row = session.workspace
local file = "demo/playground/Model.lua"
t.assertEqual(row:model(), Workspaces, "workspace is a Lapis model row")
t.assertEqual(row.modelId, "openrouter/free", "the default model is free")
t.assertEqual(#row:listFiles(), 4, "the four MVC sources are present")
t.expect(row:edit(file, "broken lua !"), "an invalid in-progress edit remains editable")
t.expect(not session:saveDrafts(), "invalid source cannot replace the running project")
t.assertEqual(row.files[file], "return {}", "failed validation preserves saved source")
t.assertEqual(row:source(file), "broken lua !", "failed validation preserves the user's draft")
t.assertEqual(#writes, 0, "invalid source never reaches disk")
t.expect(row:edit(file, "return { count = 3 }"), "edit valid Lua")
fail = true
t.expect(not session:saveDrafts(), "disk errors are surfaced")
t.assertEqual(row.revision, 0, "a failed save does not change project revision")
t.assertEqual(#row.history, 0, "a failed save does not add undo history")
fail = false
t.expect(session:saveDrafts(), "save the complete draft batch")
t.assertEqual(row.revision, 1, "a completed save changes the revision")
t.assertEqual(row.files[file], "return { count = 3 }", "saved source becomes current")
t.assertEqual(row.files["demo/playground/init.lua"], seed["demo/playground/init.lua"], "unrelated source survives")
t.assertEqual(next(row.drafts), nil, "saved drafts are cleared")
t.expect(session:undo(), "undo persists the prior source")
t.assertEqual(row.files[file], "return {}", "undo restores source")
t.expect(not session:undo(), "empty undo is explicit")
t.expect(not session:apply({{path = "demo/playground/../secret.lua", content = "return 1"}}), "path traversal is rejected")
t.expect(not session:apply({{path = file, content = "return 1"}, {path = file, content = "return 2"}}), "duplicate paths are rejected")
t.expect(not session:apply({{path = file, content = "return 1"}, {path = "demo/playground/views/Bad.etlua", content = "<% if %>"}}), "invalid templates reject the whole batch")
t.assertEqual(row.files[file], "return {}", "a rejected batch has no partial mutation")
t.expect(not session:setModel("invalid"), "invalid model IDs are rejected")
fail = true
t.expect(not session:setModel("provider/other"), "a failed settings write is reported")
t.assertEqual(row.modelId, "openrouter/free", "a failed settings write is rolled back")
fail = false
t.expect(session:setModel("provider/other"), "the model selection is saved")
t.assertEqual(writes[#writes].modelId, "provider/other", "model ID is persisted")
local second = Session.open(storage, seed, "Two")
second.workspace:edit(file, "return false")
t.assertEqual(next(row.drafts), nil, "projects own separate edit drafts")
t.assertEqual(Workspaces:find("One"), row, "the store retains the first workspace")
row:message("user", "Hello")
t.assertEqual(#second.workspace.messages, 0, "conversations do not cross projects")
t.expect(row:transcript():find("Hello", 1, true), "the transcript contains actual messages")
t.expect(not Workspaces.validPath("demo/playground/project.lua"), "the source editor cannot overwrite its manifest")
t.expect(not session:apply({{path=file,content=string.rep(" ",128*1024+1)}}), "oversized source is rejected")
os.exit(t.summary() and 0 or 1)
