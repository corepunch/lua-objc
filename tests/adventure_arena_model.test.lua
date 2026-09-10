_G.__headless = true

local t = require("TestKit")
local Model = require("examples.adventure-arena.Model")
local catalog = Model.new()

t.assertEqual(#catalog:listGames(), 9, "AdventureArena catalog contains the complete Lua catalog")
t.assertEqual(catalog:game("infocom.zork1").title,
	"Zork I: The Great Underground Empire",
	"catalog resolves games by stable id")
t.assertEqual(#catalog:featured(), 3, "featured catalog is bounded")

t.expect(catalog:listGames()[1].cover:find("examples/adventure-arena/assets/", 1, true) == 1,
	"catalog records use bundled cover assets")
t.expect(catalog:game("missing") == nil, "unknown game ids return nil")

t.assertEqual(catalog:listGames()[1].id, "infocom.planetfall", "catalog is sorted by title")
t.assertEqual(catalog:featured()[2].id, "books.blackwood-horror", "second featured game matches source")
t.assertEqual(catalog:featured()[3].id, "infocom.spellbreaker", "third featured game matches source")
local expectedCounts = { ["infocom.spellbreaker"] = 891, ["infocom.zork2"] = 1872,
	["infocom.zork3"] = 1567, ["books.limehouse-killings"] = 342 }
for id, count in pairs(expectedCounts) do
	t.assertEqual(catalog:game(id).reviewCount, count, "source review count for " .. id)
end
local reviews = 0
for _, game in ipairs(catalog:listGames()) do
	reviews = reviews + #game.reviews
	t.expect(#game.description > 200, "complete source description for " .. game.id)
end
t.assertEqual(reviews, 21, "all individual source reviews are preserved")
t.assertEqual(catalog:game("books.limehouse-killings").genres[1], "Victorian Mystery")

local commands = {}
local state = Model.new({ engineFactory = function(game, ...)
	t.assertEqual(game.id, catalog:listGames()[1].id, "model resolves engine input by id")
	t.assertEqual(select("#", ...), 0, "engine receives domain data without a UI platform")
	return { start = function()
		return { resume = function(_, command)
			commands[#commands + 1] = command
			if command == "fail" then error("command failure") end
			return "You look around."
		end }, "An opening."
	end }
end })
t.expect(state:startSession(catalog:listGames()[1].id), "session starts through injected runtime")
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
t.expect(not state:startSession(catalog:listGames()[2].id), "startup errors are caught")
t.assertEqual(state:transcript(), before, "failed startup preserves current session")
t.assertEqual(state.currentGame.id, catalog:listGames()[1].id, "failed startup preserves game identity")

local engine = state.engine
t.expect(not state:startSession("missing"), "missing game is rejected before startup")
t.assertEqual(state.engine, engine, "missing game preserves current engine")
t.assertEqual(state:transcript(), before, "missing game preserves transcript")
t.assertEqual(catalog:transcript(), "", "session mutations do not leak between models")
t.expect(not catalog:startSession(catalog:listGames()[1].id), "missing engine is a model error")
t.expect(not catalog:submit("look"), "commands without a session leave state untouched")

local empty = Model.new { games = {} }
t.assertEqual(#empty:listGames(), 0, "empty catalog stays empty")
t.assertEqual(#empty:featured(), 0, "empty catalog has no featured records")
t.assertEqual(empty:game(catalog:listGames()[1].id), nil, "instance queries never fall back to global catalog")
local one = Model.new { games = { catalog:listGames()[2] } }
t.assertEqual(#one:featured(), 1, "featured query handles a short catalog")
t.assertEqual(one:featured()[1].id, catalog:listGames()[2].id, "featured query uses instance order")
local result = one:listGames()
result[1] = nil
t.assertEqual(#one:listGames(), 1, "editing a query result list leaves the catalog intact")

os.exit(t.summary() and 0 or 1)
