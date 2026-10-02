_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Session = require("apps.adventure-arena.models.Session")
local ReadingSettings = require("apps.adventure-arena.models.ReadingSettings")
local SessionController = require("apps.adventure-arena.controllers.SessionController")
local Template = require("ui.template")

-- Dictation is the Speech plugin, injected as `speech`: the composer offers
-- a microphone only when it is there, and the recognizer's events fill the
-- command field.
local function engine()
	return {
		start = function()
			return {
				resume = function() return "Nothing happens." end,
				exits = function() return {} end,
				roomName = function() return "West of House" end,
			}, "West of House"
		end,
	}
end

local function open(speech)
	local refs
	local controller = SessionController.new {
		model = Session.new { engineFactory = function() return engine() end },
		findGame = function() return { id = "zork", title = "Zork", description = "A story." } end,
		push = function(_, data)
			local view
			view, refs = xml.renderFile("apps/adventure-arena/views/Session.etlua", data, ns)
			return view, refs
		end,
		back = function() end,
		ns = ns,
		readingSettings = ReadingSettings.new(),
		renderTemplate = function() end,
		mountTemplate = function(host, template)
			return Template.new(host, "apps/adventure-arena/views/" .. template .. ".etlua", ns)
		end,
		presentSheet = function() end,
		dismissSheet = function() end,
		haptics = { impact = function() end, notification = function() end },
		after = function() end,
		reduceMotion = function() return true end,
		speech = speech,
	}
	t.expect(controller:show("zork"), "the story opens")
	return controller, refs
end

local _, quiet = open(nil)
t.expect(quiet.dictate == nil, "without the Speech plugin the composer has no microphone")

local events, calls = nil, {}
local Speech = {
	recognizer = function(onEvent)
		events = onEvent
		return {
			start = function() table.insert(calls, "start") end,
			stop = function() table.insert(calls, "stop") end,
			cancel = function() table.insert(calls, "cancel") end,
		}
	end,
}
local controller, refs = open(Speech)
t.expect(refs.dictate ~= nil, "with it the composer offers the microphone")
controller:toggleDictation()
t.assertEqual(calls[1], "start", "the microphone starts the recognizer")
events("listening", "", "")
events("partial", "open the", "")
t.assertEqual(refs.input.text, "open the", "partial text fills the command field")
controller:toggleDictation()
t.assertEqual(calls[2], "stop", "tapping again finishes")
events("finished", "open the mailbox", "")
t.assertEqual(refs.input.text, "open the mailbox", "the final text replaces it")

os.exit(t.summary() and 0 or 1)
