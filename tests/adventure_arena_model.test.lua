_G.__headless = true

local t = require("TestKit")
local Adventures = require("apps.adventure-arena.models.Adventures")
local Session = require("apps.adventure-arena.models.Session")
local Store = require("apps.adventure-arena.Store")
Store.new()
local catalog = Adventures

t.assertEqual(#catalog:all(), 9, "AdventureArena catalog contains the complete Lua catalog")
t.assertEqual(catalog:find("infocom.zork1").title,
	"Zork I: The Great Underground Empire",
	"catalog resolves games by stable id")
t.assertEqual(#catalog:featured(), 3, "featured catalog is bounded")

t.expect(catalog:all()[1].cover:find("apps/adventure-arena/assets/", 1, true) == 1,
	"catalog records use bundled cover assets")
t.expect(catalog:find("missing") == nil, "unknown game ids return nil")

t.assertEqual(catalog:all()[1].id, "infocom.planetfall", "catalog is sorted by title")
t.assertEqual(catalog:featured()[2].id, "books.blackwood-horror", "second featured game matches source")
t.assertEqual(catalog:featured()[3].id, "infocom.spellbreaker", "third featured game matches source")
local expectedCounts = { ["infocom.spellbreaker"] = 891, ["infocom.zork2"] = 1872,
	["infocom.zork3"] = 1567, ["books.limehouse-killings"] = 342 }
for id, count in pairs(expectedCounts) do
	t.assertEqual(catalog:find(id).reviewCount, count, "source review count for " .. id)
end
local reviews = 0
for _, game in ipairs(catalog:all()) do
	reviews = reviews + #game.reviews
	t.expect(#game.description > 200, "complete source description for " .. game.id)
end
t.assertEqual(reviews, 21, "all individual source reviews are preserved")
t.assertEqual(catalog:find("books.limehouse-killings").genre, "Victorian Mystery")
for _, game in ipairs(catalog:all()) do
	t.expect(type(game.collection) == "string", "every game belongs to a library shelf: " .. game.id)
	t.expect(game.tint:match("^#%x%x%x%x%x%x$") ~= nil, "every game has a hex accent: " .. game.id)
	t.expect(type(game.titleFont) == "string", "every game names its title typeface: " .. game.id)
	t.expect(game.tintDark and game.tintDark:match("^#%x%x%x%x%x%x$") ~= nil, "every game has a dark-page ink: " .. game.id)
	t.assertEqual(game.ink, game.tint .. "|" .. game.tintDark, "the page ink pairs both variants: " .. game.id)
	-- White type on the tint (Play buttons, genre tiles) must reach WCAG AA.
	local function luminance(hex)
		local total = 0
		for index, weight in ipairs({ 0.2126, 0.7152, 0.0722 }) do
			local channel = tonumber(hex:sub(index * 2, index * 2 + 1), 16) / 255
			channel = channel <= 0.03928 and channel / 12.92 or ((channel + 0.055) / 1.055) ^ 2.4
			total = total + weight * channel
		end
		return total
	end
	t.expect(1.05 / (luminance(game.tint) + 0.05) >= 4.5, "white type on the tint reaches 4.5:1: " .. game.id)
	t.expect(({ Introductory = true, Standard = true, Advanced = true, Expert = true })[game.difficulty],
		"difficulty uses Infocom's published levels: " .. game.id)
end

local commands = {}
local state = Session.new({ engineFactory = function(game, ...)
	t.assertEqual(game.id, catalog:all()[1].id, "session runtime receives domain data")
	local extra = { ... }
	t.expect(#extra == 1 and type(extra[1]) == "number", "the engine receives domain data and a seed, never a UI platform")
	return { start = function()
		return { resume = function(_, command)
			table.insert(commands, command)
			if command == "fail" then error("command failure") end
			return "You look around."
		end }, "An opening."
	end }
end })
local function transcriptText(session)
	local parts = {}
	for _, entry in ipairs(session:presentation().entries) do
		if entry.kind == "command" then table.insert(parts, "> " .. entry.text) end
		if entry.initial then table.insert(parts, entry.initial .. entry.lead) end
		for _, paragraph in ipairs(entry.paragraphs or {}) do table.insert(parts, paragraph) end
	end
	return table.concat(parts, "\n\n")
end
t.expect(state:start(catalog:all()[1]), "session starts through injected runtime")
t.assertEqual(transcriptText(state), "An opening.", "opening belongs to model")
t.expect(not state:submit("   "), "empty commands do not advance engine")
t.assertEqual(#commands, 0, "empty input leaves runtime untouched")
t.expect(state:submit("  look  "), "typed commands reach runtime")
t.assertEqual(commands[1], "look", "input is trimmed before execution")
t.expect(transcriptText(state):find("> look", 1, true), "transcript retains command")
t.expect(not state:submit("fail"), "runtime errors are reported without dropping prior output")
t.expect(transcriptText(state):find("An opening.", 1, true), "errors preserve prior transcript")
local before = transcriptText(state)
state.engineFactory = function() error("start failure") end
t.expect(not state:start(catalog:all()[2]), "startup errors are caught")
t.assertEqual(transcriptText(state), before, "failed startup preserves current session")
t.assertEqual(state.currentGame.id, catalog:all()[1].id, "failed startup preserves game identity")

local engine = state.engine
t.expect(not state:start(nil), "missing game is rejected before startup")
t.assertEqual(state.engine, engine, "missing game preserves current engine")
t.assertEqual(transcriptText(state), before, "missing game preserves transcript")

local first, second = catalog:all()[1], catalog:all()[2]
Store.new { games = {} }
local empty = Adventures
t.assertEqual(#empty:all(), 0, "empty catalog stays empty")
t.assertEqual(#empty:featured(), 0, "empty catalog has no featured records")
t.assertEqual(empty:find(first.id), nil, "queries read the bound store, never the bundled catalog")
Store.new { games = { second } }
local one = Adventures
t.assertEqual(#one:featured(), 1, "featured query handles a short catalog")
t.assertEqual(one:featured()[1].id, second.id, "featured query uses the store's order")
local result = one:all()
result[1] = nil
t.assertEqual(#one:all(), 1, "editing a query result list leaves the catalog intact")

os.exit(t.summary() and 0 or 1)
