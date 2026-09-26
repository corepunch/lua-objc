_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Adventures = require("apps.adventure-arena.models.Adventures")
local Session = require("apps.adventure-arena.models.Session")
local Controller = require("apps.adventure-arena.Controller")

-- A scripted engine: "take egg" scores, everything else echoes.
local score = 0
local sessionModel = Session.new({ engineFactory = function()
	score = 0
	return { start = function()
		return {
			resume = function(_, command)
				if command == "take egg" then score = score + 5 end
				return "You " .. command .. "."
			end,
			progress = function() return { score = score, moves = 0, maxScore = 350 } end,
			roomName = function() return "West of House" end,
		}, "West of House\nYou are standing in an open field."
	end }
end })

local function memoryStore() local value return { load = function() return value end, save = function(v) value = v end } end
local saves = memoryStore()
local haptics, timers = {}, {}
local catalog = Adventures.new()
local controller = Controller.new {
	adventures = catalog, sessionModel = sessionModel, ns = ns,
	saveStore = saves, readingStore = memoryStore(),
	haptics = { notification = function(kind) table.insert(haptics, kind) end },
	after = function(seconds, callback) table.insert(timers, { seconds = seconds, callback = callback }) end,
}
local config, refs = xml.renderFile("apps/adventure-arena/views/Window.etlua", controller:libraryData(), ns)
controller.navigation = refs.navigation
controller.navigations = { library = refs.navigation, bookshelf = refs.bookshelfNavigation,
	create = refs.createNavigation, settings = refs.settingsNavigation, search = refs.searchNavigation }
controller.tabs = refs.tabs
controller:attach(refs)

-- Nothing read yet: no shelf, an empty Library tab, no accessory.
t.expect(controller.continueShelf.refs.continue_1 == nil, "Continue Reading is absent before any story is read")
t.expect(controller.bookshelf.refs.emptyBookshelf ~= nil, "the Library tab explains how stories arrive")
t.expect(controller.tabs.accessoryHidden, "the tab accessory waits for a story in progress")
t.expect(controller.settings ~= nil and controller.readingOptions.mounted[1].preview,
	"the Settings tab mounts the reading options with a sample page")

-- Opening a book and reading one page puts it on every shelf.
local zork = catalog:find("infocom.zork1")
t.expect(controller.sessionController:show(zork.id), "a story opens")
t.expect(controller.tabs.accessoryHidden, "an open book hides the accessory with the tab bar")
controller.sessionController:submitCommand("take egg")
local page = controller.sessionController.refs
t.expect(page.scoreToast.hidden == false, "points raise the glass toast")
t.assertEqual(page.scoreToastText.text, "+5 points", "the toast names the points")
t.assertEqual(haptics[#haptics], "success", "points are felt as a success haptic")
t.assertEqual(timers[#timers].seconds, 2.2, "the toast dismisses itself after a beat")
timers[#timers].callback()
t.expect(page.scoreToast.hidden == true, "the toast fades when its timer fires")
controller.sessionController:submitCommand("look")
t.assertEqual(#haptics, 1, "a command without points is silent")

controller.navigation:pop()
controller.sessionController:onDisappear()
t.expect(not controller.tabs.accessoryHidden, "closing the book shows the accessory")
t.assertEqual(controller.nowReading.refs.nowReadingTitle.text, zork.title, "the accessory names the story")
t.assertEqual(controller.nowReading.refs.nowReadingPlace.text, "Chapter I · West of House", "the accessory names the chapter and room")
t.assertEqual(controller.continueShelf.refs.continue_1.accessibilityLabel,
	"Continue " .. zork.title .. ", Chapter I · West of House", "Continue Reading offers the story")
t.expect(controller.bookshelf.refs.shelfRow_1 ~= nil, "the Library tab lists the story")
local shelf = controller.library:bookshelf()
t.assertEqual(shelf.entries[1].status, "Score 5 of 350 · 0 moves", "the Library row carries the status line")
t.assertEqual(shelf.entries[1].progress, 5 / 350, "the Library row shows progress toward the maximum")
t.assertEqual(#saves.load().games, 1, "the autosave is persisted")

-- The detail page offers Continue and Start Over for a story in progress.
local detail
local renderFile = xml.renderFile
xml.renderFile = function(path, data, platform)
	if path:find("Detail.etlua", 1, true) then detail = data end
	return renderFile(path, data, platform)
end
controller.library:showGame(zork.id, "library")
xml.renderFile = renderFile
t.assertEqual(detail.saved.place, "Chapter I · West of House", "the detail page knows where the reader stopped")
controller.navigation:pop()

-- The accessory resumes the story at its last page.
t.expect(controller:resumeLatest(), "the accessory resumes the latest story")
t.assertEqual(#controller.sessionModel.history, 2, "resuming replays both commands")
t.assertEqual(controller.sessionModel.scoreChange, 0, "resuming does not announce old points")
controller.navigation:pop()
controller.sessionController:onDisappear()

-- Start Over reads from the title page; Remove takes it off every shelf.
local actions = controller.library:bookshelf().actions
actions.restart_1()
t.assertEqual(#controller.sessionModel.history, 0, "Start Over begins at the title page")
controller.navigation:pop()
controller.sessionController:onDisappear()
t.expect(controller.library:removeSaved(zork.id), "a story can be removed from the Library")
t.expect(controller.continueShelf.refs.continue_1 == nil, "a removed story leaves Continue Reading")
t.expect(controller.bookshelf.refs.emptyBookshelf ~= nil, "the Library tab is empty again")
t.expect(controller.tabs.accessoryHidden, "the accessory hides with nothing to resume")
t.expect(not controller:resumeLatest(), "there is nothing to resume")

os.exit(t.summary() and 0 or 1)
