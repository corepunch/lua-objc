_G.__headless = true
local t = require("TestKit")
local Session = require("apps.adventure-arena.zilscript.zilscript.reader.Session")
local Runtime = require("apps.adventure-arena.services.ZILRuntime")
local catalog = require("apps.adventure-arena.catalog.Adventures")
local titles = {
	["books.pocket-weather"] = "The Pocket Weather Bureau",
	["books.silent-vector"] = "The Silent Vector",
	["books.last-broadcast"] = "The Last Broadcast",
}
local function engineFactory(book, seed) return Runtime.new(book, nil, seed) end
local count = 0
for _, book in ipairs(catalog) do
	if titles[book.id] then
		count = count + 1
		t.assertEqual(book.title, titles[book.id], "new story identity matches its library entry")
		t.assertEqual(book.collection, "Arena Originals", "new stories belong to the originals shelf")
		t.assertEqual(book.author, "Studio Null", "cover and catalog have the same credit")
		t.assertEqual(book.year, 2026, "new stories carry their actual release year")
		t.assertEqual(book.rating, 0, "unreviewed books have no fabricated ratings")
		t.assertEqual(book.reviewCount, 0, "unreviewed books have no fabricated reader counts")
		t.assertEqual(#book.reviews, 0, "no illustrative review is published as real feedback")
		local cover = assert(io.open(book.cover, "rb"))
		t.assertEqual(cover:read(8), "\137PNG\13\10\26\10", "new cover is a real bundled PNG")
		cover:close()
		local session = Session.new { engineFactory = engineFactory, newSeed = function() return 2026 end }
		t.expect(session:start(book), "library entry boots its own real story through the app runtime")
		t.expect(#session.items > 0 and session.scene ~= nil, "opening exposes the actual room and its objects")
		t.assertEqual(Session.statusLine(book, 0, 0, 7), "7 moves", "scoreless stories show turns rather than an invented score")
		local first = session.roomTitle
		local command
		for _, links in ipairs(session.scene.links or {}) do
			for _, link in ipairs(links) do
				for _, action in ipairs(session:linkActions(link.target)) do
					if action.command:match("^examine ") then command = action.command; break end
				end
				if command then break end
			end
			if command then break end
		end
		t.expect(command ~= nil, "opening prose provides an actual examination affordance")
		t.expect(session:submit(command), "a supplied reader command executes")
		t.assertEqual(session.roomTitle, first, "examining does not silently change rooms")
		local saved = session:snapshot()
		local restored = Session.new { engineFactory = engineFactory }
		t.expect(restored:start(book, saved), "app saves resume the selected new title")
		t.assertEqual(restored.roomTitle, session.roomTitle, "resumed room matches")
		t.assertEqual(restored.score, session.score, "resumed score matches")
		t.assertEqual(#restored.items, #session.items, "resumed object scope matches")
		t.assertEqual(#restored:linkActions("nonexistent gateway"), 0, "prose cannot invent a physical interaction")
	end
end
t.assertEqual(count, 3, "all three new adventures are available in the real catalog")
local zork
for _, book in ipairs(catalog) do if book.id == "infocom.zork1" then zork = book end end
local classics = Runtime.new(zork, nil, 2026):start()
t.assertEqual(classics:progress().maxScore, 350, "runtime reads normalized ZIL score identifiers")
os.exit(t.summary() and 0 or 1)
