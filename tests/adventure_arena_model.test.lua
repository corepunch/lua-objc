_G.__headless = true

local t = require("TestKit")
local Model = require("examples.adventure-arena.Model")

t.assertEqual(#Model.games, 9, "AdventureArena catalog contains the complete Lua catalog")
t.assertEqual(Model.game("infocom.zork1").title,
	"Zork I: The Great Underground Empire",
	"catalog resolves games by stable id")
t.assertEqual(#Model.featured(), 3, "featured catalog is bounded")

t.assertEqual(Model.ratingLabel(Model.game("books.wondertown")), "4.7 (286)",
	"rating label preserves review count")
t.expect(Model.games[1].cover:find("examples/adventure-arena/assets/", 1, true) == 1,
	"catalog records use bundled cover assets")
t.expect(Model.game("missing") == nil, "unknown game ids return nil")

t.assertEqual(Model.games[1].id, "infocom.planetfall", "catalog is sorted by title")
t.assertEqual(Model.featured()[2].id, "books.blackwood-horror", "second featured game matches source")
t.assertEqual(Model.featured()[3].id, "infocom.spellbreaker", "third featured game matches source")
local expectedCounts = { ["infocom.spellbreaker"] = 891, ["infocom.zork2"] = 1872,
	["infocom.zork3"] = 1567, ["books.limehouse-killings"] = 342 }
for id, count in pairs(expectedCounts) do
	t.assertEqual(Model.game(id).reviewCount, count, "source review count for " .. id)
end
local reviews = 0
for _, game in ipairs(Model.games) do
	reviews = reviews + #game.reviews
	t.expect(#game.description > 200, "complete source description for " .. game.id)
end
t.assertEqual(reviews, 21, "all individual source reviews are preserved")
t.assertEqual(Model.game("books.limehouse-killings").genres[1], "Victorian Mystery")

local commands = {}
local state = Model.new(function()
	return { start = function()
		return { resume = function(_, command)
			commands[#commands + 1] = command
			if command == "fail" then error("command failure") end
			return "You look around."
		end }, "An opening."
	end }
end)
t.expect(state:startSession(Model.games[1], {}), "session starts through injected runtime")
t.assertEqual(state:transcript(), "An opening.", "opening belongs to model")
t.expect(not state:submit("   "), "empty commands do not advance engine")
t.assertEqual(#commands, 0, "empty input leaves runtime untouched")
t.expect(state:submit("  look  "), "typed commands reach runtime")
t.assertEqual(commands[1], "look", "input is trimmed before execution")
t.expect(state:transcript():find("> look", 1, true), "transcript retains command")
t.expect(not state:submit("fail"), "runtime errors are reported without dropping prior output")
t.expect(state:transcript():find("An opening.", 1, true), "errors preserve prior transcript")
local before = state:transcript()
state.engineFactory = function() error("start failure") end
t.expect(not state:startSession(Model.games[2], {}), "startup errors are caught")
t.assertEqual(state:transcript(), before, "failed startup preserves current session")
t.assertEqual(state.currentGame.id, Model.games[1].id, "failed startup preserves game identity")

os.exit(t.summary() and 0 or 1)
