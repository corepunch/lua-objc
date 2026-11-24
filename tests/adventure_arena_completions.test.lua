_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local xml = require("ui.xml")
local Template = require("ui.template")
local Store = require("apps.adventure-arena.Store")
local Session = require("apps.adventure-arena.zilscript.zilscript.reader.Session")
local Controller = require("apps.adventure-arena.controllers.SessionController")

-- Render the phone's templates with native headless controls, and invoke the
-- callbacks bound to their buttons. This covers accepting successive words,
-- rather than only querying the suggestion model.
local commands = {}
local phone = setmetatable({ idiom = "phone" }, { __index = ns })
local items = { { "old broom", { "TAKE" }, {}, nil, "old broom" }, { "brass key", { "TAKE" }, {}, nil, "brass key" } }
Store.new { games = { { id = "story", title = "Story", description = "A workshop." } } }
local model = Session.new { engineFactory = function()
	return { start = function()
		return {
			resume = function(_, command)
				table.insert(commands, command)
				if command == "take broom" then items = { items[2] } end
				return "Done."
			end,
			items = function() return items end,
		}, "Workshop\nAn old broom and a brass key lie here."
	end }
end }
local controller = Controller.new {
	model = model, ns = phone,
	push = function(_, data)
		return xml.renderFile("apps/adventure-arena/views/pages/Session.etlua", data, phone)
	end,
	back = function() end, renderTemplate = function() end,
	presentSheet = function() end, dismissSheet = function() end,
	reduceMotion = function() return true end,
	mountTemplate = function(host, name)
		return Template.new(host, "apps/adventure-arena/views/" .. name .. ".etlua", phone)
	end,
}
local function nativeButton(view)
	if view.className:find("Button", 1, true) then return view end
	for _, child in ipairs(view.subviews) do
		local button = nativeButton(child)
		if button then return button end
	end
end
local function click(view)
	local button = nativeButton(view)
	t.expect(button ~= nil, "the completion uses a native button")
	if button then bridge._invokeAction(button) end
end

t.expect(controller:show("story", true), "the phone reader opens")
local input = controller.refs.input
t.expect(controller:readerData().composer.verbatim, "the command field uses the app's vocabulary")
t.expect(controller.completions.host.hidden, "an empty command has no completion bar")

controller.actions.inputChanged("ta")
local refs = controller.completions.refs
t.expect(not controller.completions.host.hidden, "typing shows the completion bar")
t.assertEqual(nativeButton(refs.completion1).title, "take", "the first step offers the verb alone")
t.assertEqual(refs.completion1.accessibilityLabel, "Complete take", "the verb button is accessible")
t.expect(refs.completion2 == nil, "unmatched verbs are excluded")
click(refs.completion1)
t.assertEqual(controller.draft, "take ", "the verb button leaves a space for the object")
t.assertEqual(controller.refs.input.text, "take ", "the chosen verb reaches the input")
t.expect(controller.refs.input == input, "accepting the verb retains the input control")
t.assertEqual(#commands, 0, "accepting a verb does not play a turn")

refs = controller.completions.refs
t.assertEqual(nativeButton(refs.completion1).title, "broom", "the next step offers the object alone")
t.assertEqual(nativeButton(refs.completion2).title, "key", "other eligible objects are separate choices")
t.assertEqual(refs.completion1.accessibilityLabel, "Complete broom", "the reused button has the object's label")
click(refs.completion1)
t.assertEqual(controller.draft, "take broom ", "the object button preserves the chosen verb")
t.assertEqual(controller.refs.input.text, "take broom ", "the complete command reaches the input")
t.expect(controller.refs.input == input, "accepting the object retains the input control")
t.expect(controller.completions.host.hidden, "a complete command hides the completion bar")
t.assertEqual(#commands, 0, "accepting an object still waits for Send")

click(controller.refs.send)
t.assertEqual(#commands, 1, "Send plays exactly one turn")
t.assertEqual(commands[1], "take broom", "Send submits the assembled command")
t.assertEqual(controller.refs.input.text, "", "Send clears the composer")
t.expect(controller.completions.host.hidden, "Send leaves no stale suggestions")

controller.actions.inputChanged("take ")
refs = controller.completions.refs
t.assertEqual(nativeButton(refs.completion1).title, "key", "suggestions reflect the changed room inventory")
t.expect(refs.completion2 == nil, "the taken object is no longer offered")
controller.actions.inputChanged("take b")
t.assertEqual(nativeButton(controller.completions.refs.completion1).title, "brass key", "typing an adjective completes the matching noun phrase")
controller.actions.inputChanged("xyz")
t.expect(controller.completions.host.hidden, "unmatched input hides the bar")
controller.actions.inputChanged("")
t.assertEqual(controller.refs.input.text, "", "deleting the draft clears the input")
t.expect(controller.completions.host.hidden, "deleting the draft collapses the bar")

controller.actions.inputChanged("ta")
local lateButton = nativeButton(controller.completions.refs.completion1)
controller:onDisappear()
t.assertEqual(controller.completions, nil, "closing the reader releases its completion template")
bridge._invokeAction(lateButton)
t.assertEqual(#commands, 1, "a disposed completion button cannot play another turn")

os.exit(t.summary() and 0 or 1)
