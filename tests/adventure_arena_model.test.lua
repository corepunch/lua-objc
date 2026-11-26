_G.__headless = true

local t = require("TestKit")
local jsonParse = require("AppKit").json_parse
local Adventures = require("apps.adventure-arena.models.Adventures")
local Session = require("apps.adventure-arena.zilscript.zilscript.reader.Session")
local Store = require("apps.adventure-arena.Store")
Store.new()
local catalog = Adventures

t.assertEqual(#catalog:all(), 19, "the English library holds the complete English catalog and no other edition")
t.assertEqual(catalog:find("infocom.zork1").title,
	"Zork I: The Great Underground Empire",
	"catalog resolves games by stable id")

t.expect(catalog:all()[1].cover:find("apps/adventure-arena/assets/", 1, true) == 1,
	"catalog records use bundled cover assets")
t.expect(catalog:find("missing") == nil, "unknown game ids return nil")

t.assertEqual(catalog:all()[1].id, "infocom.planetfall", "catalog is sorted by title")
local reviews = 0
for _, game in ipairs(catalog:all()) do
	reviews = reviews + #game.reviews
	t.expect(#game.description > 0, "source description for " .. game.id)
	local storyFolder = game.id:gsub("%.", "/", 1)
	local manifest <close> = assert(io.open("apps/adventure-arena/zilscript/" .. storyFolder .. "/game.json", "r"))
	local story = jsonParse(manifest:read("*a"))
	t.assertEqual(game.shortDescription, story.shortDescription, "card summary matches the story manifest for " .. game.id)
	t.assertEqual(game.description, story.description, "synopsis matches the story manifest for " .. game.id)
	t.assertEqual(game.language, story.language or "en", "the catalog language matches the story manifest for " .. game.id)
end
t.assertEqual(reviews, 0, "bundled catalog contains no unsourced reader feedback")
t.assertEqual(catalog:find("books.limehouse-killings").genre, "Victorian Mystery")
for _, game in ipairs(catalog:all()) do
	t.expect(type(game.collection) == "string", "every game belongs to a library shelf: " .. game.id)
	t.expect(game.tint == nil and game.tintDark == nil and game.ink == nil and game.titleFont == nil,
		"games do not supply individual accents or title fonts: " .. game.id)
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
t.assertEqual(empty:find(first.id), nil, "queries read the bound store, never the bundled catalog")
Store.new { games = { second } }
local one = Adventures
t.assertEqual(one:all()[1].id, second.id, "the catalog reads the injected store")
local result = one:all()
result[1] = nil
t.assertEqual(#one:all(), 1, "editing a query result list leaves the catalog intact")

os.exit(t.summary() and 0 or 1)
