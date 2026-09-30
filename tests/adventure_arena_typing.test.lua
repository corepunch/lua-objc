_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Session = require("apps.adventure-arena.models.Session")
local ReadingSettings = require("apps.adventure-arena.models.ReadingSettings")
local SessionController = require("apps.adventure-arena.controllers.SessionController")
local Template = require("ui.template")

-- The story types itself: new prose appears a few characters per tick with
-- steady soft haptic pulses, the page follows it, and a resumed story
-- opens already set.
local OPENING = "West of House\nYou are standing in an open field west of a white house.\nThere is a small mailbox here."
local ANSWER = "Opening the small mailbox reveals a leaflet.\nIt is written in a careful hand."

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
local now = 0
local HAPTIC_INTERVAL = (4 / 30) / 1.75
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
			impact = function(style, intensity) table.insert(haptics, { style = style, intensity = intensity, time = now }) end,
			notification = function() end,
		},
		after = function(seconds, callback) table.insert(timers, { seconds = seconds, due = now + seconds, callback = callback }) end,
		reduceMotion = function() return reduceMotion end,
	}
	local scrollTranscript = controller.scrollTranscript
	controller.scrollTranscript = function(self, animated)
		scrolls = scrolls + 1
		return scrollTranscript(self, animated)
	end
	return controller
end

local function nextTimer()
	table.sort(timers, function(a, b) return a.due < b.due end)
	local timer = table.remove(timers, 1)
	if timer then now = timer.due; timer.callback() end
	return timer
end
local function tick()
	local timer = nextTimer()
	while timer and timer.seconds == HAPTIC_INTERVAL do timer = nextTimer() end
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
t.assertEqual(first.revealedCharacters, 3, "each tick reveals a few characters")
t.assertEqual(haptics[1].style, "soft", "typing uses a soft impact")
t.expect(scrolls > 0, "the page follows the typing")
t.assertEqual(timers[#timers].seconds, 1 / 30, "three characters at 30 Hz print 25% slower")
t.assertEqual(haptics[1].intensity, 0.5, "typing impacts use the quieter intensity")
t.assertEqual(timers[1].seconds, HAPTIC_INTERVAL, "pulses use their own fixed timer")
tick()
t.assertEqual(first.revealedCharacters, 6, "typing continues")
t.expect(page().paragraph_1_2.hidden == true, "the next paragraph waits its turn")

local ticks = 2
while page().paragraph_1_1.revealedCharacters ~= -1 do tick(); ticks = ticks + 1 end
t.expect(rawequal(page().paragraph_1_1, first), "typing never rebuilds the paragraph")
t.expect(#haptics > 1, "printing emits repeated pulses")
for index = 2, #haptics do
	t.expect(math.abs(haptics[index].time - haptics[index - 1].time - HAPTIC_INTERVAL) < 0.000001,
		"pulses stay evenly spaced across words and spaces")
	t.assertEqual(haptics[index].intensity, 0.5, "every pulse has the same strength")
	t.assertEqual(haptics[index].style, "soft", "every pulse uses the same soft impact")
end
local paragraphFinishedAt = now
local countAtPause = #haptics
nextTimer()
t.assertEqual(#haptics, countAtPause, "pending pulses are silent during the paragraph pause")
t.assertEqual(timers[1].seconds, 0.15, "a short beat separates paragraphs")
local pause = nextTimer()
t.expect(math.abs(pause.due - paragraphFinishedAt - 0.15) < 0.000001, "printing waits through the paragraph break")
t.expect(page().paragraph_1_2.hidden == false, "printing resumes after the break")
t.assertEqual(page().paragraph_1_2.revealedCharacters, 3, "the next paragraph starts with one tick")
t.assertEqual(#haptics, countAtPause + 1, "haptics resume with printing")
t.assertEqual(haptics[#haptics].time, pause.due, "the first resumed pulse accompanies the next paragraph")
t.expect(haptics[#haptics].time - haptics[countAtPause].time >= 0.15,
	"a single newline leaves at least 0.15 seconds of haptic silence")
finish()
t.expect(not controller:isTyping(), "the opening finishes")
t.expect(page().paragraph_1_2.hidden == false and page().paragraph_1_2.revealedCharacters == -1,
	"every paragraph ends fully shown")

local firstFrame, secondFrame = page().paragraph_1_1.frame, page().paragraph_1_2.frame
local gap = math.abs(secondFrame.origin.y - firstFrame.origin.y) - (secondFrame.origin.y < firstFrame.origin.y and secondFrame.size.height or firstFrame.size.height)
t.expect(math.abs(gap - 20) < 0.01, "paragraphs have a 50% larger gap at the default type size")

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
t.assertEqual(answer.revealedCharacters, 6, "the answer types")

-- Changing reading settings mid-answer re-sets the page without losing place.
controller:applyReadingSettings()
t.assertEqual(page().paragraph_3_1.revealedCharacters, 6, "a re-render keeps the typed characters")
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
local countAtClose = #haptics
t.expect(not controller:isTyping(), "closing the book stops typing")
finish()
t.assertEqual(#haptics, countAtClose, "closing cancels pending haptic pulses")

-- A resumed story opens at its last line without typing.
saved = { seed = 1, commands = { "open mailbox" } }
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

-- A long unbroken word has the same pulse rhythm as ordinary prose.
OPENING = string.rep("x", 90)
saved, reduceMotion, timers, haptics = nil, false, {}, {}
local unbroken = build()
unbroken:show("zork")
finish()
t.expect(#haptics > 10, "haptics keep playing without any word boundaries")
for index = 2, #haptics do
	t.expect(math.abs(haptics[index].time - haptics[index - 1].time - HAPTIC_INTERVAL) < 0.000001,
		"unbroken text has the same even pulse intervals")
end
local countAtFinish = #haptics
finish()
t.assertEqual(#haptics, countAtFinish, "printing completion leaves no active pulses")

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
