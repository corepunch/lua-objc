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
t.expect(session:submit("  look  "), "trimmed command succeeds")
t.assertEqual(#session.messages, 3, "command and first response append exactly two entries")
t.assertEqual(session:transcript(), "Welcome.\n\n> look\n\nA doorway appears.",
	"transcript preserves opening, command, and response order")
t.expect(session:submit("wait"), "nil response is a successful command")
t.assertEqual(#session.messages, 5, "nil response appends an empty message without a hole")
t.assertEqual(session.messages[5], "", "nil response is normalized to an empty string")
t.expect(not session:submit("fail"), "engine failure is reported")
t.assertEqual(session.messages[6], "> fail", "failed command stays in sequence")
t.assertEqual(session.messages[7], "Engine failure", "error response follows failed command")
local before = session:transcript()
t.expect(not session:submit("   "), "blank commands are rejected")
t.assertEqual(session:transcript(), before, "rejected command leaves transcript unchanged")
t.assertEqual(session.currentGame, game, "appending messages preserves game identity")
t.assertEqual(#Session.new().messages, 0, "session histories remain independent")
os.exit(t.summary() and 0 or 1)
