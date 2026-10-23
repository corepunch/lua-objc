_G.__headless = true
local t = require("TestKit")
local Model = require("apps.studio.Model")
local Agent = require("apps.studio.services.Agent")
local Preview = require("apps.studio.services.Preview")
local Providers = require("apps.studio.services.Providers")
local Keys = require("apps.studio.services.Keys")
local Changes = require("apps.studio.helpers.Changes")
local ns = require("AppKit")
local function read(path)
	local file = assert(io.open(path)); local value = file:read("*a"); file:close(); return value
end
local seed = {}
for _, name in ipairs({ "init.lua", "Model.lua", "Controller.lua", "views/Window.etlua" }) do
	seed["demo/playground/" .. name] = read("demo/playground/" .. name)
end
local saved, failSave
local storage = { load = function() return nil end, save = function(value)
	if failSave then return nil, "disk full" end
	saved = value; return true
end }
local model = Model.new(storage, seed)
t.assertEqual(model.provider, nil, "a new project has not chosen a provider yet")
t.assertEqual(#model:listFiles(), 4, "starter has four MVC files")
for _, path in ipairs({ "../secret.lua", "/tmp/file.lua", "demo/playground/../studio/Model.lua", "demo/playground//a.lua", "demo/playground/evil.txt", "demo/playground/a\\b.lua" }) do
	t.expect(not Model.validPath(path), "reject unsafe path " .. path)
end
local path = "demo/playground/Model.lua"
local original = model.files[path]
local ok = model:apply({ { path = path, content = "invalid lua !" } })
t.expect(not ok, "invalid Lua rejected")
t.assertEqual(model.files[path], original, "failed edits preserve project")
ok = model:apply({ { path = path, content = "return {}" }, { path = path, content = "return {}" } })
t.expect(not ok, "duplicate edits rejected")
ok = model:apply({ { path = path, content = "return {}" }, { path = "demo/playground/views/Broken.etlua", content = "<% if %>" } })
t.expect(not ok, "template syntax error rejects whole batch")
t.assertEqual(model.files[path], original, "atomic syntax validation")
failSave = true
ok = model:apply({ { path = path, content = "return {}" } })
t.expect(not ok, "write failure is surfaced")
t.assertEqual(#model.history, 0, "failed persistence does not create undo history")
failSave = false
local summary = model:apply({ { path = path, content = "return {}" } })
t.expect(summary, "valid edits save")
t.assertEqual(summary[1].path, "Model.lua", "the change summary names the file relative to the project")
t.assertEqual(summary[1].added, 1, "and counts the lines it gained")
t.assertEqual(summary[1].removed, 9, "and lost")
t.assertEqual(saved.files[path], "return {}", "changes persist")
t.assertEqual(model.files["demo/playground/init.lua"], seed["demo/playground/init.lua"], "unrelated file unchanged")
t.expect(model:undo(), "undo succeeds")
t.assertEqual(model.files[path], original, "undo restores original")
t.expect(not model:undo(), "empty undo is safe")
t.expect(not model:setAgent("", "x") and not model:setAgent("openai", "two words"), "the agent choice is validated")
t.expect(model:setAgent("openai", "gpt-5-mini"), "a provider and model are chosen")
t.assertEqual(saved.provider .. "/" .. saved.model, "openai/gpt-5-mini", "the choice persists with the project")
failSave = true
t.expect(not model:setAgent("anthropic", "x"), "a choice that cannot be saved is refused")
t.assertEqual(model.provider, "openai", "and the previous choice stays")
failSave = false
local restored = Model.new({ load = function() return saved end, save = storage.save }, seed)
t.assertEqual(restored.provider .. "/" .. restored.model, "openai/gpt-5-mini", "the choice is restored")
model:message("user", "hi"); model:message("agent", "", { { path = "a.lua", added = 1, removed = 0 } })
t.assertEqual(model.messages[2].changes[1].path, "a.lua", "a message may carry a change summary")
model:clearMessages()
t.assertEqual(#model.messages, 0, "a conversation can start over")

-- Line counts for change cards.
local added, removed = Changes.count("a\nb\nc\n", "a\nc\nd\ne\n")
t.expect(added == 2 and removed == 1, "added and removed lines are counted")
added, removed = Changes.count("a\nb\n", "b\na\n")
t.expect(added == 0 and removed == 0, "moved lines count for neither")
added, removed = Changes.count(nil, "x\n\ny\n")
t.expect(added == 2 and removed == 0, "a new file adds its non-empty lines")

-- The agent speaks to whichever provider the project chose, through a
-- transport that only sees finished requests.
local json = { encode = ns._jsonEncode, decode = ns.json_parse }
local providers = Providers.load(json)
local store = { openai = "test-key" }
local keys = Keys.new({ _keychainGet = function(_, account) return store[account] end,
	_keychainSet = function(_, account, value) store[account] = value; return true end,
	_keychainDelete = function(_, account) store[account] = nil; return true end })
local pending, request, cancelled, reloads, renders = nil, nil, 0, 0, 0
local agent = Agent.new({ model = model, providers = providers, keys = keys, json = json,
	http = function(req, callback)
		request, pending = req, callback
		return function() cancelled = cancelled + 1 end
	end,
	preview = function() reloads = reloads + 1; return true end,
	changed = function() renders = renders + 1 end })
local function respond(message)
	pending(json.encode({ choices = { { message = message } } }), nil, 200)
end
t.expect(not agent:send(""), "empty prompt rejected")
model.provider = "anthropic"
local started, why = agent:send("hello")
t.expect(not started and why:find("your Anthropic API key", 1, true), "a provider without a key says so")
model.provider = "openai"
t.expect(agent:send("Change my app"), "agent starts")
t.expect(not agent:send("again"), "concurrent sends rejected")
t.assertEqual(model.messages[1].role .. ": " .. model.messages[1].text, "user: Change my app", "the request joins the transcript")
t.assertEqual(request.url, "https://api.openai.com/v1/chat/completions", "the chosen provider's request goes out")
t.assertEqual(request.headers.Authorization, "Bearer test-key", "with the key from the keychain")
local body = json.decode(request.body)
t.assertEqual(body.model, "gpt-5-mini", "configured model used")
t.assertEqual(#body.tools, 4, "tools sent with request")
t.assertEqual(body.messages[#body.messages].content, "Change my app", "the user's words close the request")
respond({ role = "assistant", content = "Reading.", tool_calls = {
	{ id = "call-1", type = "function", ["function"] = { name = "readFile", arguments = '{"path":"demo/playground/Model.lua"}' } } } })
body = json.decode(request.body)
local last = body.messages[#body.messages]
t.assertEqual(last.role, "tool", "the tool result follows the call")
t.assertEqual(last.tool_call_id, "call-1", "tool result tied to call")
t.assertEqual(json.decode(last.content).result, original, "readFile returns actual source")
t.assertEqual(model.messages[2].text, "Reading.", "the agent's words join the transcript")
respond({ role = "assistant", content = "Done" })
t.expect(not agent.busy, "agent finishes after final answer")
t.assertEqual(#agent.conversation, 4, "user, assistant, tool, assistant")
t.expect(agent:send("Try again"), "next turn starts")
local late = pending
agent:stop()
t.assertEqual(cancelled, 1, "stop cancels HTTP request")
t.assertEqual(#agent.conversation, 4, "a stopped turn is dropped from the conversation")
local messages = #model.messages
late(json.encode({ choices = { { message = { role = "assistant", content = "late" } } } }), nil, 200)
t.assertEqual(#model.messages, messages, "late response ignored")
t.expect(agent:send("Try again"), "restart after cancellation")
pending(nil, "offline", 0)
t.expect(not agent.busy, "network errors clear busy state")
t.assertEqual(model.messages[#model.messages].role, "error", "a network error is an error line")
t.expect(model:transcript():find("offline", 1, true) ~= nil, "network error visible")
t.expect(agent:send("Once more"), "restart after a network error")
pending("<html>Bad gateway</html>", nil, 502)
t.expect(model.messages[#model.messages].text:find("HTTP 502", 1, true), "a non-JSON body reports its status")
t.expect(agent:send("Again"), "restart after a bad body")
pending(json.encode({ error = { message = "insufficient_quota" } }), nil, 429)
t.expect(model.messages[#model.messages].text:find("insufficient_quota", 1, true), "the provider's error is shown")
local result = agent:execute({ name = "applyFiles", arguments = { files = { { path = "demo/playground/Model.lua", content = "return {}" } } } })
t.expect(result.saved, "tool applies files")
t.assertEqual(reloads, 1, "tool reloads preview")
t.assertEqual(model.messages[#model.messages].changes[1].path, "Model.lua", "an edit joins the transcript as a change card")
result = agent:execute({ name = "applyFiles", arguments = { files = { { path = "demo/playground/Model.lua", content = "nope(" } } } })
t.expect(result.error, "a bad edit returns its error to the provider")
model:undo()
agent:reset()
t.expect(#agent.conversation == 0 and #model.messages == 0, "a new conversation forgets everything")
model.provider = "anthropic"; store.anthropic = "sk-ant"
t.expect(agent:send("hi"), "the project can switch providers")
t.assertEqual(request.headers["x-api-key"], "sk-ant", "and the next request speaks that provider's protocol")
agent:stop()

local previewNS = {}
for k, v in pairs(ns) do previewNS[k] = v end
previewNS.HostingController = function(view) return view end
local preview = Preview.new(previewNS, read)
local view, err = preview:render(model.files)
t.expect(view ~= nil, "starter renders in isolated preview: " .. tostring(err))
local broken = {}; for k, v in pairs(model.files) do broken[k] = v end
broken[path] = 'error("preview failure")'
view, err = preview:render(broken)
t.expect(not view and err:find("preview failure", 1, true), "runtime error captured")
t.expect(preview:render(model.files) ~= nil, "preview recovers after runtime error")
broken[path] = 'while true do end'
view, err = preview:render(broken)
t.expect(not view and err:find("execution budget", 1, true), "runaway initial render interrupted")
t.expect(preview:render(model.files) ~= nil, "hook restored after budget error")
-- Inspect the workspace template without constructing native UI.
local description = require("ui.xml").describeFile("apps/studio/views/layouts/Workspace.etlua", {
	rail = require("apps.studio.models.Rail").presentation(nil, nil, require("apps.studio.models.Projects").menu({
		{ id = "HabitPal", title = "HabitPal", icon = "checklist", selected = true, action = "openProject_HabitPal" },
	})),
	preview = require("apps.studio.models.Preview").presentation(),
	chat = require("apps.studio.models.Chat").presentation(),
})
t.expect(description.source:find("HabitPal", 1, true) ~= nil, "project navigation renders")
t.expect(description.source:find('action="openProject_HabitPal"', 1, true) ~= nil, "a project in the menu opens")
t.expect(description.source:find('title="New Project" systemImage="plus" action="newProject"', 1, true) ~= nil, "the menu makes a project")
t.expect(description.source:find("width=\"440\"", 1, true) ~= nil, "preview is sized to the device")
t.expect(description.source:find("minWidth=\"380\"", 1, true) ~= nil, "chat keeps a usable minimum width")
local Projects = require("apps.studio.models.Projects")
t.assertEqual(#Projects.iconChoices, 3, "Studio offers three project icons")
t.assertEqual(Projects.defaultProjectIcon, "rocket-sketch", "the rocket sketch is the default project artwork")
local writes = {}
local listed = Projects.list(function(path)
	if path == "projects.json" then return '["Demo"]' end
	if path == "Demo/project.lua" then return 'return { name = "Demo", bundleId = "org.example.demo" }' end
end, ns.json_parse, ns._jsonEncode, function(path, value) writes[path] = value; return true end)
t.assertEqual(listed[1].appIcon, "app.fill", "projects get a consistent default app icon")
t.assertEqual(listed[1].projectIcon, "rocket-sketch", "projects use the rocket sketch artwork by default")
t.assertEqual(listed[1].bundleId, "org.example.demo", "Lua metadata loads bundle identifier")
local ok = Projects.save(function(path, value) writes[path] = value; return true end, "Demo", {
	name = "Demo App", bundleId = "org.example.demo", appIcon = "checklist",
})
t.expect(ok and writes["Demo/project.lua"]:find('appIcon = "checklist"', 1, true), "project settings persist as readable Lua")
t.expect(writes["Demo/project.lua"]:find('projectIcon = "rocket-sketch"', 1, true),
	"project settings persist the default artwork choice")
-- Templates and folder names for new projects.
t.assertEqual(#Projects.templates, 2, "a project starts blank or as the habit tracker")
local blank = Projects.templateFiles(Projects.template("blank"), read)
t.assertEqual(blank["init.lua"], read("demo/playground/init.lua"), "the blank template is the playground")
local habits = Projects.templateFiles(Projects.template("habits"), read)
t.expect(habits["views/Today.etlua"] ~= nil, "the habit template carries its tabs")
t.expect(not Projects.templateFiles({ root = "nowhere/", files = { "x.lua" } }, function() return nil end), "a missing template file is an error")
t.assertEqual(Projects.folderName("My App 2!", {}), "MyApp2", "a folder keeps the name's letters and digits")
t.expect(not Projects.folderName("!!!", {}) and not Projects.folderName(nil, {}), "a name needs letters or digits")
t.expect(not Projects.folderName("habit tracker", { { id = "HabitTracker" } }), "folders are unique, ignoring case")
t.assertEqual(Projects.bundleId("MyApp"), "org.example.myapp", "a bundle id follows the folder")
-- The preview runs any project by its init module: demo/todo, which uses
-- retained templates, renders from its files alone.
local todoFiles = {}
for _, name in ipairs({ "init.lua", "Model.lua", "Controller.lua", "views/Window.etlua", "views/Sidebar.etlua",
	"views/Content.etlua", "views/TaskRow.etlua" }) do
	todoFiles["demo/todo/" .. name] = assert(io.open("demo/todo/" .. name)):read("a")
end
local todoPreview = Preview.new(previewNS, function(p) return assert(io.open(p)):read("a") end)
local todoView, todoErr = todoPreview:render(todoFiles, "demo.todo.init")
t.expect(todoView ~= nil, "another project renders by its entry module: " .. tostring(todoErr))

-- The chat is a transcript; an agent's change card carries the diff lines.
local Chat = require("apps.studio.models.Chat")
local chat = Chat.presentation({ messages = {
	{ role = "user", text = "Add a filter." },
	{ role = "agent", text = "Done.", conclusion = "Try it.", changes = { { path = "views/Content.etlua", added = 5, removed = 1,
		lines = { "+ <Picker id=\"filter\">", "- <Old />", "  <Same />" } } } },
}, draft = "Make it blue", listening = true })
t.assertEqual(#chat.messages, 2, "a showcase conversation replaces the starter one")
local change = chat.messages[2].changes[1]
t.assertEqual(change.lines[1].color, "systemGreen", "added lines are green")
t.assertEqual(change.lines[2].color, "systemRed", "removed lines are red")
t.assertEqual(change.lines[3].color, "secondary", "context lines are secondary")
t.assertEqual(change.delta, "+5 −1", "a change counts added and removed lines")
t.assertEqual(chat.messages[2].summary.title, "1 file changed", "the card summarises its files")
t.assertEqual(chat.draft, "Make it blue", "the composer shows the draft")
t.expect(chat.listening, "dictation can be shown listening")
t.assertEqual(chat.agent.model, "No provider", "without a provider the header says so")
local starter = Chat.presentation()
t.expect(starter.messages[1].role == "user" and #starter.messages[2].changes == 7, "the starter conversation describes the complete app")
local fresh = Chat.presentation({ messages = {}, project = "Habit Tracker", projectIcon = "checklist", busy = true,
	agent = { name = "OpenAI", model = "gpt-5-mini", icon = "brain" } })
t.expect(#fresh.messages == 0 and fresh.welcome.title == "Habit Tracker" and fresh.welcome.icon == "checklist",
	"a quiet project opens on a welcome hero in place of a transcript")
t.expect(fresh.welcome.text:find("Habit Tracker", 1, true) ~= nil, "the welcome names the project")
t.assertEqual(Chat.presentation({ messages = {} }).welcome, nil, "a showcase without a project shows no hero")
t.assertEqual(fresh.agent.name .. " " .. fresh.agent.model, "OpenAI gpt-5-mini", "the header names the provider and model")
t.expect(fresh.busy, "the composer knows the agent is working")
t.assertEqual(fresh.status.text, "Ready", "without a status the header says Ready")
local reported = Chat.presentation({ messages = {}, status = { text = "Add your OpenAI API key in Settings", tone = "problem" } })
t.expect(reported.status.tone == "problem" and reported.status.busy == false, "the header status carries its tone")
local pane = require("ui.xml").describeFile("apps/studio/views/sections/ChatPane.etlua", chat)
t.expect(pane.source:find("&lt;Old /&gt;", 1, true) ~= nil, "the chat pane renders diff lines")
t.expect(pane.source:find('text="Make it blue"', 1, true) ~= nil, "the chat pane renders the draft")
t.expect(pane.source:find('id="sendButton"', 1, true) ~= nil, "an idle composer offers Send")
local busyPane = require("ui.xml").describeFile("apps/studio/views/sections/ChatPane.etlua", fresh)
t.expect(busyPane.source:find('id="stopButton"', 1, true) ~= nil and not busyPane.source:find('id="sendButton"', 1, true),
	"a working composer offers Stop instead")
t.expect(busyPane.source:find('id="welcome"', 1, true) and busyPane.source:find('id="welcomeTitle" text="Habit Tracker"', 1, true),
	"the chat pane renders the welcome hero")
t.expect(busyPane.source:find('id="agentChooser"[^>]-action="openSettings"') ~= nil, "the header agent opens Settings")
local errorPane = require("ui.xml").describeFile("apps/studio/views/sections/ChatPane.etlua", Chat.presentation({ messages = {
	{ role = "user", text = "x" }, { role = "error", text = "HTTP 401: bad key" }, { role = "agent", text = "", changes = { { path = "a.lua", added = 1 } } } } }))
t.expect(errorPane.source:find("exclamationmark.triangle.fill", 1, true) ~= nil, "an error line shows a warning symbol")
t.expect(errorPane.source:find('text="HTTP 401: bad key"', 1, true) ~= nil, "with its message")
t.expect(not errorPane.source:find('text="" size="15"', 1, true), "an agent message that is only a change card shows no empty label")

local Code = require("apps.studio.models.Code")
local code = Code.presentation({
	["demo/playground/Controller.lua"] = "local value = 'return true' -- if false",
	["demo/playground/views/Today.etlua"] = '<Label text="Today" /><% if ready then return end %>',
}, "views/Today.etlua")
t.assertEqual(code.language, "etlua", "template files select the etlua lexer")
t.assertEqual(code.files[2].folder, "views", "project tree entries retain their folder")
t.expect(Code.rules.languages.etlua.regions[1].rules == Code.rules.languages.lua,
	"embedded etlua Lua blocks reuse the Lua token rules")
t.expect(Code.rules.languages.lua.matches[#Code.rules.languages.lua.matches].color == "comment",
	"comments take precedence over keyword matches")

local Workspace = require("apps.studio.services.Workspace")
local documents = {}
local documentNS = {
	_documentPath = function(path) return "/Documents/" .. path end,
	_documentRead = function(path) return documents[path] end,
	_documentWrite = function(path, content) documents[path] = content; return true end,
	_documentExists = function(path) return documents[path] ~= nil end,
	_documentWriteData = function(path, content) documents[path] = content; return true end,
	_readFile = function(path) return read(path) end,
	_jsonEncode = ns._jsonEncode,
	json_parse = ns.json_parse,
}
local fakeGit = { open = function() return {
	log = function() return { { id = "existing" } } end,
} end }
local workspace = Workspace.open(documentNS, read, fakeGit, "HabitTracker")
t.assertEqual(#Code.presentation(workspace.seed).files, 7, "the bundled Habit Tracker has seven source files")
t.expect(documents["HabitTracker/project.lua"] ~= nil and documents["HabitTracker/views/Today.etlua"] ~= nil,
	"the bundled app is materialized in Documents on first launch")
t.assertEqual(documents["HabitTracker/AppIcon.png"], read("apps/studio/ProjectIcons/rocket-sketch.png"),
	"first launch copies the default project icon into Documents")
for _, choice in ipairs(Projects.iconChoices) do
	t.assertEqual(documents["HabitTracker/ProjectIcons/" .. choice.file],
		read("apps/studio/ProjectIcons/" .. choice.file), "first launch installs the " .. choice.id .. " choice")
end
t.expect(workspace.selectIcon("desk"), "a project can select another bundled icon")
t.assertEqual(documents["HabitTracker/AppIcon.png"], read("apps/studio/ProjectIcons/desk.png"),
	"icon selection replaces the project's app artwork")
documents["HabitTracker/AppIcon.png"] = "custom project artwork"
local editedFiles = {}
for path, content in pairs(workspace.seed) do editedFiles[path] = content end
editedFiles["demo/playground/Model.lua"] = "return { saved = true }\n"
t.expect(workspace.storage.save({ files = editedFiles, provider = "openai", model = "gpt-5-mini" }),
	"project files and settings save to Documents")
t.assertEqual(ns.json_parse(documents["HabitTracker/settings.json"]).provider, "openai", "the agent choice is the project's setting")
local reopened = Workspace.open(documentNS, read, fakeGit, "HabitTracker")
t.assertEqual(reopened.seed["demo/playground/Model.lua"], "return { saved = true }\n",
	"saved project source is reopened from Documents")
local loaded = reopened.storage.load()
t.assertEqual(loaded.provider .. "/" .. loaded.model, "openai/gpt-5-mini", "the agent choice is reopened with the project")
t.assertEqual(documents["HabitTracker/AppIcon.png"], "custom project artwork",
	"opening a project preserves its own app icon")
t.expect(reopened.localStorage.set("test-state", "{\"saved\":true}"), "app local storage writes into its Documents folder")
t.assertEqual(reopened.localStorage.get("test-state"), "{\"saved\":true}", "app local storage reads persisted data")
-- Creating a project writes its files, metadata and catalog entry.
local created = Workspace.create(documentNS, fakeGit, "Fresh", { name = "Fresh App", bundleId = "org.example.fresh", appIcon = "app" }, blank)
t.expect(documents["Fresh/project.lua"]:find('name = "Fresh App"', 1, true), "a created project has its metadata")
t.assertEqual(documents["Fresh/init.lua"], blank["init.lua"], "and its template files")
t.expect(ns.json_parse(documents["projects.json"])[1] == "Fresh" or ns.json_parse(documents["projects.json"])[2] == "Fresh",
	"and joins the catalog")
t.assertEqual(#Code.presentation(created.seed).files, 4, "the created workspace is open")

os.exit(t.summary() and 0 or 1)
