_G.__headless = true

local t = require("TestKit")
local Runtime = require("apps.adventure-arena.services.ZILRuntime")
local Session = require("apps.adventure-arena.zilscript.zilscript.reader.Session")
local catalog = require("apps.adventure-arena.catalog.Adventures")

local expected = {
	["infocom.zork1"] = "banner,scene",
	["infocom.zork2"] = "banner,scene",
	["infocom.zork3"] = "banner,narration,scene",
	["infocom.lurkinghorror"] = "banner,narration,scene",
	["infocom.planetfall"] = "banner,narration,scene",
	["infocom.spellbreaker"] = "banner,scene",
}
local count = 0
for _, game in ipairs(catalog) do
	if expected[game.id] then
		count = count + 1
		local original
		local session = Session.new {
			engineFactory = function(book, seed)
				return { start = function()
					local engine, output = Runtime.new(book, nil, seed):start()
					original = output
					return engine, output
				end }
			end,
			newSeed = function() return 42 end,
		}
		t.expect(session:start(game), game.title .. " starts")
		local kinds = {}
		for _, entry in ipairs(session.entries) do
			table.insert(kinds, entry.kind)
			if entry.kind == "banner" then
				local renderedBanner = entry.title .. "\n" .. table.concat(entry.lines, "\n")
				t.expect(original:find(renderedBanner, 1, true) ~= nil, game.title .. " keeps the printed credits in order")
			end
		end
		t.assertEqual(table.concat(kinds, ","), expected[game.id], game.title .. " opens with its title and credits")
		if game.id == "infocom.zork3" then
			t.expect(session.entries[2].paragraphs[1]:find("As in a dream", 1, true) == 1,
				"Zork III keeps its dream prologue directly under the credits")
			t.assertEqual(session.entries[3].title, "Endless Stair", "Zork III opens its first room after the prologue")
		end
	end
end
t.assertEqual(count, 6, "every bundled Infocom game is covered")

os.exit(t.summary() and 0 or 1)
