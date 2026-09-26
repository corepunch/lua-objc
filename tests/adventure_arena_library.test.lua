_G.__headless = true
local t = require("TestKit")
local Adventures = require("apps.adventure-arena.models.Adventures")

-- The library is designed for 20-30 adventures; build a synthetic 30-game
-- catalog so shelf, chart and search limits are exercised past today's nine.
local collections = { "The Zork Trilogy", "Infocom Classics", "Arena Originals", "Mysteries" }
local genres = { "Classic Adventure", "Sci-Fi Adventure", "Psychological Horror", "Victorian Mystery", "Fantasy Adventure" }
local games = {}
for index = 1, 30 do
	table.insert(games, {
		id = "game." .. index,
		title = "Adventure " .. index,
		author = index % 2 == 0 and "Infocom" or "Studio Null",
		genre = genres[(index % #genres) + 1],
		collection = index <= 12 and collections[2] or collections[(index % 3) + 1],
		shortDescription = index == 7 and "A wizard's tower." or "A story.",
		rating = 3 + (index % 10) / 5, reviewCount = index * 10, year = 1980 + index,
		tint = "#123456", difficulty = "Standard",
	})
end
local library = Adventures.new { games = games }

local shelves = library:shelves()
t.assertEqual(shelves[1].title, "Infocom Classics", "shelves follow the catalog's editorial order")
local total = 0
for _, shelf in ipairs(shelves) do
	total = total + shelf.count
	t.expect(#shelf.games <= 10, "a shelf carousel is capped: " .. shelf.title)
	t.expect(#shelf.games <= shelf.count, "a shelf never shows more games than it has")
end
t.assertEqual(total, 30, "every game appears on exactly one shelf")
t.assertEqual(shelves[1].count, 18, "shelf counts include games beyond the carousel")
t.assertEqual(#library:collection("Infocom Classics"), 18, "See All lists the whole collection")
t.assertEqual(#library:collection("Victorian Mystery"), 6, "genres are browsable collections too")
t.assertEqual(#library:collection("Nothing"), 0, "unknown collections are empty")

local top = library:topRated()
t.assertEqual(#top, 5, "the chart shows five adventures")
t.assertEqual(top[1].rank, 1, "chart entries carry their rank")
for index = 2, #top do
	local a, b = top[index - 1].game, top[index].game
	t.expect(a.rating > b.rating or (a.rating == b.rating and a.reviewCount >= b.reviewCount),
		"chart is ordered by rating, then review count")
end
t.assertEqual(#library:topRated(50), 30, "a long chart is bounded by the catalog")

local tiles = library:genres()
t.assertEqual(#tiles, #genres, "one genre tile per distinct genre")
local tileCount = 0
for _, tile in ipairs(tiles) do tileCount = tileCount + tile.count end
t.assertEqual(tileCount, 30, "genre tiles cover the catalog")

t.assertEqual(#library:search(""), 0, "an empty query shows the browse state, not results")
t.assertEqual(#library:search("   "), 0, "a blank query shows the browse state")
t.assertEqual(library:search("wizard")[1].id, "game.7", "search matches descriptions")
t.assertEqual(#library:search("WIZARD Studio"), 1, "search is case-insensitive across fields")
t.assertEqual(#library:search("wizard mystery"), 0, "every query term must match")
t.assertEqual(library:search("adventure 30")[1].id, "game.30", "search matches years and titles")
t.assertEqual(#library:search("infocom mysteries"), #library:search("infocom mysteries"), "search is stable")
t.assertEqual(#library:search("zzzz"), 0, "unmatched queries return no results")
local mixed = library:search("studio 7")
t.assertEqual(mixed[1].id, "game.7", "title matches rank ahead of other fields")

local related = library:related("game.1")
t.expect(#related > 0 and #related <= 6, "detail offers a bounded 'More in' shelf")
for _, game in ipairs(related) do t.expect(game.id ~= "game.1", "related games exclude the current one") end
t.assertEqual(#library:related("missing"), 0, "unknown ids have no related games")

-- Real catalog: three shelves of three, Zork trilogy together.
local real = Adventures.new()
local realShelves = {}
for _, shelf in ipairs(real:shelves()) do realShelves[shelf.title] = shelf.count end
t.assertEqual(realShelves["The Zork Trilogy"], 3, "the Zork trilogy shares a shelf")
t.assertEqual(realShelves["Infocom Classics"], 3, "classic Infocom titles share a shelf")
t.assertEqual(realShelves["Arena Originals"], 3, "studio titles share a shelf")
t.assertEqual(real:related("infocom.zork1")[1].id, "infocom.zork2", "Zork I suggests the rest of the trilogy")
t.assertEqual(#real:search("zork"), 3, "searching Zork finds the trilogy")

os.exit(t.summary() and 0 or 1)
