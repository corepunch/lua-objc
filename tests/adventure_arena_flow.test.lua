_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Adventures = require("apps.adventure-arena.models.Adventures")
local Session = require("apps.adventure-arena.zilscript.zilscript.reader.Session")
local Store = require("apps.adventure-arena.Store")
local SavedGames = require("apps.adventure-arena.models.SavedGames")
local catalog = Adventures
local Controller = require("apps.adventure-arena.Controller")
local renderFile, button = xml.renderFile, ns.Button
local scrollView, topEdgeStyles = ns.ScrollView, {}
ns.ScrollView = function(props)
	local view = scrollView(props)
	topEdgeStyles[view] = props.topEdgeEffectStyle
	return view
end
local addDrag = ns._addDrag
local rendered, callbacks, drags = {}, {}, {}
local controller
-- The open book's page and running head are retained sections.
local function reader() return controller.sessionController.refs end
local function heading() return controller.sessionController.heading.refs end

-- Capture the callbacks actually supplied by the XML renderer to native buttons.
ns.Button = function(props)
	local view = button(props)
	callbacks[view] = props.action
	return view
end
ns._addDrag = function(view, callback) drags[view] = callback end
xml.renderFile = function(path, data, ...)
	local view, refs = renderFile(path, data, ...)
	rendered = { view = view, refs = refs, data = data }
	return view, refs
end
local function click(ref)
	local view = rendered.refs[ref] or (controller.sessionController.refs or {})[ref]
		or controller.pages:refs("discover")[ref]
	local callback = callbacks[view]
	t.expect(type(callback) == "function", ref .. " has a bound action")
	if callback then callback() end
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
controller = Controller.new {
	sessionModel = sessionModel, ns = ns,
	documents = { saves = memoryStore(), reading = memoryStore() },
	haptics = { notification = function(kind) table.insert(haptics, kind) end },
	after = function() end,
}
controller:home()
local refs = controller.pages:refs("discover")
t.assertEqual(topEdgeStyles[refs.libraryScroll], "soft", "the catalog scrolls beneath a soft top edge")
t.assertEqual(topEdgeStyles[refs.shelfScroll_1], nil, "the horizontal shelf leaves the page edge to its parent")
t.expect(refs.tabs == nil and refs.nowReading == nil, "the window has no tabs or floating reading accessory")
t.expect(refs.continueShelf == nil and refs.featuredCarousel == nil, "a fresh Home opens on the catalog shelves")
-- The transcript is retained while the command is edited.
local function page() return controller.sessionController.transcript.refs end
local function lastEntry()
	local entries = controller.sessionModel:presentation().entries
	return #entries, entries[#entries]
end
for _, size in ipairs({ { 640, 720 }, { 420, 360 }, { 1000, 900 } }) do
	controller.navigation.frameSize = ns.Size(size[1], size[2])
	controller.navigation:layout(size[1])
	t.assertSize(controller.navigation, size[1], size[2], "navigation fills the window")
end
local homeRendering = rendered
local firstShelf = catalog:genreShelves()[1]
local firstBook = firstShelf.games[1]
t.expect(refs.genre_1 == nil and refs.seeAll_1 == nil, "shelves replace the genre tiles and See All buttons")
t.assertEqual(refs.shelfHeading_1.accessibilityLabel, "See all Read with Kids", "the read-aloud shelf leads Discover")
t.assertEqual(refs.shelfHeading_1.superview.paddingHorizontal, refs.shelfBooks_1.paddingHorizontal,
	"the heading shares both side insets with its covers")
click("shelfHeading_1")
t.assertEqual(controller.navigation.depth, 2, "the heading opens the collection")
t.assertEqual(rendered.data.title, "Read with Kids", "the collection uses the shelf's title")
for index, game in ipairs(catalog:collection(firstShelf.title)) do
	t.assertEqual(rendered.refs["collectionCover_" .. index].accessibilityLabel, game.title,
		"the collection shows the matching book")
	local author = rendered.refs["collectionCover_" .. index .. "_author"]
	t.assertEqual(author.text, game.author, "the card shows the author below the title")
	t.assertEqual(author.superview.spacing, 1, "the title and author are closely grouped")
end
t.expect(rendered.refs["collectionCover_" .. (firstShelf.count + 1)] == nil, "unrelated books are excluded")
controller.navigation:pop()
rendered = homeRendering
click("cover_1_1")
t.assertEqual(controller.navigation.depth, 2, "a shelf cover opens detail")
t.assertEqual(topEdgeStyles[rendered.refs.detailScrollView], "soft", "the story cover meets a soft navigation edge")
t.assertEqual(rendered.refs.detailScrollView.ignoresSafeArea, "top", "the artwork extends behind the native bar")
t.assertEqual(rendered.refs.title.text, firstBook.title, "detail renders selected game")
t.assertEqual(rendered.refs.cover.clipsToBounds, true, "detail cover clips aspect-fill overflow before title")
t.assertEqual(rendered.refs.play.title, "Start Reading", "an unplayed story offers Start Reading")
t.expect(rendered.refs.play.image == nil, "Start Reading is text-only")
local _, resumedRefs = renderFile("apps/adventure-arena/views/pages/Detail.etlua", {
	game = firstBook, saved = { place = "Sanitarium Gate" },
	actions = { play = function() end, restart = function() end },
}, ns)
t.assertEqual(resumedRefs.play.title, "Continue", "Continue omits the saved room name")
t.expect(resumedRefs.play.image == nil, "Continue is text-only")
t.assertEqual(resumedRefs.play.accessibilityLabel, "Continue " .. firstBook.title,
	"Continue retains the story title for accessibility")
t.expect(resumedRefs.restart ~= nil, "a saved story still offers Start over")
local bookInfoSynopsis = rendered.refs.description.text
t.assertEqual(bookInfoSynopsis, firstBook.description, "detail preserves full description")
local ancestor = rendered.refs.play.superview
while ancestor and ancestor ~= rendered.refs.detailScrollView do ancestor = ancestor.superview end
t.expect(ancestor == rendered.refs.detailScrollView, "Start Reading scrolls with book details")
click("play")
t.assertEqual(controller.navigation.depth, 3, "detail play opens session")
t.assertEqual(heading().sessionTitle.text, firstBook.title, "the opening location heads the reader")
t.expect(rendered.refs.bookCommands == nil and rendered.refs.readingActions == nil, "the reader has no ellipsis menu")
t.expect(rendered.refs.back == nil and rendered.refs.sessionHeader == nil,
	"the system navigation owns the back button; the screen draws no header")
t.expect(page().bannerTitle_1 == nil and page().synopsis == nil, "the reader only uses what the game prints")
t.assertEqual(page().sceneTitle_1.text, firstBook.title, "the opening scene is named")
t.assertEqual(page().paragraph_1_1.text, "Opening <&>", "transcript escapes XML characters")
t.assertEqual(#page().paragraph_1_1.textContainer.exclusionPaths, 0, "the opening prose uses the full column")
t.expect(reader().backdrop == nil, "the page is paper, not blurred cover art")
t.assertEqual(heading().sessionScore.text, "Score 0", "the toolbar shows score without the clock")
t.expect(page().progress == nil, "the transcript has no stats footer")
t.assertEqual(controller.sessionController.completions, nil, "desktop has no suggestion UI")
t.assertEqual(reader().input.accessibilityLabel, "Command", "composer retains accessibility label")
t.assertEqual(reader().input.bezeled, false, "glass composer owns the visible border")
t.assertEqual(reader().input.bordered, false, "plain input has no inner border")
local composerAncestor, composerHorizontalInset = reader().commandBar.superview, false
while composerAncestor and composerAncestor ~= reader().sessionContent do
	if composerAncestor.paddingHorizontal == 12 then composerHorizontalInset = true end
	composerAncestor = composerAncestor.superview
end
t.expect(composerHorizontalInset, "composer horizontal clearance is owned by the safe-area inset")
t.assertEqual(reader().send.enabled, false, "empty composer disables sending")
ns._textFieldTestInput(reader().input, "inv")
t.assertEqual(reader().input.text, "inv", "typing preserves the command draft")
ns._textFieldTestInput(reader().input, "inventory")
t.assertEqual(reader().send.enabled, true, "typing enables sending")
click("send")
t.assertEqual(page().command_2.text, "inventory", "the command appears on the page")
t.assertEqual(page().paragraph_3_1.text, 'Response <&> "inventory"', "send updates transcript")
t.assertEqual(reader().input.text, "", "send clears input")
t.assertEqual(heading().sessionScore.text, "Score 0", "the clock never appears alongside the score")
-- The score capsule is part of the page's state: shown with its text, then
-- drawn away again.
controller.sessionController:announceScore(5)
t.assertEqual(reader().toastLayer.safeAreaPadding, "top", "score feedback stays clear of the navigation bar")
t.expect(not reader().scoreToast.hidden and reader().scoreToastText.text == "+5 points", "a score change shows its capsule")
controller.sessionController.toast = nil
controller.sessionController:render()
t.expect(reader().scoreToast.hidden, "and the capsule goes once the page is drawn without it")
t.assertEqual(SavedGames:latest().gameId, firstBook.id, "a played story is saved")
ns._textFieldTestInput(reader().input, "look")
click("send")
local lookIndex = lastEntry()
t.assertEqual(page()["paragraph_" .. lookIndex .. "_1"].text, 'Response <&> "look"', "typed look reaches session")
local transcript = lastEntry()
click("send")
t.assertEqual(lastEntry(), transcript, "empty submission leaves transcript unchanged")
transcript = lastEntry()
t.expect(not ns._textFieldTestCommand(reader().input, "cancel"), "unhandled keys retain native behavior")
controller.sessionController:close()
t.assertEqual(controller.navigation.depth, 2, "close returns to detail")
t.assertEqual(lastEntry(), transcript, "navigation preserves session state")
t.assertEqual(controller.sessionController.transcript, nil, "closing releases the transcript template")
controller.navigation:pop()
controller.sessionModel.engineFactory = function() error('Missing <story> & "engine"', 0) end
controller.sessionController:show(firstBook.id)
t.assertEqual(controller.navigation.depth, 2, "failed start opens template error state")
click("back")
t.assertEqual(controller.navigation.depth, 1, "error back restores catalog")
t.assertEqual(controller.window, nil, "template components never create windows")

local game = {}
for key, value in pairs(firstBook) do game[key] = value end
game.title = 'An <Adventure> & "Quotes"'
game.description = string.rep("A long description & more. ", 40)
require("data.model").db.adventures = { game }
controller.sessionModel.engineFactory = function()
	return { start = function()
		return { resume = function(_, command) return 'Response <&> "' .. command .. '"' end }, "Opening <&>"
	end }
end
controller.pages:page("discover"):flow("Opening"):game(game.id)
t.assertEqual(rendered.refs.title.text, game.title, "detail round-trips special characters")
t.assertEqual(rendered.refs.description.text, game.description, "detail preserves long text")
controller.navigation:pop()
t.assertEqual(controller.navigation.depth, 1, "detail back restores catalog")
t.expect(not controller.pages:page("discover"):flow("Opening"):game("missing"), "missing detail record is rejected")
t.expect(not controller.sessionController:show("missing"), "missing session record is rejected")
t.assertEqual(controller.navigation.depth, 1, "missing records do not disturb navigation")
local data = controller.pages:data("discover")
t.assertEqual(#data.games, 1, "controller queries its injected model catalog")
t.assertEqual(data.inProgress[1].game.title, game.title, "the saved story uses the current catalog title")
t.assertEqual(game.stars, nil, "presentation does not decorate domain records with symbols")
t.assertEqual(game.ratingLabel, nil, "presentation does not decorate domain records with formatting")
controller:home()
click("cover_1_1")
t.assertEqual(rendered.refs.title.text, game.title, "catalog actions resolve stable game ids")

local empty = Controller.new { games = {}, sessionModel = Session.new(), ns = ns,
	documents = { saves = memoryStore(), reading = memoryStore() } }
empty:home()
t.expect(empty.pages:refs("discover").emptyCatalog ~= nil, "empty model renders the etlua empty state")
t.assertEqual(empty.navigation.depth, 1, "empty catalog retains navigation root")
local _, systemRefs = renderFile("apps/adventure-arena/views/pages/Session.etlua", {
	roomTitle = "Gate",
	speechAvailable = false,
	actions = { disappear = function() end, readingSettings = function() end, look = function() end, inventory = function() end, inputChanged = function() end, inputCommand = function() end, inputFocused = function() end, submit = function() end },
}, ns)
t.expect(systemRefs.back == nil, "the navigation bar owns the back button")
local _, titleRefs = renderFile("apps/adventure-arena/views/sections/SessionTitle.etlua", {
	roomTitle = "Kitchen", score = 0, maxScore = 0,
}, ns)
t.assertEqual(titleRefs.sessionTitle.text, "Kitchen", "the running head names the room")
t.assertEqual(titleRefs.sessionScore.text, "Score 0", "the running head shows score on its second line")
ns.Button, ns._addDrag, xml.renderFile = button, addDrag, renderFile
ns.ScrollView = scrollView

os.exit(t.summary() and 0 or 1)
