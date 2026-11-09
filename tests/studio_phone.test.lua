_G.__headless = true
local t = require("TestKit")
local xml = require("ui.xml")
local Capsule = require("apps.studio.helpers.Capsule")
local Chat = require("apps.studio.helpers.Chat")
local Code = require("apps.studio.helpers.Code")
local Theme = require("apps.studio.helpers.Theme")
local Root = require("apps.studio.Controller")
local PhoneController = require("apps.studio.controllers.PhoneController")

-- The capsule folds the conversation to one line.
local project = { id = "One", title = "Habit Garden", icon = "leaf.fill" }
local status = Capsule.status({ messages = {}, project = project, modelId = "openrouter/free" })
t.assertEqual(status.title, "Ask to change anything", "an untouched project invites a request")
t.assertEqual(status.detail, "Habit Garden · openrouter/free", "and names the project and its model")
t.assertEqual(Capsule.status({}).title, "No project", "without a project the capsule offers to create one")
local busy = Capsule.status({ project = project, busy = true, messages = { { role = "user", text = "Add a badge\nplease" } } })
t.expect(busy.busy and busy.title == "Working…" and busy.detail == "Add a badge", "while working it shows the request, first line only")
local turn = { { role = "user", text = "Add a badge" },
	{ role = "agent", text = "Saved 2 file(s). Undo is available.", previewState = "ready",
		changes = { { path = "views/Today.etlua", added = 9, removed = 2 }, { path = "Model.lua", added = 3, removed = 1 } } },
	{ role = "agent", text = "Saved 1 file(s). Undo is available.", previewState = "ready", changes = { { path = "Model.lua", added = 2, removed = 0 } } },
	{ role = "agent", text = "Added the badge.\nTap it to see the streak." } }
local updated = Capsule.status({ project = project, messages = turn })
t.assertEqual(updated.title, "Preview updated", "a turn that changed files reports it")
t.assertEqual(updated.detail, "2 files changed, +14 −3. Tap to review.", "counting each file once across its saves")
turn[3].previewState = "error"
local broken = Capsule.status({ project = project, messages = turn })
t.expect(broken.failed and broken.title == "Preview failed", "a save that broke the preview is a failure")
t.expect(broken.detail:find("Last working version kept", 1, true) ~= nil, "and says the old version still runs")
turn[3].previewState = "ready"
local talk = Capsule.status({ project = project, messages = { { role = "user", text = "Hi" }, { role = "agent", text = "Hello!\nWhat shall we build?" } } })
t.assertEqual(talk.title, "Hello!", "a reply without edits is quoted")
t.assertEqual(talk.detail, "Tap to continue", "with an invitation")
local failed = Capsule.status({ project = project, messages = { { role = "user", text = "Hi" },
	{ role = "error", text = "OpenRouter HTTP 401: bad key. Check your API key in Settings." } } })
t.expect(failed.failed and failed.title == "Something went wrong", "an error ends the turn visibly")
t.expect(Capsule.status({ project = project, messages = {}, previewError = "Model.lua:3: oops" }).failed, "a preview broken by hand shows as failed")

-- The window: the project full screen, Studio in its bottom accessory.
local layout = xml.describeFile("apps/studio/views/layouts/Phone.etlua", {}).source
t.expect(layout:find('<Preview id="stage" fullScreen="true"', 1, true) ~= nil, "the project runs full screen in the preview host")
local accessory = assert(layout:match("<BottomAccessory>(.-)</BottomAccessory>"), "Studio takes the bottom accessory of the project")
t.expect(accessory:find('id="chrome"', 1, true) ~= nil, "which hosts the capsule template")
t.expect(not layout:find("<GlassEffect", 1, true) and not layout:find("orientation=", 1, true),
	"nothing floats over the project and the phone is not locked to landscape")
t.expect(not pcall(xml.render, '<Preview><Label text="x" /></Preview>', {}, require("AppKit")), "a Preview takes no child but an accessory")

local function capsule(state)
	state.brand, state.tint, state.actions = Theme.brand, Theme.tint, {}
	return xml.describeFile("apps/studio/views/sections/Capsule.etlua", state).source
end
local idle = capsule({ title = "Preview updated", detail = "2 files changed, +14 −3. Tap to review." })
t.expect(idle:find('<HStack id="capsule"', 1, true) ~= nil and not idle:match('id="capsule"[^>]-background='), "the capsule is one row with no fill of its own")
t.expect(idle:find('onTap="openConversation"', 1, true) ~= nil, "a tap anywhere opens the conversation")
t.expect(idle:find('action="dictate"', 1, true) ~= nil and idle:find('action="openConversation"', 1, true) ~= nil, "idle, it offers dictation and Open")
local working = capsule({ title = "Working…", detail = "Add a badge", busy = true })
t.expect(working:find("<ProgressView", 1, true) ~= nil and working:find('action="stopAgent"', 1, true) ~= nil
	and not working:find('action="dictate"', 1, true), "while working it shows progress and Stop")
t.expect(capsule({ title = "Preview failed", detail = "x", failed = true }):find('color="systemOrange"', 1, true) ~= nil, "a failure colours the title")

-- The sheet: the project menu leads, Code and Done trail.
local projects = { { id = "One", title = "Habit Garden", icon = "leaf.fill", selected = true, action = "openProject_One" },
	{ id = "Two", title = "Starter", icon = "app.dashed", action = "openProject_Two" } }
local shell = xml.describeFile("apps/studio/views/sheets/ConversationShell.etlua",
	{ project = projects[1], modelId = "openrouter/free", projects = projects, actions = {} }).source
t.expect(shell:find('<NavigationStack id="conversationNav" title="Habit Garden" subtitle="openrouter/free"', 1, true) ~= nil,
	"the sheet is titled with the project and its model")
t.expect(shell:find('placement="topBarLeading"', 1, true) < shell:find('id="projectMenu"', 1, true), "the project menu leads the bar")
t.expect(shell:find('action="openProject_Two"', 1, true) ~= nil, "and switches projects")
for _, action in ipairs({ "reloadPreview", "undoChange", "newConversation", "commitProject", "shareProject", "showGitHub",
	"newProject", "showDeleteProject", "showSettings" }) do
	t.expect(shell:find('action="' .. action .. '"', 1, true) ~= nil, "the project menu offers " .. action)
end
t.expect(shell:find('action="showCode"', 1, true) ~= nil and shell:find('systemItem="done"', 1, true) ~= nil
	and shell:find('action="closeConversation"', 1, true) ~= nil, "Code and Done trail")

local chat = Chat.presentation({ messages = { { role = "user", text = "Add a badge" }, turn[2] }, draft = "Make it blue" })
chat.actions = {}
local conversation = xml.describeFile("apps/studio/views/sheets/Conversation.etlua", chat).source
t.expect(conversation:find('<SafeAreaInset edge="bottom"', 1, true) ~= nil, "the composer sits in the bottom inset, above the keyboard")
t.expect(conversation:find('horizontal="true"', 1, true) ~= nil and not conversation:find("<FlowStack", 1, true), "suggestions shelve sideways on a phone")
t.expect(select(2, conversation:gsub("2 files changed", "")) == 1, "the edit renders as one change card")
t.expect(conversation:find('text="Make it blue"', 1, true) ~= nil, "the composer shows the draft")
local fresh = Chat.presentation(); fresh.actions = {}
t.expect(xml.describeFile("apps/studio/views/sheets/Conversation.etlua", fresh).source:find("Ask for a change", 1, true) ~= nil,
	"an empty conversation explains itself")
local pane = xml.describeFile("apps/studio/views/sections/ChatPane.etlua", chat).source
t.expect(select(2, pane:gsub("2 files changed", "")) == 1 and pane:find("<FlowStack", 1, true) ~= nil,
	"the iPad card lays out the same turns with wrapping suggestions")

-- The code: a menu of files over the editor.
local files = { ["demo/playground/Controller.lua"] = "return {}", ["demo/playground/views/Today.etlua"] = "<Label />" }
local code = Code.presentation(files, "views/Today.etlua")
local editor = xml.describeFile("apps/studio/views/sections/Editor.etlua", { code = code, syntaxRules = Code.rules, busy = false, actions = {} }).source
t.expect(editor:find('<Menu id="fileMenu" title="Today.etlua"', 1, true) ~= nil, "the file menu is titled with the open file")
t.expect(editor:find('title="views/Today.etlua"[^>]-checked="true"') ~= nil and editor:find('title="Controller.lua"[^>]-checked="false"') ~= nil,
	"and checks it")
t.expect(editor:find('action="selectFile_views/Today.etlua"', 1, true) ~= nil, "files select by name")
t.expect(editor:find('onChange="editSource"', 1, true) ~= nil and editor:find('action="saveSource"', 1, true) ~= nil,
	"the source edits and saves through the root actions")
local page = xml.describeFile("apps/studio/views/pages/Code.etlua", { project = projects[1], actions = {} }).source
t.expect(page:find('onDisappear="codeClosed"', 1, true) ~= nil and page:find('id="editorHost"', 1, true) ~= nil,
	"the code page hosts the editor and reports leaving")

-- Wiring: the phone layer drives the real session, agent and preview.
local seed = { ["demo/playground/init.lua"] = "return {}", ["demo/playground/Model.lua"] = "return {}",
	["demo/playground/Controller.lua"] = "return {}", ["demo/playground/views/pages/Main.etlua"] = '<Label text="Hello" />' }
local saved, key, pending, presented, rendered = {}, nil, nil, {}, 0
local catalog = {
	list = function() return { { id = "One", title = "Habit Garden", icon = "leaf.fill" } } end,
	templates = function() return { { id = "StarterApp", title = "Blank App" } } end,
	open = function(_, id) return { seed = seed, versions = { close = function() end },
		storage = { load = function() return saved[id] end, save = function(value) saved[id] = value; return true end } } end,
}
local ns = { _documentExists = function() return false end, _documentPath = function(p) return p end,
	presentSheet = function(builder, options) table.insert(presented, options); return builder end,
	dismiss = function() table.remove(presented) end,
	pushScreen = function(_, _, builder) return builder end }
local root = Root.new({ ns = ns, catalog = catalog,
	device = { json = { encode = function(v) return v end, decode = function(v) return v end },
		transport = function(_, _, callback) pending = callback; return function() end end,
		credentials = { read = function() return key end, save = function(v) key = v; return true end, clear = function() key = nil; return true end },
		appwrite = { load = function() return nil end, save = function() return nil, "not in this test" end, clear = function() return true end } },
	sheets = { present = function() end, update = function() end, close = function() end },
	previewFactory = function() return { render = function() rendered = rendered + 1; return {} end, close = function() end } end })
root.phone = PhoneController.new(root, ns)
t.expect(root:openProject("One"), "a project opens on the phone without a window")
local phone = root.phone
t.assertEqual(phone:capsuleData().title, "Ask to change anything", "the capsule reads the fresh conversation")
t.expect(type(root.actions.openConversation) == "function" and type(root.actions.dictate) == "function", "the phone actions join the root table")
t.expect(type(root.actions["selectFile_views/pages/Main.etlua"]) == "function", "files resolve to actions by name")
root.actions["selectFile_views/pages/Main.etlua"]()
t.assertEqual(root.selectedFile, "views/pages/Main.etlua", "and select the file in the root")
t.assertEqual(phone:editorData().code.name, "Main.etlua", "the editor shows the selected file")
root.actions.openConversation()
t.assertEqual(#presented, 1, "the capsule presents the conversation sheet")
t.assertEqual(presented[1].largestUndimmedDetent, "medium", "with the project live beneath its medium detent")
t.expect(type(presented[1].onDismiss) == "function", "and learns when the user drags it away")
key = "fixture-key"
root.chat.draft = "Add a greeting"
t.expect(root:sendMessage(), "the composer sends through the agent")
t.assertEqual(phone:capsuleData().title, "Working…", "the capsule shows the agent working")
t.assertEqual(phone:capsuleData().detail, "Add a greeting", "on the request")
local before = rendered
pending({ choices = { { message = { tool_calls = { { id = "call-1", ["function"] = { name = "applyFiles",
	arguments = { files = { { path = "demo/playground/views/pages/Main.etlua", content = '<Label text="Hello" />\n<Label text="Welcome" />' } } } } } } } } } })
t.assertEqual(rendered, before + 1, "an applied edit reloads the preview")
pending({ choices = { { message = { content = "Added a welcome line." } } } })
local done = phone:capsuleData()
t.assertEqual(done.title, "Preview updated", "the capsule reports the edit")
t.assertEqual(done.detail, "1 file changed, +1. Tap to review.", "with its file count and delta")
t.assertEqual(#phone:conversationData().messages, 3, "the sheet renders the real transcript")
t.expect(not root.chat.agent.busy, "and the agent is idle again")
root.chat.listening = true
presented[1].onDismiss()
t.expect(not root.chat.listening and not phone:conversationOpen(), "a dragged-away sheet stops dictation and is gone for the phone layer")
os.exit(t.summary() and 0 or 1)
