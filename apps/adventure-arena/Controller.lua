local Adventures = require("apps.adventure-arena.models.Adventures")
local ReadingSettings = require("apps.adventure-arena.models.ReadingSettings")
local Session = require("apps.adventure-arena.models.Session")
local ZILRuntime = require("apps.adventure-arena.services.ZILRuntime")
local LibraryController = require("apps.adventure-arena.controllers.LibraryController")
local SessionController = require("apps.adventure-arena.controllers.SessionController")
local xml = require("ui.xml")

local Controller = {}
Controller.__index = Controller

function Controller.new(options)
	options = options or {}
	local ns = options.ns or require("ns")
	local adventures = options.adventures or Adventures.new { games = options.games }
	local readFile = ns._readFile
	local sessionModel = options.sessionModel or Session.new {
		engineFactory = options.engineFactory or function(game)
			return ZILRuntime.new(game, readFile)
		end,
	}
	local self = setmetatable({ ns = ns, adventures = adventures, sessionModel = sessionModel }, Controller)
	self.readingSettings = ReadingSettings.new()
	local function push(template, data)
		return self:push(template, data)
	end
	local function back() return self:back() end
	self.library = LibraryController.new {
		model = adventures,
		push = push,
		back = back,
		openSession = function(id) return self.sessionController:show(id) end,
	}
	self.sessionController = SessionController.new {
		model = sessionModel,
		findGame = function(id) return self.adventures:find(id) end,
		push = push,
		back = back,
		ns = ns,
		readingSettings = self.readingSettings,
		renderTemplate = function(template, data)
			return xml.renderFile("apps/adventure-arena/views/" .. template .. ".etlua", data, ns)
		end,
		presentSheet = function(sheet, detents)
			return ns.presentSheet(sheet, { parent = self.window, detents = detents })
		end,
		dismissSheet = function(sheet)
			if sheet then return ns.dismiss(sheet) end
		end,
	}
	return self
end

-- Screens are <Page> templates: title, toolbar and presentation are declared
-- there, so pushing is render-and-push.
function Controller:push(template, data)
	local page, refs = xml.renderFile("apps/adventure-arena/views/" .. template .. ".etlua", data, self.ns)
	self.navigation:push(page)
	return page, refs
end

function Controller:back()
	self.sessionController:cancelDictation()
	self.navigation:pop()
end

function Controller:home()
	local _, refs = xml.renderFile("apps/adventure-arena/views/Home.etlua", self.library:presentation(), self.ns)
	self.navigation = refs.navigation
	return self.navigation
end

function Controller:createWindow()
	local config, refs = xml.renderFile("apps/adventure-arena/views/Window.etlua", self.library:presentation(), self.ns)
	self.navigation = refs.navigation
	self.window = self.ns.Window(config)
	return self.window
end

return Controller
