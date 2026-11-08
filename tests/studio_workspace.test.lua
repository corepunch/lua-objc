_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local Template = require("ui.template")
local Root = require("apps.studio.Controller")

-- The workspace is a retained template drawn from the controller's state.
-- Each action changes the state and draws again; the panes keep their native
-- views and only their attributes change.
local root = Root.new({ns = ns})
require("data.model").bind(root.store)
root.session = require("apps.studio.services.Session").open({load = function() end, save = function() return true end}, {
	["demo/playground/Controller.lua"] = "return {}", ["demo/playground/Model.lua"] = "return 1",
	["demo/playground/init.lua"] = "return {}", ["demo/playground/views/pages/Main.etlua"] = '<Label text="Hello" />',
}, "Test")
root.model = root.session.workspace
root.projects = { { id = "StarterApp", title = "Starter App", action = "openProject_StarterApp", icon = "paperplane.fill", selected = true } }
root.mode = "chat"
root.chat.agent = {busy = false}
root.actions = root:workspaceActions()
root.workspace = Template.new(ns.VStack {}, "apps/studio/views/sections/Workspace.etlua", ns)
root:render()
local codePane, chatPane = root.refs.codePane, root.refs.chatPane
t.expect(codePane.hidden and not root.refs.transcriptScroll.hidden, "the workspace opens on the conversation")
t.expect(root.refs["rail/preview/on"] ~= nil and root.refs.preview ~= nil, "beside the preview")
t.assertEqual(root.refs.sidePane.maxWidth, 440, "in a side column sized to the device")

root.actions.showPanel_files()
t.expect(root.refs["rail/files/on"] ~= nil and root.refs["rail/preview/on"] == nil, "the rail highlight follows the view")
t.expect(root.refs.preview == nil and root.refs.codeFiles ~= nil, "Files replaces the preview in the column")
t.assertEqual(root.refs.chatPane, chatPane, "the agent card keeps its view")
t.expect(codePane.hidden, "showing Files alone opens no file")

root.actions.selectFile(nil, nil, { id = "Model.lua" })
t.expect(not root.refs.codePane.hidden and root.refs.transcriptScroll.hidden and root.refs.composerPane.hidden,
	"choosing a file opens it in place of the conversation")
t.assertEqual(root.refs.codePane, codePane, "the code pane keeps its view")
t.assertEqual(root.refs.codeFileTitle.text, "Model.lua", "selecting a file names it")
t.assertEqual(root.refs.sourceCode.text, "return 1", "and shows its source")
root.actions.showChat()
t.expect(root.refs.codePane.hidden and not root.refs.transcriptScroll.hidden, "closing the file returns to the conversation")
t.assertEqual(root.actions.showCode, nil, "the iPad opens code through Files only")
t.assertEqual(root.actions.toggleTree, nil, "the editor has no tree to toggle")

local recorded = {}
root.versions = {
	record = function(_, message) table.insert(recorded, message); return "0123456789" end,
	log = function() return { { id = "0123456789", shortId = "0123456", summary = "Update project", time = os.time() } } end,
}
root.actions.showPanel_git()
t.expect(root.refs.history ~= nil and root.refs.commitButton ~= nil, "Source Control shows the history and commits")
root.actions.editCommitMessage("Add a tab")
root.actions.commitProject()
t.assertEqual(recorded[1], "Add a tab", "the typed message is committed")
t.assertEqual(root.refs.gitStatus.text, "Committed 0123456", "the status line reports the commit")
t.assertEqual(root.refs.commitMessage.text, "", "a commit clears the message")
root.actions.commitProject()
t.assertEqual(recorded[2], "Update project", "an empty field commits with the default message")

root.actions.showPanel_projects()
t.expect(root.refs.projectList ~= nil and root.refs.newProjectButton ~= nil, "Projects lists the projects")
t.expect(root.actions["selectProjectIcon_rocket-sketch"] ~= nil, "project icons are offered again")

root.actions.showPanel_preview()
t.expect(root.refs.preview ~= nil and root.refs.history == nil, "the preview comes back to the column")

os.exit(t.summary() and 0 or 1)
