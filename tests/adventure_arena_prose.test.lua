_G.__headless = true
local t = require("TestKit")
local Runtime = require("apps.adventure-arena.services.ZILRuntime")
local Session = require("apps.adventure-arena.zilscript.zilscript.reader.Session")
local catalog = require("apps.adventure-arena.catalog.en")

local originals = {
	["books.blackwood-horror"] = true, ["books.wondertown"] = true,
	["books.limehouse-killings"] = true, ["books.pocket-weather"] = true,
	["books.silent-vector"] = true, ["books.last-broadcast"] = true,
}
local books, reads = 0, 0
local originalOpen = io.open
local function readFile(path)
	reads = reads + 1
	t.expect(not path:match("^apps/adventure%-arena/assets/"), "story runtime never requests artwork")
	local file, err = originalOpen(path, "rb")
	if not file then return nil, err end
	local contents = file:read("*a")
	file:close()
	return contents
end

for _, book in ipairs(catalog) do
	if originals[book.id] then
		books = books + 1
		for _, streamed in ipairs({ false, true }) do
			local function factory(game, seed)
				return Runtime.new(game, streamed and readFile or nil, seed)
			end
			local session = Session.new { engineFactory = factory, newSeed = function() return 42 end }
			local started, err = session:start(book)
			t.expect(started, book.id .. " starts locally and streamed without room art: " .. tostring(err))
			if not started then os.exit(1) end
			local banner, narration = session.entries[1], session.entries[2]
			t.assertEqual(narration.kind, "narration", "the story's opening narration precedes the first room")
			t.assertEqual(banner.kind, "banner", "the story prints its own opening credits")
			t.assertEqual(banner.title, book.title, "the story's printed title matches the catalog")
			t.assertEqual(banner.lines[1], book.author .. ", " .. book.year, "credits include the story's studio and year")
			t.assertEqual(banner.lines[2], "Release 1", "release appears after the credit")
			if book.id == "books.blackwood-horror" then
				t.expect(narration.paragraphs[1]:find("For three weeks the same dream", 1, true) == 1,
					"Sanitarium keeps its dream prologue directly under the credits")
				t.assertEqual(session.entries[3].title, "Sanitarium Gate", "Sanitarium opens its first room after the prologue")
			end
			if book.id == "books.silent-vector" then
				t.assertEqual(session.entries[3].title, "Restraint Cradle", "the first room follows the game's opening narration")
			end
			t.assertEqual(session.engine.roomIcon, nil, "the engine has no room artwork API")
			t.expect(session.scene and #session.scene.paragraphs > 0, "the opening scene retains its prose")
			t.assertEqual(session.scene.icon, nil, "scene records contain no artwork")
			t.expect(session:submit("look"), "the text-only reader accepts commands")
			local restored = Session.new { engineFactory = factory }
			t.expect(restored:start(book, session:snapshot()), "saved commands restore without artwork")
			t.assertEqual(restored.entries[1].title, banner.title, "the restored opening starts with the book title")
			t.assertEqual(restored.entries[2].paragraphs[1], narration.paragraphs[1], "restoring preserves the prologue")
			t.assertEqual(restored.roomTitle, session.roomTitle, "restoring preserves the current room")
			t.assertEqual(restored.moves, session.moves, "restoring preserves the move count")
			for _, entry in ipairs(restored.entries) do
				t.assertEqual(entry.icon, nil, "restored entries contain only text and prose actions")
			end
		end
	end
end

t.assertEqual(books, 6, "all six original books are covered")
t.expect(reads > 0, "streamed coverage exercises the injected file reader")
os.exit(t.summary() and 0 or 1)
