_G.__headless = true
local t = require("TestKit")
local Session = require("apps.adventure-arena.models.Session")

local function kinds(session)
	local list = {}
	for _, entry in ipairs(session:presentation().entries) do table.insert(list, entry.kind) end
	return table.concat(list, ",")
end

-- Plain engine: no room names, so the opening still opens Chapter I.
local session = Session.new({ engineFactory = function()
	return { start = function()
		return { resume = function(_, command)
			if command == "wait" then return nil end
			if command == "fail" then error("Engine failure", 0) end
			return "A doorway appears.", "extra result"
		end }, "Welcome."
	end }
end })
local game = { id = "test", title = "Test Story" }
t.expect(session:start(game), "session starts with an opening message")
t.assertEqual(session:presentation().progress, "Score 0 · 0 moves", "new session starts with empty progress")
local opening = session:presentation().entries[1]
t.assertEqual(opening.kind, "scene", "the opening starts a chapter")
t.assertEqual(opening.chapterLabel, "Chapter I", "chapters are numbered in roman numerals")
t.assertEqual(opening.title, "Test Story", "without a room name the chapter takes the game title")
t.assertEqual(opening.paragraphs[1], "Welcome.", "the chapter keeps its whole first paragraph; the view drops the initial")
t.expect(session:submit("  look  "), "trimmed command succeeds")
t.assertEqual(session:presentation().progress, "Score 0 · 1 move", "submitted commands increment the move count")
t.assertEqual(kinds(session), "scene,command,narration", "a command and its response append two entries")
t.assertEqual(session:presentation().entries[2].text, "look", "commands are stored trimmed")
t.assertEqual(session:presentation().entries[3].paragraphs[1], "A doorway appears.", "extra engine results are ignored")
t.expect(session:submit("wait"), "nil response is a successful command")
t.assertEqual(kinds(session), "scene,command,narration,command", "a silent response adds no empty narration")
t.expect(not session:submit("fail"), "engine failure is reported")
t.assertEqual(session:presentation().progress, "Score 0 · 3 moves", "failed game commands still count as moves")
local entries = session:presentation().entries
t.assertEqual(entries[#entries - 1].text, "fail", "failed command stays in sequence")
t.assertEqual(entries[#entries].paragraphs[1], "Engine failure", "error response follows failed command")
local count = #session.entries
t.expect(not session:submit("   "), "blank commands are rejected")
t.assertEqual(#session.entries, count, "rejected command leaves transcript unchanged")
t.assertEqual(session.currentGame, game, "appending messages preserves game identity")
t.assertEqual(#Session.new().entries, 0, "session histories remain independent")
t.assertEqual(session.history[1], "look", "command history is kept for the player")

-- Real Infocom output: banner paragraph, then a heading line naming the room.
local room = "Deck Nine"
local banner = "PLANETFALL\nInfocom interactive fiction - a science fiction story\n"
	.. "Copyright (c) 1983 by Infocom, Inc. All rights reserved.\nRelease 0 / Serial number 000000"
local story = Session.new({ engineFactory = function()
	return { start = function()
		return {
			resume = function(_, command)
				if command == "up" then room = "Gangway" return "Gangway\nA steep gangway.\n\n" end
				if command == "starboard" then room = "Reactor" return "The reactor hums.\n\n" end
				if command == "look" then return room .. "\nStill here.\n\n" end
				return "You can't go that way.\n\n"
			end,
			roomName = function() return room end,
		}, banner .. "\n\nAnother routine day.\n\nDeck Nine\nA featureless corridor.\nA brush lies here.\n\n"
	end }
end })
t.expect(story:start({ id = "planetfall", title = "Planetfall" }), "banner opening starts")
t.assertEqual(kinds(story), "banner,narration,scene", "banner, prologue, then the first room")
local entries = story:presentation().entries
t.assertEqual(entries[1].title, "PLANETFALL", "the banner keeps the story title")
t.assertEqual(#entries[1].lines, 3, "the banner keeps its credit lines")
t.assertEqual(entries[2].paragraphs[1], "Another routine day.", "prologue precedes the first chapter")
t.assertEqual(entries[3].title, "Deck Nine", "a heading line names the chapter")
t.assertEqual(entries[3].paragraphs[1], "A featureless corridor.\nA brush lies here.", "the heading line is not repeated")
t.assertEqual(story:presentation().roomTitle, "Deck Nine", "presentation names the active room")
story:submit("north")
t.assertEqual(kinds(story), "banner,narration,scene,command,narration", "a failed move is narration")
story:submit("look")
entries = story:presentation().entries
t.assertEqual(entries[#entries].kind, "narration", "looking again does not open a new chapter")
t.assertEqual(entries[#entries].paragraphs[1], "Still here.", "the repeated heading line is dropped")
story:submit("up")
entries = story:presentation().entries
t.assertEqual(entries[#entries].chapterLabel, "Chapter II", "a printed heading opens the next chapter")
t.assertEqual(entries[#entries].title, "Gangway", "the new chapter is named for the new room")
story:submit("starboard")
entries = story:presentation().entries
t.assertEqual(entries[#entries].title, "Reactor", "a room change without a heading still opens a chapter")
t.assertEqual(entries[#entries].paragraphs[1], "The reactor hums.", "that chapter opens with its description")
t.assertEqual(Session.roman(1994), "MCMXCIV", "roman numerals cover long games")

-- Openings that start with punctuation keep it and skip the initial.
local quoted = Session.new({ engineFactory = function()
	return { start = function() return { resume = function() return "" end }, "\"Hello,\" says a voice." end }
end })
quoted:start({ id = "q", title = "Q" })
t.assertEqual(quoted:presentation().entries[1].paragraphs[1], "\"Hello,\" says a voice.", "the text is untouched")

-- Long sessions: the reader renders only the most recent entries.
local long = Session.new({ engineFactory = function()
	return { start = function() return { resume = function(_, c) return "Echo " .. c end }, "Start." end }
end })
long:start({ id = "long", title = "Long" })
for index = 1, 100 do long:submit("wait " .. index) end
local recent, earlier = long:transcript(50)
t.assertEqual(#recent, 50, "the transcript is bounded")
t.assertEqual(earlier, 201 - 50, "the count of hidden entries is reported")
t.assertEqual(recent[#recent].paragraphs[1], "Echo wait 100", "the newest entry is kept")
t.assertEqual(long:presentation().earlierEntries, 201 - 120, "the default bound keeps 120 entries")

local progressEngine = {
	score = 4, moves = 2, maxScore = 20, exits = { "n", "east", "u" }, room = "Sanitarium Gate",
	items = { { "rusted gate", { "OPEN", "CLOSE" }, {} }, { "brass plaque", { "READ" }, {} } },
}
local tracked = Session.new({ engineFactory = function()
	return { start = function()
		return {
			resume = function(_, command)
				progressEngine.moves = progressEngine.moves + 1
				if command == "solve" then progressEngine.score = 5 end
				if command == "take plaque" then progressEngine.items = { progressEngine.items[1] } end
				return "Updated."
			end,
			progress = function() return progressEngine end,
			exits = function() return progressEngine.exits end,
			roomName = function() return progressEngine.room end,
			items = function() return progressEngine.items end,
		}, "Welcome."
	end }
end })
t.expect(tracked:start(game), "session starts with game progress")
t.assertEqual(tracked:presentation().progress, "Score 4 of 20 · 2 moves", "presentation uses engine score and move totals")
t.expect(tracked:hasExit("north"), "full exit names are available to the compass")
t.expect(tracked:hasExit("e"), "exit abbreviations normalize for compass selection")
t.expect(tracked:hasExit("up"), "vertical exits are recognised")
t.expect(not tracked:hasExit("south"), "unavailable exits stay disabled")
t.assertEqual(table.concat(tracked.exitList, ","), "north,east,up", "exits are listed in compass order")
t.assertEqual(tracked:presentation().roomTitle, "Sanitarium Gate", "runtime room name replaces the game title")
t.assertEqual(tracked:presentation().gameDescription, "", "missing synopsis renders as empty text")
t.assertEqual(#tracked.items, 2, "visible objects come from the engine")
t.expect(tracked:submit("solve"), "tracked session accepts a command")
t.assertEqual(tracked:presentation().progress, "Score 5 of 20 · 3 moves", "commands refresh live engine progress")
tracked:submit("take plaque")
t.assertEqual(#tracked.items, 1, "objects that left the room are no longer visible")
t.assertEqual(#tracked.knownItems, 2, "objects seen earlier stay suggestible")
local chips = {}
for _, chip in ipairs(tracked:suggestions("read ")) do table.insert(chips, chip.title) end
t.assertEqual(table.concat(chips, ","), "plaque", "suggestions use the remembered objects")

t.assertEqual(tracked.scoreChange, 0, "a command without points announces nothing")
t.assertEqual(tracked:presentation().progressFraction, 5 / 20, "progress is the share of the maximum score")

-- Scores that change are reported for the reader's "+5 points" moment.
progressEngine.score = 5
local scoring = Session.new({ engineFactory = function()
	return { start = function()
		return {
			resume = function(_, command) if command == "win" then progressEngine.score = 12 end return "Yes." end,
			progress = function() return progressEngine end,
		}, "Hello."
	end }
end })
scoring:start(game)
scoring:submit("win")
t.assertEqual(scoring.scoreChange, 7, "a scoring command reports the points it earned")

-- Planetfall's MOVES is its chronometer; its status line says so.
t.assertEqual(Session.statusLine({ statusLine = "time" }, 0, 0, 4595), "Score 0 · Time 4595",
	"time-keeping games show the clock, not a move count")
t.assertEqual(Session.statusLine({}, 1, 0, 1), "Score 1 · 1 move", "one move is singular")

-- Snapshots carry what a resume needs; the seed reaches the engine.
local seeds = {}
local seeded = Session.new({
	newSeed = function() return 77 end,
	engineFactory = function(_, seed)
		table.insert(seeds, seed)
		return { start = function() return { resume = function(_, c) return "Did " .. c end }, "Start." end }
	end,
})
seeded:start(game)
seeded:submit("look")
local snapshot = seeded:snapshot()
t.assertEqual(snapshot.seed, 77, "a new story gets a seed")
t.assertEqual(snapshot.commands[1], "look", "the snapshot keeps the commands")
t.assertEqual(snapshot.gameId, "test", "the snapshot names the story")
seeded:start(game, snapshot)
t.assertEqual(seeds[2], 77, "a resumed story reuses its seed")
t.assertEqual(#seeded.history, 1, "the saved commands are replayed")
t.assertEqual(seeded.entries[#seeded.entries].paragraphs[1], "Did look", "the replay rebuilds the transcript")
t.expect(Session.new():snapshot() == nil, "an unopened session has nothing to save")

os.exit(t.summary() and 0 or 1)
