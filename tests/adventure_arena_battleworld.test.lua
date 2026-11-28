local t = require("TestKit")
local Store = require("apps.adventure-arena.Store")
local Adventures = require("apps.adventure-arena.models.Adventures")
local Session = require("apps.adventure-arena.zilscript.zilscript.reader.Session")
local Runtime = require("apps.adventure-arena.services.ZILRuntime")

local function reader()
	return Session.new { engineFactory = function(game, seed)
		return Runtime.new(game, nil, seed)
	end, newSeed = function() return 97 end }
end

for _, edition in ipairs({
	{ language = "en", title = "The Last Door of Battleworld", hero = "Storm", north = "north", ridge = "The Ridge" },
	{ language = "ru", title = "Последняя дверь Мира битв", hero = "Гроза", north = "север", ridge = "Гребень холма" },
}) do
	Store.new { language = edition.language }
	local game = assert(Adventures:search(edition.title)[1])
	t.assertEqual(game.id, "books." .. edition.language .. ".last-door-of-battleworld")
	local cover = assert(io.open(game.cover, "rb"))
	t.assertEqual(cover:read(2), "\255\216", "catalog artwork is a JPEG")
	cover:close()
	local book = reader()
	local setup = assert(book:prepare(game))
	t.assertEqual(#setup.profiles, 3)
	for _, profile in ipairs(setup.profiles) do
		local portrait = assert(io.open(profile.portrait, "rb"))
		t.assertEqual(portrait:read(8), "\137PNG\r\n\26\n")
		portrait:close()
	end
	t.assertEqual(setup.profiles[2].title, edition.hero)
	t.expect(book:start(game, nil, { id = "storm" }, setup))
	t.expect(book:submit(edition.north))
	t.assertEqual(book.roomTitle, edition.ridge)
	local saved = book:snapshot()
	local resumed = reader()
	t.expect(resumed:start(game, saved))
	t.assertEqual(resumed.roomTitle, edition.ridge)
	t.assertEqual(resumed.engine:characterSheet().name, edition.hero)
	t.assertEqual(resumed.engine:characterSheet().portrait, setup.profiles[2].portrait, "printed sheet uses the selected card portrait")
end
os.exit(t.summary() and 0 or 1)
