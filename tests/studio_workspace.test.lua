_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local Template = require("ui.template")
local Root = require("apps.studio.Controller")
local Providers = require("apps.studio.services.Providers")
local Keys = require("apps.studio.services.Keys")

-- The workspace is a retained template drawn from the controller's state.
-- Each action changes the state and draws again; the panes keep their native
-- views and only their attributes change.
local root = Root.new()
root.model = { files = { ["demo/playground/Controller.lua"] = "return {}", ["demo/playground/Model.lua"] = "return 1" }, messages = {} }
root.projects = { { id = "StarterApp", title = "Starter App", icon = "app.fill", selected = true } }
root.activeProject = root.projects[1]
root.mode = "chat"
root.actions = root:workspaceActions()
root.workspace = Template.new(ns.VStack {}, "apps/studio/views/layouts/Workspace.etlua", ns)
root:render()
local codePane = root.refs.codePane
t.expect(codePane.hidden and not root.refs.welcomePane.hidden and root.refs.transcriptScroll.hidden,
	"a quiet project opens on its welcome, in place of the empty transcript")
t.assertEqual(root.refs.previewStatus, nil, "at rest the header shows no status")
t.expect(not root.refs.sendButton.enabled, "Send waits for a draft")
t.expect(root.refs["rail/chat/on"] ~= nil and root.refs["rail/code/on"] == nil, "the rail highlights the chat")
t.assertEqual(root.refs.codeProject.text, "Files", "the navigator says what it lists; the project menu names the project")

local resigned
root.ns = setmetatable({ _resignFocus = function(view) resigned = view end }, { __index = ns })
local composer = root.refs.composer
root.actions.showCode()
t.assertEqual(resigned, composer, "leaving the conversation dismisses the composer's keyboard")
t.expect(not root.refs.codePane.hidden and root.refs.transcriptScroll.hidden and root.refs.composerPane.hidden
	and root.refs.welcomePane.hidden, "code mode shows the code pane in place of the conversation")
t.assertEqual(root.refs.codePane, codePane, "the code pane keeps its view")
t.expect(root.refs["rail/code/on"] ~= nil and root.refs["rail/chat/on"] == nil, "the rail highlight follows the mode")

root.actions.toggleTree()
t.expect(root.refs.treePane.hidden and root.refs.treeDivider.hidden, "hiding the tree hides its divider too")
t.assertEqual(root.refs.treeToggle.accessibilityLabel, "Show project tree", "the toggle offers to show it again")
root.actions.toggleTree()
t.expect(not root.refs.treePane.hidden, "the tree comes back")

root.actions.selectFile(nil, nil, { id = "Model.lua" })
t.assertEqual(root.refs.codeFileTitle.text, "Model.lua", "selecting a file names it")
t.assertEqual(root.refs.sourceCode.text, "return 1", "and shows its source")

root.versions = { record = function() return "0123456789" end }
root.actions.commitProject()
t.assertEqual(root.refs.previewStatus.text, "Committed 0123456", "the status line in the card header is drawn from the state")
root.actions.showCode()
t.assertEqual(root.refs.previewStatus, nil, "a result lasts until the next action")
root.actions.showChat()
local sentWhileEmpty = false
root.agent = { send = function() sentWhileEmpty = true; return true end, stop = function() end }
root.draft = ""
root.actions.composerCommand("submit")
t.expect(not sentWhileEmpty and root.refs.previewStatus == nil, "Return on an empty field does nothing")
root.agent = nil
root.actions.commitProject()
t.expect(root.refs.projectMenu ~= nil, "the project menu heads the rail")
t.assertEqual(root.refs.projectMenu.accessibilityLabel, "Project: Starter App", "and names the open project")

-- The composer: the draft is kept as it is typed, a chip fills it, Return sends.
root.actions.showChat()
root.actions.suggest_feature()
t.assertEqual(root.refs.composer.text, "Add a feature: ", "a suggestion chip fills the composer")
t.expect(root.refs.sendButton.enabled, "and enables Send")
local sendButton = root.refs.sendButton
root.actions.editDraft("   ")
t.expect(not root.refs.sendButton.enabled, "blank text disables Send again")
t.assertEqual(root.refs.sendButton, sendButton, "in the same button")
root.actions.editDraft("Add a feature: ")
root.actions.editDraft("Add a feature: a streak counter")
t.assertEqual(root.draft, "Add a feature: a streak counter", "typing keeps the draft")
local sent
root.agent = { send = function(_, text) sent = text; return true end, stop = function() end, reset = function() end }
t.expect(root.actions.composerCommand("submit"), "Return submits the composer")
t.assertEqual(sent, "Add a feature: a streak counter", "and sends the draft")
t.assertEqual(root.refs.composer.text, "", "a sent draft clears the composer")
root.agent.send = function() return nil, "Add your OpenAI API key in Settings" end
root.draft = "x"
root.actions.send()
t.assertEqual(root.refs.previewStatus.text, "Add your OpenAI API key in Settings", "a refused send explains itself in the status line")
t.assertEqual(root.refs.activitySymbol.accessibilityLabel or "", "", "the warning symbol stays decorative; the label carries the text")

-- A working agent shows Stop and Thinking.
root.agent.busy = true
root:render()
t.expect(root.refs.stopButton ~= nil and root.refs.sendButton == nil, "a working agent's composer offers Stop")
t.assertEqual(root.refs.previewStatus.text, "Thinking…", "and the header says the agent is thinking")
t.expect(root.refs.activitySpinner ~= nil and root.refs.activitySymbol == nil, "with a spinner in place of the symbol")
root.agent.busy = false
root:render()
t.expect(root.refs.sendButton ~= nil, "an idle agent's composer offers Send")
t.expect(root.refs.activitySymbol ~= nil and root.refs.activitySpinner == nil, "and the symbol returns")

-- Sheets open one at a time through the injected presenter.
local presented, dismissed = {}, {}
local json = { encode = ns._jsonEncode, decode = ns.json_parse }
local store = { openai = "sk-saved" }
local sheeted = Root.new({
	present = function(sheet, detents) table.insert(presented, { sheet = sheet, detents = detents }); return sheet end,
	dismiss = function(sheet) table.insert(dismissed, sheet) end,
})
sheeted.providers = Providers.load(json)
sheeted.problems = { { file = "Plugins/broken.lua", message = "syntax error" } }
sheeted.keys = Keys.new({ _keychainGet = function(_, account) return store[account] end,
	_keychainSet = function(_, account, value) store[account] = value; return true end,
	_keychainDelete = function(_, account) store[account] = nil; return true end })
local savedChoice
sheeted.model = { files = root.model.files, messages = {}, provider = "openai", model = "gpt-5-mini",
	setAgent = function(self, provider, model) savedChoice = provider .. "/" .. model; self.provider, self.model = provider, model; return true end }
sheeted.projects = { { id = "StarterApp", title = "Starter App", icon = "app.fill", selected = true } }
sheeted.activeProject = sheeted.projects[1]
sheeted.actions = sheeted:workspaceActions()
sheeted.workspace = Template.new(ns.VStack {}, "apps/studio/views/layouts/Workspace.etlua", ns)
sheeted:render()
t.assertEqual(sheeted.refs.previewStatus, nil, "the header starts without a status")

sheeted.actions.openSettings()
t.assertEqual(#presented, 1, "Settings presents a sheet")
t.assertEqual(presented[1].detents[1], "large", "as a large sheet")
t.assertEqual(sheeted.sheetRefs.providerPicker.selectedIndex or sheeted.sheetRefs.providerPicker.indexOfSelectedItem, 1, "the provider picker shows the project's provider")
t.assertEqual(sheeted.sheetRefs.customModel.text, "", "a listed model needs no custom id")
t.assertEqual(sheeted.sheetRefs["keyStatus/openai"].text, "Saved in the keychain", "a saved key is reported, never shown")
t.assertEqual(sheeted.sheetRefs["keyStatus/anthropic"].text, "Not set", "a missing key is reported")
t.assertEqual(sheeted.sheetRefs["keyField/openai"].text, "", "the key field starts empty")
t.expect(sheeted.actions.openPlugins() == nil, "one sheet at a time")
sheeted.actions.chooseProvider(0)
t.assertEqual(sheeted.sheetState.provider .. "/" .. sheeted.sheetState.model, "anthropic/claude-sonnet-5-5",
	"choosing a provider selects its default model")
sheeted.actions.chooseModel(1)
t.assertEqual(sheeted.sheetState.model, "claude-opus-5-5", "the model picker chooses a listed model")
sheeted.actions.chooseModel(3)
t.assertEqual(sheeted.sheetRefs.customModel.text, "", "Other… opens the custom id")
sheeted.actions.editModel("claude-next-1")
t.assertEqual(sheeted.sheetState.model, "claude-next-1", "a typed id becomes the model")
sheeted.actions.editKey_anthropic("sk-ant-new")
sheeted.actions.editKey_openai("")
sheeted.actions.saveSettings()
t.assertEqual(store.anthropic, "sk-ant-new", "Done saves a typed key to the keychain")
t.assertEqual(store.openai, nil, "a cleared field removes its key")
t.assertEqual(savedChoice, "anthropic/claude-next-1", "and the project remembers its agent")
t.assertEqual(#dismissed, 1, "the sheet closes")
t.assertEqual(sheeted.sheet, nil, "and is forgotten")
t.expect(sheeted.refs.previewStatus.text:find("Anthropic · claude-next-1", 1, true) ~= nil, "the status line names the agent")

-- A failed save keeps the sheet open with its reason.
sheeted.actions.openSettings()
sheeted.model.setAgent = function() return nil, "disk full" end
sheeted.actions.saveSettings()
t.assertEqual(sheeted.sheetRefs.settingsError.text, "disk full", "the sheet explains why Done failed")
t.assertEqual(#dismissed, 1, "and stays open")
sheeted.actions.closeSheet()
t.assertEqual(#dismissed, 2, "Cancel closes it")

-- The Plugins sheet lists what loaded and what did not.
sheeted.actions.openPlugins()
t.expect(sheeted.sheetRefs["plugin/openai"] ~= nil and sheeted.sheetRefs["plugin/gemini"] ~= nil, "bundled providers are listed")
local pluginsPage = require("ui.xml").describeFile("apps/studio/views/sheets/Plugins.etlua", sheeted:sheetData()).source
t.expect(pluginsPage:find("Plugins/broken.lua", 1, true) and pluginsPage:find("syntax error", 1, true), "a broken plugin file is named with its error")
t.expect(pluginsPage:find("Key saved", 1, true) and pluginsPage:find("No key", 1, true), "each provider says whether it has a key")
sheeted.actions.closeSheet()

-- New Project: a name and a template make a project, which opens.
local createdWith
sheeted.createProject = function(self, name, template) createdWith = name .. "/" .. template; return "Streaks" end
sheeted.actions.newProject()
t.expect(not sheeted.sheetRefs.create.enabled, "Create waits for a name")
sheeted.actions.editProjectName("Streaks!")
t.assertEqual(sheeted.sheetRefs.projectFolder.text, "Documents/Streaks", "the folder follows the name")
t.expect(sheeted.sheetRefs.create.enabled, "a name enables Create")
sheeted.actions.chooseTemplate_habits()
t.expect(sheeted.sheetRefs["template/habits"] ~= nil, "templates are offered")
t.assertEqual(sheeted.sheetState.template, "habits", "a template can be chosen")
sheeted.actions.projectNameCommand("submit")
t.assertEqual(createdWith, "Streaks!/habits", "Return creates the project from the chosen template")
t.assertEqual(sheeted.sheet, nil, "and the sheet closes")
sheeted.createProject = function() return nil, "A project called Streaks already exists" end
sheeted.actions.newProject()
sheeted.actions.editProjectName("Streaks")
sheeted.actions.createProject()
t.assertEqual(sheeted.sheetRefs.projectError.text, "A project called Streaks already exists", "a refused project says why")
sheeted.actions.closeSheet()

os.exit(t.summary() and 0 or 1)
