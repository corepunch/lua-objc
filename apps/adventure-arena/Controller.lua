local Adventures = require("apps.adventure-arena.models.Adventures")
local ReadingSettings = require("apps.adventure-arena.models.ReadingSettings")
local SavedGames = require("apps.adventure-arena.models.SavedGames")
local Session = require("apps.adventure-arena.models.Session")
local JsonDocument = require("apps.adventure-arena.services.JsonDocument")
local ZILRuntime = require("apps.adventure-arena.services.ZILRuntime")
local LibraryController = require("apps.adventure-arena.controllers.LibraryController")
local ReadingSettingsController = require("apps.adventure-arena.controllers.ReadingSettingsController")
local SessionController = require("apps.adventure-arena.controllers.SessionController")
local Template = require("ui.template")
local xml = require("ui.xml")

local VIEWS = "apps/adventure-arena/views/"
local DOCUMENTS = { saves = "adventure-arena/saves.json", reading = "adventure-arena/reading.json" }

-- Tabs in template order; each owns a navigation stack so a page opens in
-- the tab the tap came from.
local TABS = { "library", "bookshelf", "create", "settings", "search" }

local Controller = {}
Controller.__index = Controller

function Controller.new(options)
	options = options or {}
	local ns = options.ns or require("ns")
	local adventures = options.adventures or Adventures.new { games = options.games }
	local readFile = ns._readFile
	local sessionModel = options.sessionModel or Session.new {
		engineFactory = options.engineFactory or function(game, seed)
			return ZILRuntime.new(game, readFile, seed)
		end,
	}
	local self = setmetatable({ ns = ns, adventures = adventures, sessionModel = sessionModel }, Controller)
	local function mountTemplate(host, template)
		return Template.new(host, VIEWS .. template .. ".etlua", ns)
	end
	-- Headless test runs never read or write the reader's real library.
	local function document(name)
		if rawget(_G, "__headless") then return {} end
		return JsonDocument.new(ns, name)
	end
	local readingStore = options.readingStore or document(DOCUMENTS.reading)
	self.readingSettings = options.readingSettings or ReadingSettings.new(readingStore.load and readingStore.load())
	self.savedGames = options.savedGames or SavedGames.new {
		store = options.saveStore or document(DOCUMENTS.saves),
	}
	self.readingOptions = ReadingSettingsController.new {
		model = self.readingSettings,
		store = readingStore,
		mountTemplate = mountTemplate,
		onChange = function() self.sessionController:applyReadingSettings() end,
	}
	local function push(template, data)
		return self:push(template, data)
	end
	local function back() return self:back() end
	self.library = LibraryController.new {
		model = adventures,
		savedGames = self.savedGames,
		push = push,
		back = back,
		focus = function(origin) self:focus(origin) end,
		openSession = function(id, fresh) return self.sessionController:show(id, fresh) end,
		onSavesChanged = function() self:refreshProgress() end,
	}
	self.sessionController = SessionController.new {
		model = sessionModel,
		findGame = function(id) return self.adventures:find(id) end,
		push = push,
		back = back,
		ns = ns,
		readingSettings = self.readingSettings,
		readingOptions = self.readingOptions,
		savedGames = self.savedGames,
		haptics = options.haptics or require("ui.haptics"),
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

function Controller:back()
	self.sessionController:cancelDictation()
	self.navigation:pop()
end

function Controller:focus(origin)
	local navigation = self.navigations and self.navigations[origin]
	if navigation then self.navigation = navigation end
end

-- The accessory resumes the latest story in whichever tab is showing.
function Controller:resumeLatest()
	local latest = self.savedGames:latest()
	if not latest then return false end
	self:focus(TABS[(self.selectedTab or 0) + 1])
	return self.sessionController:show(latest.gameId)
end

function Controller:libraryData()
	local library = self.library:presentation()
	local actions = library.actions
	actions.tabChanged = function(_, index)
		self.selectedTab = tonumber(index) or 0
		self:focus(TABS[self.selectedTab + 1])
	end
	return { library = library, actions = actions }
end

-- Everything that shows reading progress: the Discover shelf, the Library
-- tab and the tab bar accessory.
function Controller:refreshProgress()
	if self.continueShelf and not self.continueShelf:isDisposed() then
		self.continueShelf:update(self.library:continueShelf())
	end
	if self.bookshelf and not self.bookshelf:isDisposed() then
		self.bookshelf:update(self.library:bookshelf())
	end
	if self.nowReading and not self.nowReading:isDisposed() then
		local latest = self.savedGames:latest()
		local entry = latest and self.library:progressEntry(latest)
		self.nowReading:update({
			game = entry and entry.game, place = entry and entry.place or "",
			actions = { resume = function() self:resumeLatest() end },
		})
		-- The accessory belongs to the tab bar: an open book hides both.
		if self.tabs then self.tabs.accessoryHidden = entry == nil or self.sessionController:isOpen() end
	end
end

function Controller:attach(refs)
	-- An empty catalog shows its empty state and has no shelf to fill.
	if refs.continueShelf then self.continueShelf = self.mountTemplate(refs.continueShelf, "ContinueShelf") end
	if refs.bookshelf then self.bookshelf = self.mountTemplate(refs.bookshelf, "Bookshelf") end
	if refs.nowReading then self.nowReading = self.mountTemplate(refs.nowReading, "NowReading") end
	if refs.settings then
		local settings = self.mountTemplate(refs.settings, "Settings")
		local _, settingsRefs = settings:update({})
		self.settings = settings
		self.readingOptions:mount(settingsRefs.readingOptions, true)
	end
	self:refreshProgress()
end

function Controller:home()
	local _, refs = xml.renderFile(VIEWS .. "Home.etlua", self:libraryData(), self.ns)
	self.navigation = refs.navigation
	self.navigations = { library = refs.navigation }
	self:attach(refs)
	return self.navigation
end

function Controller:createWindow()
	local config, refs = xml.renderFile(VIEWS .. "Window.etlua", self:libraryData(), self.ns)
	self.navigation = refs.navigation
	self.navigations = {
		library = refs.navigation, bookshelf = refs.bookshelfNavigation, create = refs.createNavigation,
		settings = refs.settingsNavigation, search = refs.searchNavigation,
	}
	self.tabs = refs.tabs
	self.window = self.ns.Window(config)
	self.library:attachSearch(Template.new(refs.searchResults, VIEWS .. "SearchResults.etlua", self.ns))
	self:attach(refs)
	return self.window
end

return Controller
