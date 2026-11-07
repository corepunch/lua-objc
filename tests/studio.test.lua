_G.__headless = true
local t = require("TestKit")
local Model = require("apps.studio.Model")
local Agent = require("apps.studio.services.Agent")
local Preview = require("apps.studio.services.Preview")
local ns = require("AppKit")
local function read(path)
	local file = assert(io.open(path)); local value = file:read("*a"); file:close(); return value
end
local seed = {}
for _, name in ipairs({ "init.lua", "Model.lua", "Controller.lua", "views/Window.etlua" }) do
	seed["demo/playground/" .. name] = read("demo/playground/" .. name)
end
local DataModel = require("data.model")
DataModel.bind(require("apps.studio.Store")())
local session = require("apps.studio.services.Session").open({ load = function() end, save = function() return true end }, seed, "Native")
local model = session.workspace
local path = "demo/playground/Model.lua"
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
-- Inspect the two-pane workspace template without constructing native UI.
local description = require("ui.xml").describeFile("apps/studio/views/sections/Workspace.etlua", {
	rail = require("apps.studio.helpers.Rail").presentation(),
	preview = require("apps.studio.helpers.Preview").presentation({
		{ title = "HabitPal", icon = "checklist", selected = true },
	}),
	chat = require("apps.studio.helpers.Chat").presentation(),
})
t.expect(description.source:find("HabitPal", 1, true) ~= nil, "project navigation renders")
t.expect(description.source:find("maxWidth=\"440\"", 1, true) ~= nil, "preview is sized to the device")
t.expect(description.source:find("minWidth=\"280\"", 1, true) ~= nil, "chat keeps a usable minimum width")
t.expect(description.source:find("toggleChat", 1, true) ~= nil, "chat visibility customization remains available")
local Projects = require("apps.studio.services.Projects")
t.assertEqual(#Projects.iconChoices, 3, "Studio offers three project icons")
t.assertEqual(Projects.defaultProjectIcon, "rocket-sketch", "the rocket sketch is the default project artwork")
local writes = {}
local listed = Projects.list(function(path)
	if path == "projects.json" then return '["Demo"]' end
	if path == "Demo/project.lua" then return 'return { name = "Demo", bundleId = "org.example.demo" }' end
end, ns.json_parse, ns._jsonEncode, function(path, value) writes[path] = value; return true end)
t.assertEqual(listed[1].appIcon, "rocket.fill", "projects get a consistent default app icon")
t.assertEqual(listed[1].projectIcon, "rocket-sketch", "projects use the rocket sketch artwork by default")
t.assertEqual(listed[1].bundleId, "org.example.demo", "Lua metadata loads bundle identifier")
local ok = Projects.save(function(path, value) writes[path] = value; return true end, "Demo", {
	name = "Demo App", bundleId = "org.example.demo", appIcon = "checklist",
})
t.expect(ok and writes["Demo/project.lua"]:find('appIcon = "checklist"', 1, true), "project settings persist as readable Lua")
t.expect(writes["Demo/project.lua"]:find('projectIcon = "rocket-sketch"', 1, true),
	"project settings persist the default artwork choice")
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
local Chat = require("apps.studio.helpers.Chat")
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
local starter = Chat.presentation()
t.assertEqual(#starter.messages, 0, "new projects have no fabricated conversation")
local pane = require("ui.xml").describeFile("apps/studio/views/sections/ChatPane.etlua", chat)
t.expect(pane.source:find("&lt;Old /&gt;", 1, true) ~= nil, "the chat pane renders diff lines")
t.expect(pane.source:find('text="Make it blue"', 1, true) ~= nil, "the chat pane renders the draft")

local Code = require("apps.studio.helpers.Code")
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
	_documentRemove = function(path) documents[path] = nil; return true end,
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
t.expect(workspace.storage.save({ files = editedFiles, modelId = "provider/test" }),
	"project files and settings save to Documents")
local reopened = Workspace.open(documentNS, read, fakeGit, "HabitTracker")
t.assertEqual(reopened.seed["demo/playground/Model.lua"], "return { saved = true }\n",
	"saved project source is reopened from Documents")
t.assertEqual(documents["HabitTracker/AppIcon.png"], "custom project artwork",
	"opening a project preserves its own app icon")
t.expect(reopened.localStorage.set("test-state", "{\"saved\":true}"), "app local storage writes into its Documents folder")
t.assertEqual(reopened.localStorage.get("test-state"), "{\"saved\":true}", "app local storage reads persisted data")

os.exit(t.summary() and 0 or 1)
