_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Session = require("apps.adventure-arena.zilscript.zilscript.reader.Session")
local ReadingSettings = require("apps.adventure-arena.models.ReadingSettings")
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
					if command == "north" then return "Cellar\nA damp cellar. “[[door]]” swings open." end
					if command == "look" then return longAnswer end
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
Store.new { games = { { id = "zork", title = "Zork", author = "Infocom", description = "A story." } } }
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
t.expect(controller:isTyping(), "a new story types its opening")
finishTimers()
t.expect(not controller:isTyping(), "the opening finishes typing")
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
local titlePage = controller.transcript.refs
t.assertEqual(titlePage.gameAuthor.text, "Infocom", "the title page names the studio")
t.assertEqual(titlePage.gameAuthor.frameInWindow.origin.x, titlePage.synopsis.frameInWindow.origin.x,
	"the studio starts at the text column")
t.assertEqual(titlePage.gameTitle.frameInWindow.origin.x, titlePage.synopsis.frameInWindow.origin.x,
	"the book title starts at the text column")
t.assertEqual(#titlePage.titlePage.subviews, 3, "the title page has only studio, title and synopsis")
local authorFrame = titlePage.gameAuthor.frameInWindow
local titleFrame = titlePage.gameTitle.frameInWindow
local synopsisFrame = titlePage.synopsis.frameInWindow
t.assertEqual(authorFrame.origin.y - titleFrame.origin.y - titleFrame.size.height, 10,
	"the studio stays close to the book title")
t.assertEqual(titleFrame.origin.y - synopsisFrame.origin.y - synopsisFrame.size.height, 18,
	"the synopsis is separated from the title")
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
t.expect(model:hasExit("north") and not model:hasExit("south"), "the session still knows its exits")
t.expect(controller.transcript.refs.chapter_1 == nil, "a scene carries no chapter line above its title")
t.assertEqual(controller.transcript.refs.sceneTitle_1.text, "Zork", "a scene opens with its title")

-- A room heading and a prose response use the same gap after a command.
controller:submitCommand("north")
local cellar = model:entryCount()
t.assertEqual(controller.transcript.refs["sceneTitle_" .. cellar].text, "Cellar", "the move opens a scene")
local prefix = "paragraph_" .. cellar .. "_1"
local prose = controller.transcript.refs[prefix]
local quote = controller.transcript.refs[prefix .. "_2"]
local following = controller.transcript.refs[prefix .. "_3"]
t.assertEqual(prose.text, "A damp cellar.", "prose stops before the quote")
t.assertEqual(quote.text, "door", "the quotation gets its own paragraph without outer marks")
t.assertEqual(following.text, "swings open.", "prose continues below the quote")
t.assertEqual(quote.font.pointSize, prose.font.pointSize + 2, "quotes are two points larger")
t.expect(quote.frameInWindow.origin.x > prose.frameInWindow.origin.x, "quotes are indented")
t.assertEqual(quote.revealedCharacters, 0, "quotes wait for the prose before them to type")
t.assertEqual(following.revealedCharacters, 0, "following prose waits for the quote to type")
finishTimers()
t.assertEqual(quote.revealedCharacters, -1, "the quote is fully revealed")
t.assertEqual(following.revealedCharacters, -1, "the following prose is fully revealed")
local attrs = require("AppKitNative")._paragraphAttributes(quote, 0)
t.expect(attrs.italic and attrs.bold, "a quoted story link is rendered in bold italic")
t.assertEqual(controller.transcript.refs["entry_" .. cellar].paddingTop,
	controller.transcript.refs.entry_3.paddingTop, "the heading uses the same command gap as prose")
t.assertEqual(controller.transcript.refs.titlePage.paddingBottom,
	math.floor(ReadingSettings:current():presentation().fontSize * 1.3), "the full synopsis has a section break below it")

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
t.expect(page.titlePage ~= nil and page.gameTitle.text == "Zork", "the story opens on a title page")

-- Keep the command prompt plain and preserve the accessible speaker label.
local command = controller.transcript.refs.command_2
t.assertEqual(command.text, "look", "the command text contains only the reader’s words")
t.assertEqual(command.accessibilityLabel, "You: look", "VoiceOver says who spoke")
t.expect(command.superview.backgroundColor == nil or command.superview.backgroundColor.alphaComponent == 0,
	"a command has no bubble behind it")

os.exit(t.summary() and 0 or 1)
