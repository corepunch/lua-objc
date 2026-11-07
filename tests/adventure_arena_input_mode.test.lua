_G.__headless = true
local t = require("TestKit")
local etlua = require("etlua")
local Store = require("apps.adventure-arena.Store")
local Session = require("apps.adventure-arena.zilscript.zilscript.reader.Session")
local Controller = require("apps.adventure-arena.controllers.SessionController")
local catalog = require("apps.adventure-arena.catalog.Adventures")
local function render(path, data)
	local file = assert(io.open("apps/adventure-arena/views/" .. path .. ".etlua"))
	local source = file:read("*a"); file:close()
	return assert(etlua.compile(source))(data)
end
local originals = 0
for _, game in ipairs(catalog) do
	if game.id:match("^books%.") then
		originals = originals + 1
		t.assertEqual(game.hideTextInput, true, game.id .. " uses prose links")
	else
		t.expect(not game.hideTextInput, game.id .. " keeps its parser")
	end
end
t.assertEqual(originals, 6, "all six originals are covered")

local commands, recognizers, pageXML = {}, 0, ""
local controller = Controller.new {
	model = Session.new { engineFactory = function()
		return { start = function() return {
			resume = function(_, command) table.insert(commands, command); return "A reply." end,
		}, "A [[door]]." end }
	end },
	push = function(_, data)
		pageXML = render("pages/Session", data)
		return {}, { reader = {}, heading = {}, suggestions = {} }
	end,
	back = function() end, ns = {}, renderTemplate = function() end,
	presentSheet = function() end, dismissSheet = function() end,
	reduceMotion = function() return true end,
	speech = { recognizer = function() recognizers = recognizers + 1; return {} end },
	mountTemplate = function(_, name)
		return {
			refs = {}, isDisposed = function() return false end, dispose = function() end,
			update = function(_, data)
				if name == "sections/Reader" then render(name, data) end
				return {}, { transcript = {} }
			end,
		}
	end,
}
Store.new { games = {
	{ id = "links", title = "Links", hideTextInput = true },
	{ id = "parser", title = "Parser", hideTextInput = false },
	{ id = "default", title = "Default" },
} }
for _, id in ipairs({ "links", "parser", "links", "default" }) do
	local hidden = id == "links"
	local before = recognizers
	t.expect(controller:show(id, true), "opens " .. id)
	local data = controller:readerData()
	t.assertEqual(data.composer.hidden, hidden, "flag reaches retained reader")
	t.assertEqual(recognizers - before, hidden and 0 or 1, "link mode creates no speech recognizer")
	t.assertEqual(controller.suggestions == nil, hidden, "keyboard suggestions only mount for typing")
	t.assertEqual(pageXML:find('id="suggestionBar"', 1, true) == nil, hidden, "keyboard toolbar follows adventure")
	local output = render("sections/Reader", data)
	for _, ref in ipairs({ "input", "dictate", "dictationStatus" }) do
		t.assertEqual(output:find('id="' .. ref .. '"', 1, true) == nil, hidden, ref .. " follows adventure")
	end
	t.expect(output:find('id="quickActions"', 1, true), "quick actions remain available")
	t.expect(output:find('id="progress"', 1, true), "progress remains available")
	controller.actions.look()
	t.assertEqual(commands[#commands], "look", "quick action submits without input ref")
	controller.model.linkActions = function() return {{title = "Open", command = "open door"}} end
	local _, actions = controller:linkMenus({{ kind = "scene", links = {{{target = "door", location = 0, length = 4, label = "door"}}} }})
	actions.link_1_1_1_1()
	t.assertEqual(commands[#commands], "open door", "prose action submits without input ref")
	controller:onDisappear()
end
os.exit(t.summary() and 0 or 1)
