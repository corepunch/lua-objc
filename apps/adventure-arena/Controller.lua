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
	local function push(template, data, title, options)
		return self:push(template, data, title, options)
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

-- `options` carries per-screen navigation behavior from the controller that
-- owns the screen: onDisappear, hidesTabBar, hidesNavigationBar.
function Controller:push(template, data, title, options)
	options = options or {}
	local view, refs = xml.renderFile("apps/adventure-arena/views/" .. template .. ".etlua", data, self.ns)
	local hostingController = self.ns.HostingController(view, options.onDisappear, {
		hidesTabBar = options.hidesTabBar == true,
		hidesNavigationBar = options.hidesNavigationBar == true,
	})
	self.navigation:push(hostingController, title)
	if data.systemNavigation and self.ns.installNavigationChrome then
		local titleView, titleRefs = xml.renderFile(
			"apps/adventure-arena/views/SessionTitle.etlua", data, self.ns)
		for key, value in pairs(titleRefs) do refs[key] = value end
		self.ns.installNavigationChrome(hostingController, titleView,
			data.actions and data.actions.readingSettings)
	end
	return view, refs
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
