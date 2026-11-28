_G.__headless = true
local t = require("TestKit")
local Store = require("apps.adventure-arena.Store")
local Adventures = require("apps.adventure-arena.models.Adventures")
local Session = require("apps.adventure-arena.zilscript.zilscript.reader.Session")
local Runtime = require("apps.adventure-arena.services.ZILRuntime")

Store.new()
local titles = {
	["books.en.bell-grew-leaves"] = "The Bell That Grew Leaves",
	["books.en.borrowed-tomorrows"] = "The Library of Borrowed Tomorrows",
	["books.en.house-of-the-ebb"] = "House of the Ebb",
	["books.en.museum-unsent-signals"] = "The Museum of Unsent Signals",
	["books.en.station-minus-one"] = "The Station at Minus One",
	["books.en.the-midnight-ledger"] = "The Midnight Ledger",
}
for id, title in pairs(titles) do
	local book = Adventures:find(id)
	t.expect(book ~= nil, id .. " is in the library")
	if book then
		t.assertEqual(book.title, title, "catalog preserves the book's title")
		t.expect(#Adventures:search(title) > 0, title .. " is searchable")
		local cover = io.open(book.cover, "rb")
		t.expect(cover ~= nil, title .. " has its bundled cover")
		if cover then
			t.assertEqual(cover:read(2), "\255\216", "cover is a JPEG")
			cover:close()
		end
		local function factory(game, seed) return Runtime.new(game, nil, seed) end
		local session = Session.new { engineFactory = factory, newSeed = function() return 42 end }
		local started = session:start(book)
		t.expect(started, title .. " starts through the app runtime")
		if started then
			local banner = session.entries[1]
			t.assertEqual(banner.kind, "banner", "the story opens with a printed banner")
			t.assertEqual(banner.title, book.title, "the printed title matches the catalog")
			t.assertEqual(banner.lines[1], book.author .. ", " .. book.year, "the story prints its own credits")
			t.expect(session.scene ~= nil, title .. " has an opening scene")
			t.assertEqual(session.engine.roomIcon, nil, title .. " has no room artwork API")
			t.expect(session:submit("look"), title .. " accepts a command")
			local restored = Session.new { engineFactory = factory }
			t.expect(restored:start(book, session:snapshot()), title .. " restores its saved session")
			t.assertEqual(restored.roomTitle, session.roomTitle, title .. " restores the room")
		end
	end
end
os.exit(t.summary() and 0 or 1)
