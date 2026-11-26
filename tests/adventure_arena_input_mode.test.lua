_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Template = require("ui.template")
local Words = require("apps.adventure-arena.services.Words")
local function resources() return Words.load("en") end
local Store = require("apps.adventure-arena.Store")
local Session = require("apps.adventure-arena.zilscript.zilscript.reader.Session")
local Controller = require("apps.adventure-arena.controllers.SessionController")
local catalog = require("apps.adventure-arena.catalog.en")
for _, game in ipairs(catalog) do
	t.assertEqual(game.hideTextInput, nil, game.id .. " has no separate link input mode")
end
local commands, recognizers = {}, 0
Store.new { games = {{ id = "original", title = "Original" }, { id = "classic", title = "Classic" }} }
local controller = Controller.new { resources = resources,
	model = Session.new { engineFactory = function()
		return { start = function() return {
			resume = function(_, command) table.insert(commands, command); return "A reply." end,
			exits = function() return { "north" } end,
		}, "A [[door]]." end }
	end },
	push = function(_, data) return xml.renderFile("apps/adventure-arena/views/pages/Session.etlua", data, ns) end,
	back = function() end, ns = ns, renderTemplate = function() end,
	presentSheet = function() end, dismissSheet = function() end,
	reduceMotion = function() return true end,
	speech = { recognizer = function() recognizers = recognizers + 1; return {} end },
	mountTemplate = function(host, name)
		return Template.new(host, "apps/adventure-arena/views/" .. name .. ".etlua", ns, resources)
	end,
}
for _, id in ipairs({ "original", "classic", "original" }) do
	local count = recognizers
	t.expect(controller:show(id, true), "opens " .. id)
	t.expect(controller.refs.input ~= nil and controller.refs.dictate ~= nil, "every story supports typing and dictation")
	t.assertEqual(recognizers, count + 1, "each session creates its speech recognizer")
	t.expect(controller.completions == nil, "desktop has no completion row")
	local before = #commands
	controller:updateComposer("go north")
	t.assertEqual(controller.refs.input.text, "go north", "typing fills the input")
	t.assertEqual(#commands, before, "typing does not advance the story")
	controller.actions.inputCommand("submit")
	t.assertEqual(commands[#commands], "go north", "Return submits the completed direction")
	controller:onDisappear()
	t.assertEqual(controller.refs, nil, "closing releases the reader")
end
os.exit(t.summary() and 0 or 1)
