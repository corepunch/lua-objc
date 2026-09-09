local Model = require("examples.adventure-arena.Model")
local xml = require("ui.xml")
local Detail = require("examples.adventure-arena.views.Detail")
local Session = require("examples.adventure-arena.views.Session")
local Tabs = require("examples.adventure-arena.views.Tabs")

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({ model = Model.new() }, Controller)
end

function Controller:showGame(game)
	local ns = require("ns")
	local view = Detail(ns, game, {
		play = function() self:showSession(game) end,
		back = function() self.navigation:pop() end,
	})
	self.navigation:push(ns.HostingController(view), game.title)
end

function Controller:showSession(game)
	local ns = require("ns")
	local ok, err = self.model:startSession(game, ns)
	if not ok then
		local view = ns.VStack {
			ns.ContentUnavailable { title = "Couldn’t start adventure",
				systemImage = "exclamationmark.triangle", description = err },
			ns.Button { title = "Back", action = function() self.navigation:pop() end },
		}
		self.navigation:push(ns.HostingController(view), game.title)
		return
	end
	local view, refs
	local function submit(command)
		self.model:submit(command)
		refs.output.text = self.model:transcript()
		refs.input.text = ""
		view:layout()
	end
	view, refs = Session(ns, game, self.model:transcript(), {
		submit = function() submit(refs.input.text) end,
		command = submit,
		close = function() self.navigation:pop() end,
	})
	self.sessionView, self.sessionRefs = view, refs
	self.navigation:push(ns.HostingController(view), game.title)
end

function Controller:home()
	local ns = require("ns")
	local featured = Model.featured()[1]
	local actions = { featured = function() self:showGame(featured) end }
	for index, game in ipairs(Model.games) do
		actions["game_" .. index] = function() self:showGame(game) end
	end
	local view = xml.renderFile("examples/adventure-arena/views/Adventures.etlua",
		{ games = Model.games, featured = featured, actions = actions }, ns)
	self.navigation = ns.NavigationStack { content = view, title = "Adventures", hidesNavigationBar = true }
	return self.navigation
end

function Controller:createWindow()
	local ns = require("ns")
	local config = xml.renderFile("examples/adventure-arena/views/Window.etlua")
	config.content = Tabs(ns, self:home())
	self.window = ns.Window(config)
	return self.window
end

return Controller
