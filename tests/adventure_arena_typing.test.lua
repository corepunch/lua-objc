_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Session = require("apps.adventure-arena.zilscript.zilscript.reader.Session")
local Store = require("apps.adventure-arena.Store")
local SavedGames = require("apps.adventure-arena.models.SavedGames")
local SessionController = require("apps.adventure-arena.controllers.SessionController")
local Template = require("ui.template")

-- The opening appears whole. Command responses come in a few characters per
-- tick with steady soft haptic pulses and one scroll to the full answer.
local OPENING = "West of House\nYou are standing in an open field west of a white house.\nThere is a small mailbox here."
local ANSWER = "Opening the small mailbox reveals a leaflet.\nIt is written in a careful hand."

local function engine()
	return {
		start = function()
			return {
				resume = function(_, command)
					if command == "open mailbox" then return ANSWER end
					if command == "read leaflet" then return string.rep("x", 90) end
					return "Nothing happens."
				end,
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
	Store.new { games = { { id = "zork", title = "Zork", description = "A story." } } }
	if saved then saved.gameId = "zork"; SavedGames:create(saved) end
	local controller = SessionController.new {
		model = Session.new { engineFactory = function() return engine() end },
		push = function(_, data)
			local view, refs = xml.renderFile("apps/adventure-arena/views/pages/Session.etlua", data, ns)
			rendered = { view = view, refs = refs }
			return view, refs
		end,
		back = function() end,
		ns = ns,
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
	-- Record what the open page is asked to scroll to; the native scroll
	-- still runs. Opening sets the page without counting as a scroll.
	local scrollPage, show, recording = controller.scrollPage, controller.show, false
	controller.scrollPage = function(self, target, animated, anchor)
		if recording then table.insert(scrolls, { target = target, animated = animated, anchor = anchor }) end
		return scrollPage(self, target, animated, anchor)
	end
	controller.show = function(self, ...)
		recording = false
		local shown = show(self, ...)
		recording = true
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

-- A new story shows its first scene immediately.
local controller = build()
t.expect(controller:show("zork"), "a new story opens")
local page = function() return controller.transcript.refs end
t.expect(not controller:isTyping(), "the opening appears without typing")
t.assertEqual(#timers, 0, "opening the story schedules no typing or haptic ticks")
t.assertEqual(#haptics, 0, "opening the story emits no typing haptics")
t.assertEqual(page().sceneTitle_1.text, "West of House", "the opening shows the scene title")
t.assertEqual(page().sceneTitle_1.opacity, 1, "the opening title is visible immediately")
t.assertEqual(page().paragraph_1_1.revealedCharacters, -1, "the first paragraph appears whole")
t.assertEqual(page().paragraph_1_2.revealedCharacters, -1, "the second paragraph appears whole")
t.expect(page().paragraph_1_1.hidden == false and page().paragraph_1_2.hidden == false,
	"both opening paragraphs are visible")
t.expect(page().synopsis == nil, "no synopsis precedes the opening scene")

local firstFrame, secondFrame = page().paragraph_1_1.frame, page().paragraph_1_2.frame
local gap = math.abs(secondFrame.origin.y - firstFrame.origin.y) - (secondFrame.origin.y < firstFrame.origin.y and secondFrame.size.height or firstFrame.size.height)
t.expect(math.abs(gap - 12) < 0.01, "opening paragraphs use the single 12-point gap")

-- A command types its answer; the command itself is set at once.
controller:submitCommand("open mailbox")
local answer = page().paragraph_3_1
local answerHeight = page().entry_3.size.height
t.expect(controller:isTyping(), "a command starts typing its answer")
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
t.assertEqual(tick().seconds, 1 / 30, "the answer starts on the ordinary typing tick")
t.assertEqual(answer.revealedCharacters, 3, "each tick reveals a few characters")
t.assertEqual(timers[1].seconds, HAPTIC_INTERVAL, "pulses use their own fixed timer")
tick()
t.assertEqual(answer.revealedCharacters, 6, "the answer types")
t.assertEqual(answer.frame.origin.y, answerTop, "typing moves nothing")
t.assertEqual(#scrolls, 1, "and scrolls nothing")

while answer.revealedCharacters ~= -1 do tick() end
t.expect(rawequal(page().paragraph_3_1, answer), "typing never rebuilds the paragraph")
local paragraphFinishedAt = now
local nextParagraph = tick()
t.expect(math.abs(nextParagraph.due - paragraphFinishedAt - 1 / 30) < 0.000001,
	"the next paragraph prints on the ordinary tick without a pause")
t.assertEqual(page().paragraph_3_2.revealedCharacters, 3, "the next paragraph starts with one tick")
finish()
t.expect(#haptics > 1, "printing emits repeated pulses")
for index, haptic in ipairs(haptics) do
	t.assertEqual(haptic.intensity, 0.5, "every pulse has the same strength")
	t.assertEqual(haptic.style, "soft", "every pulse uses the same soft impact")
	if index > 1 then
		t.expect(math.abs(haptic.time - haptics[index - 1].time - HAPTIC_INTERVAL) < 0.000001,
			"pulses stay evenly spaced across words and paragraph boundaries")
	end
end
t.expect(not controller:isTyping(), "the answer finishes")
t.assertEqual(page().paragraph_3_2.revealedCharacters, -1, "every paragraph ends fully shown")
t.assertEqual(page().entry_3.size.height, answerHeight, "typing never resizes the answer")
t.assertEqual(#scrolls, 1, "the answer scrolls once through the entire reveal")

-- Changing reading settings mid-answer re-sets the page without losing place.
controller:submitCommand("open mailbox")
tick(); tick()
controller:applyReadingSettings()
t.assertEqual(page().paragraph_5_1.revealedCharacters, 6, "a re-render keeps the typed characters")
t.assertEqual(page().paragraph_5_2.revealedCharacters, 0, "a re-render keeps waiting paragraphs waiting")

-- A new command sets the rest of the answer at once, then types its own.
controller:submitCommand("wait")
t.expect(page().paragraph_5_1.revealedCharacters == -1,
	"a new command finishes the previous answer")
t.expect(page().paragraph_5_2.revealedCharacters == -1,
	"the previous answer's waiting paragraphs appear whole")
t.assertEqual(page().paragraph_7_1.revealedCharacters, 0, "the new answer waits to type")
t.assertEqual(scrolls[#scrolls].target, "entry_6", "each command scrolls to its own line")
local stale = #timers
finish()
t.expect(page().paragraph_7_1.revealedCharacters == -1, "the new answer finishes")
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
saved, reduceMotion, timers, haptics = nil, false, {}, {}
local unbroken = build()
unbroken:show("zork")
unbroken:submitCommand("read leaflet")
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
