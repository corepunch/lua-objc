_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Session = require("apps.adventure-arena.models.Session")
local ReadingSettings = require("apps.adventure-arena.models.ReadingSettings")
local SessionController = require("apps.adventure-arena.controllers.SessionController")
local Template = require("ui.template")

-- The story types itself: new prose appears a few characters per tick with
-- steady soft haptic pulses. The page makes room for the whole answer when
-- it arrives and scrolls there once; a resumed story opens already set.
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

local timers, haptics, scrolls = {}, {}, {}
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
	-- Record what the page is asked to scroll to; the native scroll still runs.
	local show = controller.show
	controller.show = function(self, ...)
		local shown = show(self, ...)
		local scroll = self.refs and self.refs.transcriptScroll
		if scroll then
			self.refs.transcriptScroll = setmetatable({}, { __index = function(_, key)
				if key ~= "scrollTo" then return scroll[key] end
				return function(_, target, animated, anchor)
					table.insert(scrolls, { target = target, animated = animated, anchor = anchor })
					return scroll:scrollTo(target, animated, anchor)
				end
			end })
		end
		return shown
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
t.assertEqual(page().paragraph_1_1.revealedCharacters, 0, "nothing is revealed before the first tick")
t.assertEqual(page().paragraph_1_2.revealedCharacters, 0, "later paragraphs wait too")
t.expect(page().paragraph_1_1.hidden ~= true and page().paragraph_1_2.hidden ~= true,
	"waiting paragraphs keep their place on the page")
t.expect(page().gameTitle ~= nil and page().gameTitle.hidden ~= true, "the title page is set at once")
t.assertEqual(page().sceneTitle_1.opacity, 0, "a chapter heading waits for its text")
local openingHeight = page().entry_1.size.height
t.expect(page().paragraph_1_2.size.height > 0 and openingHeight > page().paragraph_1_2.size.height,
	"the page is as tall as the whole opening before any of it types")

tick()
local first = page().paragraph_1_1
t.expect(first.hidden == false, "the first tick shows the paragraph being typed")
t.expect(page().sceneTitle_1.opacity == 1 and page().sceneTitle_1.text == "West of House", "the chapter opens with its text")
t.assertEqual(first.revealedCharacters, 3, "each tick reveals a few characters")
t.assertEqual(haptics[1].style, "soft", "typing uses a soft impact")
t.assertEqual(#scrolls, 0, "typing scrolls nothing: the opening is read from its title page")
t.assertEqual(timers[#timers].seconds, 1 / 30, "three characters at 30 Hz print 25% slower")
t.assertEqual(haptics[1].intensity, 0.5, "typing impacts use the quieter intensity")
t.assertEqual(timers[1].seconds, HAPTIC_INTERVAL, "pulses use their own fixed timer")
tick()
t.assertEqual(first.revealedCharacters, 6, "typing continues")
t.assertEqual(page().paragraph_1_2.revealedCharacters, 0, "the next paragraph waits its turn")

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
local nextParagraph = tick()
t.expect(math.abs(nextParagraph.due - paragraphFinishedAt - 1 / 30) < 0.000001,
	"the next paragraph prints on the ordinary tick without a pause")
t.assertEqual(page().paragraph_1_2.revealedCharacters, 3, "the next paragraph starts with one tick")
finish()
for index = 2, #haptics do
	t.expect(math.abs(haptics[index].time - haptics[index - 1].time - HAPTIC_INTERVAL) < 0.000001,
		"haptic pulses keep their cadence across paragraph boundaries")
end
t.expect(not controller:isTyping(), "the opening finishes")
t.expect(page().paragraph_1_2.revealedCharacters == -1, "every paragraph ends fully shown")
t.assertEqual(page().entry_1.size.height, openingHeight, "typing never resized the page")
t.assertEqual(#scrolls, 0, "and never scrolled it")

local firstFrame, secondFrame = page().paragraph_1_1.frame, page().paragraph_1_2.frame
local gap = math.abs(secondFrame.origin.y - firstFrame.origin.y) - (secondFrame.origin.y < firstFrame.origin.y and secondFrame.size.height or firstFrame.size.height)
t.expect(math.abs(gap - 20) < 0.01, "paragraphs have a 50% larger gap at the default type size")

-- A command types its answer; the command itself is set at once.
controller:submitCommand("open mailbox")
local answer = page().paragraph_3_1
t.assertEqual(page().command_2.text, "open mailbox", "the command appears at once")
t.expect(answer.revealedCharacters == 0 and page().paragraph_3_2.revealedCharacters == 0, "the answer waits to type")
t.expect(page().entry_3.hidden ~= true and page().entry_2.hidden ~= true, "the command shows while its answer waits")
t.expect(answer.size.height > 0 and page().paragraph_3_2.size.height > 0,
	"the page makes room for the whole answer at once")
t.assertEqual(#scrolls, 1, "a command scrolls the page once")
t.assertEqual(scrolls[1].target, "entry_2", "to the command, with its answer below")
t.expect(scrolls[1].animated == true and scrolls[1].anchor == "top",
	"smoothly, and no further than the command's own line")
local answerTop = answer.frame.origin.y
t.expect(page().entry_1.hidden == false, "earlier chapters stay shown")
t.expect(page().paragraph_1_1.hidden == false and page().paragraph_1_1.revealedCharacters == -1,
	"earlier paragraphs stay fully shown")
tick(); tick()
t.assertEqual(answer.revealedCharacters, 6, "the answer types")
t.assertEqual(answer.frame.origin.y, answerTop, "typing moves nothing")
t.assertEqual(#scrolls, 1, "and scrolls nothing")

-- Changing reading settings mid-answer re-sets the page without losing place.
controller:applyReadingSettings()
t.assertEqual(page().paragraph_3_1.revealedCharacters, 6, "a re-render keeps the typed characters")
t.assertEqual(page().paragraph_3_2.revealedCharacters, 0, "a re-render keeps waiting paragraphs waiting")

-- A new command sets the rest of the answer at once, then types its own.
controller:submitCommand("wait")
t.expect(page().paragraph_3_1.revealedCharacters == -1,
	"a new command finishes the previous answer")
t.expect(page().paragraph_3_2.revealedCharacters == -1,
	"the previous answer's waiting paragraphs appear whole")
t.assertEqual(page().paragraph_5_1.revealedCharacters, 0, "the new answer waits to type")
t.assertEqual(scrolls[#scrolls].target, "entry_4", "each command scrolls to its own line")
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
t.expect(resumed.transcript.refs.paragraph_3_1.revealedCharacters == -1, "a resumed story is set whole")

-- Reduce Motion shows answers at once.
saved, reduceMotion, timers = nil, true, {}
local still = build()
still:show("zork")
t.expect(not still:isTyping(), "Reduce Motion does not type the opening")
still:submitCommand("open mailbox")
t.expect(not still:isTyping(), "Reduce Motion does not type answers")
t.assertEqual(still.transcript.refs.paragraph_3_1.revealedCharacters, -1, "Reduce Motion shows answers whole")
t.expect(scrolls[#scrolls].target == "entry_2" and scrolls[#scrolls].animated == false,
	"Reduce Motion goes to the answer without the scroll animation")

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
