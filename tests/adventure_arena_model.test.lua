_G.__headless = true

local t = require("TestKit")
local Model = require("examples.adventure-arena.Model")

t.assertEqual(#Model.games, 3, "AdventureArena catalog has its initial games")
t.assertEqual(Model.game("infocom.zork1").title,
	"Zork I: The Great Underground Empire",
	"catalog resolves games by stable id")
t.assertEqual(#Model.featured(), 3, "featured catalog is bounded")
t.assertEqual(Model.ratingLabel(Model.games[1]), "4.8 (2341)",
	"rating label preserves review count")
t.expect(Model.game("missing") == nil, "unknown game ids return nil")

os.exit(t.summary() and 0 or 1)
