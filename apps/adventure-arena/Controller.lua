local Adventures = require("apps.adventure-arena.models.Adventures")
local ReadingSettings = require("apps.adventure-arena.models.ReadingSettings")
local Session = require("apps.adventure-arena.models.Session")
local ZILRuntime = require("apps.adventure-arena.services.ZILRuntime")
local LibraryController = require("apps.adventure-arena.controllers.LibraryController")
local SessionController = require("apps.adventure-arena.controllers.SessionController")
local Template = require("ui.template")
local xml = require("ui.xml")

local VIEWS = "apps/adventure-arena/views/"

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
		focus = function(origin) self:focus(origin) end,
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
			return xml.renderFile(VIEWS .. template .. ".etlua", data, ns)
		end,
		mountTemplate = function(host, template)
			return Template.new(host, VIEWS .. template .. ".etlua", ns)
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
	local page, refs = xml.renderFile(VIEWS .. template .. ".etlua", data, self.ns)
	self.navigation:push(page)
	return page, refs
end

function Controller:back()
	self.sessionController:cancelDictation()
	self.navigation:pop()
end

-- Each tab owns a navigation stack; pages open in the one the tap came from.
function Controller:focus(origin)
	local navigation = self.navigations and self.navigations[origin]
	if navigation then self.navigation = navigation end
end

function Controller:libraryData()
	local library = self.library:presentation()
	return { library = library, actions = library.actions }
end

function Controller:home()
	local _, refs = xml.renderFile(VIEWS .. "Home.etlua", self:libraryData(), self.ns)
	self.navigation = refs.navigation
	self.navigations = { library = refs.navigation }
	return self.navigation
end

function Controller:createWindow()
	local config, refs = xml.renderFile(VIEWS .. "Window.etlua", self:libraryData(), self.ns)
	self.navigation = refs.navigation
	self.navigations = { library = refs.navigation, search = refs.searchNavigation }
	self.window = self.ns.Window(config)
	self.library:attachSearch(Template.new(refs.searchResults, VIEWS .. "SearchResults.etlua", self.ns))
	return self.window
end

return Controller
