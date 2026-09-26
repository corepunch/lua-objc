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
				resume = function(_, command) return "Response " .. command end,
				exits = function() return { "north", "east" } end,
			}, opening
		end,
	}
end

local model = Session.new { engineFactory = function() return engine() end }
local rendered = {}
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
}
t.expect(controller:show("zork"), "new session opens")
local scroll = rendered.refs.transcriptScroll
scroll.frameSize = ns.Size(320, 120)
scroll:layout(320)
t.assertEqual(scroll.contentView.bounds.origin.y, 0, "opening a session shows the latest line")
t.expect(scroll.scrollOnKeyboard == true, "the transcript follows the keyboard")

scroll:scrollTo("top", false)
t.expect(scroll.contentView.bounds.origin.y > 0, "the reader can leave the latest line")
ns._textFieldTestFocus(rendered.refs.input)
t.assertEqual(scroll.contentView.bounds.origin.y, 0, "showing the keyboard returns to the latest line")

scroll:scrollTo("top", false)
rendered.refs.input.text = "look"
controller:submitCommand("look")
scroll.frameSize = ns.Size(320, 120)
scroll:layout(320)
t.assertEqual(scroll.contentView.bounds.origin.y, 0, "a new message returns to the latest line")
t.assertEqual(controller.transcript.refs.command_2.text, "look", "the submitted command is in the transcript")
t.assertEqual(controller.transcript.refs.paragraph_3_1.text, "Response look", "the response follows the command")
t.assertEqual(rendered.refs.compassExit_north.strokeAlpha, 1, "loaded exits stay marked after a command")
t.assertEqual(rendered.refs.compassExit_south.strokeAlpha, 0, "closed exits stay unmarked after a command")

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
}
t.expect(loaded:show("zork"), "loading a session opens the transcript")
scroll = rendered.refs.transcriptScroll
scroll.frameSize = ns.Size(320, 120)
scroll:layout(320)
t.assertEqual(scroll.contentView.bounds.origin.y, 0, "loading a session shows the latest line")
t.assertEqual(loaded.transcript.refs.lead_1.text:sub(1, 20), " long opening paragr", "a loaded session keeps its opening")
t.expect(loaded.transcript.refs.paragraph_1_1.text:find("> inventory", 1, true) ~= nil, "a loaded session keeps its commands")

os.exit(t.summary() and 0 or 1)
