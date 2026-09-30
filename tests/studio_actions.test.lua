_G.__headless = true

local t = require("TestKit")
local Preview = require("apps.studio.controllers.PreviewController")
local Chat = require("apps.studio.models.Chat")

local presentation = Preview.new():presentation({
	{ title = "Starter App", icon = "rocket.fill" },
	{ title = "Habit Tracker", icon = "checklist", selected = true },
})
t.assertEqual(presentation.project.title, "Habit Tracker", "the selected project heads the stage")
t.assertEqual(#presentation.projects, 2, "every project is offered")
t.assertEqual(Preview.new():presentation({ { title = "Only", icon = "app" } }).project.title, "Only",
	"the first project is current when none is selected")
t.assertEqual(Preview.new():presentation().project.title, "No Project", "missing projects are safe")

local changes, summary = Chat.changes({
	{ path = "init.lua", added = 2 },
	{ path = "views/deep/Row.etlua", added = 5 },
	{ path = "assets/notes.txt", added = 1 },
})
t.assertEqual(summary.title, "3 files changed", "summary counts files")
t.assertEqual(summary.delta, "+8", "summary totals added lines")
t.assertEqual(changes[1].folder, "", "root files have no folder")
t.assertEqual(changes[1].icon, "doc.text", "Lua modules use a document symbol")
t.assertEqual(changes[2].name, "Row.etlua", "nested files show their name")
t.assertEqual(changes[2].folder, "views/deep", "nested files keep their whole folder")
t.assertEqual(changes[2].icon, "chevron.left.forwardslash.chevron.right", "templates use a code symbol")
t.assertEqual(changes[3].icon, "doc", "other files fall back to a plain document")
local _, single = Chat.changes({ { path = "Model.lua", added = 1 } })
t.assertEqual(single.title, "1 file changed", "a single change is singular")
local none, emptySummary = Chat.changes({})
t.assertEqual(#none, 0, "no changes")
t.assertEqual(emptySummary.delta, "+0", "no changes add no lines")

local Root = require("apps.studio.Controller")
local child = {}
local root = setmetatable({
	model = { files = {} },
	preview = { render = function() return child end },
	refs = { preview = {}, previewStatus = {} },
}, Root)
t.expect(root:reloadPreview(), "Run reloads the embedded controller")
t.assertEqual(root.refs.preview.content, child, "successful reload replaces preview content")
t.assertEqual(root.refs.previewStatus.text, "Ready", "successful reload clears the prior status")
root.preview.render = function() return nil, "bad project" end
t.expect(not root:reloadPreview(), "failed reload is reported")
t.assertEqual(root.refs.preview.content, child, "failed reload preserves the prior preview")
t.expect(root.refs.previewStatus.text:find("bad project", 1, true) ~= nil,
	"failed reload displays its error")
local anchored
root.refs.transcriptScroll = { scrollTo = function(_, target, animated) anchored = { target, animated } end }
root:showLatestTurn()
t.assertEqual(anchored[1], "bottom", "the conversation opens at its latest turn")
t.assertEqual(anchored[2], false, "without animating")
os.exit(t.summary() and 0 or 1)
