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
local phone = setmetatable({ idiom = "phone", platform = "UIKit" }, { __index = ns })
local resolvedColors = {}
function phone.Color(name)
	local color = ns.Color(name)
	resolvedColors[color] = name
	return color
end
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
		local _, refs = xml.renderFile("apps/adventure-arena/views/pages/Session.etlua", data, phone)
		return { view = {} }, refs
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
t.expect(not controller.completions.host.hidden, "an empty command keeps its completion bar")
t.assertEqual(nativeButton(controller.completions.refs.completion1).title, "Look around", "the first default action is Look around")
t.assertEqual(nativeButton(controller.completions.refs.completion2).title, "Inventory", "the second default action is Inventory")
t.assertEqual(controller.actions.look, nil, "the removed menu has no Look handler")
t.assertEqual(controller.actions.inventory, nil, "the removed menu has no Inventory handler")
local function layoutBar()
	controller.completions.host.size = ns.Size(390, 44)
	controller.completions.host:layout(390)
	t.assertSize(controller.completions.refs.completionRow, 390, 44, "the row keeps its width and height in every state")
end
layoutBar()
local defaults = controller.completions.refs
t.expect(math.abs(defaults.completion1.size.width - defaults.completion2.size.width) < 1,
	"the default actions share the row equally")
t.expect(nativeButton(defaults.completion1).bordered == false, "completion buttons have no glass or bezel")

controller.actions.inputChanged("ta")
local refs = controller.completions.refs
t.expect(not controller.completions.host.hidden, "typing shows the completion bar")
t.assertEqual(nativeButton(refs.completion1).title, "take", "the first step offers the verb alone")
t.assertEqual(refs.completion1.accessibilityLabel, "Complete take", "the verb button is accessible")
t.expect(refs.completion2 == nil, "unmatched verbs are excluded")
click(refs.completion1)
layoutBar()
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
t.expect(not controller.completions.host.hidden, "a complete command keeps the empty row in place")
layoutBar()
t.assertEqual(#commands, 0, "accepting an object still waits for Send")

click(controller.refs.send)
t.assertEqual(#commands, 1, "Send plays exactly one turn")
t.assertEqual(commands[1], "take broom", "Send submits the assembled command")
t.assertEqual(controller.refs.input.text, "", "Send clears the composer")
t.expect(not controller.completions.host.hidden, "Send preserves the bar")
t.assertEqual(nativeButton(controller.completions.refs.completion1).title, "Look around", "Send restores the default actions")
layoutBar()

controller.actions.inputChanged("take ")
refs = controller.completions.refs
t.assertEqual(nativeButton(refs.completion1).title, "key", "suggestions reflect the changed room inventory")
t.expect(refs.completion2 == nil, "the taken object is no longer offered")
controller.actions.inputChanged("take b")
t.assertEqual(nativeButton(controller.completions.refs.completion1).title, "brass key", "typing an adjective completes the matching noun phrase")
controller.actions.inputChanged("xyz")
t.expect(not controller.completions.host.hidden, "unmatched input preserves the row")
t.expect(controller.completions.refs.completion1 == nil, "unmatched input has no invented completion")
layoutBar()
controller.actions.inputChanged("")
t.assertEqual(controller.refs.input.text, "", "deleting the draft clears the input")
t.expect(not controller.completions.host.hidden, "deleting the draft preserves the bar")
layoutBar()
click(controller.completions.refs.completion1)
t.assertEqual(commands[2], "look", "the default Look around button plays look")
t.assertEqual(controller.refs.input.text, "", "Look around leaves the composer empty")
click(controller.completions.refs.completion2)
t.assertEqual(commands[3], "inventory", "the default Inventory button plays inventory")
t.assertEqual(controller.refs.input.text, "", "Inventory leaves the composer empty")
t.assertEqual(#commands, 3, "each default command plays exactly one turn")
layoutBar()

local settings = require("apps.adventure-arena.models.ReadingSettings"):current()
for _, theme in ipairs({ { 0, "paper" }, { 3, "night" } }) do
	settings:setThemeIndex(theme[1])
	controller:applyReadingSettings()
	local row = controller.completions.refs.completionRow
	t.assertEqual(resolvedColors[controller.page.view.backgroundColor], settings:presentation().pageColor,
		theme[2] .. " canvas extends beyond the keyboard guide")
	t.expect(row.backgroundColor == nil or row.backgroundColor.alphaComponent == 0,
		theme[2] .. " suggestions let the page and composer shadow show through")
	t.assertEqual(row.colorScheme, theme[2] == "night" and "dark" or "system",
		theme[2] .. " suggestions follow the page appearance")
end
settings:setThemeIndex(0)
controller:applyReadingSettings()

controller.actions.inputChanged("ta")
local lateButton = nativeButton(controller.completions.refs.completion1)
controller:onDisappear()
t.assertEqual(controller.completions, nil, "closing the reader releases its completion template")
bridge._invokeAction(lateButton)
t.assertEqual(#commands, 3, "a disposed completion button cannot play another turn")

os.exit(t.summary() and 0 or 1)
