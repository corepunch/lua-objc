_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Session = require("apps.adventure-arena.models.Session")
local ReadingSettings = require("apps.adventure-arena.models.ReadingSettings")
local SessionController = require("apps.adventure-arena.controllers.SessionController")
local Template = require("ui.template")
local function mountTemplate(host, template)
	return Template.new(host, "apps/adventure-arena/views/" .. template .. ".etlua", ns)
end

local opening = string.rep("A long opening paragraph. ", 40)
local function engine()
	return {
		start = function()
			return {
				resume = function(_, command)
					if command == "north" then return "Cellar\nA damp cellar." end
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
local controller = SessionController.new {
	model = model,
	findGame = function() return { id = "zork", title = "Zork", description = "A story." } end,
	push = function(_, data)
		local view, refs = xml.renderFile("apps/adventure-arena/views/Session.etlua", data, ns)
		rendered = { view = view, refs = refs }
		return view, refs
	end,
	back = function() end,
	ns = ns,
	readingSettings = ReadingSettings.new(),
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
local scroll = rendered.refs.transcriptScroll
-- The page owns the transcript's frame, as the window does in the app.
local function resizePage(height)
	rendered.refs.session.size = ns.Size(320, height)
	rendered.refs.session:layout(320)
end
local function fromTop()
	return scroll.documentView.frame.size.height - scroll.contentSize.height - scroll.contentView.bounds.origin.y
end
resizePage(220)
t.expect(scroll.contentSize.height > 0 and scroll.documentView.frame.size.height > scroll.contentSize.height,
	"the opening is taller than the page")
t.assertEqual(fromTop(), 0, "a new story opens at its title page")
t.expect(scroll.scrollOnKeyboard == true, "the transcript follows the keyboard")

ns._textFieldTestFocus(rendered.refs.input)
t.assertEqual(scroll.contentView.bounds.origin.y, 0, "showing the keyboard goes to the latest line")
scroll:scrollTo("top", false)
t.expect(scroll.contentView.bounds.origin.y > 0, "the reader can leave the latest line")

rendered.refs.input.text = "look"
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
t.assertEqual(scroll.contentView.bounds.origin.y, 0, "an answer that fits the screen is shown to the foot of the page")
t.expect(controller.transcript.refs.entry_5.frame.origin.y >= 80,
	"the last line keeps clear of the command field")
t.assertEqual(controller.transcript.refs.command_2.text, "look", "the submitted command is in the transcript")
t.assertEqual(controller.transcript.refs.paragraph_3_1.text, "Response look", "the response follows the command")
t.expect(rendered.refs.compassControl == nil and rendered.refs.compassExit_north == nil,
	"the reader's page shows no compass")
t.expect(model:hasExit("north") and not model:hasExit("south"), "the session still knows its exits")
t.expect(controller.transcript.refs.chapter_1 == nil, "a scene carries no chapter line above its title")
t.assertEqual(controller.transcript.refs.sceneTitle_1.text, "Zork", "a scene opens with its title")

-- A new room follows the command that led there closely: the gap above its
-- title is half what it once was, 1.3 lines of type.
controller:submitCommand("north")
finishTimers()
local cellar = model:entryCount()
t.assertEqual(controller.transcript.refs["sceneTitle_" .. cellar].text, "Cellar", "the move opens a scene")
t.assertEqual(controller.transcript.refs["entry_" .. cellar].paddingTop,
	math.floor(ReadingSettings.new():presentation().fontSize * 1.3), "a scene sits 1.3 lines below its command")

-- The command field takes the width the compass left: it ends at the bar's
-- trailing edge, and the bar holds only the menu and the field.
local bar = rendered.refs.quickActions.superview
rendered.refs.session.size = ns.Size(390, 700)
rendered.refs.session:layout(390)
local field = rendered.refs.input
local glass = field.superview
while glass.superview ~= bar do glass = glass.superview end
t.assertEqual(#bar.subviews, 2, "the command bar holds the menu and the field")
t.assertEqual(glass.frame.origin.x + glass.frame.size.width, bar.bounds.size.width,
	"the command field fills the bar to its trailing edge")

local savedOpening = opening .. "\n\n> inventory\n\nYou are empty handed."
local saved = Session.new { engineFactory = function()
	return { start = function()
		return {
			resume = function(_, command) return "Response " .. command end,
			exits = function() return { "north" } end,
		}, savedOpening
	end }
end }
local loaded = SessionController.new {
	model = saved,
	findGame = function() return { id = "zork", title = "Zork", description = "A story." } end,
	push = function(_, data)
		local view, refs = xml.renderFile("apps/adventure-arena/views/Session.etlua", data, ns)
		rendered = { view = view, refs = refs }
		return view, refs
	end,
	back = function() end,
	ns = ns,
	readingSettings = ReadingSettings.new(),
	renderTemplate = function() end,
	mountTemplate = mountTemplate,
	presentSheet = function() end,
	dismissSheet = function() end,
	savedGames = { find = function() return { seed = 1, commands = {} } end, record = function() end },
	after = after,
	reduceMotion = function() return false end,
}
t.expect(loaded:show("zork"), "loading a session opens the transcript")
t.expect(not loaded:isTyping(), "a resumed story opens already set, without typing")
scroll = rendered.refs.transcriptScroll
scroll.frameSize = ns.Size(320, 120)
scroll:layout(320)
t.assertEqual(scroll.contentView.bounds.origin.y, 0, "loading a session shows the latest line")
local page = loaded.transcript.refs
t.assertEqual(page.paragraph_1_1.text:sub(1, 20), "A long opening parag", "a loaded session keeps its opening, first letter included")
t.expect(page.paragraph_1_1.figureView == nil, "a room without an icon sets its prose to the margin")
t.expect(page.paragraph_1_2.text:find("> inventory", 1, true) ~= nil, "a loaded session keeps its commands")
t.expect(page.titlePage ~= nil and page.gameTitle.text == "Zork", "the story opens on a title page")

-- Commands read as stage directions, not chat bubbles.
local command = controller.transcript.refs.command_2
t.assertEqual(command.text, "look", "the command keeps the reader's words")
t.assertEqual(command.accessibilityLabel, "You: look", "VoiceOver says who spoke")
t.expect(command.superview.backgroundColor == nil or command.superview.backgroundColor.alphaComponent == 0,
	"a command has no bubble behind it")
t.expect(command.font.fontDescriptor.fontAttributes.NSCTFontFeatureSettingsAttribute ~= nil,
	"a command is set in small capitals")

os.exit(t.summary() and 0 or 1)
