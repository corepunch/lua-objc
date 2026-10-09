_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local Template = require("ui.template")
local Root = require("apps.studio.Controller")

-- The workspace is a retained template drawn from the controller's state.
-- Each action changes the state and draws again; the panes keep their native
-- views and only their attributes change.
local root = Root.new()
root.model = { files = { ["demo/playground/Controller.lua"] = "return {}", ["demo/playground/Model.lua"] = "return 1" } }
root.projects = { { id = "StarterApp", title = "Starter App", icon = "rocket.fill", selected = true } }
root.mode = "chat"
root.actions = root:workspaceActions()
root.workspace = Template.new(ns.VStack {}, "apps/studio/views/Workspace.etlua", ns)
root:render()
local codePane, chatPane, previewPane = root.refs.codePane, root.refs.chatPane, root.refs.previewPane
t.expect(codePane.hidden and not root.refs.transcriptScroll.hidden, "the workspace opens on the conversation")
t.expect(root.refs["rail/chat/on"] ~= nil and root.refs["rail/code/on"] == nil, "the rail highlights the chat")

root.actions.showCode()
t.expect(not root.refs.codePane.hidden and root.refs.transcriptScroll.hidden and root.refs.composerPane.hidden,
	"code mode shows the code pane in place of the conversation")
t.assertEqual(root.refs.codePane, codePane, "the code pane keeps its view")
t.expect(root.refs["rail/code/on"] ~= nil and root.refs["rail/chat/on"] == nil, "the rail highlight follows the mode")

root.actions.toggleTree()
t.expect(root.refs.treePane.hidden and root.refs.treeDivider.hidden, "hiding the tree hides its divider too")
t.assertEqual(root.refs.treeToggle.accessibilityLabel, "Show project tree", "the toggle offers to show it again")
root.actions.toggleTree()
t.expect(not root.refs.treePane.hidden, "the tree comes back")

root.actions.toggleChat()
t.expect(root.refs.chatPane.hidden, "focusing the preview hides the chat")
t.assertEqual(root.refs.chatPane, chatPane, "the chat keeps its view")
t.assertEqual(root.refs.previewPane.fixedWidth, nil, "and the stage drops its fixed width")
t.assertEqual(root.refs.chatVisibility.accessibilityLabel, "Show Chat", "the toggle offers the chat back")
root.actions.toggleChat()
t.expect(not root.refs.chatPane.hidden, "the chat comes back")
t.assertEqual(root.refs.previewPane.fixedWidth, 440, "beside a stage sized to the device")
t.assertEqual(root.refs.previewPane, previewPane, "the stage keeps its view")

root.actions.selectFile(nil, nil, { id = "Model.lua" })
t.assertEqual(root.refs.codeFileTitle.text, "Model.lua", "selecting a file names it")
t.assertEqual(root.refs.sourceCode.text, "return 1", "and shows its source")

root.versions = { record = function() return "0123456789" end }
root.actions.commitProject()
t.assertEqual(root.refs.previewStatus.text, "Committed 0123456", "the status line is drawn from the state")

os.exit(t.summary() and 0 or 1)
