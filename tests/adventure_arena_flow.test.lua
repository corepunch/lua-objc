_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Adventures = require("apps.adventure-arena.models.Adventures")
local Session = require("apps.adventure-arena.models.Session")
local catalog = Adventures.new()
local Controller = require("apps.adventure-arena.Controller")
local renderFile, button, menu = xml.renderFile, ns.Button, ns.Menu
local addDrag = ns._addDrag
local rendered, callbacks, menus, drags = {}, {}, {}, {}

-- Capture the callbacks actually supplied by the XML renderer to native buttons.
ns.Button = function(props)
	local view = button(props)
	callbacks[view] = props.action
	return view
end
ns.Menu = function(props)
	local view = menu(props)
	menus[view] = props.items
	return view
end
ns._addDrag = function(view, callback) drags[view] = callback end
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
local function chooseMenu(title)
	local items = menus[rendered.refs.quickActions] or {}
	for _, item in ipairs(items) do
		if item.title == title then
			t.expect(type(item.action) == "function", title .. " has a bound menu action")
			if item.action then item.action() end
			return
		end
	end
	t.expect(false, title .. " appears in the quick actions menu")
end

local sessionModel = Session.new({ engineFactory = function()
	return { start = function()
		return {
			resume = function(_, command) return 'Response <&> "' .. command .. '"' end,
			exits = function() return { "north" } end,
		}, "Opening <&>"
	end }
end })
local controller = Controller.new { adventures = catalog, sessionModel = sessionModel, ns = ns }
local config, refs = xml.renderFile("apps/adventure-arena/views/Window.etlua", controller.library:presentation(), ns)
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
t.assertEqual(rendered.refs.title.text, catalog:list()[1].title, "detail renders selected game")
t.assertEqual(rendered.refs.description.text, catalog:list()[1].description, "detail preserves full description")
click("play")
t.assertEqual(controller.navigation.depth, 3, "detail play opens session")
t.assertEqual(rendered.refs.sessionTitle.text, catalog:list()[1].title, "session header retains the game title")
t.assertEqual(rendered.refs.output.text, "Opening <&>", "transcript escapes XML characters")
t.assertEqual(rendered.refs.input.accessibilityLabel, "Command", "composer retains accessibility label")
t.assertEqual(rendered.refs.input.bezeled, false, "glass composer owns the visible border")
t.assertEqual(rendered.refs.input.bordered, false, "plain input has no inner border")
t.assertEqual(rendered.refs.send.enabled, false, "empty composer disables sending")
ns._textFieldTestInput(rendered.refs.input, "inventory")
t.assertEqual(rendered.refs.send.enabled, true, "typing enables sending")
click("send")
t.expect(rendered.refs.output.text:find('Response <&> "inventory"', 1, true), "send updates transcript")
t.assertEqual(rendered.refs.input.text, "", "send clears input")
local compassDrag = drags[rendered.refs.compassControl]
t.expect(type(compassDrag) == "function", "compass binds the native drag gesture")
if compassDrag then
	compassDrag({ state = "ended", translation = { x = 0, y = 24 } })
	t.expect(rendered.refs.output.text:find("> go north", 1, true), "compass drag submits an available direction")
	local compassTranscript = rendered.refs.output.text
	compassDrag({ state = "ended", translation = { x = 24, y = 0 } })
	t.assertEqual(rendered.refs.output.text, compassTranscript, "compass ignores unavailable directions")
end
chooseMenu("Look")
t.expect(rendered.refs.output.text:find('Response <&> "look"', 1, true), "quick command reaches session")
	local transcript = rendered.refs.output.text
click("send")
t.assertEqual(rendered.refs.output.text, transcript, "empty submission leaves transcript unchanged")
t.expect(not ns._textFieldTestCommand(rendered.refs.input, "cancel"), "unhandled keys retain native behavior")
chooseMenu("End session")
t.assertEqual(controller.navigation.depth, 2, "close returns to detail")
	t.assertEqual(controller.sessionModel:presentation().transcript, transcript, "navigation preserves session state")
controller.navigation:pop()
controller.sessionModel.engineFactory = function() error('Missing <story> & "engine"', 0) end
controller.sessionController:show(catalog:list()[1].id)
t.assertEqual(controller.navigation.depth, 2, "failed start opens template error state")
click("back")
t.assertEqual(controller.navigation.depth, 1, "error back restores catalog")
t.assertEqual(controller.window, nil, "template components never create windows")

local game = {}
for key, value in pairs(catalog:list()[1]) do game[key] = value end
game.title = 'An <Adventure> & "Quotes"'
game.description = string.rep("A long description & more. ", 40)
local oneAdventure = Adventures.new { games = { game } }
controller.adventures = oneAdventure
controller.library.model = oneAdventure
controller.sessionModel.engineFactory = function()
	return { start = function()
		return { resume = function(_, command) return 'Response <&> "' .. command .. '"' end }, "Opening <&>"
	end }
end
controller.library:showGame(game.id)
t.assertEqual(rendered.refs.title.text, game.title, "detail round-trips special characters")
t.assertEqual(rendered.refs.description.text, game.description, "detail preserves long text")
controller.navigation:pop()
t.assertEqual(controller.navigation.depth, 1, "detail back restores catalog")
t.expect(not controller.library:showGame("missing"), "missing detail record is rejected")
t.expect(not controller.sessionController:show("missing"), "missing session record is rejected")
t.assertEqual(controller.navigation.depth, 1, "missing records do not disturb navigation")
local data = controller.library:presentation()
t.assertEqual(#data.games, 1, "controller queries its injected model catalog")
t.assertEqual(data.featured.id, game.id, "controller uses the injected featured query")
t.assertEqual(game.stars, nil, "presentation does not decorate domain records with symbols")
t.assertEqual(game.ratingLabel, nil, "presentation does not decorate domain records with formatting")
controller:home()
click("coverButton_1")
t.assertEqual(rendered.refs.title.text, game.title, "catalog actions resolve stable game ids")

local empty = Controller.new { adventures = Adventures.new { games = {} }, sessionModel = Session.new(), ns = ns }
empty:home()
t.expect(rendered.refs.emptyCatalog ~= nil, "empty model renders the etlua empty state")
t.assertEqual(empty.navigation.depth, 1, "empty catalog retains navigation root")
ns.Button, ns.Menu, ns._addDrag, xml.renderFile = button, menu, addDrag, renderFile

os.exit(t.summary() and 0 or 1)
