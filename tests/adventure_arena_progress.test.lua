_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Adventures = require("apps.adventure-arena.models.Adventures")
local Session = require("apps.adventure-arena.zilscript.zilscript.reader.Session")
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
local catalog = Adventures
local controller = Controller.new {
	sessionModel = sessionModel, ns = ns,
	documents = { saves = saves, reading = memoryStore() },
	haptics = { notification = function(kind) table.insert(haptics, kind) end },
	after = function(seconds, callback) table.insert(timers, { seconds = seconds, callback = callback }) end,
}
local config, refs = xml.renderFile("apps/adventure-arena/views/layouts/Window.etlua", controller:libraryData(), ns)
controller.navigation = refs.navigation
t.expect(refs.tabs == nil and refs.nowReading == nil, "no bottom tabs or accessory")
local catalogActions = controller.pages:data("discover").actions
t.expect(refs.continueShelf == nil, "Home has no progress shelf")
catalogActions.openSettings()
t.expect(controller.pages:refs("settings").noGamesInProgress ~= nil and controller.readingOptions.mounted[1].preview,
	"Settings opens with a sample page")
controller.navigation:pop()

-- Opening a book and reading one page puts it on every shelf.
local zork = catalog:find("infocom.zork1")
t.expect(controller.sessionController:show(zork.id), "a story opens")
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
catalogActions.openSettings()
local settingsRefs = controller.pages:refs("settings")
t.assertEqual(settingsRefs.shelfRow_1.accessibilityLabel,
	"Continue " .. zork.title .. ", West of House", "Settings lists the saved game")
local shelf = controller.pages:data("settings")
t.assertEqual(shelf.entries[1].status, "Score 5 of 350 · 0 moves", "the saved row carries the status line")
t.assertEqual(shelf.entries[1].progress, 5 / 350, "the saved row shows progress toward the maximum")
controller.navigation:pop()
t.assertEqual(#saves.load().games, 1, "the autosave is persisted")

-- The detail page offers Continue and Start Over for a story in progress.
local detail
local renderFile = xml.renderFile
xml.renderFile = function(path, data, platform)
	if path:find("Detail.etlua", 1, true) then detail = data end
	return renderFile(path, data, platform)
end
controller.pages:page("discover"):flow("Opening"):game(zork.id)
xml.renderFile = renderFile
t.assertEqual(detail.saved.place, "West of House", "the detail page knows where the reader stopped")
controller.navigation:pop()

-- Continue and restart work from Settings, and removing a save refreshes it.
catalogActions.openSettings()
local actions = controller.pages:data("settings").actions
t.expect(actions.continue_1(), "Settings resumes the saved game")
t.assertEqual(#controller.sessionModel.history, 2, "resuming replays both commands")
t.assertEqual(controller.sessionModel.scoreChange, 0, "resuming does not announce old points")
controller.navigation:pop()
controller.sessionController:onDisappear()
t.expect(controller.pages:refs("settings").shelfRow_1 ~= nil, "returning from the reader keeps Settings mounted")

actions.restart_1()
t.assertEqual(#controller.sessionModel.history, 0, "Start Over begins at the title page")
controller.navigation:pop()
controller.sessionController:onDisappear()
t.expect(actions.remove(zork.id), "a saved game can be removed from Settings")
t.expect(controller.pages:refs("settings").noGamesInProgress ~= nil, "removing the game refreshes Settings")
controller.navigation:pop()
t.expect(controller.pages:refs("settings") == nil, "leaving Settings releases its mounted page")

os.exit(t.summary() and 0 or 1)
