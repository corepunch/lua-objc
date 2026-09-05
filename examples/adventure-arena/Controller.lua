local Model = require("examples.adventure-arena.Model")
local xml = require("ui.xml")

local Controller = {}
Controller.__index = Controller

local function label(text, props)
	props = props or {}
	props[1] = text
	return ns.Label(props)
end

local function gameCard(ns, game, onSelect)
	return ns.VStack {
		padding = 16,
		spacing = 8,
		fillWidth = true,
		action = onSelect,
		ns.HStack {
			spacing = 12,
			ns.SystemImage {
				name = game.systemImage,
				size = 28,
				color = "accent",
				fixedWidth = 36,
			},
			ns.VStack {
				spacing = 4,
				flexGrow = 1,
				alignment = "leading",
				label(game.title, { size = 18, weight = "bold", lines = 2 }),
				label(game.shortDescription, { size = 14, color = "secondary", lines = 2 }),
				ns.HStack {
					spacing = 6,
					label(game.genre, { size = 12, color = "secondary" }),
					label("★ " .. Model.ratingLabel(game), { size = 12, color = "secondary" }),
				},
			},
		},
	}
end

function Controller.new()
	return setmetatable({ selectedGame = nil }, Controller)
end

function Controller:showGame(game)
	self.selectedGame = game
	-- Detail navigation is intentionally kept as a controller seam until the
	-- UIKit NavigationStack bridge lands; no fake navigation bar is introduced.
end

function Controller:createWindow()
	local ns = require("ns")
	local config = xml.renderFile("examples/adventure-arena/views/Window.etlua")
	local cards = {}
	for _, game in ipairs(Model.games) do
		cards[#cards + 1] = gameCard(ns, game, function()
			self:showGame(game)
		end)
	end

	local content = ns.VStack {
		padding = 20,
		spacing = 18,
		fillWidth = true,
		label("Adventures", { size = 32, weight = "bold" }),
		label("Choose a story and begin exploring.", { size = 16, color = "secondary" }),
		ns.VStack {
			spacing = 10,
			fillWidth = true,
			table.unpack(cards),
		},
	}
	config.content = content
	return ns.Window(config)
end

return Controller
