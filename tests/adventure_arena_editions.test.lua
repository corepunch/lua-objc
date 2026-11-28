_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local Adventures = require("apps.adventure-arena.models.Adventures")
local SavedGames = require("apps.adventure-arena.models.SavedGames")
local ReadingSettings = require("apps.adventure-arena.models.ReadingSettings")
local Controller = require("apps.adventure-arena.Controller")
local Store = require("apps.adventure-arena.Store")
local Words = require("apps.adventure-arena.services.Words")
local Languages = require("apps.adventure-arena.helpers.Languages")
local Session = require("apps.adventure-arena.zilscript.zilscript.reader.Session")

local englishId, germanId = "books.en.blackout-at-meridian", "books.de.blackout-at-meridian"
local reading, saves
local documents = {
	reading = { load = function() return reading end, save = function(value) reading = value end },
	saves = { load = function() return saves end, save = function(value) saves = value end },
}

-- Every string a view shows: text, titles, placeholders and accessibility labels.
local function shown(view, into)
	into = into or {}
	for _, key in ipairs({ "text", "title", "placeholder", "accessibilityLabel" }) do
		local ok, value = pcall(function() return view[key] end)
		if type(value) == "string" and value ~= "" then table.insert(into, value) end
	end
	for _, child in ipairs(view.subviews or {}) do shown(child, into) end
	return into
end
local function contains(view, text)
	for _, value in ipairs(shown(view)) do
		if value:find(text, 1, true) then return true end
	end
	return false
end

local function launch(preferred, extra)
	local options = { documents = documents, preferredLanguages = preferred }
	for key, value in pairs(extra or {}) do options[key] = value end
	local app = Controller.new(options)
	app:home()
	return app
end

-- ── An English device: the English library, without the German edition ──
local app = launch({ "en-GB", "de-DE" })
t.assertEqual(ReadingSettings.language(), "en", "the first preferred language with a catalog is the app's")
t.assertEqual(#Adventures:all(), 19, "the English library holds the English books")
t.expect(Adventures:find(englishId) ~= nil, "Blackout at Meridian is in English")
t.assertEqual(Adventures:find(germanId), nil, "the German edition never appears in the English library")
local english = Adventures:find(englishId)
t.assertEqual(english.language, "en", "the catalog carries its language into the reader")
t.expect(germanId ~= englishId, "an edition has an id of its own")
t.expect(contains(app.navigation, "Discover") or contains(app.pages:refs("discover").libraryScroll, "Top Rated"),
	"the app speaks English on an English device")
t.assertEqual(Words.load(ReadingSettings.language()).continueReading, "Continue Reading")

SavedGames:record { gameId = englishId, commands = { "look" } }
t.assertEqual(#SavedGames:inProgress(), 1, "English progress shows in the English library")

-- ── The setting overrides the device, Automatic restores it ────────────
app:openCatalogPage("settings")
local picker = app.pages:refs("settings").language
local settings = app.pages:data("settings")
t.assertEqual(settings.languageIndex, 0, "Automatic starts selected")
t.assertEqual(#settings.languages, 3, "Settings offers every language by its own name")
t.assertEqual(settings.languages[2].title, "Deutsch")
t.assertEqual(picker.selectedSegment, 0, "the native picker shows Automatic")

settings.actions.changeLanguage(2)
t.assertEqual(reading.language, "de", "Settings persists the chosen language")
t.assertEqual(app.pages:refs("settings").language.selectedSegment, 2, "the native picker shows Deutsch")
t.assertEqual(ReadingSettings.language(), "de", "the choice overrides the English device")
t.assertEqual(Adventures:find(englishId), nil, "the English edition is hidden in the German library")
t.assertEqual(#Adventures:all(), 3, "the German library lists the three German editions only")
t.assertEqual(Adventures:all()[1].id, germanId)
t.assertEqual(#SavedGames:inProgress(), 0, "English progress does not show in the German library")
t.expect(contains(app.pages:refs("discover").libraryScroll, "Stromausfall in Meridian"), "Discover shows the German edition")
t.expect(contains(app.pages:refs("settings").settingsScroll, "Hilfe"), "Settings speaks German at once")
t.expect(not contains(app.pages:refs("settings").settingsScroll, "Help"), "and no English is left on it")

-- Saves are keyed by edition: the two editions never share progress.
local german = Adventures:find(germanId)
t.assertEqual(german.language, "de", "the German edition carries the language into the reader")
local reader = Session.new { engineFactory = function()
	return { start = function() return { resume = function() return "Los." end }, "Willkommen." end }
end }
t.expect(reader:start(german), "the German edition starts")
reader:submit("schau")
SavedGames:record(reader:snapshot())
t.assertEqual(#SavedGames:inProgress(), 1, "German progress belongs to the German edition")
t.expect(SavedGames:find(englishId) ~= nil, "English saves stay in storage")
t.assertEqual(SavedGames:find(germanId).commands[1], "schau", "each edition keeps its own commands")
t.assertEqual(SavedGames:inProgress()[1].game.id, germanId)

-- A fresh launch reads the choice back.
local relaunched = launch({ "en-GB" })
t.assertEqual(ReadingSettings.language(), "de", "a fresh launch loads the chosen language")
t.expect(Adventures:find(germanId) ~= nil, "an explicit choice overrides the device language")

settings.actions.changeLanguage(0)
t.assertEqual(reading.language, "automatic", "Automatic clears the explicit choice")
t.assertEqual(ReadingSettings.language(), "en", "Automatic follows the device again: this device is English")
launch({ "fr-FR", "de-AT", "en-GB" })
t.expect(Adventures:find(germanId) ~= nil, "an Austrian German preference matches the German library")
t.expect(Adventures:find(englishId) == nil, "the first supported preference wins")
launch({ "de-DE" })
t.assertEqual(ReadingSettings.language(), "de", "a German device speaks German")
launch({ "fr-CA", "ja-JP" })
t.assertEqual(ReadingSettings.language(), "en", "English is used when no preferred language has a library")
t.expect(Adventures:find(englishId) ~= nil)
Store.new { games = { { id = englishId, language = "en" } }, preferredLanguages = { "de-DE" } }
t.assertEqual(ReadingSettings.language(), "en", "a German preference with no German catalog is skipped")

-- The launch argument overrides both and is not saved.
reading = nil
launch({ "en-GB" }, { language = "de" })
t.assertEqual(ReadingSettings.language(), "de", "--language=de overrides the device")
t.assertEqual(reading, nil, "a launch argument is not written to the settings")
t.assertThrows(function() Store.new { language = "tlh" } end, "an unknown language is refused")

-- ── A German device: German library and German words everywhere ─────────
reading, saves = nil, nil
app = launch({ "de-DE" })
local discover = app.pages:refs("discover").libraryScroll
t.assertEqual(ReadingSettings.language(), "de")
t.assertEqual(#Adventures:all(), 3, "the German library lists the German editions only")
t.expect(contains(discover, "Am besten bewertet"), "Discover speaks German")
t.expect(contains(discover, "Arena-Originale"), "the German shelves carry German names")
t.expect(not contains(discover, "Top Rated"), "no English is left on Discover")

SavedGames:record { gameId = germanId, commands = { "schau" }, room = "Leitstelle", moves = 1 }
app.pages:refresh()
discover = app.pages:refs("discover").libraryScroll
t.expect(contains(discover, "Weiterlesen"), "the shelf of saved stories is Weiterlesen")

local _, detailRefs = app:pushPage("detail", { id = germanId })
local detail = detailRefs.detailScrollView
local words = Words.load("de")
t.expect(contains(detail, words.aboutStory), "the detail page speaks German")
t.expect(contains(detail, words.factDifficulty) and contains(detail, words.noRatings), "and so do its facts")
t.expect(not contains(detail, "About this Story") and not contains(detail, "Start Reading"), "with no English left")
t.assertEqual(detailRefs.play.title, words.continue, "a saved story offers to continue, in German")

app:openCatalogPage("settings")
local page = app.pages:refs("settings")
t.expect(contains(page.settingsScroll, words.help) and contains(page.settingsScroll, words.howToPlay), "Settings speaks German")
t.expect(contains(page.settingsScroll, words.textSize) and contains(page.settingsScroll, words.theme_night),
	"so do the reading options")
t.expect(contains(page.settingsScroll, words.gamesInProgress), "and the saved stories")

app:openCatalogPage("search")
app.pages:data("search").actions.search("stromausfall")
t.assertEqual(#app.pages:data("search").results, 1, "search finds the German title")
app.pages:data("search").actions.search("ÖFFNEN")
t.assertEqual(#Adventures:search("STROMAUSFALL"), 1, "search ignores case")
t.assertEqual(Languages.lower("ÄÖÜ Straße"), "äöü straße", "case folding knows German capitals")

-- ── The reader: chrome follows the app language, the story its edition ──
local sessionModel = Session.new { engineFactory = function()
	return { start = function() return { resume = function() return "Los." end }, "Willkommen." end,
		exits = function() return {} end }
end }
-- Only the English edition has been read so far.
saves = { games = { { gameId = englishId, commands = { "look" } } } }
local starts = {}
local realStart = sessionModel.start
sessionModel.start = function(self, game, saved)
	table.insert(starts, saved or false)
	return realStart(self, game, saved)
end
local reader = Controller.new { documents = documents, preferredLanguages = { "de-DE" }, sessionModel = sessionModel,
	speech = { recognizer = function() return {} end } }
reader:home()
t.expect(reader.sessionController:show(germanId), "the German edition opens in the reader")
local refs = reader.sessionController.refs
t.assertEqual(refs.input.placeholder, words.placeholder, "the command field asks in German")
t.assertEqual(refs.input.accessibilityLabel, words.command)
t.assertEqual(refs.dictate.accessibilityLabel, words.dictate)
t.assertEqual(reader.sessionController.heading.refs.sessionScore.text, "0 Züge", "the running head counts in German")
t.assertEqual(starts[#starts], false, "opening the German edition resumes none of the English edition's progress")
t.expect(not reader.sessionController:show(englishId), "the English edition cannot be opened from the German library")

local nativeLanguages = require("ns").preferredLanguages()
t.expect(type(nativeLanguages) == "table" and type(nativeLanguages[1]) == "string",
	"the native bridge returns the device's language tags as a list")

os.exit(t.summary() and 0 or 1)
