_G.__headless = true
-- The Russian edition and the way every language counts: three plural forms
-- in Russian, chosen in one place (helpers/Plurals.lua) from the strings a
-- language's resources declare.
local t = require("TestKit")
local jsonParse = require("AppKit").json_parse
local Session = require("apps.adventure-arena.zilscript.zilscript.reader.Session")
local ReaderStatus = require("apps.adventure-arena.helpers.ReaderStatus")
local Plurals = require("apps.adventure-arena.helpers.Plurals")
local Languages = require("apps.adventure-arena.helpers.Languages")
local Words = require("apps.adventure-arena.services.Words")
local englishCatalog, russianCatalog = require("apps.adventure-arena.catalog.en"), require("apps.adventure-arena.catalog.ru")

local ru, de, en = Words.load("ru"), Words.load("de"), Words.load("en")

-- ── Plural forms ───────────────────────────────────────────────────────
local MOVES = { [0] = "0 ходов", [1] = "1 ход", [2] = "2 хода", [3] = "3 хода", [4] = "4 хода", [5] = "5 ходов",
	[11] = "11 ходов", [12] = "12 ходов", [14] = "14 ходов", [20] = "20 ходов", [21] = "21 ход", [22] = "22 хода",
	[25] = "25 ходов", [101] = "101 ход", [111] = "111 ходов", [112] = "112 ходов", [121] = "121 ход" }
for count, expected in pairs(MOVES) do
	t.assertEqual(Plurals.format(ru, "moveCount", count), expected, "ru moves: " .. count)
	t.assertEqual(ReaderStatus.progress(ru, "moves", 0, 0, count), expected, "the running head counts " .. count)
end
local POINTS = { [0] = "0 очков", [1] = "1 очко", [2] = "2 очка", [5] = "5 очков", [11] = "11 очков",
	[21] = "21 очко", [22] = "22 очка", [25] = "25 очков", [101] = "101 очко", [111] = "111 очков" }
for count, expected in pairs(POINTS) do
	t.assertEqual(Plurals.format(ru, "pointCount", count), expected, "ru points: " .. count)
	if count > 0 then t.assertEqual(ReaderStatus.toast(ru, count), "+" .. expected, "the toast adds " .. count) end
end
t.assertEqual(ReaderStatus.toast(ru, -2), "−2 очка", "a loss is a minus and the form of its size")
local RATINGS = { [0] = "0 оценок", [1] = "1 оценка", [3] = "3 оценки", [12] = "12 оценок", [31] = "31 оценка" }
for count, expected in pairs(RATINGS) do t.assertEqual(Plurals.format(ru, "ratingsCount", count), expected) end
t.assertEqual(Plurals.form(ru, 1), "one")
t.assertEqual(Plurals.form(ru, 2), "few")
t.assertEqual(Plurals.form(ru, 5), "many")
t.assertEqual(Plurals.form(ru, 11), "many")

-- English and German have two forms.
for count, expected in pairs({ [0] = "0 moves", [1] = "1 move", [2] = "2 moves", [11] = "11 moves", [21] = "21 moves" }) do
	t.assertEqual(Plurals.format(en, "moveCount", count), expected, "en moves: " .. count)
end
for count, expected in pairs({ [0] = "0 Züge", [1] = "1 Zug", [2] = "2 Züge", [21] = "21 Züge" }) do
	t.assertEqual(Plurals.format(de, "moveCount", count), expected, "de moves: " .. count)
end
t.assertEqual(Plurals.format(en, "ratingsCount", 1), "1 rating")
t.assertEqual(ReaderStatus.toast(en, 1), "+1 point")
t.assertEqual(ReaderStatus.toast(de, -5), "−5 Punkte")
t.assertThrows(function() Plurals.format({ pluralRule = "klingon" }, "moveCount", 1) end, "an unknown rule is refused")
t.assertThrows(function() Plurals.format({ pluralRule = "oneOther" }, "moveCount", 1) end, "a missing form is refused")

-- Every language declares the forms its rule distinguishes, for every counted noun.
for _, language in ipairs(Languages.list()) do
	local strings = Words.load(language.id)
	for _, noun in ipairs({ "moveCount", "pointCount", "ratingsCount" }) do
		for _, form in ipairs(Plurals.forms(strings.pluralRule)) do
			t.expect(strings[noun .. "_" .. form] ~= nil, language.id .. " has " .. noun .. "_" .. form)
		end
	end
end

-- ── The language list ──────────────────────────────────────────────────
t.assertEqual(Languages.find("ru").title, "Русский")
t.assertEqual(Languages.speechLocale("ru"), "ru-RU", "dictation listens in Russian")
local has = { en = true, de = true, ru = true }
for _, tag in ipairs({ "ru-RU", "ru-BY", "ru-UA", "ru-KZ", "ru_RU", "ru" }) do
	t.assertEqual(Languages.preferred({ tag }, has), "ru", tag .. " is Russian")
end
t.assertEqual(Languages.preferred({ "uk-UA", "ru-UA" }, has), "ru", "an unsupported first preference is skipped")
t.assertEqual(Languages.preferred({ "ru-RU" }, { en = true }), "en", "no Russian catalog: English")
t.assertEqual(Languages.lower("МЕРИДИАН Ёж"), "меридиан ёж", "Cyrillic capitals fold")
t.assertEqual(Languages.lower("ЀЍ"), "ѐѝ", "the extended capitals fold too")
t.assertEqual(Languages.fold("Ёлка"), "елка", "search reads ё as е")
t.assertEqual(Languages.fold("Straße ÖFFNEN"), "straße öffnen", "German folds as before")

-- ── The edition ────────────────────────────────────────────────────────
t.assertEqual(#russianCatalog, 1, "the Russian library holds the Russian edition of Blackout")
local entry, english = russianCatalog[1], nil
for _, game in ipairs(englishCatalog) do if game.id == "books.en.blackout-at-meridian" then english = game end end
t.assertEqual(entry.id, "books.ru.blackout-at-meridian")
t.assertEqual(entry.collection, "Оригинальные приключения")
t.assertEqual(entry.title, "Огни Меридиана")
t.assertEqual(entry.genre, "Супергеройская ролевая игра")
t.assertEqual(entry.statusLine, "moves")
t.assertEqual(entry.ruleset, english.ruleset, "the rules are the English edition's")
t.assertEqual(entry.cover, english.cover, "the editions share one cover")
t.assertEqual(entry.startFile, "blackout-at-meridian.zil")
t.assertEqual(require("apps.adventure-arena.models.Adventures").genreSymbol(entry.genre), "bolt.fill", "the genre has its symbol")

-- The catalog matches the engine manifest and boots the real Russian story.
local folder = "apps/adventure-arena/zilscript/" .. entry.id:gsub("%.", "/")
local manifest = assert(io.open(folder .. "/game.json", "r"))
local story = jsonParse(manifest:read("*a"))
manifest:close()
t.assertEqual(entry.title, story.title, "the title matches the story manifest")
t.assertEqual(entry.shortDescription, story.shortDescription)
t.assertEqual(entry.description, story.description)
local Runtime = require("apps.adventure-arena.services.ZILRuntime")
local book = Session.new { engineFactory = function(game, seed) return Runtime.new(game, nil, seed) end,
	newSeed = function() return 7 end }
local game = { language = "ru" }
for key, value in pairs(entry) do game[key] = value end
t.expect(book:start(game), "the Russian edition boots through the app runtime")
t.assertEqual(book.currentGame.language, "ru")
t.assertEqual(book:presentation().language, "ru", "the presentation carries the story language")
t.expect(#book:suggestions("") > 0, "the reader offers commands in Russian")
t.assertEqual(book:presentation().progress, "Ходы: 0", "the engine status line counts in Russian")

os.exit(t.summary() and 0 or 1)
