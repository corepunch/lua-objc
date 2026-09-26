_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local SavedGames = require("apps.adventure-arena.models.SavedGames")
local JsonDocument = require("apps.adventure-arena.services.JsonDocument")
local Session = require("apps.adventure-arena.models.Session")
local Adventures = require("apps.adventure-arena.models.Adventures")
local ZILRuntime = require("apps.adventure-arena.services.ZILRuntime")

-- ── The model keeps one autosave per adventure, newest first ─────────────
local written
local clock = 100
local memory = { load = function() return written end, save = function(value) written = value end }
local saves = SavedGames.new { store = memory, clock = function() return clock end }
t.assertEqual(#saves:list(), 0, "a new library has no saved games")
t.expect(not saves:record({ gameId = "zork", commands = {} }),
	"opening a story without playing it is not saved")
t.expect(not saves:record({ commands = { "look" } }), "a save needs a game")
t.expect(saves:record({ gameId = "zork", seed = 7, commands = { "open mailbox" }, chapter = 1, room = "West of House" }),
	"a played story is saved")
clock = 200
saves:record({ gameId = "planetfall", seed = 9, commands = { "up" }, chapter = 2, room = "Gangway" })
t.assertEqual(saves:latest().gameId, "planetfall", "the most recently played story comes first")
clock = 300
saves:record({ gameId = "zork", seed = 7, commands = { "open mailbox", "read leaflet" }, chapter = 1, room = "West of House" })
t.assertEqual(saves:latest().gameId, "zork", "playing again moves a story to the front")
t.assertEqual(#saves:find("zork").commands, 2, "a save replaces the previous one for the same story")
t.assertEqual(written.version, 1, "the store receives a versioned document")
t.assertEqual(#written.games, 2, "every saved story is persisted")

local reloaded = SavedGames.new { store = memory }
t.assertEqual(#reloaded:list(), 2, "saves survive a relaunch")
t.assertEqual(reloaded:find("planetfall").room, "Gangway", "saved details survive a relaunch")
t.expect(reloaded:remove("planetfall"), "a saved story can be removed")
t.expect(not reloaded:remove("planetfall"), "removing twice reports nothing removed")
t.assertEqual(#SavedGames.new({ store = memory }):list(), 1, "removal is persisted")

local corrupt = SavedGames.new { store = { load = function() return { version = 99, games = { 1, 2 } } end } }
t.assertEqual(#corrupt:list(), 0, "an unknown save format is an empty library")
local broken = SavedGames.new { store = { load = function() return { version = 1, games = { { gameId = 3 } } } end } }
t.assertEqual(#broken:list(), 0, "malformed records are skipped")
t.assertEqual(#SavedGames.new():list(), 0, "the model works without a store")

-- ── The store is JSON in the platform document folder ─────────────────
local documents = {}
local fakeNs = {
	_documentRead = function(name) return documents[name] end,
	_documentWrite = function(name, body) documents[name] = body return true end,
	_jsonEncode = ns._jsonEncode,
	json_parse = ns.json_parse,
}
local store = JsonDocument.new(fakeNs, "test/saves.json")
t.expect(store.load() == nil, "a missing save file loads as nothing")
store.save({ version = 1, games = { { gameId = "zork", commands = { "look" } } } })
t.expect(documents["test/saves.json"]:find('"zork"', 1, true) ~= nil, "the store writes JSON")
t.assertEqual(store.load().games[1].commands[1], "look", "the store reads back what it wrote")
documents["test/saves.json"] = "{not json"
t.expect(store.load() == nil, "an unreadable file loads as nothing")
t.expect(JsonDocument.new({}, "x.json").load() == nil, "a platform without documents loads nothing")

-- ── A seeded engine replays the same story ────────────────────────────
local sequence = ZILRuntime.random(42)
local again = ZILRuntime.random(42)
local draws = {}
for index = 1, 20 do
	local value = sequence(1, 6)
	table.insert(draws, value)
	t.expect(value >= 1 and value <= 6, "random(m, n) stays in range")
	t.assertEqual(again(1, 6), value, "the same seed draws the same sequence")
end
local unit = ZILRuntime.random(5)()
t.expect(unit >= 0 and unit < 1, "random() is a unit float")
local single = ZILRuntime.random(5)(3)
t.expect(single >= 1 and single <= 3, "random(n) draws from 1 to n")

local catalog = Adventures.new()
-- The runtime routes io.open through this reader while it runs.
local open = io.open
local function readFile(path)
	local file = open(path, "r")
	if not file then return nil end
	local body = file:read("*a")
	file:close()
	return body
end
local function play(seed)
	local session = Session.new {
		engineFactory = function(game, gameSeed) return ZILRuntime.new(game, readFile, gameSeed) end,
		newSeed = function() return seed end,
	}
	return session
end
local planetfall = catalog:find("infocom.planetfall")
local first = play(1234)
t.expect(first:start(planetfall), "Planetfall starts with a seed")
for _, command in ipairs({ "look", "wait", "up", "look" }) do first:submit(command) end
local snapshot = first:snapshot()
t.assertEqual(snapshot.gameId, planetfall.id, "the snapshot names its game")
t.assertEqual(snapshot.seed, 1234, "the snapshot keeps the seed")
t.assertEqual(#snapshot.commands, 4, "the snapshot keeps every command")

local resumed = play(999)
t.expect(resumed:start(planetfall, snapshot), "a saved game resumes")
t.assertEqual(resumed.moves, first.moves, "the ship's clock resumes at the same time")
t.assertEqual(resumed.roomTitle, first.roomTitle, "the story resumes in the same room")
t.assertEqual(resumed.chapters, first.chapters, "the same chapters are rebuilt")
t.assertEqual(#resumed.entries, #first.entries, "the whole transcript is rebuilt")
t.assertEqual(resumed.scoreChange, 0, "replaying does not announce old points")
local last = resumed.entries[#resumed.entries]
local original = first.entries[#first.entries]
t.assertEqual(table.concat(last.paragraphs or {}, "\n"), table.concat(original.paragraphs or {}, "\n"),
	"the last page reads the same after resuming")

os.exit(t.summary() and 0 or 1)
