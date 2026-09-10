_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Model = require("examples.adventure-arena.Model")
local catalog = Model.new()
local Controller = require("examples.adventure-arena.Controller")
local renderFile, button = xml.renderFile, ns.Button
local rendered, callbacks = {}, {}

-- Capture the callbacks actually supplied by the XML renderer to native buttons.
ns.Button = function(props)
	local view = button(props)
	callbacks[view] = props.action
	return view
end
xml.renderFile = function(...)
	local view, refs = renderFile(...)
	rendered = { view = view, refs = refs }
	return view, refs
end
local function click(ref)
	local callback = callbacks[rendered.refs[ref]]
	t.expect(type(callback) == "function", ref .. " has a bound action")
	if callback then callback() end
end

local model = Model.new({ engineFactory = function()
	return { start = function()
		return { resume = function(_, command) return 'Response <&> "' .. command .. '"' end }, "Opening <&>"
	end }
end })
local controller = Controller.new { model = model, ns = ns }
local config, refs = xml.renderFile("examples/adventure-arena/views/Window.etlua", controller:homeData(), ns)
controller.navigation = refs.navigation
local tabs = refs.tabs
for _, size in ipairs({ { 640, 720 }, { 420, 360 }, { 1000, 900 } }) do
	tabs.frameSize = ns.Size(size[1], size[2])
	tabs:layout(size[1])
	t.assertSize(tabs, size[1], size[2], "template tabs consume available space")
end
for index, title in ipairs({ "Adventures", "Ongoing", "Create Game", "Settings" }) do
	tabs:selectTab(index - 1)
	t.assertEqual(tabs.selectedTabViewItem.label, title, "template preserves tab title and order")
end
tabs:selectTab(0)
click("featuredCoverButton")
t.assertEqual(controller.navigation.depth, 2, "featured cover opens detail")
t.assertEqual(rendered.refs.title.text, catalog:listGames()[1].title, "detail renders selected game")
t.assertEqual(rendered.refs.description.text, catalog:listGames()[1].description, "detail preserves full description")
click("play")
t.assertEqual(controller.navigation.depth, 3, "detail play opens session")
t.assertEqual(rendered.refs.output.text, "Opening <&>", "transcript escapes XML characters")
t.assertEqual(rendered.refs.input.accessibilityLabel, "Command", "composer retains accessibility label")
ns._textFieldTestInput(rendered.refs.input, "inventory")
click("send")
t.expect(rendered.refs.output.text:find('Response <&> "inventory"', 1, true), "send updates transcript")
t.assertEqual(rendered.refs.input.text, "", "send clears input")
click("look")
t.expect(rendered.refs.output.text:find('Response <&> "look"', 1, true), "quick command reaches session")
local transcript = rendered.refs.output.text
click("send")
t.assertEqual(rendered.refs.output.text, transcript, "empty submission leaves transcript unchanged")
t.expect(not ns._textFieldTestCommand(rendered.refs.input, "cancel"), "unhandled keys retain native behavior")
click("close")
t.assertEqual(controller.navigation.depth, 2, "close returns to detail")
t.assertEqual(controller.model:transcript(), transcript, "navigation preserves session state")
controller.navigation:pop()
controller.model = Model.new({ engineFactory = function() error('Missing <story> & "engine"', 0) end })
controller:showSession(catalog:listGames()[1].id)
t.assertEqual(controller.navigation.depth, 2, "failed start opens template error state")
click("back")
t.assertEqual(controller.navigation.depth, 1, "error back restores catalog")
t.assertEqual(controller.window, nil, "template components never create windows")

local game = {}
for key, value in pairs(catalog:listGames()[1]) do game[key] = value end
game.title = 'An <Adventure> & "Quotes"'
game.description = string.rep("A long description & more. ", 40)
controller.model = Model.new { games = { game } }
controller:showGame(game.id)
t.assertEqual(rendered.refs.title.text, game.title, "detail round-trips special characters")
t.assertEqual(rendered.refs.description.text, game.description, "detail preserves long text")
click("back")
t.assertEqual(controller.navigation.depth, 1, "detail back restores catalog")
t.expect(not controller:showGame("missing"), "missing detail record is rejected")
t.expect(not controller:showSession("missing"), "missing session record is rejected")
t.assertEqual(controller.navigation.depth, 1, "missing records do not disturb navigation")
local data = controller:homeData()
t.assertEqual(#data.games, 1, "controller queries its injected model catalog")
t.assertEqual(data.featured.id, game.id, "controller uses the injected featured query")
t.assertEqual(game.stars, nil, "presentation does not decorate domain records with symbols")
t.assertEqual(game.ratingLabel, nil, "presentation does not decorate domain records with formatting")
controller:home()
click("coverButton_1")
t.assertEqual(rendered.refs.title.text, game.title, "catalog actions resolve stable game ids")

local empty = Controller.new { model = Model.new { games = {} }, ns = ns }
empty:home()
t.expect(rendered.refs.emptyCatalog ~= nil, "empty model renders the etlua empty state")
t.assertEqual(empty.navigation.depth, 1, "empty catalog retains navigation root")
ns.Button, xml.renderFile = button, renderFile

os.exit(t.summary() and 0 or 1)
