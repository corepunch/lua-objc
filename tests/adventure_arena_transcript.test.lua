_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Session = require("apps.adventure-arena.zilscript.zilscript.reader.Session")
local Store = require("apps.adventure-arena.Store")
local SavedGames = require("apps.adventure-arena.models.SavedGames")
local SessionController = require("apps.adventure-arena.controllers.SessionController")
local Template = require("ui.template")
local function mountTemplate(host, template)
	return Template.new(host, "apps/adventure-arena/views/" .. template .. ".etlua", ns)
end

local opening = string.rep("A long opening paragraph. ", 40)
local longAnswer = string.rep("Response look. ", 30):sub(1, -2)
local function engine()
	return {
		start = function()
			return {
				resume = function(_, command)
				if command == "north" then return "Cellar\nA damp cellar. “[[door]]” swings open.\n\nThe stairs creak." end
					if command == "look" then return longAnswer end
				if command == "wait" then return "Response wait.\n\nNothing happens." end
					return "Response " .. command
				end,
				exits = function() return { "north", "east" } end,
			}, opening
		end,
	}
end

local model = Session.new { engineFactory = function() return engine() end }
local rendered = {}
-- Typing advances on timers; tests run them to the end of the story.
local timers = {}
local function after(_, callback) table.insert(timers, callback) end
local function finishTimers()
	while #timers > 0 do table.remove(timers, 1)() end
end
Store.new { games = { { id = "zork", title = "Zork", description = "A story." } } }
local controller = SessionController.new {
	model = model,
	push = function(_, data)
		local view, refs = xml.renderFile("apps/adventure-arena/views/pages/Session.etlua", data, ns)
		rendered = { view = view, refs = refs }
		return view, refs
	end,
	back = function() end,
	ns = ns,
	renderTemplate = function() end,
	mountTemplate = mountTemplate,
	presentSheet = function() end,
	dismissSheet = function() end,
	after = after,
	reduceMotion = function() return false end,
}
t.expect(controller:show("zork"), "new session opens")
t.assertEqual(controller.transcript.refs.paragraph_1_1.revealedCharacters, -1, "the opening is visible on the first render")
t.assertEqual(controller.transcript.refs.entry_1.paddingTop, 0, "the opening starts at the page margin")
local scroll = controller.refs.transcriptScroll
-- The page owns the transcript's frame, as the window does in the app.
local function resizePage(height)
	rendered.refs.reader.size = ns.Size(320, height)
	rendered.refs.reader:layout(320)
end
local function fromTop()
	return scroll.documentView.frame.size.height - scroll.contentSize.height - scroll.contentView.bounds.origin.y
end
resizePage(220)
t.expect(scroll.contentSize.height > 0 and scroll.documentView.frame.size.height > scroll.contentSize.height,
	"the opening is taller than the page")
t.assertEqual(fromTop(), 0, "a new story opens at its title page")
t.expect(scroll.scrollOnKeyboard == true, "the transcript follows the keyboard")

ns._textFieldTestFocus(controller.refs.input)
t.assertEqual(scroll.contentView.bounds.origin.y, -scroll.scrollOverlayAccessory.frame.size.height, "showing the keyboard clears the composer")
scroll:scrollTo("top", false)
t.expect(scroll.contentView.bounds.origin.y > 0, "the reader can leave the latest line")

controller.refs.input.text = "look"
controller:submitCommand("look")
local offset = scroll.contentView.bounds.origin.y
t.expect(offset > 0, "an answer taller than the screen rests on its command's line, not the foot of the page")
local command = controller.transcript.refs.entry_2
t.assertEqual(command.frame.origin.y + command.frame.size.height, offset + scroll.contentSize.height,
	"the command's line is at the top of the screen")
resizePage(220)
t.assertEqual(scroll.contentView.bounds.origin.y, offset, "laying the page out keeps that place")

resizePage(900)
scroll:scrollTo("top", false)
controller:submitCommand("wait")
t.assertEqual(scroll.contentView.bounds.origin.y, -scroll.scrollOverlayAccessory.frame.size.height, "the latest answer clears the composer")
t.assertEqual(controller.transcript.refs.entry_5.frame.origin.y, 36, "the last entry clears the bottom by 36 points")
t.assertEqual(controller.transcript.refs.command_2.text, "look", "the submitted command is in the transcript")
local serif = ns.Text { "look", size = 17, design = "serif", weight = "medium" }
t.assertEqual(controller.transcript.refs.command_2.font.fontName, serif.font.fontName, "commands use the selected serif")
t.assertEqual(controller.transcript.refs.paragraph_3_1.text, longAnswer, "the response follows the command")
local function verticalGap(upper, lower)
	return upper.frame.origin.y - (lower.frame.origin.y + lower.frame.size.height)
end
local reply = controller.transcript.refs
t.assertEqual(reply.entry_2.paddingTop, 24, "a new command starts after a double gap")
t.assertEqual(reply.entry_3.paddingTop, 12, "a prose reply starts after a single gap")
t.assertEqual(verticalGap(reply.paragraph_5_1, reply.paragraph_5_2), 12, "paragraphs in a reply use a single gap")
t.expect(model:hasExit("north") and not model:hasExit("south"), "the session still knows its exits")
t.expect(controller.transcript.refs.chapter_1 == nil, "a scene carries no chapter line above its title")
t.assertEqual(controller.transcript.refs.sceneTitle_1.text, "Zork", "a scene opens with its title")

-- A room heading and a prose response use the same gap after a command.
controller:submitCommand("north")
local cellar = model:entryCount()
t.assertEqual(controller.transcript.refs["sceneTitle_" .. cellar].text, "Cellar", "the move opens a scene")
local paragraph = controller.transcript.refs["paragraph_" .. cellar .. "_1"]
t.assertEqual(paragraph.text, "A damp cellar. “door” swings open.", "the quote stays inline with its visible marks")
t.assertEqual(paragraph.revealedCharacters, 0, "the whole paragraph waits to type")
finishTimers()
t.assertEqual(paragraph.revealedCharacters, -1, "the whole paragraph finishes typing")
local attributes = require("AppKitNative")._paragraphAttributes
local attrs = attributes(paragraph, 16)
t.expect(attrs.italic and not attrs.bold, "a marked word inside a quotation is italic only")
t.expect(attributes(paragraph, 15).italic and attributes(paragraph, 20).italic, "the quote marks are italic too")
t.expect(not attributes(paragraph, 22).italic, "prose resumes in regular type after the quote")
local move = controller.transcript.refs
t.assertEqual(move["entry_" .. (cellar - 1)].paddingTop, 24, "a movement command starts after a double gap")
t.assertEqual(move["entry_" .. cellar].paddingTop, 12, "a room heading starts after a single gap")
t.assertEqual(verticalGap(move["sceneTitle_" .. cellar], paragraph), 12, "a room heading sits a single gap above its prose")
t.assertEqual(verticalGap(paragraph, move["paragraph_" .. cellar .. "_2"]), 12, "scene paragraphs use a single gap")

-- The command field spans the inset without any adjacent controls.
local bar = controller.refs.commandBar
rendered.refs.reader.size = ns.Size(390, 700)
rendered.refs.reader:layout(390)
t.assertEqual(bar.frame.origin.x + bar.frame.size.width, bar.superview.bounds.size.width,
	"the command bar fills the inset to its trailing edge")
t.expect(controller.refs.quickActions == nil, "the reader reserves no space for a quick actions button")

local savedOpening = opening .. "\n\n> inventory\n\nYou are empty handed."
local saved = Session.new { engineFactory = function()
	return { start = function()
		return {
			resume = function(_, command) return "Response " .. command end,
			exits = function() return { "north" } end,
		}, savedOpening
	end }
end }
Store.new { games = { { id = "zork", title = "Zork", description = "A story." } } }
local record = { seed = 1, commands = {} }
record.gameId = "zork"
SavedGames:create(record)
local loaded = SessionController.new {
	model = saved,
	push = function(_, data)
		local view, refs = xml.renderFile("apps/adventure-arena/views/pages/Session.etlua", data, ns)
		rendered = { view = view, refs = refs }
		return view, refs
	end,
	back = function() end,
	ns = ns,
	renderTemplate = function() end,
	mountTemplate = mountTemplate,
	presentSheet = function() end,
	dismissSheet = function() end,
	after = after,
	reduceMotion = function() return false end,
}
t.expect(loaded:show("zork"), "loading a session opens the transcript")
t.expect(not loaded:isTyping(), "a resumed story opens already set, without typing")
scroll = loaded.refs.transcriptScroll
scroll.frameSize = ns.Size(320, 120)
scroll:layout(320)
t.assertEqual(scroll.contentView.bounds.origin.y, 0, "loading a session shows the latest line")
local page = loaded.transcript.refs
t.assertEqual(page.paragraph_1_1.text:sub(1, 20), "A long opening parag", "a loaded session keeps its opening, first letter included")
t.assertEqual(#page.paragraph_1_1.textContainer.exclusionPaths, 0, "restored prose uses the full column")
t.expect(page.paragraph_1_2.text:find("> inventory", 1, true) ~= nil, "a loaded session keeps its commands")
t.expect(page.bannerTitle_1 == nil and page.synopsis == nil, "a game without a banner opens directly on the scene")

-- Keep the command prompt plain and preserve the accessible speaker label.
local command = controller.transcript.refs.command_2
t.assertEqual(command.text, "look", "the command text contains only the reader’s words")
t.assertEqual(command.accessibilityLabel, "You: look", "VoiceOver says who spoke")
t.expect(command.superview.backgroundColor == nil or command.superview.backgroundColor.alphaComponent == 0,
	"a command has no bubble behind it")

os.exit(t.summary() and 0 or 1)
