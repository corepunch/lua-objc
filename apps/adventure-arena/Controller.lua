local SavedGames = require("apps.adventure-arena.models.SavedGames")
local Session = require("apps.adventure-arena.models.Session")
local JsonDocument = require("apps.adventure-arena.services.JsonDocument")
local Store = require("apps.adventure-arena.Store")
local ZILRuntime = require("apps.adventure-arena.services.ZILRuntime")
local PageHost = require("apps.adventure-arena.controllers.PageHost")
local OnboardingController = require("apps.adventure-arena.controllers.OnboardingController")
local ReadingSettingsController = require("apps.adventure-arena.controllers.ReadingSettingsController")
local SessionController = require("apps.adventure-arena.controllers.SessionController")
local Template = require("ui.template")
local xml = require("ui.xml")

local VIEWS = "apps/adventure-arena/views/"
local DOCUMENTS = {
	saves = "adventure-arena/saves.json",
	reading = "adventure-arena/reading.json",
	onboarding = "adventure-arena/onboarding.json",
}

-- Tabs in template order; each owns a navigation stack so a page opens in
-- the tab the tap came from.
local TABS = { "library", "bookshelf", "create", "settings", "search" }

local Controller = {}
Controller.__index = Controller

function Controller.new(options)
	options = options or {}
	local ns = options.ns or require("ns")
	local readFile = ns._readFile
	local sessionModel = options.sessionModel or Session.new {
		engineFactory = options.engineFactory or function(game, seed)
			return ZILRuntime.new(game, readFile, seed)
		end,
	}
	local self = setmetatable({ ns = ns, sessionModel = sessionModel }, Controller)
	local function mountTemplate(host, template)
		return Template.new(host, VIEWS .. template .. ".etlua", ns)
	end
	-- Headless test runs never read or write the reader's real library.
	local function document(name)
		if rawget(_G, "__headless") then return {} end
		return JsonDocument.new(ns, name)
	end
	-- The store the models read: the catalog, the saves and the reader's
	-- settings, loaded from and written to their documents.
	local documents = options.documents or {}
	self.store = Store.new {
		games = options.games,
		documents = {saves = documents.saves or document(DOCUMENTS.saves), reading = documents.reading or document(DOCUMENTS.reading)},
	}
	self.readingOptions = ReadingSettingsController.new {
		mountTemplate = mountTemplate,
		onChange = function() self.sessionController:applyReadingSettings() end,
	}
	local function push(template, data)
		return self:push(template, data)
	end
	-- What only the window can do for a page (pages/*.lua reads these as
	-- `self.app`).
	self.pages = PageHost.new(ns, {
		push = function(id, state) return self:pushPage(id, state) end,
		back = function() return self:back() end,
		focus = function(origin) self:focus(origin) end,
		selectTab = function(name) return self:selectTab(name) end,
		tabChanged = function(index)
			self.selectedTab = index
			self:focus(TABS[index + 1])
		end,
		openSession = function(id, fresh) return self.sessionController:show(id, fresh) end,
		resume = function() return self:resumeLatest() end,
		showAccessory = function(resumable) self:showAccessory(resumable) end,
		openGuide = function() self.onboarding:openGuide(self.window) end,
		mountReadingOptions = function(host) self:mountReadingOptions(host) end,
	})
	local function back() return self:back() end
	self.sessionController = SessionController.new {
		model = sessionModel,
		push = push,
		back = back,
		ns = ns,
		readingOptions = self.readingOptions,
		haptics = options.haptics or require("ui.haptics"),
		-- Dictation is the Speech plugin (src/plugins/speech), which the iOS
		-- hosts link; elsewhere the composer offers no microphone.
		speech = options.speech or (function()
			local ok, Speech = pcall(require, "Speech")
			return ok and Speech or nil
		end)(),
		after = options.after or function(seconds, callback)
			if type(ns.async) ~= "function" then return end
			ns.async(function()
				ns.sleep(seconds)
				callback()
			end)
		end,
		onProgress = function() self:refreshProgress() end,
		renderTemplate = function(template, data)
			return xml.renderFile(VIEWS .. template .. ".etlua", data, ns)
		end,
		mountTemplate = mountTemplate,
		presentSheet = function(sheet, detents)
			return ns.presentSheet(sheet, { parent = self.window, detents = detents })
		end,
		dismissSheet = function(sheet)
			if sheet then return ns.dismiss(sheet) end
		end,
	}
	self.onboarding = options.onboarding or OnboardingController.new {
		store = documents.onboarding or document(DOCUMENTS.onboarding),
		ns = ns,
		presentSheet = function(sheet, detents)
			return ns.presentSheet(sheet, { parent = self.window, detents = detents })
		end,
		dismissSheet = function(sheet)
			if sheet then return ns.dismiss(sheet) end
		end,
		openSession = function(id, fresh) return self.sessionController:show(id, fresh) end,
	}
	self.mountTemplate = mountTemplate
	return self
end

-- Screens are <Page> templates: title, toolbar and presentation are declared
-- there, so pushing is render-and-push.
function Controller:push(template, data)
	local page, refs = xml.renderFile(VIEWS .. template .. ".etlua", data, self.ns)
	self.navigation:push(page)
	return page, refs
end

-- A page of a route pushed on the navigation stack that is showing.
function Controller:pushPage(id, state)
	local page, refs = self.pages:render(id, state)
	self.navigation:push(page)
	return page, refs
end

function Controller:back()
	self.sessionController:cancelDictation()
	self.navigation:pop()
end

function Controller:focus(origin)
	local navigation = self.navigations and self.navigations[origin]
	if navigation then self.navigation = navigation end
end

-- Discover / Library / Create / Settings / Search, matching Tabs.etlua.
function Controller:selectTab(name)
	local index
	for i, key in ipairs(TABS) do
		if key == name then index = i - 1 break end
	end
	if not index then return false end
	self.selectedTab = index
	self:focus(name)
	if self.tabs then self.tabs:selectTab(index) end
	return true
end

-- The accessory resumes the latest story in whichever tab is showing.
function Controller:resumeLatest()
	local latest = SavedGames:latest()
	if not latest then return false end
	self:focus(TABS[(self.selectedTab or 0) + 1])
	return self.sessionController:show(latest.gameId)
end

-- Discover's data and the actions of every page the window layout names:
-- Discover's own, and the search field's.
function Controller:libraryData()
	local library = self.pages:data("discover")
	local actions = {}
	for name, action in pairs(library.actions) do actions[name] = action end
	actions.search = self.pages:data("search").actions.search
	return { library = library, actions = actions }
end

-- Everything that shows reading progress: the Discover shelf, the Library
-- tab and the tab bar accessory, each asked again.
function Controller:refreshProgress()
	self.pages:refresh()
end

-- An open book hides the accessory with the tab bar, as does having
-- nothing to resume.
function Controller:showAccessory(resumable)
	if self.tabs then self.tabs.accessoryHidden = not resumable or self.sessionController:isOpen() end
end

-- The reading options are shared with the in-book sheet: mounted once per
-- host the Settings page draws.
function Controller:mountReadingOptions(host)
	if not host or self.readingHost == host then return end
	self.readingHost = host
	self.readingOptions:mount(host, true)
end

function Controller:attach(refs)
	local pages = self.pages
	-- An empty catalog shows its empty state and has no shelf to fill.
	if refs.continueShelf then pages:mount("continueShelf", refs.continueShelf) end
	if refs.bookshelf then pages:mount("bookshelf", refs.bookshelf) end
	if refs.nowReading then pages:mount("nowReading", refs.nowReading) end
	if refs.searchResults then pages:mount("search", refs.searchResults) end
	if refs.settings then pages:mount("settings", refs.settings) end
end

function Controller:home()
	local _, refs = xml.renderFile(VIEWS .. "layouts/Home.etlua", self:libraryData(), self.ns)
	self.navigation = refs.navigation
	self.navigations = { library = refs.navigation }
	self:attach(refs)
	return self.navigation
end

function Controller:createWindow()
	local config, refs = xml.renderFile(VIEWS .. "layouts/Window.etlua", self:libraryData(), self.ns)
	self.navigation = refs.navigation
	self.navigations = {
		library = refs.navigation, bookshelf = refs.bookshelfNavigation, create = refs.createNavigation,
		settings = refs.settingsNavigation, search = refs.searchNavigation,
	}
	self.tabs = refs.tabs
	self.window = self.ns.Window(config)
	self:attach(refs)
	-- Headless runs drive the tour themselves; a live launch shows it once.
	if not rawget(_G, "__headless") and self.onboarding:needed() then
		self.onboarding:open(self.window)
	end
	return self.window
end

return Controller
