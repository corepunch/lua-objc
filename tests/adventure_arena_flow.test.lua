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
-- In-memory stores: headless tests never read or write the reader's real saves.
local function memoryStore() local value return { load = function() return value end, save = function(v) value = v end } end
local haptics = {}
local controller = Controller.new {
	adventures = catalog, sessionModel = sessionModel, ns = ns,
	saveStore = memoryStore(), readingStore = memoryStore(),
	haptics = { notification = function(kind) table.insert(haptics, kind) end },
	after = function() end,
}
local config, refs = xml.renderFile("apps/adventure-arena/views/Window.etlua", controller:libraryData(), ns)
controller.navigation = refs.navigation
controller.navigations = { library = refs.navigation, search = refs.searchNavigation }
controller.tabs = refs.tabs
controller:attach(refs)
local tabs = refs.tabs
-- The transcript and suggestion strip are retained templates inside the page.
local function page() return controller.sessionController.transcript.refs end
local function chips() return controller.sessionController.suggestions.refs end
local function lastEntry()
	local entries = controller.sessionModel:presentation().entries
	return #entries, entries[#entries]
end
for _, size in ipairs({ { 640, 720 }, { 420, 360 }, { 1000, 900 } }) do
	tabs.frameSize = ns.Size(size[1], size[2])
	tabs:layout(size[1])
	t.assertSize(tabs, size[1], size[2], "template tabs consume available space")
end
for index, title in ipairs({ "Discover", "Library", "Create", "Settings", "Search" }) do
	tabs:selectTab(index - 1)
	t.assertEqual(tabs.selectedTabViewItem.label, title, "template preserves tab title and order")
end
tabs:selectTab(0)
click("featured_1")
t.assertEqual(controller.navigation.depth, 2, "featured cover opens detail")
t.assertEqual(rendered.refs.title.text, catalog:list()[1].title, "detail renders selected game")
t.assertEqual(rendered.refs.cover.clipsToBounds, true, "detail cover clips aspect-fill overflow before title")
t.assertEqual(rendered.refs.description.text, catalog:list()[1].description, "detail preserves full description")
click("play")
t.assertEqual(controller.navigation.depth, 3, "detail play opens session")
t.assertEqual(rendered.refs.sessionTitle.text, catalog:list()[1].title, "session header retains the game title")
t.expect(rendered.refs.back == nil and rendered.refs.sessionHeader == nil,
	"the system navigation owns the back button; the screen draws no header")
local compassParent = rendered.refs.compassControl.superview
local reachesOverlay, entersInset = false, false
while compassParent do
	if compassParent == rendered.refs.sessionOverlay then reachesOverlay = true end
	if compassParent == rendered.refs.sessionContent then entersInset = true end
	compassParent = compassParent.superview
end
t.expect(entersInset and not reachesOverlay,
	"the compass rides in the glass command bar instead of covering the page")
t.assertEqual(page().gameTitle.text, catalog:list()[1].title, "the title page names the game")
t.assertEqual(page().gameDescription.text, catalog:list()[1].shortDescription,
	"the title page carries the tagline as its epigraph")
t.assertEqual(page().sceneTitle_1.text, catalog:list()[1].title, "the opening chapter is named")
t.assertEqual(page().paragraph_1_1.text, "Opening <&>", "transcript escapes XML characters")
t.expect(page().paragraph_1_1.dropCap, "the opening starts with a drop cap")
t.expect(rendered.refs.backdrop == nil, "the page is paper, not blurred cover art")
t.assertEqual(rendered.refs.progress.text, "Score 0 · Time 0", "Planetfall's folio shows its clock")
t.expect(chips().suggestion_1 ~= nil, "the suggestion strip offers commands before typing")
t.assertEqual(rendered.refs.input.accessibilityLabel, "Command", "composer retains accessibility label")
t.assertEqual(rendered.refs.input.bezeled, false, "glass composer owns the visible border")
t.assertEqual(rendered.refs.input.bordered, false, "plain input has no inner border")
local composerAncestor, composerHorizontalInset = rendered.refs.quickActions.superview, false
while composerAncestor and composerAncestor ~= rendered.refs.sessionContent do
	if composerAncestor.paddingHorizontal == 12 then composerHorizontalInset = true end
	composerAncestor = composerAncestor.superview
end
t.expect(composerHorizontalInset, "composer horizontal clearance is owned by the safe-area inset")
t.assertEqual(rendered.refs.send.enabled, false, "empty composer disables sending")
ns._textFieldTestInput(rendered.refs.input, "inv")
t.assertEqual(controller.sessionController.currentSuggestions[1].title, "inventory", "typing narrows the suggestions")
t.expect(chips().suggestion_1 ~= nil and chips().suggestion_2 == nil, "the chip strip shows only the narrowed suggestion")
ns._textFieldTestInput(rendered.refs.input, "inventory")
t.assertEqual(rendered.refs.send.enabled, true, "typing enables sending")
click("send")
t.assertEqual(page().command_2.text, "inventory", "the command appears on the page")
t.assertEqual(page().paragraph_3_1.text, 'Response <&> "inventory"', "send updates transcript")
t.assertEqual(rendered.refs.input.text, "", "send clears input")
t.assertEqual(rendered.refs.progress.text, "Score 0 · Time 1", "session refreshes progress after a command")
t.assertEqual(controller.savedGames:latest().gameId, catalog:list()[1].id, "a played story is saved")
t.expect(controller.tabs.accessoryHidden, "the tab accessory stays hidden while the book is open")
local compassDrag = drags[rendered.refs.compassControl]
t.expect(type(compassDrag) == "function", "compass binds the native drag gesture")
t.assertEqual(rendered.refs.compassExit_north.strokeAlpha, 1, "compass marks the north exit")
t.assertEqual(rendered.refs.compassExit_east.strokeAlpha, 0, "compass hides exits the player cannot take")
t.assertEqual(rendered.refs.compassTrack.stroke, "secondary", "compass keeps the full direction ring")
if compassDrag then
	compassDrag({ state = "changed", translation = { x = 0, y = -24 } })
	t.assertEqual(rendered.refs.compassDrag_north.strokeAlpha, 1, "dragging north highlights that section")
	t.assertEqual(rendered.refs.compassDrag_north.stroke, "accent", "an available drag uses the accent section")
	t.expect(rendered.refs.compassImage.offsetY < 0, "compass follows a north drag")
	compassDrag({ state = "ended", translation = { x = 0, y = -24 } })
	t.assertEqual(select(2, lastEntry()).paragraphs[1], 'Response <&> "go north"', "compass drag submits an available direction")
	t.assertEqual(rendered.refs.compassDrag_north.strokeAlpha, 0, "releasing the compass clears the highlight")
	t.assertEqual(rendered.refs.compassImage.offsetY, 0, "released compass returns to center")
	local compassTranscript = lastEntry()
	compassDrag({ state = "changed", translation = { x = 24, y = 0 } })
	t.assertEqual(rendered.refs.compassDrag_east.stroke, "tertiary", "an unavailable drag uses the tertiary section")
	compassDrag({ state = "ended", translation = { x = 24, y = 0 } })
	t.assertEqual(lastEntry(), compassTranscript, "compass ignores unavailable directions")
end
chooseMenu("Look Around")
local lookIndex = lastEntry()
t.assertEqual(page()["paragraph_" .. lookIndex .. "_1"].text, 'Response <&> "look"', "quick command reaches session")
local transcript = lastEntry()
click("send")
t.assertEqual(lastEntry(), transcript, "empty submission leaves transcript unchanged")
local chip = controller.sessionController.currentSuggestions[1]
t.expect(chip and chip.submit, "an empty composer offers a one-tap command")
if chip then
	local callbackBefore = lastEntry()
	controller.sessionController:applySuggestion(chip)
	t.assertEqual(lastEntry(), callbackBefore + 2, "a one-tap suggestion plays the command")
end
transcript = lastEntry()
t.expect(not ns._textFieldTestCommand(rendered.refs.input, "cancel"), "unhandled keys retain native behavior")
chooseMenu("Close Book")
t.assertEqual(controller.navigation.depth, 2, "close returns to detail")
t.assertEqual(lastEntry(), transcript, "navigation preserves session state")
t.assertEqual(controller.sessionController.transcript, nil, "closing releases the transcript template")
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
t.assertEqual(data.featured[1].id, game.id, "controller uses the injected featured query")
t.assertEqual(game.stars, nil, "presentation does not decorate domain records with symbols")
t.assertEqual(game.ratingLabel, nil, "presentation does not decorate domain records with formatting")
controller:home()
click("cover_1_1")
t.assertEqual(rendered.refs.title.text, game.title, "catalog actions resolve stable game ids")

local empty = Controller.new { adventures = Adventures.new { games = {} }, sessionModel = Session.new(), ns = ns,
	saveStore = memoryStore(), readingStore = memoryStore() }
empty:home()
t.expect(rendered.refs.emptyCatalog ~= nil, "empty model renders the etlua empty state")
t.assertEqual(empty.navigation.depth, 1, "empty catalog retains navigation root")
local _, systemRefs = renderFile("apps/adventure-arena/views/Session.etlua", {
	gameTitle = "Zork", gameDescription = "A story", chapterLabel = "Chapter I", ink = "accent", tint = "accent",
	roomTitle = "Gate", progress = "Score 0 · 0 moves",
	speechAvailable = false, availableDirections = {}, compassSegments = {},
	actions = { disappear = function() end, readingSettings = function() end },
}, ns)
t.expect(systemRefs.back == nil, "the navigation bar owns the back button")
local _, titleRefs = renderFile("apps/adventure-arena/views/SessionTitle.etlua", {
	gameTitle = "Zork", chapterLabel = "Chapter II", roomTitle = "Kitchen",
}, ns)
t.assertEqual(titleRefs.sessionTitle.text, "Zork", "the running head keeps the game name")
t.assertEqual(titleRefs.sessionPlace.text, "Chapter II · Kitchen", "the running head names the chapter and room")
ns.Button, ns.Menu, ns._addDrag, xml.renderFile = button, menu, addDrag, renderFile

os.exit(t.summary() and 0 or 1)
