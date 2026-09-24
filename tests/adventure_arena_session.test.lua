_G.__headless = true
local t = require("TestKit")
local Session = require("apps.adventure-arena.models.Session")

local session = Session.new({ engineFactory = function()
	return { start = function()
		return { resume = function(_, command)
			if command == "wait" then return nil end
			if command == "fail" then error("Engine failure", 0) end
			return "A doorway appears.", "extra result"
		end }, "Welcome."
	end }
end })
local game = { id = "test" }
t.expect(session:start(game), "session starts with an opening message")
t.assertEqual(session:presentation().progress, "Score 0 | Moves 0", "new session starts with empty progress")
t.expect(session:submit("  look  "), "trimmed command succeeds")
t.assertEqual(session:presentation().progress, "Score 0 | Moves 1", "submitted commands increment the move count")
t.assertEqual(#session.messages, 3, "command and first response append exactly two entries")
t.assertEqual(session:presentation().transcript, "Welcome.\n\n> look\n\nA doorway appears.",
	"presentation preserves opening, command, and response order")
t.expect(session:submit("wait"), "nil response is a successful command")
t.assertEqual(#session.messages, 5, "nil response appends an empty message without a hole")
t.assertEqual(session.messages[5], "", "nil response is normalized to an empty string")
t.expect(not session:submit("fail"), "engine failure is reported")
t.assertEqual(session:presentation().progress, "Score 0 | Moves 3", "failed game commands still count as moves")
t.assertEqual(session.messages[6], "> fail", "failed command stays in sequence")
t.assertEqual(session.messages[7], "Engine failure", "error response follows failed command")
local before = session:presentation().transcript
t.expect(not session:submit("   "), "blank commands are rejected")
t.assertEqual(session:presentation().transcript, before, "rejected command leaves transcript unchanged")
t.assertEqual(session.currentGame, game, "appending messages preserves game identity")
t.assertEqual(#Session.new().messages, 0, "session histories remain independent")

local titled = Session.new({ engineFactory = function()
	return { start = function()
		return { resume = function() return "The room is quiet." end },
			"Sanitarium\n\nThe rusted gate stands open."
	end }
end })
t.expect(titled:start({ id = "sanitarium", title = "Sanitarium" }), "titled session starts")
t.assertEqual(titled:presentation().roomTitle, "Sanitarium", "presentation separates the room heading")
t.assertEqual(titled:presentation().transcript, "The rusted gate stands open.", "presentation separates the room description")
t.expect(titled:submit("look"), "titled session accepts a command")
t.assertEqual(titled:presentation().roomTitle, "Sanitarium", "command updates retain the room heading")
t.assertEqual(titled:presentation().transcript,
	"The rusted gate stands open.\n\n> look\n\nThe room is quiet.",
	"command updates preserve the formatted transcript body")
local progressEngine = {
	score = 4, moves = 2, maxScore = 20, exits = { "n", "east" }, room = "Sanitarium Gate",
}
local tracked = Session.new({ engineFactory = function()
	return { start = function()
		return {
			resume = function(_, command)
				progressEngine.moves = progressEngine.moves + 1
				if command == "solve" then progressEngine.score = 5 end
				return "Updated."
			end,
			progress = function() return progressEngine end,
			exits = function() return progressEngine.exits end,
			roomName = function() return progressEngine.room end,
		}, "Welcome."
	end }
end })
t.expect(tracked:start(game), "session starts with game progress")
t.assertEqual(tracked:presentation().progress, "Score 4/20 | Moves 2", "presentation uses engine score and move totals")
t.expect(tracked:hasExit("north"), "full exit names are available to the compass")
t.expect(tracked:hasExit("e"), "exit abbreviations normalize for compass selection")
t.expect(not tracked:hasExit("south"), "unavailable exits stay disabled")
t.assertEqual(tracked:presentation().roomTitle, "Sanitarium Gate", "runtime room name replaces the game title")
t.assertEqual(tracked:presentation().gameDescription, game.description or "", "intro synopsis comes from the selected game")
t.expect(tracked:submit("solve"), "tracked session accepts a command")
t.assertEqual(tracked:presentation().progress, "Score 5/20 | Moves 3", "commands refresh live engine progress")

os.exit(t.summary() and 0 or 1)
