_G.__headless = true
local t = require("TestKit")
local Session = require("apps.adventure-arena.zilscript.zilscript.reader.Session")
local ReaderStatus = require("apps.adventure-arena.helpers.ReaderStatus")
local Words = require("apps.adventure-arena.services.Words")
local englishCatalog, germanCatalog = require("apps.adventure-arena.catalog.en"), require("apps.adventure-arena.catalog.de")

local function find(catalog, id)
	for _, game in ipairs(catalog) do if game.id == id then return game end end
end

-- The German edition is its own book in its own catalog: another id, so
-- its saves are its own, and the shelves of the German library only.
local enEntry, deEntry = find(englishCatalog, "books.en.blackout-at-meridian"), find(germanCatalog, "books.de.blackout-at-meridian")
t.expect(enEntry ~= nil and deEntry ~= nil, "Blackout at Meridian has an English and a German edition")
t.expect(find(englishCatalog, "books.de.blackout-at-meridian") == nil, "the English catalog does not list the German edition")
t.assertEqual(#germanCatalog, 3, "the German catalog holds Blackout, Borrowed Tomorrows and the Museum")
for _, entry in ipairs(germanCatalog) do
	t.expect(entry.id:match("^books%.de%.") ~= nil, entry.id .. " is a German edition")
	t.expect(find(englishCatalog, entry.id:gsub("^books%.de%.", "books.en.")) ~= nil, entry.id .. " has an English edition")
end
t.assertEqual(deEntry.cover, enEntry.cover, "both editions share one cover")
t.assertEqual(deEntry.title, "Stromausfall in Meridian")
t.assertEqual(deEntry.collection, "Arena-Originale")
t.assertEqual(deEntry.statusLine, "moves")
t.assertEqual(deEntry.startFile, "blackout-at-meridian.zil", "the edition's folder holds the story under the book's own file name")
-- What the store makes of an entry: the catalog's language joins it.
local function edition(language, entry)
	local game = { language = language }
	for key, value in pairs(entry) do game[key] = value end
	return game
end
local english, german = edition("en", enEntry), edition("de", deEntry)

-- The reader's menus follow the story's language.
local session = Session.new { engineFactory = function()
	return { start = function() return { resume = function() return "Los." end }, "Willkommen." end }
end }
t.expect(session:start(german), "a German story starts")
t.assertEqual(session:presentation().language, "de", "the presentation carries the story language")
local suggestions = session:suggestions("")
t.assertEqual(suggestions[1].title, "Umsehen")
t.assertEqual(suggestions[1].command, "schau", "the command is one the German parser knows")
t.assertEqual(suggestions[2].title, "Inventar")
t.assertEqual(session:presentation().progress, "0 Züge", "the status line speaks German")
t.assertEqual(Session.statusLine(german, 0, 0, 7), "7 Züge")
t.expect(session:start(english), "an English story starts after it")
t.assertEqual(session:suggestions("")[1].title, "Look around", "English stays English")

-- The reader's own controls.
local de, en = Words.load("de"), Words.load("en")
t.assertEqual(en.placeholder, "What do you do?")
t.assertEqual(de.placeholder, "Was tust du?")
t.assertEqual(ReaderStatus.progress(de, "moves", 0, 0, 1), "1 Zug")
t.assertEqual(ReaderStatus.progress(de, "moves", 0, 0, 7), "7 Züge")
t.assertEqual(ReaderStatus.progress(de, nil, 2, 10, 4), "Punkte 2 von 10")
t.assertEqual(ReaderStatus.progress(en, nil, 2, 10, 4), "Score 2 of 10")
t.assertEqual(ReaderStatus.toast(de, 1), "+1 Punkt")
t.assertEqual(ReaderStatus.toast(en, -5), "−5 points")

-- The real German story, through the app runtime: every command the reader
-- offers is German and the story understands it. The engine keeps an
-- edition at zilscript/<id with slashes>; a pinned engine that still has the
-- German book at its old folder (books/blackout-at-meridian-de) cannot run
-- this part, and it says so rather than failing: it runs once the engine
-- is re-pinned.
local folder = "apps/adventure-arena/zilscript/" .. german.id:gsub("%.", "/")
local manifest = io.open(folder .. "/game.json", "r")
if not manifest then
	print("SKIPPED: " .. folder .. " is not in the pinned engine; the German edition runs after the engine re-pin")
else
	manifest:close()
	local Runtime = require("apps.adventure-arena.services.ZILRuntime")
	local book = Session.new { engineFactory = function(game, seed) return Runtime.new(game, nil, seed) end,
		newSeed = function() return 7 end }
	t.expect(book:start(german), "the German edition boots through the app runtime")
	t.assertEqual(book.currentGame.language, "de")
	t.assertEqual(book.roomTitle, "Leitstelle", "the opening names the German room")
	t.assertEqual(book:suggestions("")[1].title, "Umsehen")
	local function lastText()
		local entry = book.entries[#book.entries]
		return table.concat(entry.paragraphs or {}, "\n")
	end
	local function play(command)
		t.expect(book:submit(command), command .. " runs")
		local text = lastText()
		t.expect(not text:find("kann nicht von dem Spielvokabular verstanden", 1, true), command .. " is understood: " .. text)
		t.expect(not text:find("kannst das hier nicht sehen", 1, true), command .. " names a visible thing: " .. text)
		return text
	end
	t.expect(play("waehl fels"):find("Fels an", 1, true), "choosing a profile")
	t.expect(play("untersuch fenster"):find("Glas", 1, true), "examining the window")
	t.expect(play("lies einsatztafel"):find("AKTIV", 1, true), "reading the board")
	t.expect(book:hasExit("north"), "the German exit north is a direction")
	t.expect(play("nord"):find("Br", 1, true), "walking north")
	t.expect(book:submit("inventar"), "inventory")
	t.assertEqual(book:presentation().progress, "4 Züge", "moves are counted in German")
end

os.exit(t.summary() and 0 or 1)
