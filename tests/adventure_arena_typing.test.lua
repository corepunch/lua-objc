_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Session = require("apps.adventure-arena.models.Session")
local ReadingSettings = require("apps.adventure-arena.models.ReadingSettings")
local SessionController = require("apps.adventure-arena.controllers.SessionController")
local Template = require("ui.template")

-- The story types itself: new prose appears a few characters per tick with
-- a soft haptic at word starts, the page follows it, and a resumed story
-- opens already set.
local OPENING = "West of House\nYou are standing in an open field west of a white house.\n\nThere is a small mailbox here."
local ANSWER = "Opening the small mailbox reveals a leaflet.\n\nIt is written in a careful hand."

local function engine()
	return {
		start = function()
			return {
				resume = function(_, command) return command == "open mailbox" and ANSWER or "Nothing happens." end,
				exits = function() return { "north" } end,
				roomName = function() return "West of House" end,
			}, OPENING
		end,
	}
end

local timers, haptics, scrolls = {}, {}, 0
local reduceMotion = false
local rendered = {}
local saved = nil
local function build()
	local controller = SessionController.new {
		model = Session.new { engineFactory = function() return engine() end },
		findGame = function() return { id = "zork", title = "Zork", description = "A story." } end,
		push = function(_, data)
			local view, refs = xml.renderFile("apps/adventure-arena/views/Session.etlua", data, ns)
			rendered = { view = view, refs = refs }
			return view, refs
		end,
		back = function() end,
		ns = ns,
		readingSettings = ReadingSettings.new(),
		savedGames = { find = function() return saved end, record = function() end },
		renderTemplate = function() end,
		mountTemplate = function(host, template)
			return Template.new(host, "apps/adventure-arena/views/" .. template .. ".etlua", ns)
		end,
		presentSheet = function() end,
		dismissSheet = function() end,
		haptics = {
			impact = function(style) table.insert(haptics, style) end,
			notification = function() end,
		},
		after = function(seconds, callback) table.insert(timers, { seconds = seconds, callback = callback }) end,
		reduceMotion = function() return reduceMotion end,
	}
	local scrollTranscript = controller.scrollTranscript
	controller.scrollTranscript = function(self, animated)
		scrolls = scrolls + 1
		return scrollTranscript(self, animated)
	end
	return controller
end

local function tick()
	local timer = table.remove(timers, 1)
	if timer then timer.callback() end
	return timer
end
local function finish()
	while tick() do end
end

-- A new story types its opening once the page has slid in.
local controller = build()
t.expect(controller:show("zork"), "a new story opens")
local page = function() return controller.transcript.refs end
t.expect(controller:isTyping(), "a new story types its opening")
t.expect(timers[1].seconds > 0.3, "typing waits for the page to finish sliding in")
t.expect(page().paragraph_1_1.hidden == true, "the opening waits hidden")
t.assertEqual(page().paragraph_1_1.revealedCharacters, 0, "nothing is revealed before the first tick")
t.expect(page().paragraph_1_2.hidden == true, "later paragraphs wait too")
t.expect(page().gameTitle ~= nil and page().gameTitle.hidden ~= true, "the title page is set at once")
t.expect(page().entry_1.hidden == true, "a chapter heading waits for its text")

tick()
local first = page().paragraph_1_1
t.expect(first.hidden == false, "the first tick shows the paragraph being typed")
t.expect(page().entry_1.hidden == false and page().sceneTitle_1.text == "West of House", "the chapter opens with its text")
t.assertEqual(first.revealedCharacters, 4, "each tick reveals a few characters")
t.assertEqual(haptics[1], "soft", "typing starts with a soft haptic")
t.expect(scrolls > 0, "the page follows the typing")
t.expect(timers[1].seconds < 0.1, "the next characters follow quickly")
tick()
t.assertEqual(first.revealedCharacters, 8, "typing continues")
t.expect(page().paragraph_1_2.hidden == true, "the next paragraph waits its turn")

local ticks = 2
while page().paragraph_1_1.revealedCharacters ~= -1 do tick(); ticks = ticks + 1 end
t.expect(rawequal(page().paragraph_1_1, first), "typing never rebuilds the paragraph")
t.expect(#haptics > 1 and #haptics <= math.ceil(ticks / 4), "haptics tick at word starts, never faster than every fourth tick")
t.expect(timers[1].seconds > 0.1, "a beat separates paragraphs")
finish()
t.expect(not controller:isTyping(), "the opening finishes")
t.expect(page().paragraph_1_2.hidden == false and page().paragraph_1_2.revealedCharacters == -1,
	"every paragraph ends fully shown")

-- A command types its answer; the command itself is set at once.
controller:submitCommand("open mailbox")
local answer = page().paragraph_3_1
t.assertEqual(page().command_2.text, "open mailbox", "the command appears at once")
t.expect(answer.hidden == true and page().paragraph_3_2.hidden == true, "the answer waits to type")
t.expect(page().entry_3.hidden == true and page().entry_2.hidden ~= true, "the command shows while its answer waits")
t.expect(page().entry_1.hidden == false, "earlier chapters stay shown")
t.expect(page().paragraph_1_1.hidden == false and page().paragraph_1_1.revealedCharacters == -1,
	"earlier paragraphs stay fully shown")
tick(); tick()
t.assertEqual(answer.revealedCharacters, 8, "the answer types")

-- Changing reading settings mid-answer re-sets the page without losing place.
controller:applyReadingSettings()
t.assertEqual(page().paragraph_3_1.revealedCharacters, 8, "a re-render keeps the typed characters")
t.expect(page().paragraph_3_2.hidden == true, "a re-render keeps waiting paragraphs hidden")
t.expect(page().entry_3.hidden == false, "a re-render keeps the entry being typed shown")

-- A new command sets the rest of the answer at once, then types its own.
controller:submitCommand("wait")
t.expect(page().paragraph_3_1.hidden == false and page().paragraph_3_1.revealedCharacters == -1,
	"a new command finishes the previous answer")
t.expect(page().paragraph_3_2.hidden == false and page().paragraph_3_2.revealedCharacters == -1,
	"the previous answer's waiting paragraphs appear whole")
t.expect(page().paragraph_5_1.hidden == true, "the new answer waits to type")
local stale = #timers
finish()
t.expect(page().paragraph_5_1.revealedCharacters == -1, "the new answer finishes")
t.expect(stale >= 1, "the superseded answer's timer was pending")

-- Closing the book stops typing; a late tick does nothing.
controller:submitCommand("open mailbox")
controller:onDisappear()
t.expect(not controller:isTyping(), "closing the book stops typing")
finish()

-- A resumed story opens at its last line without typing.
saved = { seed = 1, commands = { "open mailbox" },
	checkpoints = { { room = "West of House", score = 0, moves = 1 } } }
timers, haptics = {}, {}
local resumed = build()
t.expect(resumed:show("zork"), "a saved story resumes")
t.expect(not resumed:isTyping(), "a resumed story does not retype")
t.assertEqual(#timers, 0, "nothing is scheduled for a resumed story")
t.expect(resumed.transcript.refs.paragraph_3_1.hidden == false
	and resumed.transcript.refs.paragraph_3_1.revealedCharacters == -1, "a resumed story is set whole")

-- Reduce Motion shows answers at once.
saved, reduceMotion, timers = nil, true, {}
local still = build()
still:show("zork")
t.expect(not still:isTyping(), "Reduce Motion does not type the opening")
still:submitCommand("open mailbox")
t.expect(not still:isTyping(), "Reduce Motion does not type answers")
t.expect(still.transcript.refs.paragraph_3_1.hidden == false, "Reduce Motion shows answers whole")

-- Model: the paragraphs a reader has not seen yet.
local model = Session.new { engineFactory = function() return engine() end }
model:start({ id = "zork", title = "Zork" })
local before = model:entryCount()
model:submit("open mailbox")
local fresh = model:paragraphsSince(before + 1)
t.assertEqual(#fresh, 2, "a command's answer is its new paragraphs")
t.assertEqual(fresh[1].entry, before + 2, "paragraphs name their entry, after the command")
t.assertEqual(fresh[2].paragraph, 2, "and their place in it")
t.assertEqual(#model:paragraphsSince(model:entryCount() + 1), 0, "nothing new past the end")

os.exit(t.summary() and 0 or 1)
