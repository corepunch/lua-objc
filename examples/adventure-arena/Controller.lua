local Model = require("examples.adventure-arena.Model")
local ZIL = require("examples.adventure-arena.ZIL")
local xml = require("ui.xml")

local Controller = {}
Controller.__index = Controller

function Controller.new(options)
	options = options or {}
	local ns = options.ns or require("ns")
	local readFile = ns._readFile
	local model = options.model or Model.new {
		engineFactory = function(game) return ZIL.new(game, readFile) end,
	}
	return setmetatable({ model = model, ns = ns }, Controller)
end

function Controller:push(template, data, title)
	local view, refs = xml.renderFile("examples/adventure-arena/views/" .. template .. ".etlua", data, self.ns)
	self.navigation:push(self.ns.HostingController(view), title)
	return view, refs
end

function Controller:back()
	self.navigation:pop()
end

function Controller:showGame(id)
	local game = self.model:game(id)
	if not game then return false end
	self:push("Detail", { game = game, actions = {
		play = function() self:showSession(id) end,
		back = function() self:back() end,
	} }, game.title)
	return true
end

function Controller:showSession(id)
	local game = self.model:game(id)
	if not game then return false end
	local ok, err = self.model:startSession(id)
	if not ok then
		self:push("SessionError", {
			message = err, actions = { back = function() self:back() end },
		}, game.title)
		return false
	end
	local actions = {
		submit = function() self:submitCommand(self.sessionRefs.input.text) end,
		look = function() self:submitCommand("look") end,
		inventory = function() self:submitCommand("inventory") end,
		close = function() self:back() end,
	}
	self.sessionView, self.sessionRefs = self:push("Session", {
		transcript = self.model:transcript(), actions = actions,
	}, game.title)
	self.sessionRefs.input.accessibilityLabel = "Command"
	self.ns._textFieldCallbacks(self.sessionRefs.input, nil, function(command)
		if command ~= "submit" then return false end
		actions.submit()
		return true
	end)
	return true
end

function Controller:submitCommand(command)
	local ok, err = self.model:submit(command)
	self.sessionRefs.output.text = self.model:transcript()
	self.sessionRefs.input.text = ""
	self.sessionView:layout()
	return ok, err
end

function Controller:homeData()
	local games, featured = self.model:listGames(), self.model:featured()[1]
	local actions = {}
	if featured then actions.featured = function() self:showGame(featured.id) end end
	for _, game in ipairs(games) do
		actions[game.id] = function() self:showGame(game.id) end
	end
	return { games = games, featured = featured, actions = actions }
end

function Controller:home()
	local _, refs = xml.renderFile("examples/adventure-arena/views/Home.etlua", self:homeData(), self.ns)
	self.navigation = refs.navigation
	return self.navigation
end

function Controller:createWindow()
	local config, refs = xml.renderFile("examples/adventure-arena/views/Window.etlua", self:homeData(), self.ns)
	self.navigation = refs.navigation
	self.window = self.ns.Window(config)
	return self.window
end

return Controller
