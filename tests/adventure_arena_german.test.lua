_G.__headless = true
local t = require("TestKit")
local Session = require("apps.adventure-arena.zilscript.zilscript.reader.Session")
local ReaderText = require("apps.adventure-arena.helpers.ReaderText")
local catalog = require("apps.adventure-arena.catalog.Adventures")

local function find(id)
	for _, game in ipairs(catalog) do if game.id == id then return game end end
end

-- The German edition sits next to the English one on the same shelves.
local english, german = find("books.blackout-at-meridian"), find("books.blackout-at-meridian-de")
t.expect(german ~= nil, "the library offers the German edition")
t.assertEqual(german.language, "de", "the catalog names the story's language")
t.assertEqual(english.language, nil, "English is the default language")
t.assertEqual(german.cover, english.cover, "both editions share one cover")
t.assertEqual(german.collection, "Arena Originals")
t.assertEqual(german.categories[1], "Superheroes")
t.assertEqual(german.statusLine, "moves")

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
local de, en = ReaderText.strings("de"), ReaderText.strings(nil)
t.assertEqual(en.placeholder, "What do you do?")
t.assertEqual(de.placeholder, "Was tust du?")
t.assertEqual(ReaderText.progress(de, "moves", 0, 0, 1), "1 Zug")
t.assertEqual(ReaderText.progress(de, "moves", 0, 0, 7), "7 Züge")
t.assertEqual(ReaderText.progress(de, nil, 2, 10, 4), "Punkte 2 von 10")
t.assertEqual(ReaderText.progress(en, nil, 2, 10, 4), "Score 2 of 10")
t.assertEqual(ReaderText.toast(de, 1), "+1 Punkt")
t.assertEqual(ReaderText.toast(en, -5), "−5 points")

-- The real German story, through the app runtime: every command the reader
-- offers is German and the story understands it.
local Runtime = require("apps.adventure-arena.services.ZILRuntime")
local book = Session.new { engineFactory = function(game, seed) return Runtime.new(game, nil, seed) end,
	newSeed = function() return 7 end }
t.expect(book:start(german), "the German edition boots through the app runtime")
t.assertEqual(book.currentGame.language, "de")
t.assertEqual(book.roomTitle, "Leitstelle", "the opening names the German room")
t.assertEqual(book:suggestions("")[1].title, "Umsehen")
local function offered(command)
	for _, entry in ipairs(book.entries) do
		for _, links in ipairs(entry.links or {}) do
			for _, link in ipairs(links) do
				for _, action in ipairs(book:linkActions(link.target)) do
					if action.command == command then return action end
				end
			end
		end
	end
end
local function lastText()
	local entry = book.entries[#book.entries]
	return table.concat(entry.paragraphs or {}, "\n")
end
local function play(command)
	t.expect(offered(command) ~= nil or command == "schau" or command == "inventar", "the menu offers " .. command)
	t.expect(book:submit(command), command .. " runs")
	local text = lastText()
	t.expect(not text:find("kann nicht von dem Spielvokabular verstanden", 1, true), command .. " is understood: " .. text)
	t.expect(not text:find("kannst das hier nicht sehen", 1, true), command .. " names a visible thing: " .. text)
	return text
end
t.assertEqual(offered("untersuch fenster").title, "Untersuchen", "menus name actions in German")
t.expect(offered("examine window") == nil, "no English command is offered")
t.expect(play("untersuch fenster"):find("Glas", 1, true), "examining the window")
t.expect(play("lies einsatztafel"):find("Profilkarten", 1, true), "reading the board")
t.expect(play("waehl fels"):find("Fels an", 1, true), "choosing a profile from the menu")
t.expect(book:hasExit("north"), "the German exit north is a direction")
t.assertEqual(book:linkActions("north")[1].command, "nord")
t.expect(play("nord"):find("Br", 1, true), "walking north")
t.expect(book:submit("inventar"), "inventory")
t.assertEqual(book:presentation().progress, "5 Züge", "moves are counted in German")

os.exit(t.summary() and 0 or 1)
