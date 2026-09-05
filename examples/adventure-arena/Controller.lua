local Model = require("examples.adventure-arena.Model")
local ZIL = require("examples.adventure-arena.ZIL")
local xml = require("ui.xml")

local Controller = {}
Controller.__index = Controller

local function text(ns, value, props)
	props = props or {}
	props.fillWidth = true
	props[1] = value
	return ns.Text(props)
end

local function stack(ns, children, padding, spacing)
	children.padding = padding or 20
	children.spacing = spacing or 14
	children.fillWidth = true
	return ns.VStack(children)
end

local function rating(ns, game)
	return ns.HStack { spacing = 5,
		text(ns, "★★★★★", { size = 13, color = "accent" }),
		text(ns, string.format("%.1f", game.rating), { size = 12, color = "secondary" }),
	}
end

local function cover(ns, game, action)
	return ns.VStack {
		ns.Image { path = game.cover, fixedWidth = 130, fixedHeight = 176,
			contentMode = "fill", cornerRadius = 10 },
		ns.Button { title = game.title, action = action, fixedWidth = 142 },
		rating(ns, game),
		fixedWidth = 142,
	}
end

function Controller.new()
	return setmetatable({ currentEngine = nil }, Controller)
end

function Controller:install(view, title)
	return require("ns").Window { title = title or "Adventure Arena", content = view }
end

function Controller:detail(game)
	local ns = require("ns")
	return ns.ScrollView { vertical = true, horizontal = false,
		content = stack(ns, {
			ns.Image { path = game.cover, fillWidth = true, fixedHeight = 280,
			contentMode = "fill", cornerRadius = 16 },
			text(ns, game.title, { size = 30, weight = "bold", lines = 2 }),
			ns.HStack { spacing = 8,
				text(ns, game.genre, { size = 12, color = "secondary" }),
				text(ns, game.author, { size = 12, color = "secondary" }),
				text(ns, tostring(game.year), { size = 12, color = "secondary" }),
			},
			rating(ns, game), ns.Separator(),
			text(ns, "About this Game", { size = 21, weight = "bold" }),
			text(ns, game.description, { size = 16, color = "secondary", lines = 12 }),
			ns.Button { title = "Play Adventure", action = function() self:showSession(game) end },
			ns.Button { title = "Back to Adventures", action = function()
				if self.navigation then self.navigation:pop() else self:install(self:home(), "Adventure Arena") end
			end },
		}),
	}
end

function Controller:showGame(game)
	local ns = require("ns")
	if self.navigation then
		self.navigation:push(ns.HostingController(self:detail(game)), game.title)
	else
		self:install(self:detail(game), game.title)
	end
end

function Controller:showSession(game)
	local ns = require("ns")
	local ok, session = pcall(function() return ZIL.new(game, ns) end)
	if not ok then
		return self:install(stack(ns, {
			text(ns, "Couldn’t start adventure", { size = 24, weight = "bold" }),
			text(ns, tostring(session), { color = "secondary", lines = 8 }),
			ns.Button { title = "Back", action = function() self:showGame(game) end },
		}), game.title)
	end
	local engine, opening = session:start()
	self.currentEngine = engine
	local transcript = text(ns, tostring(opening or ""), { size = 16, lines = 20 })
	local commands = ns.HStack { spacing = 8, fillWidth = true }
	for _, command in ipairs({ "look", "inventory", "north", "south" }) do
		commands:add(ns.Button { title = command, action = function()
			local success, response = pcall(function() return engine:resume(command) end)
			transcript.text = tostring(transcript.text or "") .. "\n\n> " .. command .. "\n" .. tostring(success and response or response)
		end })
	end
	self:install(ns.ScrollView { vertical = true, horizontal = false, content = stack(ns, {
		text(ns, game.title, { size = 22, weight = "bold" }), transcript, commands,
		ns.Button { title = "End session", action = function() self:showGame(game) end },
	}) }, game.title)
end

function Controller:home()
	local ns = require("ns")
	local featured = Model.featured()[2]
	local actions = { featured = function() self:showGame(featured) end }
	for index, game in ipairs(Model.games) do
		actions["game_" .. index] = function() self:showGame(game) end
	end
	local view, refs = xml.renderFile(
		"examples/adventure-arena/views/Adventures.etlua",
		{ games = Model.games, featured = featured, actions = actions }, ns)
	self.navigation = ns.NavigationStack { content = view }
	return self.navigation
end

function Controller:tabs()
	local ns = require("ns")
	local function tab(title, icon, content)
		return { __tab = true, title = title, systemImage = icon, content = content }
	end
	return ns.TabView { tabs = {
		tab("Adventures", "gamecontroller", self:home()),
		tab("Ongoing", "clock.arrow.circlepath", stack(ns, {
			text(ns, "Ongoing Games", { size = 30, weight = "bold" }),
			ns.HStack { spacing = 16,
				ns.Image { path = Model.game("books.limehouse-killings").cover, fixedWidth = 92, fixedHeight = 128,
					contentMode = "fill", cornerRadius = 8 },
				ns.VStack {
					text(ns, "The Limehouse Killings", { size = 18, weight = "bold" }),
					text(ns, "12 commands played", { color = "secondary" }),
				},
			},
		})),
		tab("Create Game", "plus.circle", stack(ns, {
			text(ns, "Create a Game", { size = 30, weight = "bold" }),
			text(ns, "Bring your own ZIL adventure to the arena.", { color = "secondary" }),
		})),
		tab("Settings", "gearshape", stack(ns, {
			text(ns, "Settings", { size = 30, weight = "bold" }),
			text(ns, "Reading preferences and accessibility.", { color = "secondary" }),
		})),
	} }
end

function Controller:createWindow()
	local config = xml.renderFile("examples/adventure-arena/views/Window.etlua")
	config.content = self:tabs()
	return require("ns").Window(config)
end

return Controller
