_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local Adventures = require("apps.adventure-arena.models.Adventures")
local Session = require("apps.adventure-arena.models.Session")
local catalog = Adventures.new()
local sessionModel = Session.new({ engineFactory = function()
	return { start = function() return { resume = function(_, command) return "Response to " .. command end }, "Opening" end }
end })
local controller = require("apps.adventure-arena.Controller").new {
	adventures = catalog, sessionModel = sessionModel, ns = ns,
}
t.assertEqual(controller.sessionModel, sessionModel, "controller uses injected session model")
local home = controller:home()
home.frameSize = ns.Size(640, 720)
home:layout(640)
t.assertEqual(home.depth, 1, "adventure home starts in one native navigation root")
controller.library:showGame(catalog:list()[1].id)
t.assertEqual(home.depth, 2, "detail stays in original navigation root")
controller.sessionController:show(catalog:list()[1].id)
t.assertEqual(home.depth, 3, "session stays above detail in original navigation root")
t.assertEqual(controller.window, nil, "component navigation never creates a window")
ns._textFieldTestInput(controller.sessionController.refs.input, "look")
t.expect(ns._textFieldTestCommand(controller.sessionController.refs.input, "submit"), "return submits typed command")
t.assertEqual(controller.sessionController.refs.input.text, "", "successful submission clears composer")
local transcript = controller.sessionController.transcript.refs
t.assertEqual(transcript.command_2.text, "look", "the command appears in the native transcript")
t.assertEqual(transcript.paragraph_3_1.text, "Response to look", "native transcript receives model output")
home:pop()
t.assertEqual(home.depth, 2, "ending session returns to detail")
home:pop()
t.assertEqual(home.depth, 1, "back returns to original catalog")
os.exit(t.summary() and 0 or 1)
